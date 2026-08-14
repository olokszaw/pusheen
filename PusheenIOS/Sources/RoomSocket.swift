import Foundation

@MainActor
final class RoomSocket: ObservableObject {
    @Published private(set) var connected = false
    var onEvent: (([String: Any]) -> Void)?
    var onReady: (() -> Void)?
    /// Called once for every successfully opened socket, immediately before
    /// its first event is delivered.  Consumers use this generation boundary
    /// to treat the first server playback snapshot after a reconnect as
    /// authoritative instead of carrying local state across connections.
    var onConnectionGenerationReady: ((Int) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var endpoint: URL?
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var wasClosedByView = false
    private var reconnectDelay: UInt64 = 1
    private var heartbeatCount = 0
    private var receivedFirstEvent = false
    private var connectionGeneration = 0

    func connect(baseURL: URL, roomID: Int, token: String) {
        close()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/rooms/\(roomID)/"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        endpoint = components.url
        wasClosedByView = false
        reconnectDelay = 1
        open()
    }

    @discardableResult
    func send(_ payload: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8),
              connected,
              let task else { return false }
        task.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.connectionFailed(for: task) }
        }
        return true
    }

    @discardableResult
    func playback(action: String, isPlaying: Bool, position: Double, videoURL: String? = nil, sequence: Int64? = nil) -> Bool {
        var value: [String: Any] = [
            "type": "playback_command",
            "action": action,
            "is_playing": isPlaying,
            "position_seconds": position,
        ]
        if let videoURL { value["vk_video_url"] = videoURL }
        if let sequence { value["sequence"] = sequence }
        return send(value)
    }
    func playbackSnapshot(isPlaying: Bool, position: Double, duration: Double, sequence: Int64? = nil) {
        guard position.isFinite, duration.isFinite else { return }
        var payload: [String: Any] = [
            "type": "playback_snapshot",
            "is_playing": isPlaying,
            "position_seconds": max(0, position),
            "duration_seconds": max(0, duration),
        ]
        if let sequence { payload["sequence"] = sequence }
        send(payload)
    }
    @discardableResult
    func chat(text: String, image: String = "", clientMessageID: String, replyToID: Int? = nil) -> Bool {
        var payload: [String: Any] = [
            "type": "chat_message",
            "text": text,
            "image_data_url": image,
            "client_message_id": clientMessageID,
        ]
        if let replyToID { payload["reply_to_id"] = replyToID }
        return send(payload)
    }
    func reaction(messageID: Int, emoji: String) { send(["type": "message_reaction", "message_id": messageID, "emoji": emoji]) }
    func typing(_ isTyping: Bool) { send(["type": "typing", "is_typing": isTyping]) }
    /// A deliberate navigation out of the room is different from a broken
    /// transport. Keep the WebSocket alive until the leave frame has actually
    /// been handed to URLSession; immediately cancelling after `send` could
    /// randomly discard that frame on a slower connection.
    func leaveAndClose() {
        guard !wasClosedByView else { return }
        wasClosedByView = true
        reconnectTask?.cancel(); reconnectTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        guard connected, let socket = task,
              let data = try? JSONSerialization.data(withJSONObject: ["type": "leave_room"]),
              let text = String(data: data, encoding: .utf8) else {
            closeTransport()
            return
        }
        socket.send(.string(text)) { [weak self, weak socket] _ in
            Task { @MainActor in
                guard let self, let socket, self.task === socket else { return }
                self.closeTransport()
            }
        }
        Task { [weak self, weak socket] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, let socket, self.task === socket else { return }
            self.closeTransport()
        }
    }

    func close() {
        wasClosedByView = true
        reconnectTask?.cancel(); reconnectTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        closeTransport()
    }

    private func closeTransport() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connected = false
    }

    func reconnectNowIfNeeded() {
        guard !connected, !wasClosedByView, endpoint != nil else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        open()
    }

    private func open() {
        guard !wasClosedByView, let endpoint else { return }
        heartbeatTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        connectionGeneration &+= 1
        let generation = connectionGeneration
        let socket = URLSession.shared.webSocketTask(with: endpoint)
        task = socket
        socket.resume()
        // `resume()` only starts the handshake. Do not advertise a usable
        // socket until the server has accepted it and sent its first event.
        connected = false
        heartbeatCount = 0
        receivedFirstEvent = false
        receive(from: socket, generation: generation)
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.heartbeatCount += 1
                self.send(["type": "heartbeat"])
                // A lightweight authoritative snapshot periodically removes
                // the 1–2 second drift that can build up on another device
                // without changing the owner's playback logic.
                if self.heartbeatCount.isMultiple(of: 2) {
                    self.send(["type": "request_state"])
                }
            }
        }
    }

    private func receive(from socket: URLSessionWebSocketTask, generation: Int) {
        socket.receive { [weak self, weak socket] result in
            guard let self, let socket else { return }
            switch result {
            case .success(let message):
                let text: String? = if case .string(let value) = message { value } else { nil }
                if let text, let data = text.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    Task { @MainActor in
                        guard self.task === socket else { return }
                        if !self.receivedFirstEvent {
                            self.receivedFirstEvent = true
                            self.connected = true
                            self.reconnectDelay = 1
                            self.onConnectionGenerationReady?(generation)
                            self.onReady?()
                        }
                        self.onEvent?(event)
                    }
                }
                Task { @MainActor in
                    guard self.task === socket else { return }
                    self.receive(from: socket, generation: generation)
                }
            case .failure:
                Task { @MainActor in self.connectionFailed(for: socket) }
            }
        }
    }

    private func connectionFailed(for failedTask: URLSessionWebSocketTask? = nil) {
        guard !wasClosedByView else { return }
        if let failedTask, task !== failedTask { return }
        connected = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
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
