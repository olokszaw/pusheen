import AVFoundation
import Foundation

@MainActor
final class RoomViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var messages: [ChatMessage] = []
    @Published var members: [RoomMember] = []
    @Published var isOwner = false
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 1
    @Published var error = ""
    private let room: Room
    private let api: APIClient
    private let token: String
    private let socket = RoomSocket()
    private var timer: Any?

    init(room: Room, api: APIClient, token: String) { self.room = room; self.api = api; self.token = token }
    deinit {
        // `deinit` is nonisolated under Swift 6. The player/socket are released
        // with the view model; cancelling explicitly here would cross actors.
    }

    func start() async {
        do {
            async let history = api.messages(roomID: room.id)
            async let people = api.members(roomID: room.id)
            let stream = try await api.stream(roomID: room.id)
            messages = try await history; members = try await people
            let item = AVPlayerItem(url: URL(string: stream.url)!)
            let roomPlayer = AVPlayer(playerItem: item)
            roomPlayer.automaticallyWaitsToMinimizeStalling = true
            player = roomPlayer
            timer = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.35, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self else { return }; self.position = time.seconds.isFinite ? time.seconds : 0
                let value = self.player?.currentItem?.duration.seconds ?? 0; if value.isFinite && value > 0 { self.duration = value }
            }
            socket.onEvent = { [weak self] event in self?.apply(event) }
            socket.connect(baseURL: api.baseURL, roomID: room.id, token: token)
        } catch let caughtError { error = caughtError.localizedDescription }
    }
    func toggle() { guard isOwner else { return }; let next = !isPlaying; if next { player?.play() } else { player?.pause() }; isPlaying = next; socket.playback(action: next ? "play" : "pause", isPlaying: next, position: position) }
    func seek(_ value: Double) { guard isOwner else { return }; player?.seek(to: CMTime(seconds: value, preferredTimescale: 600)); position = value; socket.playback(action: "seek", isPlaying: isPlaying, position: value) }
    func send(_ text: String, as profile: Profile?) { send(text: text, image: "", as: profile) }
    func send(text: String, image: String, as profile: Profile?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !image.isEmpty else { return }
        // Render immediately; the server confirmation replaces this temporary
        // message with its permanent id a moment later.
        if let profile {
            let localID = -Int(Date().timeIntervalSince1970 * 1_000_000)
            messages.append(ChatMessage(id: localID, authorId: profile.userId, nickname: profile.nickname, text: text, imageDataURL: image, avatarDataURL: profile.avatarDataUrl, reactions: []))
        }
        socket.chat(text: text, image: image)
    }
    func react(messageID: Int, emoji: String) { socket.reaction(messageID: messageID, emoji: emoji) }
    private func apply(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "playback_state":
            isOwner = event["is_owner"] as? Bool ?? false; isPlaying = event["is_playing"] as? Bool ?? false
            let remote = (event["position_seconds"] as? NSNumber)?.doubleValue ?? 0
            // The creator receives their own broadcast too. Never seek it back to
            // an older server snapshot: that was the visible forward/back loop.
            if !isOwner && abs(position - remote) > 2.5 {
                player?.seek(to: CMTime(seconds: remote, preferredTimescale: 600))
                position = remote
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
            let nickname = event["nickname"] as? String ?? "Участник"
            let online = event["is_online"] as? Bool ?? true
            if event["changed"] as? Bool == true {
                let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                messages.append(ChatMessage(id: -timestamp, authorId: 0, nickname: "", text: online ? "\(nickname) присоединился к просмотру" : "\(nickname) вышел из комнаты", imageDataURL: "", avatarDataURL: "", reactions: [], isSystem: true))
            }
            Task { self.members = (try? await self.api.members(roomID: self.room.id)) ?? self.members }
        default: break
        }
    }
}
