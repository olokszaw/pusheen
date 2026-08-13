import AVFoundation
import Foundation

@MainActor
final class RoomViewModel: ObservableObject {
    private struct PendingChatMessage: Identifiable {
        let id: String
        let localMessageID: Int
        let text: String
        let image: String
        let replyTo: ChatReplyPreview?
    }
    @Published var player: AVPlayer?
    @Published var messages: [ChatMessage] = []
    @Published var members: [RoomMember] = []
    @Published private(set) var typingUserIDs: Set<Int> = []
    @Published var isOwner = false
    @Published var isMuted = false
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 1
    @Published var error = ""
    @Published var wasRemovedFromRoom = false
    private let room: Room
    private let api: APIClient
    private let token: String
    private var currentUserID: Int?
    private let socket = RoomSocket()
    private var timer: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var audioObservers: [NSObjectProtocol] = []
    private var activityTask: Task<Void, Never>?
    private var playbackSnapshotTask: Task<Void, Never>?
    private var messageSyncTask: Task<Void, Never>?
    private var localTypingExpiryTask: Task<Void, Never>?
    private var remoteTypingExpiryTasks: [Int: Task<Void, Never>] = [:]
    private var isSendingTypingState = false
    private var messageFallbackTasks: [String: Task<Void, Never>] = [:]
    private var isStopped = false
    private var pendingMessages: [PendingChatMessage] = []
    private var isFlushingMessages = false
    private var streamGenres: [String] = []
    private var latestPlaybackStateAt: Date?
    private var hasAppliedInitialPlaybackState = false
    // The socket state normally arrives while /stream/ is still resolving.
    // Keep that first authoritative target until AVPlayerItem is ready; merely
    // assigning `position` is not enough because a fresh AVPlayer always starts
    // at 0 unless it is explicitly seeked.
    private var initialPlaybackPosition: Double?
    private var initialPlaybackShouldPlay = false
    // AVPlayer seek is asynchronous. Until its completion, the periodic clock
    // still reports the pre-seek frame (often the end of the movie). Keep the
    // user's requested position authoritative so Play cannot send that stale
    // frame back to the room.
    private var pendingSeekPosition: Double?
    private var seekGeneration = 0
    // Quick Tunnel reconnects can repeat the same presence transition several
    // times. Keep genuine join/leave notices while suppressing identical noise.
    private var lastPresenceNoticeAt: [String: Date] = [:]

    init(room: Room, api: APIClient, token: String) { self.room = room; self.api = api; self.token = token }
    func setCurrentUserID(_ id: Int?) { currentUserID = id }
    deinit {
        // `deinit` is nonisolated under Swift 6. The player/socket are released
        // with the view model; cancelling explicitly here would cross actors.
    }

