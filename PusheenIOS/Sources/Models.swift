import Foundation

struct MovieCatalogItem: Codable, Identifiable, Hashable {
    let trackId: Int?
    let trackName: String?
    let kind: String?
    let artworkUrl100: String?
    let longDescription: String?
    let shortDescription: String?
    let releaseDate: String?
    let primaryGenreName: String?
    let trackViewUrl: String?

    var id: String { "\(trackId ?? 0)-\(trackName ?? "unknown")" }
    var title: String { trackName ?? "Без названия" }
    var description: String { longDescription ?? shortDescription ?? "Описание пока недоступно." }
    var year: String { releaseDate.map { String($0.prefix(4)) } ?? "" }
}

struct MovieCatalogResponse: Codable { let results: [MovieCatalogItem] }

struct Profile: Codable, Identifiable, Equatable {
    let userId: Int
    var username: String
    var nickname: String
    var avatarDataUrl: String
    var id: Int { userId }
    enum CodingKeys: String, CodingKey { case userId = "user_id", username, nickname, avatarDataUrl = "avatar_data_url" }
}

struct AuthPayload: Codable { let token: String; let userId: Int; let username: String; let nickname: String; let avatarDataUrl: String
    enum CodingKeys: String, CodingKey { case token; case userId = "user_id"; case username, nickname; case avatarDataUrl = "avatar_data_url" }
    var profile: Profile { Profile(userId: userId, username: username, nickname: nickname, avatarDataUrl: avatarDataUrl) }
}

struct Playback: Codable, Hashable { var isPlaying: Bool; var positionSeconds: Double
    enum CodingKeys: String, CodingKey { case isPlaying = "is_playing", positionSeconds = "position_seconds" }
}

struct Room: Codable, Identifiable, Hashable {
    let id: Int
    let owner: Int
    let ownerName: String
    let title: String
    let inviteCode: String
    let mediaURL: String
    let thumbnailURL: String
    let membersCount: Int
    let playback: Playback?
    enum CodingKeys: String, CodingKey { case id, owner, title, playback; case ownerName = "owner_name"; case inviteCode = "invite_code"; case mediaURL = "media_url"; case thumbnailURL = "thumbnail_url"; case membersCount = "members_count" }
}

struct ChatReaction: Codable, Hashable, Identifiable {
    let emoji: String; let count: Int; let reacted: Bool
    var id: String { emoji }
}

struct ChatReplyPreview: Codable, Hashable, Identifiable {
    let id: Int
    let authorId: Int
    let nickname: String
    let text: String
    let hasImage: Bool
    enum CodingKeys: String, CodingKey {
        case id, nickname, text
        case authorId = "author_id"
        case hasImage = "has_image"
    }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: Int; let authorId: Int; let nickname: String; let text: String; let imageDataURL: String; let avatarDataURL: String; var reactions: [ChatReaction]; var replyTo: ChatReplyPreview? = nil; var createdAt: String? = nil; var clientMessageID: String? = nil; var isSystem: Bool = false
    enum CodingKeys: String, CodingKey { case id, nickname, text, reactions; case authorId = "author_id"; case imageDataURL = "image_data_url"; case avatarDataURL = "avatar_data_url"; case replyTo = "reply_to"; case createdAt = "created_at"; case clientMessageID = "client_message_id" }
}

struct RoomMember: Codable, Identifiable, Hashable {
    let userId: Int; let username: String; let nickname: String; let avatarDataURL: String; let isOwner: Bool; let isOnline: Bool; let isMuted: Bool
    var id: Int { userId }
    enum CodingKeys: String, CodingKey { case username, nickname; case userId = "user_id"; case avatarDataURL = "avatar_data_url"; case isOwner = "is_owner"; case isOnline = "is_online"; case isMuted = "is_muted" }
    init(userId: Int, username: String, nickname: String, avatarDataURL: String, isOwner: Bool, isOnline: Bool, isMuted: Bool = false) { self.userId = userId; self.username = username; self.nickname = nickname; self.avatarDataURL = avatarDataURL; self.isOwner = isOwner; self.isOnline = isOnline; self.isMuted = isMuted }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userId = try values.decode(Int.self, forKey: .userId)
        username = try values.decode(String.self, forKey: .username)
        nickname = try values.decode(String.self, forKey: .nickname)
        avatarDataURL = try values.decodeIfPresent(String.self, forKey: .avatarDataURL) ?? ""
        isOwner = try values.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        isOnline = try values.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
        // Lets a freshly built IPA still open a room while an old backend is
        // being replaced; the new server always supplies this field.
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
    }
}

