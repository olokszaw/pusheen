import Foundation

struct ChatOutboxItem: Codable, Equatable, Identifiable {
    let id: String
    let localMessageID: Int
    let text: String
    let image: String
    let replyTo: ChatReplyPreview?
    let authorID: Int
    let nickname: String
    let avatarDataURL: String
    let createdAt: String
}

/// A message is not delivered merely because URLSession accepted a WebSocket
/// frame. Keep the outbox until the backend returns the same client id. The
/// serial queue preserves save/remove order without doing image JSON I/O on the
/// keyboard's main thread.
final class ChatOutboxStore {
    static let shared = ChatOutboxStore()

    private let directory: URL
    private let queue = DispatchQueue(label: "online.izanagi.pusheen.chat-outbox")

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatOutbox", isDirectory: true)
    }

    func load(roomID: Int, userID: Int?) -> [ChatOutboxItem] {
        queue.sync {
            let url = fileURL(roomID: roomID, userID: userID)
            guard let data = try? Data(contentsOf: url),
                  let items = try? JSONDecoder().decode([ChatOutboxItem].self, from: data) else {
                return []
            }
            return items
        }
    }

    func replace(_ items: [ChatOutboxItem], roomID: Int, userID: Int?) {
        queue.async { [directory] in
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("room-\(roomID)-user-\(userID ?? 0).json")
            if items.isEmpty {
                try? fileManager.removeItem(at: url)
                return
            }
            guard let data = try? JSONEncoder().encode(items) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Used during room teardown so an immediately destroyed view cannot leave
    /// its last asynchronous disk update behind.
    func flushWrites() {
        queue.sync {}
    }

    private func fileURL(roomID: Int, userID: Int?) -> URL {
        directory.appendingPathComponent("room-\(roomID)-user-\(userID ?? 0).json")
    }
}
