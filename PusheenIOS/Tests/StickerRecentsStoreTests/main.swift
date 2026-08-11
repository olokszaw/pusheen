import Foundation

func sticker(_ id: Int) -> TelegramSticker {
    TelegramSticker(id: id, emoji: "", format: "static", fileURL: "/file/\(id)", previewURL: "/preview/\(id)")
}

let isolatedUserID = 9_876_543
for id in 1...32 {
    StickerRecentsStore.record(sticker(id), userID: isolatedUserID)
}

var loaded = StickerRecentsStore.load(userID: isolatedUserID)
precondition(loaded.count == 30, "Recent stickers must be capped at 30")
precondition(loaded.first?.id == 32 && loaded.last?.id == 3, "Newest sticker must be first")

StickerRecentsStore.record(sticker(12), userID: isolatedUserID)
loaded = StickerRecentsStore.load(userID: isolatedUserID)
precondition(loaded.first?.id == 12, "Reused sticker must move to the front")
precondition(loaded.filter { $0.id == 12 }.count == 1, "Recent stickers must not duplicate")

print("Sticker recents tests passed")
