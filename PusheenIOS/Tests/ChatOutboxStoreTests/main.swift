import Foundation

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("chat-outbox-tests-\(UUID().uuidString)", isDirectory: true)
let store = ChatOutboxStore(directory: root)
let reply = ChatReplyPreview(id: 9, authorId: 2, nickname: "Друг", text: "Исходное", hasImage: false)
let first = ChatOutboxItem(
    id: "client-1", localMessageID: -1, text: "Не пропадай", image: "",
    replyTo: reply, authorID: 1, nickname: "Я", avatarDataURL: "", createdAt: "2026-08-26T00:00:00Z"
)
let second = ChatOutboxItem(
    id: "client-2", localMessageID: -2, text: "Второе", image: "data:image/jpeg;base64,AA==",
    replyTo: nil, authorID: 1, nickname: "Я", avatarDataURL: "avatar", createdAt: "2026-08-26T00:00:01Z"
)

store.replace([first, second], roomID: 7, userID: 1)
store.flushWrites()
precondition(store.load(roomID: 7, userID: 1) == [first, second])
precondition(store.load(roomID: 7, userID: 2).isEmpty, "Outboxes must be isolated per account")

store.replace([second], roomID: 7, userID: 1)
store.flushWrites()
precondition(store.load(roomID: 7, userID: 1) == [second])

store.replace([], roomID: 7, userID: 1)
store.flushWrites()
precondition(store.load(roomID: 7, userID: 1).isEmpty)

let optimistic = ChatMessage(id: -1, authorId: 1, nickname: "Я", text: "Тест", imageDataURL: "", avatarDataURL: "", reactions: [], clientMessageID: "same-send")
let persisted = ChatMessage(id: 42, authorId: 1, nickname: "Я", text: "Тест", imageDataURL: "", avatarDataURL: "", reactions: [], clientMessageID: "same-send")
precondition(optimistic.timelineID == persisted.timelineID, "Acknowledgement must preserve SwiftUI row identity")
precondition(persisted.timelineID != ChatMessage(id: 43, authorId: 2, nickname: "Друг", text: "Другое", imageDataURL: "", avatarDataURL: "", reactions: []).timelineID)

try? FileManager.default.removeItem(at: root)
print("Chat outbox store tests passed")
