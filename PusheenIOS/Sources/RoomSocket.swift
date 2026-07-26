import Foundation

@MainActor
final class RoomSocket: ObservableObject {
    @Published private(set) var connected = false
    var onEvent: (([String: Any]) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var endpoint: URL?
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var wasClosedByView = false
    private var reconnectDelay: UInt64 = 1

    func connect(baseURL: URL, roomID: Int, token: String) {
        close()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/rooms/\(roomID)/"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        endpoint = components.url
        wasClosedByView = false
        open()
    }

    func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8),
              let task else { return }
        task.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.connectionFailed() }
        }
    }

    func playback(action: String, isPlaying: Bool, position: Double, videoURL: String? = nil) { var value: [String: Any] = ["type": "playback_command", "action": action, "is_playing": isPlaying, "position_seconds": position]; if let videoURL { value["vk_video_url"] = videoURL }; send(value) }
    func chat(text: String, image: String = "") { send(["type": "chat_message", "text": text, "image_data_url": image]) }
    func reaction(messageID: Int, emoji: String) { send(["type": "message_reaction", "message_id": messageID, "emoji": emoji]) }

    func close() {
        wasClosedByView = true
        reconnectTask?.cancel(); reconnectTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connected = false
    }

    private func open() {
        guard !wasClosedByView, let endpoint else { return }
        heartbeatTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        let socket = URLSession.shared.webSocketTask(with: endpoint)
        task = socket
        socket.resume()
        connected = true
        reconnectDelay = 1
        receive(from: socket)
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                self?.send(["type": "heartbeat"])
            }
        }
    }

    private func receive(from socket: URLSessionWebSocketTask) {
        socket.receive { [weak self, weak socket] result in
            guard let self, let socket else { return }
            switch result {
            case .success(let message):
                let text: String? = if case .string(let value) = message { value } else { nil }
                if let text, let data = text.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    Task { @MainActor in self.onEvent?(event) }
                }
                Task { @MainActor in
                    guard self.task === socket else { return }
                    self.receive(from: socket)
                }
            case .failure:
                Task { @MainActor in self.connectionFailed() }
            }
        }
    }

    private func connectionFailed() {
        guard !wasClosedByView else { return }
        connected = false
        heartbeatTask?.cancel(); heartbeatTask = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil, endpoint != nil, !wasClosedByView else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 12)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(delay)))
            guard !Task.isCancelled else { return }
            self?.reconnectTask = nil
            self?.open()
        }
    }
}