struct VideoStream: Codable, Hashable {
    let url: String; let title: String; let durationSeconds: Double; let quality: String; let sourceType: String; let thumbnail: String; let headers: [String: String]; let genres: [String]
    enum CodingKeys: String, CodingKey { case url, title, quality, thumbnail, headers, genres; case durationSeconds = "duration_seconds"; case sourceType = "source_type" }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decode(String.self, forKey: .url)
        title = try values.decode(String.self, forKey: .title)
        durationSeconds = try values.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        quality = try values.decodeIfPresent(String.self, forKey: .quality) ?? "MP4"
        sourceType = try values.decodeIfPresent(String.self, forKey: .sourceType) ?? "video"
        thumbnail = try values.decodeIfPresent(String.self, forKey: .thumbnail) ?? ""
        headers = try values.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        genres = try values.decodeIfPresent([String].self, forKey: .genres) ?? []
    }
}

struct ViewingGenre: Codable, Hashable, Identifiable {
    let name: String
    let seconds: Int
    let percent: Int
    var id: String { name }
}

struct ViewingCompanion: Codable, Hashable, Identifiable {
    let userId: Int
    let username: String
    let nickname: String
    let avatarDataURL: String
    let seconds: Int
    var id: Int { userId }
    enum CodingKeys: String, CodingKey {
        case username, nickname, seconds
        case userId = "user_id"
        case avatarDataURL = "avatar_data_url"
    }
}

struct ViewingStats: Codable, Hashable {
    let appSeconds: Int
    let watchedSeconds: Int
    let longestMovieSeconds: Int
    let genres: [ViewingGenre]
    let dailySeconds: [String: Int]
    let monthIncreasePercentage: Int?
    let currentStreakDays: Int?
    let topCompanion: ViewingCompanion?
    enum CodingKeys: String, CodingKey {
        case genres
        case appSeconds = "app_seconds"
        case watchedSeconds = "watched_seconds"
        case longestMovieSeconds = "longest_movie_seconds"
        case dailySeconds = "daily_seconds"
        case monthIncreasePercentage = "month_increase_percent"
        case currentStreakDays = "current_streak_days"
        case topCompanion = "top_companion"
    }
}

struct FriendProfile: Codable, Identifiable, Hashable {
    let userId: Int; let username: String; let nickname: String; let avatarDataURL: String; let isFriend: Bool
    let isOnline: Bool?; let lastSeen: String?; let lastSeenAgeSeconds: Int?; let activityVisible: Bool?
    let presenceSnapshotReceivedAt = Date()
    var id: Int { userId }
    enum CodingKeys: String, CodingKey { case username, nickname; case userId = "user_id"; case avatarDataURL = "avatar_data_url"; case isFriend = "is_friend"; case isOnline = "is_online"; case lastSeen = "last_seen"; case lastSeenAgeSeconds = "last_seen_age_seconds"; case activityVisible = "activity_visible" }
}

struct CurrentWatching: Codable, Hashable {
    let title: String
    let thumbnailURL: String
    let durationSeconds: Double
    let positionSeconds: Double
    let isPlaying: Bool
    let serverUpdatedAt: String
    let previewURL: String
    let headers: [String: String]
    let sourceType: String
    // The backend already projects `positionSeconds` to the instant when its
    // response is built. Continue that clock from the instant this iPhone
    // decoded the response, not from the backend wall clock: the VPS and the
    // phone may use different/misconfigured clocks and must not push a short
    // video straight to its final frame.
    let playbackSnapshotReceivedAt = Date()
    enum CodingKeys: String, CodingKey {
        case title, headers
        case thumbnailURL = "thumbnail_url"
        case durationSeconds = "duration_seconds"
        case positionSeconds = "position_seconds"
        case isPlaying = "is_playing"
        case serverUpdatedAt = "server_updated_at"
        case previewURL = "preview_url"
        case sourceType = "source_type"
    }
}

