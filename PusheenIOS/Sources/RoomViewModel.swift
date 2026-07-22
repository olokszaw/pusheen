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
            player = AVPlayer(playerItem: item)
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
    func send(_ text: String) { guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; socket.chat(text: text) }
    private func apply(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "playback_state":
            isOwner = event["is_owner"] as? Bool ?? false; isPlaying = event["is_playing"] as? Bool ?? false
            let remote = (event["position_seconds"] as? NSNumber)?.doubleValue ?? 0
            if abs(position - remote) > 1.2 { player?.seek(to: CMTime(seconds: remote, preferredTimescale: 600)); position = remote }
            isPlaying ? player?.play() : player?.pause()
        case "chat_message":
            if let data = try? JSONSerialization.data(withJSONObject: event), let message = try? JSONDecoder().decode(ChatMessage.self, from: data), !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
        case "presence":
            Task { self.members = (try? await self.api.members(roomID: self.room.id)) ?? self.members }
        default: break
        }
    }
}
