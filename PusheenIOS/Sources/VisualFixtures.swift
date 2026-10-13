#if DEBUG
import Foundation

/// Local simulator data only. This file and its launch flag are absent in IPA Release.
enum VisualFixtures {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--ui-fixtures") }
    static var emptyFriends: Bool { ProcessInfo.processInfo.arguments.contains("--ui-fixtures-empty-friends") }
    static let profile = Profile(userId: 1, username: "alex", nickname: "Алекс", avatarDataUrl: "")
    static let rooms = [
        Room(id: 1, owner: 1, ownerName: "Алекс", title: "Вечерний просмотр", inviteCode: "A7K2M", mediaURL: "", thumbnailURL: "", membersCount: 3, playback: nil),
        Room(id: 2, owner: 1, ownerName: "Алекс", title: "Короткометражки", inviteCode: "D4F8R", mediaURL: "", thumbnailURL: "", membersCount: 2, playback: nil),
        Room(id: 3, owner: 2, ownerName: "Маша", title: "Видео из галереи", inviteCode: "H9B3C", mediaURL: "", thumbnailURL: "", membersCount: 4, playback: nil),
    ]
    static let friends = [
        FriendProfile(userId: 2, username: "masha", nickname: "Маша", avatarDataURL: "", isFriend: true, isOnline: true, lastSeen: nil, lastSeenAgeSeconds: nil, activityVisible: true),
        FriendProfile(userId: 3, username: "nikita", nickname: "Никита", avatarDataURL: "", isFriend: true, isOnline: false, lastSeen: nil, lastSeenAgeSeconds: 120, activityVisible: true),
        FriendProfile(userId: 4, username: "anna", nickname: "Анна", avatarDataURL: "", isFriend: true, isOnline: false, lastSeen: nil, lastSeenAgeSeconds: 3000, activityVisible: true),
    ]
    static let stats = ViewingStats(appSeconds: 21000, watchedSeconds: 18000, longestMovieSeconds: 7200,
        genres: [ViewingGenre(name: "Драма", seconds: 10800, percent: 60), ViewingGenre(name: "Комедия", seconds: 5400, percent: 30), ViewingGenre(name: "Документальное", seconds: 1800, percent: 10)],
        dailySeconds: history, monthIncreasePercentage: nil, currentStreakDays: 2,
        topCompanion: ViewingCompanion(userId: 2, username: "masha", nickname: "Маша", avatarDataURL: "", seconds: 7200))
    static let history: [String: Int] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let values = [(0, 3600), (1, 900), (3, 2400), (8, 1800), (13, 1200), (21, 600), (28, 2400), (32, 900), (40, 1800), (52, 2400)]
        return Dictionary(uniqueKeysWithValues: values.compactMap { offset, seconds in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return (String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0), seconds)
        })
    }()
    static let messages = [
        ChatMessage(id: 1, authorId: 2, nickname: "Маша", text: "На какой минуте остановились?", imageDataURL: "", avatarDataURL: "", reactions: [], createdAtAgeSeconds: 240),
        ChatMessage(id: 2, authorId: 1, nickname: "Алекс", text: "На двенадцатой. Сейчас включу", imageDataURL: "", avatarDataURL: "", reactions: [ChatReaction(emoji: "👍", count: 1, reacted: false)], createdAtAgeSeconds: 200),
        ChatMessage(id: 3, authorId: 3, nickname: "Никита", text: "Я готов", imageDataURL: "", avatarDataURL: "", reactions: [], createdAtAgeSeconds: 120),
    ]
    static let members = [
        RoomMember(userId: 1, username: "alex", nickname: "Алекс", avatarDataURL: "", isOwner: true, isOnline: true),
        RoomMember(userId: 2, username: "masha", nickname: "Маша", avatarDataURL: "", isOwner: false, isOnline: true),
        RoomMember(userId: 3, username: "nikita", nickname: "Никита", avatarDataURL: "", isOwner: false, isOnline: true),
    ]
}
#endif
