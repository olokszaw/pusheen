import AVFoundation
import Foundation

@MainActor
final class RoomViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var messages: [ChatMessage] = []
    @Published var members: [RoomMember] = []
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
    private var audioObservers: [NSObjectProtocol] = []
    private var activityTask: Task<Void, Never>?
    private var messageSyncTask: Task<Void, Never>?
    private var streamGenres: [String] = []
    private var latestPlaybackStateAt: Date?

    init(room: Room, api: APIClient, token: String) { self.room = room; self.api = api; self.token = token }
    func setCurrentUserID(_ id: Int?) { currentUserID = id }
    deinit {
        // `deinit` is nonisolated under Swift 6. The player/socket are released
        // with the view model; cancelling explicitly here would cross actors.
    }

    func start() async {
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
            let stream = try await api.stream(roomID: room.id)
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
            itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch observedItem.status {
                    case .readyToPlay:
                        if self.isPlaying || self.room.playback?.isPlaying == true { self.player?.play() }
                    case .failed:
                        self.error = observedItem.error?.localizedDescription ?? "Не удалось открыть видео"
                    default:
                        break
                    }
                }
            }
            timer = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.35, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self else { return }; self.position = time.seconds.isFinite ? time.seconds : 0
                let value = self.player?.currentItem?.duration.seconds ?? 0; if value.isFinite && value > 0 { self.duration = value }
            }
            socket.onEvent = { [weak self] event in self?.apply(event) }
            socket.connect(baseURL: api.baseURL, roomID: room.id, token: token)
            startMessageSync()
            startActivityReporting()
        } catch let caughtError { error = caughtError.localizedDescription }
    }
    func stop() {
        activityTask?.cancel()
        activityTask = nil
        messageSyncTask?.cancel()
        messageSyncTask = nil
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
                guard let self else { return }
                if let serverMessages = try? await self.api.messages(roomID: self.room.id) {
                    self.mergeServerMessages(serverMessages)
                }
                try? await Task.sleep(for: .seconds(3))
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
    func toggle() { guard isOwner else { return }; let next = !isPlaying; if next { player?.play() } else { player?.pause() }; isPlaying = next; socket.playback(action: next ? "play" : "pause", isPlaying: next, position: position) }
    func seek(_ value: Double) { guard isOwner else { return }; player?.seek(to: CMTime(seconds: value, preferredTimescale: 600)); position = value; socket.playback(action: "seek", isPlaying: isPlaying, position: value) }
    func send(_ text: String, as profile: Profile?) { send(text: text, image: "", as: profile) }
    func send(text: String, image: String, as profile: Profile?) {
        guard !isMuted else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !image.isEmpty else { return }
        // Render immediately; the server confirmation replaces this temporary
        // message with its permanent id a moment later.
        if let profile {
            let localID = -Int(Date().timeIntervalSince1970 * 1_000_000)
            messages.append(ChatMessage(id: localID, authorId: profile.userId, nickname: profile.nickname, text: text, imageDataURL: image, avatarDataURL: profile.avatarDataUrl, reactions: [], createdAt: ISO8601DateFormatter().string(from: Date())))
        }
        // HTTP persists first; the server then broadcasts to every socket.
        // This prevents a message disappearing when a room socket reconnects.
        Task { [weak self] in
            guard let self else { return }
            do {
                let persisted = try await self.api.sendMessage(roomID: self.room.id, text: text, image: image)
                self.mergeServerMessages([persisted])
            } catch {
                self.error = "Не удалось отправить сообщение. Проверь подключение."
            }
        }
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
            isOwner = event["is_owner"] as? Bool ?? false; isPlaying = event["is_playing"] as? Bool ?? false
            if let muted = event["is_muted"] as? Bool { isMuted = muted }
            let remote = (event["position_seconds"] as? NSNumber)?.doubleValue ?? 0
            // The creator receives their own broadcast too. Never seek it back to
            // an older server snapshot: that was the visible forward/back loop.
            let authoritative = compensatedPosition(remote: remote, isPlaying: isPlaying, event: event)
            // Correct actual drift promptly, but do not chase normal network
            // jitter frame-by-frame. This keeps participants within ~1 sec.
            if !isOwner && abs(position - authoritative) > 0.85 {
                player?.seek(to: CMTime(seconds: authoritative, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                position = authoritative
            }
            // Apply the authoritative play/pause state to every client,
            // including the room creator on the initial socket snapshot.
            // Seeking is still skipped for the creator to avoid the old
            // forward/back loop caused by delayed server positions.
            isPlaying ? player?.play() : player?.pause()
        case "chat_message":
            if let data = try? JSONSerialization.data(withJSONObject: event), let message = try? JSONDecoder().decode(ChatMessage.self, from: data), !messages.contains(where: { $0.id == message.id }) {
                if let pending = messages.firstIndex(where: { $0.id < 0 && $0.authorId == message.authorId && $0.text == message.text && $0.imageDataURL == message.imageDataURL }) {
                    messages[pending] = message
                } else {
                    messages.append(message)
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
        case "presence":
            let userID = (event["user_id"] as? NSNumber)?.intValue ?? 0
            let nickname = event["nickname"] as? String ?? "Участник"
            let online = event["is_online"] as? Bool ?? true
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
            if event["changed"] as? Bool == true {
                let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                messages.append(ChatMessage(id: -timestamp, authorId: 0, nickname: "", text: online ? "\(nickname) присоединился к просмотру" : "\(nickname) вышел из комнаты", imageDataURL: "", avatarDataURL: "", reactions: [], isSystem: true))
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
            if let pending = messages.firstIndex(where: {
                $0.id < 0 && $0.authorId == message.authorId &&
                $0.text == message.text && $0.imageDataURL == message.imageDataURL
            }) {
                messages[pending] = message
            } else {
                messages.append(message)
            }
        }
    }
    private func compensatedPosition(remote: Double, isPlaying: Bool, event: [String: Any]) -> Double {
        guard isPlaying,
              let date = playbackStateDate(from: event) else { return remote }
        // The server timestamp is authoritative; compensate transit time so a
        // remote player starts at the live position instead of 1–2 sec behind.
        let livePosition = max(0, remote + Date().timeIntervalSince(date))
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
