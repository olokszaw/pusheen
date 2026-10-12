#if DEBUG
import Foundation

/// Local simulator data only. This file and its launch flag are absent in IPA Release.
enum VisualFixtures {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--ui-fixtures") }
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
        dailySeconds: [:], monthIncreasePercentage: 0, currentStreakDays: 0,
        topCompanion: ViewingCompanion(userId: 2, username: "masha", nickname: "Маша", avatarDataURL: "", seconds: 7200))
}
#endif
