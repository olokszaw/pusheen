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
let normalizedBootstrap = ChatTimelinePolicy.prependingHistory(oldHistory, to: [optimistic])
precondition(normalizedBootstrap.map(\.text) == ["old 1", "old 2", "new local"])

let outOfOrderLive = ChatTimelinePolicy.prependingHistory(
    [message(12, "later frame"), message(10, "earlier frame"), message(11, "middle frame")],
    to: []
)
precondition(outOfOrderLive.map(\.id) == [10, 11, 12])

let twoPending = ChatTimelinePolicy.prependingHistory([message(20, "history")], to: [
    message(-1, "pending 1", clientID: "p1"),
    message(-2, "pending 2", clientID: "p2")
])
precondition(twoPending.map(\.text) == ["history", "pending 1", "pending 2"])

var joinedNotice = message(-100, "joined")
joinedNotice.isSystem = true
let beforeAcknowledgement = [message(20, "history"), joinedNotice, optimistic]
let afterAcknowledgement = ChatTimelinePolicy.insertingPersisted(
    message(21, "new local", clientID: "pending"),
    into: Array(beforeAcknowledgement.dropLast())
)
precondition(
    afterAcknowledgement.map(\.text) == ["history", "joined", "new local"],
    "An old join notice must not move below every newly acknowledged message"
)

let repairedGap = ChatTimelinePolicy.insertingPersisted(
    message(11, "missed"),
    into: [message(10, "first"), joinedNotice, message(12, "newer")]
)
precondition(repairedGap.map(\.text) == ["first", "joined", "missed", "newer"])

precondition(!ChatTimelinePolicy.shouldAppendPresenceNotice(
    userID: 7, currentUserID: 7, changed: true,
    previousOnline: false, isOnline: true
), "A participant must never receive a notice about their own room opening")
precondition(ChatTimelinePolicy.shouldAppendPresenceNotice(
    userID: 7, currentUserID: 8, changed: true,
    previousOnline: false, isOnline: true
))
precondition(!ChatTimelinePolicy.shouldAppendPresenceNotice(
    userID: 7, currentUserID: 8, changed: true,
    previousOnline: true, isOnline: true
), "A repeated online snapshot is not another join")

print("Chat timeline policy tests passed")
