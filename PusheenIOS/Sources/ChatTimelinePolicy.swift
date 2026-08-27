import Foundation

enum ChatTimelinePolicy {
    /// During the first history load, old persisted rows belong before anything
    /// that arrived locally while that request was in flight. This operation is
    /// deliberately bootstrap-only: running it after every ACK would keep moving
    /// an old "joined the room" system row back to the bottom of the chat.
    static func prependingHistory(_ history: [ChatMessage], to messages: [ChatMessage]) -> [ChatMessage] {
        history.sorted { $0.id < $1.id } + messages
    }

    /// Insert a persisted row missed by the socket without globally sorting the
    /// timeline. Existing system/pending rows are local events and retain their
    /// visual position forever.
    static func insertingPersisted(_ message: ChatMessage, into messages: [ChatMessage]) -> [ChatMessage] {
        guard message.id > 0 else { return messages + [message] }
        var result = messages
        if let index = result.firstIndex(where: { $0.id > message.id }) {
            result.insert(message, at: index)
        } else {
            result.append(message)
        }
        return result
    }

    static func shouldAppendPresenceNotice(
        userID: Int,
        currentUserID: Int?,
        changed: Bool,
        previousOnline: Bool?,
        isOnline: Bool
    ) -> Bool {
        userID != 0
            && userID != currentUserID
            && changed
            && previousOnline != isOnline
    }
}
