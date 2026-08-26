import AVFoundation
import Foundation

@MainActor
final class RoomViewModel: ObservableObject {
    private typealias PendingChatMessage = ChatOutboxItem
    private struct PendingPlaybackCommand {
        let action: String
        let isPlaying: Bool
        let position: Double
        let expectedSequence: Int64?
    }
    @Published var player: AVPlayer?
    @Published var messages: [ChatMessage] = []
    @Published var members: [RoomMember] = []
    @Published private(set) var typingUserIDs: Set<Int> = []
    @Published var isOwner = false
    @Published var isMuted = false
    @Published var isPlaying = false
    @Published var position: Double = 0
    // Unknown until AVPlayer has loaded the item.  A fake value of one second
    // used to clamp an authoritative rejoin position (for example 10:00) to
    // 00:01 before the asset duration became available.
    @Published var duration: Double = 0
    @Published var error = ""
    @Published var wasRemovedFromRoom = false
    private let room: Room
    private let api: APIClient
    private let token: String
    private var currentUserID: Int?
    private let socket = RoomSocket()
    private let chatOutbox = ChatOutboxStore.shared
    private var timer: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var playbackStalledObserver: NSObjectProtocol?
    private var audioObservers: [NSObjectProtocol] = []
    private var activityTask: Task<Void, Never>?
    private var playbackSnapshotTask: Task<Void, Never>?
    private var playbackRecoveryTask: Task<Void, Never>?
    private var playbackHealthTask: Task<Void, Never>?
    private var messageSyncTask: Task<Void, Never>?
    private var localTypingExpiryTask: Task<Void, Never>?
    private var remoteTypingExpiryTasks: [Int: Task<Void, Never>] = [:]
    private var isSendingTypingState = false
    private var messageFallbackTasks: [String: Task<Void, Never>] = [:]
    private var isStopped = false
    private var pendingMessages: [PendingChatMessage] = []
    private var isFlushingMessages = false
    /// WebSocket frames are ordered, but the old implementation launched one
    /// realtime send per tap while an HTTP fallback could persist the same
    /// outbox concurrently. A later frame could therefore reach the database
    /// before the older fallback batch. Keep exactly one unacknowledged socket
    /// message in flight; the remaining outbox is strict FIFO.
    private var realtimeMessageInFlightID: String?
    private var nextLocalMessageID = -1
    private var streamGenres: [String] = []
    private var latestPlaybackStateAt: Date?
    private var latestPlaybackSequence: Int64?
    // Optimistically reserves sequence numbers for rapid owner commands. A
    // play immediately following a seek must not be rejected just because the
    // seek acknowledgement has not crossed the tunnel yet.
    private var outboundPlaybackSequence: Int64?
    /// Play/pause/seek can be tapped while the WebSocket handshake is still in
    /// progress. Keep the newest owner intent instead of silently dropping it;
    /// the first server state supplies the sequence needed to send it safely.
    private var pendingPlaybackCommand: PendingPlaybackCommand?
    private var awaitingConnectionPlaybackState = true
    private var activeConnectionGeneration = 0
    private var lifecycleGeneration = 0
    private var lifecycleActive = false
    private var memberResyncRevision = 0
    private var memberResyncTask: Task<Void, Never>?
    private var snapshotResyncRevision = 0
    private var snapshotResyncTask: Task<Void, Never>?
    private var hasAppliedInitialPlaybackState = false
    // The socket state normally arrives while /stream/ is still resolving.
    // Keep that first authoritative target until AVPlayerItem is ready; merely
    // assigning `position` is not enough because a fresh AVPlayer always starts
    // at 0 unless it is explicitly seeked.
    private var initialPlaybackPosition: Double?
    // AVPlayer seek is asynchronous. Until its completion, the periodic clock
    // still reports the pre-seek frame (often the end of the movie). Keep the
    // user's requested position authoritative so Play cannot send that stale
    // frame back to the room.
    private var pendingSeekPosition: Double?
    private var seekGeneration = 0
    // AVPlayerItem remains terminal after DidPlayToEnd until an explicit seek.
    private var hasReachedPlaybackEnd = false
    private var latestAuthoritativeAnchor: Double = 0
    private var latestAuthoritativeAnchorUptime: TimeInterval = 0
    private var latestAuthoritativeIsPlaying = false
    private var lastHealthyPlaybackPosition: Double = 0
    private var lastHealthyPlaybackUptime: TimeInterval = 0
    private var hasAttemptedStallSeek = false
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
        guard !lifecycleActive else { return }
        lifecycleActive = true
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        isStopped = false
        // A RoomViewModel can be kept alive while the app recovers from a
        // background/reconnect transition. Reset only the per-entry playback
        // handshake so a state from an earlier socket cannot win later.
        hasAppliedInitialPlaybackState = false
        latestPlaybackStateAt = nil
        latestPlaybackSequence = nil
        outboundPlaybackSequence = nil
        pendingPlaybackCommand = nil
        awaitingConnectionPlaybackState = true
        initialPlaybackPosition = nil
        pendingSeekPosition = nil
        hasReachedPlaybackEnd = false
        latestAuthoritativeAnchor = 0
        latestAuthoritativeAnchorUptime = ProcessInfo.processInfo.systemUptime
        latestAuthoritativeIsPlaying = false
        lastHealthyPlaybackPosition = 0
        lastHealthyPlaybackUptime = ProcessInfo.processInfo.systemUptime
        hasAttemptedStallSeek = false
        seekGeneration &+= 1
        do {
            configureAudioSession()
            // Chat, membership and playback bootstrap must never block media
            // construction. Previously a slow /messages/ request delayed the
            // WebSocket and /stream/, leaving a permanent-looking spinner.
            restorePendingMessages()
            startMessageSync()
            socket.onEvent = { [weak self] event in self?.apply(event) }
            socket.onConnectionGenerationReady = { [weak self] connectionGeneration in
                guard let self, self.lifecycleActive, !self.isStopped else { return }
                self.activeConnectionGeneration = connectionGeneration
                self.awaitingConnectionPlaybackState = true
                self.scheduleMemberResync()
            }
            socket.onReady = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.recoverMessagesImmediately()
                    self.scheduleSnapshotResync()
                }
            }
            socket.connect(baseURL: api.baseURL, roomID: room.id, token: token)
            Task { [weak self] in
                guard let self else { return }
                if let snapshot = try? await self.api.roomSnapshot(roomID: self.room.id) {
                    guard self.lifecycleActive, self.lifecycleGeneration == generation,
                          !self.isStopped else { return }
                    // If WebSocket state already won the race, this slower
                    // HTTP bootstrap is only supplemental. Marking it as a new
                    // connection authority would seek the owner backwards.
                    self.applyBootstrapSnapshot(
                        snapshot,
                        authoritativeForConnection: self.awaitingConnectionPlaybackState
                    )
                } else if let loadedPeople = try? await self.api.members(roomID: self.room.id) {
                    guard self.lifecycleActive, self.lifecycleGeneration == generation,
                          !self.isStopped else { return }
                    self.members = loadedPeople
                    self.isMuted = loadedPeople.first(where: { $0.userId == self.currentUserID })?.isMuted ?? false
                }
            }
            guard let stream = await loadStreamUntilAvailable(generation: generation) else { return }
            guard !isStopped, !Task.isCancelled else { return }
            error = ""
            streamGenres = stream.genres
            guard let streamURL = URL(string: stream.url) else { throw URLError(.badURL) }
            let assetOptions: [String: Any] = stream.headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": stream.headers]
            let item = AVPlayerItem(asset: AVURLAsset(url: streamURL, options: assetOptions))
            item.preferredForwardBufferDuration = 8
            let roomPlayer = AVPlayer(playerItem: item)
            roomPlayer.automaticallyWaitsToMinimizeStalling = true
            roomPlayer.isMuted = false
            roomPlayer.volume = 1
            player = roomPlayer
            hasReachedPlaybackEnd = false
            // WebSocket is the live authority. `/stream/` may finish after its
            // first event, so never overwrite that newer state with the stale
            // room list snapshot used to open this screen.
            // Loading the media and choosing the playback clock are separate.
            // The first playback_state of this socket is the authority; never
            // start a fresh AVPlayer from the stale room-list snapshot at 0:00.
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
                    // The notification can already be queued when a backward
                    // drag begins. The explicit user seek wins that race.
                    guard self.pendingSeekPosition == nil else { return }
                    let finalPosition = self.player?.currentTime().seconds ?? self.duration
                    // Ignore a queued end notification if the user has already
                    // recovered the item by scrubbing backwards.
                    if PlaybackRejoinPolicy.recoversFromEnd(
                        target: finalPosition,
                        duration: self.duration
                    ) { return }
                    self.hasReachedPlaybackEnd = true
                    self.isPlaying = false
                    // A guest reaches the end locally too. Previously this
                    // state was cleared only for the owner, so a guest kept
                    // reporting `playing` at the final frame forever and their
                    // public preview was repeatedly projected to the end.
                    self.socket.playbackSnapshot(
                        isPlaying: false,
                        position: finalPosition.isFinite ? finalPosition : self.duration,
                        duration: self.duration,
                        sequence: self.outboundPlaybackSequence ?? self.latestPlaybackSequence
                    )
                    guard self.isOwner else { return }
                    self.sendPlaybackCommand(
                        action: "pause",
                        isPlaying: false,
                        position: finalPosition.isFinite ? finalPosition : self.duration
                    )
                }
            }
            if let playbackStalledObserver {
                NotificationCenter.default.removeObserver(playbackStalledObserver)
            }
            playbackStalledObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isStopped, self.isPlaying else { return }
                    self.playbackRecoveryTask?.cancel()
                    self.playbackRecoveryTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled, let self, !self.isStopped,
                              self.isPlaying, self.pendingSeekPosition == nil else { return }
                        self.player?.play()
                        // Refresh the authoritative clock without making the
                        // stalled participant publish its frozen local frame.
                        self.scheduleSnapshotResync()
                    }
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
                if self.recoverUnexpectedParticipantReset(actualPosition: nextPosition) { return }
                if abs(self.position - nextPosition) >= 0.5 { self.position = nextPosition }
                let value = self.player?.currentItem?.duration.seconds ?? 0
                if value.isFinite && value > 0 && abs(self.duration - value) >= 0.1 { self.duration = value }
            }
            startPlaybackSnapshotReporting()
            startPlaybackHealthMonitoring()
            startActivityReporting()
        } catch let caughtError { error = caughtError.localizedDescription }
    }
    func stop() {
        if lifecycleActive, !isStopped {
            stopTyping()
            socket.leaveAndClose()
        } else {
            // `stop()` is intentionally idempotent. If startup failed before
            // the lifecycle became active there is no leave to publish, but a
            // partially-created transport still has to be torn down.
            socket.close()
        }
        isStopped = true
        lifecycleActive = false
        lifecycleGeneration &+= 1
        memberResyncRevision &+= 1
        memberResyncTask?.cancel()
        memberResyncTask = nil
        snapshotResyncRevision &+= 1
        snapshotResyncTask?.cancel()
        snapshotResyncTask = nil
        seekGeneration &+= 1
        if let timer { player?.removeTimeObserver(timer) }
        timer = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver) }
        playbackEndObserver = nil
        if let playbackStalledObserver { NotificationCenter.default.removeObserver(playbackStalledObserver) }
        playbackStalledObserver = nil
        playbackRecoveryTask?.cancel()
        playbackRecoveryTask = nil
        playbackHealthTask?.cancel()
        playbackHealthTask = nil
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
        persistPendingMessages()
        chatOutbox.flushWrites()
        flushPendingMessagesAfterStop()
        pendingMessages.removeAll()
        realtimeMessageInFlightID = nil
        pendingSeekPosition = nil
        hasReachedPlaybackEnd = false
        player?.pause()
        socket.onEvent = nil
        socket.onReady = nil
        socket.onConnectionGenerationReady = nil
        // `leaveAndClose()` above keeps the final explicit-leave frame alive
        // until URLSession has sent it. Do not cancel that transport here.
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
                if self.socket.connected {
                    self.sendNextPendingRealtimeIfPossible()
                } else {
                    await self.flushPendingMessages()
                }
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
                        let reportedIsPlaying = PlaybackRejoinPolicy.snapshotIsPlaying(
                            isOwner: self.isOwner,
                            desiredIsPlaying: self.isPlaying,
                            isActuallyAdvancing: isActuallyAdvancing
                        )
                        // Every participant reports the frame their AVPlayer is
                        // truly showing. The server uses this only for that
                        // user's muted profile preview; owner-only room control
                        // remains unchanged.
                        self.socket.playbackSnapshot(
                            isPlaying: reportedIsPlaying,
                            position: max(0, actual),
                            duration: hasDuration ? itemDuration : 0,
                            sequence: self.outboundPlaybackSequence ?? self.latestPlaybackSequence
                        )
                    }
                }
                // The shared playing clock is projected from `updated_at`, so
                // writing every 1.5 seconds adds SQLite contention without
                // improving late-join accuracy. Five seconds is still fresh
                // enough for the per-member preview and leaves chat writes free.
                try? await Task.sleep(for: .seconds(5))
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
        var commandPosition = pendingSeekPosition ?? position
        // Play on an item that already ended should replay from the beginning,
        // not publish "playing at duration" while AVPlayer stays frozen.
        if next, hasReachedPlaybackEnd {
            commandPosition = 0
            hasReachedPlaybackEnd = false
            position = 0
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isPlaying else { return }
                    self.player?.play()
                }
            }
        } else if next {
            player?.play()
        } else {
            player?.pause()
        }
        isPlaying = next
        position = commandPosition
        sendPlaybackCommand(action: next ? "play" : "pause", isPlaying: next, position: commandPosition)
    }

    func seek(_ value: Double) {
        guard isOwner else { return }
        let nonnegativeValue = max(0, value)
        let upperBound = duration.isFinite && duration > 0 ? duration : nonnegativeValue
        let target = min(nonnegativeValue, upperBound)
        seekGeneration &+= 1
        let generation = seekGeneration
        if hasReachedPlaybackEnd,
           PlaybackRejoinPolicy.recoversFromEnd(target: target, duration: duration) {
            hasReachedPlaybackEnd = false
            player?.pause()
        }
        pendingSeekPosition = target
        position = target
        performAuthoritativeSeek(to: target, generation: generation)
        sendPlaybackCommand(action: "seek", isPlaying: isPlaying, position: target)
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
        performAuthoritativeSeek(to: target, generation: generation)
    }

    /// `/stream/` can transiently fail while Caddy/Daphne is reconnecting or
    /// while an external source is being resolved. Keep the room, chat and
    /// socket alive and retry instead of leaving a permanent spinner until the
    /// user exits the room again.
    private func loadStreamUntilAvailable(generation: Int) async -> VideoStream? {
        var attempt = 0
        while lifecycleActive, lifecycleGeneration == generation, !isStopped, !Task.isCancelled {
            do {
                return try await api.stream(roomID: room.id, refresh: attempt > 0)
            } catch APIError.http(let status, let detail) where (400..<500).contains(status) {
                // Membership/ban/bad-room failures are permanent for this
                // screen. Retrying them forever leaves an unexplained spinner.
                self.error = detail
                return nil
            } catch APIError.unauthorized {
                self.error = "Сессия закончилась"
                return nil
            } catch {
                self.error = "Видео временно недоступно, переподключаемся…"
                attempt += 1
                let delay = min(6.0, 0.6 * pow(1.7, Double(min(attempt, 6))))
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        return nil
    }

    /// AVPlayer does not always emit `AVPlayerItemPlaybackStalled`; on some
    /// HTTP range responses it simply remains in waiting state. Detect actual
    /// lack of clock progress. First ask AVPlayer to resume, then (only after a
    /// sustained stall) seek once to the projected authoritative room clock.
    private func startPlaybackHealthMonitoring() {
        playbackHealthTask?.cancel()
        lastHealthyPlaybackUptime = ProcessInfo.processInfo.systemUptime
        lastHealthyPlaybackPosition = player?.currentTime().seconds ?? position
        playbackHealthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, !self.isStopped else { return }
                guard self.isPlaying else {
                    self.lastHealthyPlaybackUptime = ProcessInfo.processInfo.systemUptime
                    self.lastHealthyPlaybackPosition = self.player?.currentTime().seconds ?? self.position
                    self.hasAttemptedStallSeek = false
                    continue
                }
                guard self.pendingSeekPosition == nil,
                      let player = self.player,
                      player.currentItem?.status == .readyToPlay else { continue }
                let now = ProcessInfo.processInfo.systemUptime
                let actual = player.currentTime().seconds
                guard actual.isFinite else { continue }
                if actual > self.lastHealthyPlaybackPosition + 0.3 {
                    self.lastHealthyPlaybackPosition = actual
                    self.lastHealthyPlaybackUptime = now
                    self.hasAttemptedStallSeek = false
                    continue
                }
                let stalledFor = now - self.lastHealthyPlaybackUptime
                if stalledFor >= 3 {
                    player.playImmediately(atRate: 1)
                }
                // Exactly one recovery seek per continuous stall. Repeating
                // this every few seconds makes AVPlayer jump to an earlier
                // keyframe over and over, which was the visible 6–7 rewind bug.
                guard PlaybackRejoinPolicy.shouldAttemptStallSeek(
                    stalledFor: stalledFor,
                    alreadyAttempted: self.hasAttemptedStallSeek
                ) else { continue }
                self.hasAttemptedStallSeek = true
                let target = PlaybackRejoinPolicy.projectedRecoveryPosition(
                    anchor: self.latestAuthoritativeAnchor,
                    elapsed: now - self.latestAuthoritativeAnchorUptime,
                    isPlaying: self.latestAuthoritativeIsPlaying,
                    knownDuration: self.duration
                )
                self.seekGeneration &+= 1
                let generation = self.seekGeneration
                self.pendingSeekPosition = target
                self.performAuthoritativeSeek(to: target, generation: generation)
                self.scheduleSnapshotResync()
            }
        }
    }

    /// AVPlayer may cancel a seek while an HTTP asset is becoming playable.
    /// Treating that cancellation as success was the late-join-at-00:00 bug.
    /// Retry the same generation; a newer server command increments the
    /// generation and invalidates every older completion/retry.
    private func performAuthoritativeSeek(to target: Double, generation: Int, attempt: Int = 0) {
        guard !isStopped, seekGeneration == generation,
              let player, player.currentItem?.status == .readyToPlay else {
            if seekGeneration == generation {
                initialPlaybackPosition = target
                pendingSeekPosition = nil
            }
            return
        }
        player.pause()
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.12, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.12, preferredTimescale: 600)
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.seekGeneration == generation, !self.isStopped else { return }
                guard finished else {
                    let delay = attempt < 7 ? 220 : 1_000
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(delay))
                        guard !Task.isCancelled, let self,
                              self.seekGeneration == generation, !self.isStopped else { return }
                        self.performAuthoritativeSeek(
                            to: target,
                            generation: generation,
                            attempt: attempt < 7 ? attempt + 1 : 0
                        )
                    }
                    return
                }
                self.initialPlaybackPosition = nil
                self.pendingSeekPosition = nil
                self.position = target
                self.lastHealthyPlaybackPosition = target
                self.lastHealthyPlaybackUptime = ProcessInfo.processInfo.systemUptime
                self.hasAttemptedStallSeek = false
                if self.isPlaying { self.player?.play() } else { self.player?.pause() }
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
        let localID = nextLocalMessageID
        nextLocalMessageID &-= 1
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let authorID = profile?.userId ?? currentUserID ?? 0
        let nickname = profile?.nickname ?? "Вы"
        let avatarDataURL = profile?.avatarDataUrl ?? ""
        let pendingID = UUID().uuidString
        messages.append(ChatMessage(id: localID, authorId: authorID, nickname: nickname, text: text, imageDataURL: image, avatarDataURL: avatarDataURL, reactions: [], replyTo: replyTo, createdAt: createdAt, createdAtAgeSeconds: 0, clientMessageID: pendingID))
        pendingMessages.append(PendingChatMessage(
            id: pendingID,
            localMessageID: localID,
            text: text,
            image: image,
            replyTo: replyTo,
            authorID: authorID,
            nickname: nickname,
            avatarDataURL: avatarDataURL,
            createdAt: createdAt
        ))
        persistPendingMessages()
        // The WebSocket is the low-latency path: every participant receives a
        // persisted message as soon as the server handles it. The FIFO HTTP
        // outbox remains the reliable fallback for a tunnel/socket interruption.
        sendNextPendingRealtimeIfPossible()
        let fallbackTask = Task { [weak self] in
            guard let self else { return }
            defer { self.messageFallbackTasks[pendingID] = nil }
            // Never persist the same outbox concurrently over WebSocket and
            // HTTP: their arrival order is independent. HTTP is used only once
            // the socket is actually down; while it is connected, the strict
            // single-flight realtime queue owns delivery order.
            try? await Task.sleep(for: .milliseconds(self.socket.connected ? 1_200 : 40))
            guard !Task.isCancelled,
                  !self.isStopped,
                  self.pendingMessages.contains(where: { $0.id == pendingID }) else { return }
            if self.socket.connected,
               self.realtimeMessageInFlightID == pendingID {
                // A half-open WebSocket can accept a local frame while never
                // delivering its acknowledgement. Previously that single frame
                // blocked the FIFO outbox until the 18-second socket watchdog.
                // Retire that transport first, then use the idempotent HTTP batch
                // (client_message_id prevents a duplicate if the frame arrived).
                self.socket.reconnectAuthoritatively()
            }
            if !self.socket.connected { await self.flushPendingMessages() }
        }
        messageFallbackTasks[pendingID] = fallbackTask
    }

    private func sendNextPendingRealtimeIfPossible() {
        guard realtimeMessageInFlightID == nil,
              let pending = pendingMessages.first else { return }
        let sent = socket.chat(
            text: pending.text,
            image: pending.image,
            clientMessageID: pending.id,
            replyToID: pending.replyTo?.id
        )
        if sent { realtimeMessageInFlightID = pending.id }
    }

    private func finishPendingDelivery(_ clientID: String) {
        messageFallbackTasks[clientID]?.cancel()
        messageFallbackTasks[clientID] = nil
        pendingMessages.removeAll { $0.id == clientID }
        persistPendingMessages()
        if realtimeMessageInFlightID == clientID { realtimeMessageInFlightID = nil }
        sendNextPendingRealtimeIfPossible()
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
            scheduleMemberResync()
        } catch { self.error = error.localizedDescription }
    }
    private func apply(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "playback_state":
            let firstStateForConnection = awaitingConnectionPlaybackState
            let incomingSequence = playbackSequence(from: event)
            let stateDate = playbackStateDate(from: event)
            let command = event["command"] as? String ?? "state"
            if !firstStateForConnection {
                if let incomingSequence,
                   !PlaybackRejoinPolicy.accepts(
                       incomingSequence: incomingSequence,
                       latestSequence: latestPlaybackSequence,
                       authoritativeConnectionSnapshot: false
                   ) { return }
                // Older servers do not include a sequence. Retain the timestamp
                // guard as a compatibility fallback, but a monotonic server
                // sequence is authoritative whenever it is available.
                if incomingSequence == nil,
                   let stateDate, let latestPlaybackStateAt,
                   stateDate < latestPlaybackStateAt { return }
            }
            awaitingConnectionPlaybackState = false
            if let incomingSequence {
                latestPlaybackSequence = incomingSequence
                if firstStateForConnection || command == "stale" {
                    outboundPlaybackSequence = incomingSequence
                } else {
                    outboundPlaybackSequence = max(
                        outboundPlaybackSequence ?? incomingSequence,
                        incomingSequence
                    )
                }
            }
            if let stateDate { latestPlaybackStateAt = stateDate }
            let nextIsPlaying = event["is_playing"] as? Bool ?? false
            isOwner = event["is_owner"] as? Bool ?? false
            var queuedOwnerCommand: PendingPlaybackCommand?
            if isOwner, let pendingPlaybackCommand {
                let legacyPayloadMatches = command == pendingPlaybackCommand.action
                    && nextIsPlaying == pendingPlaybackCommand.isPlaying
                    && abs(((event["position_seconds"] as? NSNumber)?.doubleValue ?? 0) - pendingPlaybackCommand.position) < 0.85
                if PlaybackRejoinPolicy.acknowledgesPendingCommand(
                    expectedSequence: pendingPlaybackCommand.expectedSequence,
                    incomingSequence: incomingSequence,
                    legacyPayloadMatches: legacyPayloadMatches
                ) {
                    self.pendingPlaybackCommand = nil
                } else {
                    // Rapid Seek→Play produces two ordered acknowledgements. The
                    // seek echo is older than the queued play and must neither
                    // overwrite the local player nor trigger a duplicate command.
                    if !PlaybackRejoinPolicy.shouldReplayPendingCommand(
                        firstStateForConnection: firstStateForConnection,
                        command: command
                    ) {
                        return
                    }
                    queuedOwnerCommand = pendingPlaybackCommand
                }
            } else if !isOwner {
                pendingPlaybackCommand = nil
            }
            isPlaying = nextIsPlaying
            if let muted = event["is_muted"] as? Bool { isMuted = muted }
            let remote = (event["position_seconds"] as? NSNumber)?.doubleValue ?? 0
            // The creator receives their own broadcast too. Never seek it back to
            // an older server snapshot: that was the visible forward/back loop.
            let authoritative = compensatedPosition(remote: remote, isPlaying: isPlaying, event: event)
            latestAuthoritativeAnchor = authoritative
            latestAuthoritativeAnchorUptime = ProcessInfo.processInfo.systemUptime
            latestAuthoritativeIsPlaying = nextIsPlaying
            let itemIsReady = player?.currentItem?.status == .readyToPlay
            if let queuedOwnerCommand {
                // Do not let the first (necessarily older) server snapshot erase
                // a Play/Seek performed during the handshake. It is used only to
                // obtain the current sequence, then the newest local intent is
                // published immediately and remains the owner's visible state.
                pendingPlaybackCommand = nil
                isPlaying = queuedOwnerCommand.isPlaying
                position = queuedOwnerCommand.position
                latestAuthoritativeAnchor = queuedOwnerCommand.position
                latestAuthoritativeAnchorUptime = ProcessInfo.processInfo.systemUptime
                latestAuthoritativeIsPlaying = queuedOwnerCommand.isPlaying
                if !itemIsReady {
                    initialPlaybackPosition = queuedOwnerCommand.position
                    hasAppliedInitialPlaybackState = true
                } else if pendingSeekPosition == nil {
                    queuedOwnerCommand.isPlaying ? player?.play() : player?.pause()
                }
                sendPlaybackCommand(
                    action: queuedOwnerCommand.action,
                    isPlaying: queuedOwnerCommand.isPlaying,
                    position: queuedOwnerCommand.position
                )
                return
            }
            // The first state may arrive before AVPlayer has been constructed.
            // Persist it and seek the actual player as soon as its item is ready
            // instead of letting every re-entering participant begin at 0:00.
            if !hasAppliedInitialPlaybackState || !itemIsReady {
                // Do not preserve only the first deferred target. A newer seek,
                // pause or play can arrive while AVPlayer is loading and must
                // replace the older target before the item becomes ready.
                seekGeneration &+= 1
                pendingSeekPosition = nil
                position = authoritative
                initialPlaybackPosition = authoritative
                hasAppliedInitialPlaybackState = true
                applyInitialPlaybackStateIfNeeded()
                return
            }
            // Correct actual drift promptly, but do not chase normal network
            // jitter frame-by-frame. This keeps participants within ~1 sec.
            // A periodic/reconnect `state` snapshot must not seek an already
            // playing participant. Quick tunnels can reconnect repeatedly,
            // which previously produced the 5–10 second rewind loop. Explicit
            // owner commands and the very first room snapshot remain authoritative.
            let actualPosition = player?.currentTime().seconds
            let localPosition = (actualPosition?.isFinite == true) ? (actualPosition ?? position) : position
            let drift = abs(localPosition - authoritative)
            let shouldCatchUp = PlaybackRejoinPolicy.shouldCatchUpParticipant(
                isOwner: isOwner,
                isPlaying: nextIsPlaying,
                command: command,
                localPosition: localPosition,
                authoritativePosition: authoritative
            )
            let shouldApplyPosition = firstStateForConnection || (
                !isOwner && PlaybackRejoinPolicy.shouldSeekForRemoteState(
                    firstStateForConnection: false,
                    command: command,
                    isPlaying: nextIsPlaying
                )
            ) || shouldCatchUp
            if shouldApplyPosition && drift > 0.85 {
                // Invalidate an older initial seek before applying a newer
                // command. Without this, the old completion could rewind a
                // freshly joined viewer back to a stale time.
                seekGeneration &+= 1
                let generation = seekGeneration
                pendingSeekPosition = authoritative
                if PlaybackRejoinPolicy.recoversFromEnd(target: authoritative, duration: duration) {
                    hasReachedPlaybackEnd = false
                }
                initialPlaybackPosition = nil
                performAuthoritativeSeek(to: authoritative, generation: generation)
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
                    finishPendingDelivery(clientMessageID)
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
            scheduleMemberResync()
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
            scheduleMemberResync()
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
        for message in serverMessages {
            // Confirm only the exact optimistic message. Comparing text here
            // used to discard legitimate rapid messages such as "a, a, a".
            if let clientID = message.clientMessageID,
               let pending = pendingMessages.first(where: { $0.id == clientID }) {
                finishPendingDelivery(clientID)
                confirmPersistedMessage(message, for: pending)
                continue
            }
            // The HTTP poll and WebSocket can deliver the same persisted row in
            // either order. Update it in place so reactions/profile data stay
            // current without ever creating/removing a visible chat row.
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
                continue
            }
            if let clientID = message.clientMessageID,
               let index = messages.firstIndex(where: { $0.clientMessageID == clientID }) {
                messages[index] = message
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
                    finishPendingDelivery(clientID)
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

    private func restorePendingMessages() {
        let restored = chatOutbox.load(roomID: room.id, userID: currentUserID)
        guard !restored.isEmpty else { return }
        pendingMessages = restored
        for pending in restored where !messages.contains(where: { $0.id == pending.localMessageID }) {
            messages.append(ChatMessage(
                id: pending.localMessageID,
                authorId: pending.authorID,
                nickname: pending.nickname,
                text: pending.text,
                imageDataURL: pending.image,
                avatarDataURL: pending.avatarDataURL,
                reactions: [],
                replyTo: pending.replyTo,
                createdAt: pending.createdAt,
                createdAtAgeSeconds: 0,
                clientMessageID: pending.id
            ))
        }
        if let oldestLocalID = restored.map(\.localMessageID).min() {
            nextLocalMessageID = min(nextLocalMessageID, oldestLocalID - 1)
        }
    }

    private func persistPendingMessages() {
        chatOutbox.replace(pendingMessages, roomID: room.id, userID: currentUserID)
    }

    /// `stop()` is synchronous, but delivery may still be awaiting a socket
    /// acknowledgement. Hand the immutable batch to an unstructured task before
    /// releasing the view model; the on-disk copy remains if the request fails.
    private func flushPendingMessagesAfterStop() {
        let batch = pendingMessages
        guard !batch.isEmpty else { return }
        let api = self.api
        let roomID = room.id
        let userID = currentUserID
        let outbox = chatOutbox
        Task {
            let body = batch.map { pending -> [String: Any] in
                var value: [String: Any] = [
                    "text": pending.text,
                    "image_data_url": pending.image,
                    "client_message_id": pending.id,
                ]
                if let replyID = pending.replyTo?.id { value["reply_to_id"] = replyID }
                return value
            }
            guard let persisted = try? await api.sendMessagesBatch(roomID: roomID, messages: body) else { return }
            let confirmed = Set(persisted.compactMap(\.clientMessageID))
            guard !confirmed.isEmpty else { return }
            let remaining = outbox.load(roomID: roomID, userID: userID).filter { !confirmed.contains($0.id) }
            outbox.replace(remaining, roomID: roomID, userID: userID)
        }
    }
    private func recoverMessagesImmediately() async {
        guard !isStopped else { return }
        if let serverMessages = try? await api.messages(roomID: room.id) {
            mergeServerMessages(serverMessages)
        }
        if socket.connected {
            sendNextPendingRealtimeIfPossible()
        } else {
            await flushPendingMessages()
        }
    }

    /// Rehydrates an already-presented room when the API becomes reachable.
    /// The current view and AVPlayer remain alive.
    func refreshAfterConnectivityRecovery() async {
        guard !isStopped else { return }
        socket.reconnectAuthoritatively()
        await recoverMessagesImmediately()
        scheduleSnapshotResync()
    }

    /// Coalesces all presence/moderation/reconnect refreshes.  A slower response
    /// started before a newer one is never allowed to restore an obsolete list.
    private func scheduleMemberResync() {
        guard lifecycleActive, !isStopped else { return }
        memberResyncRevision &+= 1
        let revision = memberResyncRevision
        let lifecycle = lifecycleGeneration
        let connection = activeConnectionGeneration
        memberResyncTask?.cancel()
        memberResyncTask = Task { [weak self] in
            guard let self else { return }
            let refreshed = try? await self.api.members(roomID: self.room.id)
            guard !Task.isCancelled,
                  let refreshed,
                  self.lifecycleActive,
                  !self.isStopped,
                  self.lifecycleGeneration == lifecycle,
                  self.activeConnectionGeneration == connection,
                  self.memberResyncRevision == revision else { return }
            self.members = refreshed
            self.isMuted = refreshed.first(where: { $0.userId == self.currentUserID })?.isMuted ?? false
            self.memberResyncTask = nil
        }
    }

    /// Reconnect is a full server rehydrate, not only a WebSocket reopen. The
    /// revision/lifecycle checks make a slow response from an older connection
    /// unable to overwrite a newer playback generation or member list.
    private func scheduleSnapshotResync() {
        guard lifecycleActive, !isStopped else { return }
        snapshotResyncRevision &+= 1
        let revision = snapshotResyncRevision
        let lifecycle = lifecycleGeneration
        let connection = activeConnectionGeneration
        snapshotResyncTask?.cancel()
        snapshotResyncTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = try? await self.api.roomSnapshot(roomID: self.room.id)
            guard !Task.isCancelled,
                  let snapshot,
                  self.lifecycleActive,
                  !self.isStopped,
                  self.lifecycleGeneration == lifecycle,
                  self.activeConnectionGeneration == connection,
                  self.snapshotResyncRevision == revision else { return }
            self.applyBootstrapSnapshot(snapshot, authoritativeForConnection: false)
            self.snapshotResyncTask = nil
        }
    }

    private func applyBootstrapSnapshot(_ snapshot: RoomSnapshot, authoritativeForConnection: Bool) {
        members = snapshot.members
        isMuted = members.first(where: { $0.userId == currentUserID })?.isMuted ?? false
        // The top-level playback object is projected by the server at the
        // exact snapshot instant. `room.playback` is retained only for older
        // list payload compatibility and must not drive reconnect.
        let playback = snapshot.playback
        if let latestPlaybackSequence,
           playback.sequence < latestPlaybackSequence { return }

        var event: [String: Any] = [
            "type": "playback_state",
            "command": "state",
            "is_playing": playback.isPlaying,
            "position_seconds": playback.positionSeconds,
            "sequence": playback.sequence,
            "is_owner": snapshot.room.owner == currentUserID,
            "is_muted": isMuted,
        ]
        if let serverUpdatedAt = playback.serverUpdatedAt {
            event["server_updated_at"] = serverUpdatedAt
        }
        if authoritativeForConnection {
            awaitingConnectionPlaybackState = true
        }
        apply(event)
    }
    private func compensatedPosition(remote: Double, isPlaying: Bool, event: [String: Any]) -> Double {
        guard isPlaying,
              let date = playbackStateDate(from: event) else { return remote }
        // Compensate only normal transit time. A server clock in another
        // timezone (or with a bad clock) must never turn a paused seek into
        // an hours-long offset that clamps playback to the end of the video.
        let transitSeconds = Date().timeIntervalSince(date)
        guard transitSeconds >= 0, transitSeconds <= 5 else { return remote }
        return PlaybackRejoinPolicy.clampedPosition(
            remote + transitSeconds,
            knownDuration: duration
        )
    }

    @discardableResult
    private func recoverUnexpectedParticipantReset(actualPosition: Double) -> Bool {
        guard pendingSeekPosition == nil else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        let authoritative = PlaybackRejoinPolicy.projectedRecoveryPosition(
            anchor: latestAuthoritativeAnchor,
            elapsed: now - latestAuthoritativeAnchorUptime,
            isPlaying: latestAuthoritativeIsPlaying,
            knownDuration: duration
        )
        guard PlaybackRejoinPolicy.shouldRecoverUnexpectedZeroReset(
            isOwner: isOwner,
            isPlaying: isPlaying,
            actualPosition: actualPosition,
            previousHealthyPosition: lastHealthyPlaybackPosition,
            authoritativePosition: authoritative
        ) else { return false }
        seekGeneration &+= 1
        let generation = seekGeneration
        pendingSeekPosition = authoritative
        position = authoritative
        hasAttemptedStallSeek = true
        performAuthoritativeSeek(to: authoritative, generation: generation)
        return true
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

    private func playbackSequence(from event: [String: Any]) -> Int64? {
        if let number = event["sequence"] as? NSNumber { return number.int64Value }
        if let value = event["sequence"] as? String { return Int64(value) }
        if let number = event["version"] as? NSNumber { return number.int64Value }
        if let value = event["version"] as? String { return Int64(value) }
        return nil
    }

    private func sendPlaybackCommand(action: String, isPlaying: Bool, position: Double) {
        let baseSequence = outboundPlaybackSequence ?? latestPlaybackSequence
        // Keep the intent until its server sequence is observed. URLSession can
        // accept a frame locally and report the transport error only later, so a
        // synchronous `send == true` is not yet a playback acknowledgement.
        pendingPlaybackCommand = PendingPlaybackCommand(
            action: action,
            isPlaying: isPlaying,
            position: position,
            expectedSequence: baseSequence.map { $0 + 1 }
        )
        let sent = socket.playback(
            action: action,
            isPlaying: isPlaying,
            position: position,
            sequence: baseSequence
        )
        if sent, let baseSequence {
            outboundPlaybackSequence = baseSequence + 1
        }
    }
}