    func start() async {
        isStopped = false
        do {
            configureAudioSession()
            async let history = api.messages(roomID: room.id)
            async let people = api.members(roomID: room.id)
            // Chat is independent from the player. A bad/slow video source
            // must never make a persisted conversation look empty.
            if let loadedHistory = try? await history { messages = loadedHistory }
            if let loadedPeople = try? await people {
                members = loadedPeople
                isMuted = members.first(where: { $0.userId == currentUserID })?.isMuted ?? false
            }
            guard !isStopped, !Task.isCancelled else { return }
            // Keep retrying history even if the video endpoint is unavailable.
            // When internet returns, messages appear without reopening the room.
            startMessageSync()
            // Chat must not wait for media resolving or AVPlayer buffering.
            // Previously this socket was opened only after /stream/ finished,
            // so participants on a slow video source saw every message via the
            // three-second HTTP polling fallback instead of in real time.
            socket.onEvent = { [weak self] event in self?.apply(event) }
            socket.onReady = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.recoverMessagesImmediately()
                }
            }
            socket.connect(baseURL: api.baseURL, roomID: room.id, token: token)
            let stream = try await api.stream(roomID: room.id)
            guard !isStopped, !Task.isCancelled else { return }
            streamGenres = stream.genres
            guard let streamURL = URL(string: stream.url) else { throw URLError(.badURL) }
            let assetOptions: [String: Any] = stream.headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": stream.headers]
            let item = AVPlayerItem(asset: AVURLAsset(url: streamURL, options: assetOptions))
            let roomPlayer = AVPlayer(playerItem: item)
            roomPlayer.automaticallyWaitsToMinimizeStalling = true
            roomPlayer.isMuted = false
            roomPlayer.volume = 1
            player = roomPlayer
            isPlaying = room.playback?.isPlaying ?? false
            if let playbackEndObserver {
                NotificationCenter.default.removeObserver(playbackEndObserver)
            }
            playbackEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isStopped else { return }
                    let finalPosition = self.player?.currentTime().seconds ?? self.duration
                    self.isPlaying = false
                    // A guest reaches the end locally too. Previously this
                    // state was cleared only for the owner, so a guest kept
                    // reporting `playing` at the final frame forever and their
                    // public preview was repeatedly projected to the end.
                    self.socket.playbackSnapshot(
                        isPlaying: false,
                        position: finalPosition.isFinite ? finalPosition : self.duration,
                        duration: self.duration
                    )
                    guard self.isOwner else { return }
                    self.socket.playback(
                        action: "pause",
                        isPlaying: false,
                        position: finalPosition.isFinite ? finalPosition : self.duration
                    )
                }
            }
            itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch observedItem.status {
                    case .readyToPlay:
                        self.applyInitialPlaybackStateIfNeeded()
                    case .failed:
                        self.error = observedItem.error?.localizedDescription ?? "Не удалось открыть видео"
                    default:
                        break
                    }
                }
            }
            timer = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self else { return }
                guard self.pendingSeekPosition == nil else { return }
                // The clock is display-only. Publishing it more often forces the
                // whole room hierarchy to reevaluate while the user scrolls chat.
                let nextPosition = time.seconds.isFinite ? time.seconds : 0
                if abs(self.position - nextPosition) >= 0.5 { self.position = nextPosition }
                let value = self.player?.currentItem?.duration.seconds ?? 0
                if value.isFinite && value > 0 && abs(self.duration - value) >= 0.1 { self.duration = value }
            }
            startPlaybackSnapshotReporting()
            startActivityReporting()
        } catch let caughtError { error = caughtError.localizedDescription }
    }
    func stop() {
        isStopped = true
        if let timer { player?.removeTimeObserver(timer) }
        timer = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver) }
        playbackEndObserver = nil
        activityTask?.cancel()
        activityTask = nil
        playbackSnapshotTask?.cancel()
        playbackSnapshotTask = nil
        messageSyncTask?.cancel()
        messageSyncTask = nil
        stopTyping()
        remoteTypingExpiryTasks.values.forEach { $0.cancel() }
        remoteTypingExpiryTasks.removeAll()
        typingUserIDs.removeAll()
        messageFallbackTasks.values.forEach { $0.cancel() }
        messageFallbackTasks.removeAll()
        pendingMessages.removeAll()
        pendingSeekPosition = nil
        socket.close()
    }
    private func startActivityReporting() {
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.isPlaying else { continue }
                let stats = try? await self.api.reportActivity(
                    watchedSeconds: 30,
                    durationSeconds: Int(self.duration),
                    genres: self.streamGenres,
                    roomID: self.room.id
                )
                guard !Task.isCancelled else { return }
                // Stats are fetched by Profile when it appears; this preserves
                // the player ownership and keeps reporting off the main UI path.
                _ = stats
            }
        }
    }
    private func startMessageSync() {
        messageSyncTask?.cancel()
        messageSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isStopped else { return }
                await self.flushPendingMessages()
                if let serverMessages = try? await self.api.messages(roomID: self.room.id) {
                    self.mergeServerMessages(serverMessages)
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
    private func startPlaybackSnapshotReporting() {
        playbackSnapshotTask?.cancel()
        playbackSnapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isStopped else { return }
                if self.socket.connected,
                   self.pendingSeekPosition == nil,
                   let player = self.player,
                   let item = self.player?.currentItem,
                   item.status == .readyToPlay {
                    let actual = player.currentTime().seconds
                    let itemDuration = item.duration.seconds
                    if actual.isFinite {
                        let hasDuration = itemDuration.isFinite && itemDuration > 0
                        let isActuallyAdvancing = player.timeControlStatus == .playing
                            && (!hasDuration || actual < itemDuration - 0.1)
                        // Every participant reports the frame their AVPlayer is
                        // truly showing. The server uses this only for that
                        // user's muted profile preview; owner-only room control
                        // remains unchanged.
                        self.socket.playbackSnapshot(
                            isPlaying: isActuallyAdvancing,
                            position: max(0, actual),
                            duration: hasDuration ? itemDuration : 0
                        )
                    }
                }
                try? await Task.sleep(for: .milliseconds(1_500))
            }
        }
    }
    private func configureAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
            try audio.setActive(true)
            NSLog("Pusheen audio active. route=%@ volume=%.2f", audio.currentRoute.description, audio.outputVolume)
        } catch {
            NSLog("Pusheen audio configuration failed: %@", error.localizedDescription)
        }
        guard audioObservers.isEmpty else { return }
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: audio, queue: .main) { [weak self] note in
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .map { AVAudioSession.InterruptionType(rawValue: $0) == .ended } ?? false
            guard ended else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                self.player?.play()
            }
        })
        audioObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: audio, queue: .main) { _ in
            NSLog("Pusheen audio route changed: %@", AVAudioSession.sharedInstance().currentRoute.description)
        })
    }
    func toggle() {
        guard isOwner else { return }
        let next = !isPlaying
        let commandPosition = pendingSeekPosition ?? position
        if next { player?.play() } else { player?.pause() }
        isPlaying = next
        position = commandPosition
        socket.playback(action: next ? "play" : "pause", isPlaying: next, position: commandPosition)
    }

    func seek(_ value: Double) {
        guard isOwner else { return }
        let nonnegativeValue = max(0, value)
        let upperBound = duration.isFinite && duration > 0 ? duration : nonnegativeValue
        let target = min(nonnegativeValue, upperBound)
        seekGeneration &+= 1
        let generation = seekGeneration
        pendingSeekPosition = target
        position = target
        player?.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.seekGeneration == generation else { return }
                self.pendingSeekPosition = nil
                self.position = target
            }
        }
        socket.playback(action: "seek", isPlaying: isPlaying, position: target)
    }

    /// Applies the state received before the media item existed.  This runs only
    /// once for a newly entered room, so later heartbeat snapshots cannot keep
    /// dragging an already playing guest backwards.
    private func applyInitialPlaybackStateIfNeeded() {
        guard let target = initialPlaybackPosition,
              let player,
              player.currentItem?.status == .readyToPlay else { return }

        initialPlaybackPosition = nil
        pendingSeekPosition = target
        seekGeneration &+= 1
        let generation = seekGeneration
        player.pause()
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.seekGeneration == generation, !self.isStopped else { return }
                self.pendingSeekPosition = nil
                self.position = target
                if self.initialPlaybackShouldPlay { self.player?.play() }
            }
        }
    }
    func send(_ text: String, as profile: Profile?) { send(text: text, image: "", replyTo: nil, as: profile) }
    func send(text: String, image: String, replyTo: ChatReplyPreview? = nil, as profile: Profile?) {
        guard !isStopped else { return }
        guard !isMuted else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !image.isEmpty else { return }
        stopTyping()
        // Render immediately; the server confirmation replaces this temporary
        // message with its permanent id a moment later.
        let localID = -Int(Date().timeIntervalSince1970 * 1_000_000)
        if let profile {
            messages.append(ChatMessage(id: localID, authorId: profile.userId, nickname: profile.nickname, text: text, imageDataURL: image, avatarDataURL: profile.avatarDataUrl, reactions: [], replyTo: replyTo, createdAt: ISO8601DateFormatter().string(from: Date()), createdAtAgeSeconds: 0))
        }
        let pendingID = UUID().uuidString
        pendingMessages.append(PendingChatMessage(id: pendingID, localMessageID: localID, text: text, image: image, replyTo: replyTo))
        // The WebSocket is the low-latency path: every participant receives a
        // persisted message as soon as the server handles it. The FIFO HTTP
        // outbox remains the reliable fallback for a tunnel/socket interruption.
        let sentRealtime = socket.chat(text: text, image: image, clientMessageID: pendingID, replyToID: replyTo?.id)
        let fallbackTask = Task { [weak self] in
            guard let self else { return }
            defer { self.messageFallbackTasks[pendingID] = nil }
            // Give the realtime path a short head start. If the acknowledgement
            // never arrives, the same client id makes the HTTP retry idempotent.
            // If the handshake is not actually ready, fall back immediately;
            // waiting here was the visible delay during rapid sends.
            try? await Task.sleep(for: .milliseconds(sentRealtime ? 180 : 40))
            guard !Task.isCancelled,
                  !self.isStopped,
                  self.pendingMessages.contains(where: { $0.id == pendingID }) else { return }
            await self.flushPendingMessages()
        }
        messageFallbackTasks[pendingID] = fallbackTask
    }
    var typingMembers: [RoomMember] {
        members.filter { typingUserIDs.contains($0.userId) && $0.userId != currentUserID }
    }
    var activeMembers: [RoomMember] {
        members.filter { $0.isOnline || $0.userId == currentUserID }
    }
    func draftDidChange(_ value: String) {
        guard !isMuted else { stopTyping(); return }
        let hasText = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText else { stopTyping(); return }
        localTypingExpiryTask?.cancel()
        if !isSendingTypingState {
            isSendingTypingState = true
            socket.typing(true)
        }
        // One start plus a debounced stop avoids a WebSocket event per letter.
        localTypingExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.stopTyping()
        }
    }
    private func stopTyping() {
        localTypingExpiryTask?.cancel()
        localTypingExpiryTask = nil
        guard isSendingTypingState else { return }
        isSendingTypingState = false
        socket.typing(false)
    }
    func react(messageID: Int, emoji: String) { socket.reaction(messageID: messageID, emoji: emoji) }
    func moderate(member: RoomMember, action: String) async {
        guard isOwner, !member.isOwner else { return }
        do {
            try await api.moderateMember(roomID: room.id, userID: member.userId, action: action)
            members = try await api.members(roomID: room.id)
        } catch { self.error = error.localizedDescription }
    }
    private func apply(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "playback_state":
            let stateDate = playbackStateDate(from: event)
            if let stateDate, let latestPlaybackStateAt, stateDate < latestPlaybackStateAt { return }
            if let stateDate { latestPlaybackStateAt = stateDate }
            let command = event["command"] as? String ?? "state"
            let nextIsPlaying = event["is_playing"] as? Bool ?? false
            isOwner = event["is_owner"] as? Bool ?? false
            isPlaying = nextIsPlaying
            if let muted = event["is_muted"] as? Bool { isMuted = muted }
            let remote = (event["position_seconds"] as? NSNumber)?.doubleValue ?? 0
            // The creator receives their own broadcast too. Never seek it back to
            // an older server snapshot: that was the visible forward/back loop.
            let authoritative = compensatedPosition(remote: remote, isPlaying: isPlaying, event: event)
            // The first state may arrive before AVPlayer has been constructed.
            // Persist it and seek the actual player as soon as its item is ready
            // instead of letting every re-entering participant begin at 0:00.
            if !hasAppliedInitialPlaybackState {
                position = authoritative
                initialPlaybackPosition = authoritative
                initialPlaybackShouldPlay = nextIsPlaying
                applyInitialPlaybackStateIfNeeded()
            }
            // Correct actual drift promptly, but do not chase normal network
            // jitter frame-by-frame. This keeps participants within ~1 sec.
            // A periodic/reconnect `state` snapshot must not seek an already
            // playing participant. Quick tunnels can reconnect repeatedly,
            // which previously produced the 5–10 second rewind loop. Explicit
            // owner commands and the very first room snapshot remain authoritative.
            let shouldApplyPosition = !hasAppliedInitialPlaybackState || command != "state" || !nextIsPlaying
            if !isOwner && shouldApplyPosition && abs(position - authoritative) > 0.85 {
                player?.seek(to: CMTime(seconds: authoritative, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                position = authoritative
            }
            hasAppliedInitialPlaybackState = true
            // Apply the authoritative play/pause state to every client,
            // including the room creator on the initial socket snapshot.
            // Seeking is still skipped for the creator to avoid the old
            // forward/back loop caused by delayed server positions.
            // Do not start a newly-created player at its default 0:00 frame
            // while the initial room seek is still in flight.
            if initialPlaybackPosition == nil && pendingSeekPosition == nil {
                isPlaying ? player?.play() : player?.pause()
            }
        case "chat_message":
            if let data = try? JSONSerialization.data(withJSONObject: event),
               let message = try? JSONDecoder().decode(ChatMessage.self, from: data) {
                let clientMessageID = event["client_message_id"] as? String
                if let clientMessageID,
                   let pending = pendingMessages.first(where: { $0.id == clientMessageID }) {
                    messageFallbackTasks[clientMessageID]?.cancel()
                    messageFallbackTasks[clientMessageID] = nil
                    pendingMessages.removeAll { $0.id == clientMessageID }
                    confirmPersistedMessage(message, for: pending)
                } else {
                    mergeServerMessages([message])
                }
            }
        case "message_reaction":
            guard let messageID = event["message_id"] as? Int, let emoji = event["emoji"] as? String else { return }
            let count = (event["count"] as? NSNumber)?.intValue ?? 0
            let reacted = event["reacted"] as? Bool ?? false
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].reactions.removeAll { $0.emoji == emoji }
                if count > 0 { messages[index].reactions.append(ChatReaction(emoji: emoji, count: count, reacted: reacted)) }
            }
        case "typing":
            let userID = (event["user_id"] as? NSNumber)?.intValue ?? 0
            guard userID != 0, userID != currentUserID else { return }
            remoteTypingExpiryTasks[userID]?.cancel()
            remoteTypingExpiryTasks[userID] = nil
            if event["is_typing"] as? Bool == true {
                typingUserIDs.insert(userID)
                // A lost stop packet must not leave the indicator visible.
                remoteTypingExpiryTasks[userID] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2.4))
                    guard !Task.isCancelled else { return }
                    self?.typingUserIDs.remove(userID)
                    self?.remoteTypingExpiryTasks[userID] = nil
                }
            } else {
                typingUserIDs.remove(userID)
            }
        case "presence":
            let userID = (event["user_id"] as? NSNumber)?.intValue ?? 0
            let nickname = event["nickname"] as? String ?? "Участник"
            let online = event["is_online"] as? Bool ?? true
            let previousOnline = members.first(where: { $0.userId == userID })?.isOnline
            let member = RoomMember(
                userId: userID,
                username: event["username"] as? String ?? "",
                nickname: nickname,
                avatarDataURL: event["avatar_data_url"] as? String ?? "",
                isOwner: event["is_owner"] as? Bool ?? false,
                isOnline: online
            )
            if let index = members.firstIndex(where: { $0.userId == userID }) {
                members[index] = member
            } else if userID != 0 {
                members.append(member)
            }
            if !online {
                remoteTypingExpiryTasks[userID]?.cancel()
                remoteTypingExpiryTasks[userID] = nil
                typingUserIDs.remove(userID)
            }
            if userID != 0, event["changed"] as? Bool == true, previousOnline != online {
                let now = Date()
                let noticeKey = "\(userID):\(online)"
                let isRepeatedReconnect = lastPresenceNoticeAt[noticeKey].map { now.timeIntervalSince($0) < 12 } ?? false
                if !isRepeatedReconnect {
                    lastPresenceNoticeAt[noticeKey] = now
                    let timestamp = Int(now.timeIntervalSince1970 * 1_000_000)
                    messages.append(ChatMessage(id: -timestamp, authorId: 0, nickname: "", text: online ? "\(nickname) присоединился к просмотру" : "\(nickname) вышел из комнаты", imageDataURL: "", avatarDataURL: "", reactions: [], isSystem: true))
                }
            }
            // The event updates the UI immediately; a lightweight fetch then
            // reconciles the list in case the client missed a prior event.
            Task { self.members = (try? await self.api.members(roomID: self.room.id)) ?? self.members }
        case "members_changed":
            // Owner transfer, mute, kick and ban arrive through the room socket
            // so every open client reflects the change without reopening room.
            if let ownerID = (event["owner_id"] as? NSNumber)?.intValue {
                isOwner = ownerID == currentUserID
            }
            let targetID = (event["user_id"] as? NSNumber)?.intValue
            if event["action"] as? String == "mute", targetID == currentUserID {
                isMuted = event["muted"] as? Bool ?? isMuted
            }
            if let systemText = event["system_text"] as? String, !systemText.isEmpty {
                let timestamp = Int(Date().timeIntervalSince1970 * 1_000_000)
                messages.append(ChatMessage(id: -timestamp, authorId: 0, nickname: "", text: systemText, imageDataURL: "", avatarDataURL: "", reactions: [], isSystem: true))
            }
            Task {
                let refreshed = (try? await self.api.members(roomID: self.room.id)) ?? self.members
                self.members = refreshed
                self.isMuted = refreshed.first(where: { $0.userId == self.currentUserID })?.isMuted ?? self.isMuted
            }
        case "room_removed":
            error = "Вас удалили из комнаты"
            wasRemovedFromRoom = true
        case "error":
            if event["code"] as? String == "muted" {
                isMuted = true
            }
        default: break
        }
    }
    private func mergeServerMessages(_ serverMessages: [ChatMessage]) {
        for message in serverMessages where !messages.contains(where: { $0.id == message.id }) {
            // Confirm only the exact optimistic message. Comparing text here
            // used to discard legitimate rapid messages such as "a, a, a".
            if let clientID = message.clientMessageID,
               let pending = pendingMessages.first(where: { $0.id == clientID }) {
                messageFallbackTasks[clientID]?.cancel()
                messageFallbackTasks[clientID] = nil
                pendingMessages.removeAll { $0.id == clientID }
                confirmPersistedMessage(message, for: pending)
                continue
            }
            // Server ids are authoritative and unique. Two equal texts are two
            // real messages unless their id/client id is also equal.
            messages.append(message)
        }
    }
    private func flushPendingMessages() async {
        guard !isStopped, !isFlushingMessages else { return }
        isFlushingMessages = true
        defer { isFlushingMessages = false }
        // A disconnected socket often collects a burst while the network is
        // returning. Persist it as one ordered transaction instead of turning
        // every tap into a serial  HTTP request and a visible delayed queue.
        while !isStopped, !Task.isCancelled, !pendingMessages.isEmpty {
            let batch = Array(pendingMessages.prefix(40))
            let body = batch.map { pending -> [String: Any] in
                var value: [String: Any] = [
                    "text": pending.text,
                    "image_data_url": pending.image,
                    "client_message_id": pending.id,
                ]
                if let replyID = pending.replyTo?.id { value["reply_to_id"] = replyID }
                return value
            }
            do {
                let persisted = try await api.sendMessagesBatch(roomID: room.id, messages: body)
                guard !isStopped, !Task.isCancelled else { return }
                let pendingByID = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })
                var confirmedIDs = Set<String>()
                for message in persisted {
                    guard let clientID = message.clientMessageID,
                          let pending = pendingByID[clientID] else { continue }
                    confirmedIDs.insert(clientID)
                    messageFallbackTasks[clientID]?.cancel()
                    messageFallbackTasks[clientID] = nil
                    pendingMessages.removeAll { $0.id == clientID }
                    confirmPersistedMessage(message, for: pending)
                }
                // A malformed/old server response must not spin forever.
                guard !confirmedIDs.isEmpty else { return }
            } catch {
                // Keep the complete outbox intact. The socket recovery and next
                // heartbeat will retry it without losing or reordering a message.
                return
            }
        }
    }
    private func confirmPersistedMessage(_ persisted: ChatMessage, for pending: PendingChatMessage) {
        if let localIndex = messages.firstIndex(where: { $0.id == pending.localMessageID }) {
            // Replace in place. Never sort the entire timeline when an older
            // queued send is finally acknowledged.
            messages[localIndex] = persisted
        } else if !messages.contains(where: { $0.id == persisted.id }) {
            messages.append(persisted)
        }
    }
    private func recoverMessagesImmediately() async {
        guard !isStopped else { return }
        if let serverMessages = try? await api.messages(roomID: room.id) {
            mergeServerMessages(serverMessages)
        }
        await flushPendingMessages()
    }

    /// Rehydrates an already-presented room when the API becomes reachable.
    /// The current view and AVPlayer remain alive.
    func refreshAfterConnectivityRecovery() async {
        guard !isStopped else { return }
        socket.reconnectNowIfNeeded()
        await recoverMessagesImmediately()
        if let refreshedMembers = try? await api.members(roomID: room.id) {
            members = refreshedMembers
            isMuted = refreshedMembers.first(where: { $0.userId == currentUserID })?.isMuted ?? false
        }
    }
    private func compensatedPosition(remote: Double, isPlaying: Bool, event: [String: Any]) -> Double {
        guard isPlaying,
              let date = playbackStateDate(from: event) else { return remote }
        // Compensate only normal transit time. A server clock in another
        // timezone (or with a bad clock) must never turn a paused seek into
        // an hours-long offset that clamps playback to the end of the video.
        let transitSeconds = Date().timeIntervalSince(date)
        guard transitSeconds >= 0, transitSeconds <= 5 else { return remote }
        let livePosition = max(0, remote + transitSeconds)
        if duration.isFinite, duration > 0 { return min(livePosition, duration) }
        return livePosition
    }

    private func playbackStateDate(from event: [String: Any]) -> Date? {
        guard let value = event["server_updated_at"] as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