/// Advances a public watch preview from the instant the response reached this
/// device. Server timestamps are deliberately not an input: a VPS clock skew
/// must never be interpreted as elapsed media time.
func projectedCurrentWatchingPosition(
    positionSeconds: Double,
    isPlaying: Bool,
    receivedAt: Date,
    now: Date,
    durationSeconds: Double
) -> Double {
    var position = positionSeconds.isFinite ? max(0, positionSeconds) : 0
    if isPlaying {
        position += max(0, now.timeIntervalSince(receivedAt))
    }
    if durationSeconds.isFinite, durationSeconds > 0 {
        return min(position, max(0, durationSeconds - 0.05))
    }
    return position
}

struct PublicUserProfile: Codable, Identifiable, Hashable {
    let userId: Int
    let username: String
    let nickname: String
    let avatarDataURL: String
    let isFriend: Bool
    let analyticsVisible: Bool
    let stats: ViewingStats?
    let isOnline: Bool?
    let lastSeen: String?
    let lastSeenAgeSeconds: Int?
    let activityVisible: Bool?
    let nowWatching: CurrentWatching?
    let presenceSnapshotReceivedAt = Date()
    var id: Int { userId }
    enum CodingKeys: String, CodingKey {
        case username, nickname, stats
        case userId = "user_id"
        case avatarDataURL = "avatar_data_url"
        case isFriend = "is_friend"
        case analyticsVisible = "analytics_visible"
        case isOnline = "is_online"
        case lastSeen = "last_seen"
        case lastSeenAgeSeconds = "last_seen_age_seconds"
        case activityVisible = "activity_visible"
        case nowWatching = "now_watching"
    }
}

struct RoomInvitationSender: Codable, Hashable {
    let userId: Int
    let username: String
    let nickname: String
    let avatarDataURL: String
    let isOnline: Bool?
    let lastSeen: String?
    let lastSeenAgeSeconds: Int?
    let activityVisible: Bool?
    let presenceSnapshotReceivedAt = Date()
    enum CodingKeys: String, CodingKey {
        case username, nickname
        case userId = "user_id"
        case avatarDataURL = "avatar_data_url"
        case isOnline = "is_online"
        case lastSeen = "last_seen"
        case lastSeenAgeSeconds = "last_seen_age_seconds"
        case activityVisible = "activity_visible"
    }
}

struct RoomInvitationRoom: Codable, Hashable {
    let id: Int
    let title: String
    let thumbnailURL: String
    let inviteCode: String
    enum CodingKeys: String, CodingKey {
        case id, title
        case thumbnailURL = "thumbnail_url"
        case inviteCode = "invite_code"
    }
}

struct RoomInvitation: Codable, Identifiable, Hashable {
    let id: Int
    let status: String
    let createdAt: String
    let sender: RoomInvitationSender
    let room: RoomInvitationRoom
    enum CodingKeys: String, CodingKey { case id, status, sender, room; case createdAt = "created_at" }
}

struct RoomInvitationResponse: Codable { let status: String; let room: Room? }

struct FriendRequestProfile: Codable, Identifiable, Hashable {
    let id: Int
    let userId: Int
    let username: String
    let nickname: String
    let avatarDataURL: String
    enum CodingKeys: String, CodingKey {
        case id, username, nickname
        case userId = "user_id"
        case avatarDataURL = "avatar_data_url"
    }
}

struct FriendRequestsResponse: Codable, Hashable {
    let incoming: [FriendRequestProfile]
    let outgoing: [FriendRequestProfile]
}

struct TelegramSticker: Codable, Identifiable, Hashable {
    let id: Int
    let emoji: String
    let format: String
    let fileURL: String
    let previewURL: String
    enum CodingKeys: String, CodingKey { case id, emoji, format; case fileURL = "file_url"; case previewURL = "preview_url" }
}

struct TelegramStickerPack: Codable, Identifiable, Hashable {
    let id: Int
    let shortName: String
    let title: String
    let stickers: [TelegramSticker]
    enum CodingKeys: String, CodingKey { case id, title, stickers; case shortName = "short_name" }
}
