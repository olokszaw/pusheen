import Foundation

enum StickerRecentsStore {
    private static func key(userID: Int?) -> String {
        "pusheen.recent-stickers.\(userID.map { String($0) } ?? "anonymous")"
    }

    static func load(userID: Int?) -> [TelegramSticker] {
        guard let data = UserDefaults.standard.data(forKey: key(userID: userID)),
              let stickers = try? JSONDecoder().decode([TelegramSticker].self, from: data) else { return [] }
        return Array(stickers.prefix(30))
    }

    @discardableResult
    static func record(_ sticker: TelegramSticker, userID: Int?) -> [TelegramSticker] {
        var stickers = load(userID: userID)
        stickers.removeAll { $0.id == sticker.id }
        stickers.insert(sticker, at: 0)
        stickers = Array(stickers.prefix(30))
        if let data = try? JSONEncoder().encode(stickers) {
            UserDefaults.standard.set(data, forKey: key(userID: userID))
        }
        return stickers
    }
}
