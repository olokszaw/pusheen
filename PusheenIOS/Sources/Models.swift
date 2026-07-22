import Foundation

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

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: Int; let authorId: Int; let nickname: String; let text: String; let imageDataURL: String; var reactions: [ChatReaction]
    enum CodingKeys: String, CodingKey { case id, nickname, text, reactions; case authorId = "author_id"; case imageDataURL = "image_data_url" }
}

struct RoomMember: Codable, Identifiable, Hashable {
    let userId: Int; let username: String; let nickname: String; let avatarDataURL: String; let isOwner: Bool; let isOnline: Bool
    var id: Int { userId }
    enum CodingKeys: String, CodingKey { case username, nickname; case userId = "user_id"; case avatarDataURL = "avatar_data_url"; case isOwner = "is_owner"; case isOnline = "is_online" }
}

struct VideoStream: Codable, Hashable {
    let url: String; let title: String; let durationSeconds: Double; let quality: String; let sourceType: String; let thumbnail: String
    enum CodingKeys: String, CodingKey { case url, title, quality, thumbnail; case durationSeconds = "duration_seconds"; case sourceType = "source_type" }
}

struct FriendProfile: Codable, Identifiable, Hashable {
    let userId: Int; let username: String; let nickname: String; let avatarDataURL: String; let isFriend: Bool
    var id: Int { userId }
    enum CodingKeys: String, CodingKey { case username, nickname; case userId = "user_id"; case avatarDataURL = "avatar_data_url"; case isFriend = "is_friend" }
}
