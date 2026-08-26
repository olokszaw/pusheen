import Foundation

enum ChatTimelinePolicy {
    /// Server rows have an absolute database order. Optimistic/system rows have
    /// only a local arrival order and must never be pushed above freshly loaded
    /// history. Stable sorting preserves their existing order until ACK replaces
    /// an optimistic row with its positive server id.
    static func normalized(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.enumerated().sorted { lhs, rhs in
            let leftPersisted = lhs.element.id > 0
            let rightPersisted = rhs.element.id > 0
            if leftPersisted != rightPersisted { return leftPersisted }
            if leftPersisted { return lhs.element.id < rhs.element.id }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }
}
