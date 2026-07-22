import Foundation

@MainActor
final class RoomSocket: ObservableObject {
    @Published private(set) var connected = false
    var onEvent: (([String: Any]) -> Void)?
    private var task: URLSessionWebSocketTask?

    func connect(baseURL: URL, roomID: Int, token: String) {
        close()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/rooms/\(roomID)/"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        task = URLSession.shared.webSocketTask(with: components.url!)
        task?.resume(); connected = true; receive()
    }

    func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }
    func playback(action: String, isPlaying: Bool, position: Double, videoURL: String? = nil) { var value: [String: Any] = ["type": "playback_command", "action": action, "is_playing": isPlaying, "position_seconds": position]; if let videoURL { value["vk_video_url"] = videoURL }; send(value) }
    func chat(text: String, image: String = "") { send(["type": "chat_message", "text": text, "image_data_url": image]) }
    func reaction(messageID: Int, emoji: String) { send(["type": "message_reaction", "message_id": messageID, "emoji": emoji]) }
    func close() { task?.cancel(with: .goingAway, reason: nil); task = nil; connected = false }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let text: String? = if case .string(let value) = message { value } else { nil }
                if let text, let data = text.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { Task { @MainActor in self.onEvent?(event) } }
                self.receive()
            case .failure:
                Task { @MainActor in self.connected = false }
            }
        }
    }
}
