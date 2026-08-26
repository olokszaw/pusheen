import Foundation

func message(_ id: Int, _ text: String, clientID: String? = nil) -> ChatMessage {
    ChatMessage(
        id: id, authorId: 1, nickname: "user", text: text,
        imageDataURL: "", avatarDataURL: "", reactions: [],
        clientMessageID: clientID
    )
}

let optimistic = message(-1, "new local", clientID: "pending")
let oldHistory = [message(7, "old 1"), message(8, "old 2")]
let normalizedBootstrap = ChatTimelinePolicy.normalized([optimistic] + oldHistory)
precondition(normalizedBootstrap.map(\.text) == ["old 1", "old 2", "new local"])

let outOfOrderLive = ChatTimelinePolicy.normalized([
    message(12, "later frame"), message(10, "earlier frame"), message(11, "middle frame")
])
precondition(outOfOrderLive.map(\.id) == [10, 11, 12])

let twoPending = ChatTimelinePolicy.normalized([
    message(-1, "pending 1", clientID: "p1"),
    message(-2, "pending 2", clientID: "p2"),
    message(20, "history")
])
precondition(twoPending.map(\.text) == ["history", "pending 1", "pending 2"])

print("Chat timeline policy tests passed")
