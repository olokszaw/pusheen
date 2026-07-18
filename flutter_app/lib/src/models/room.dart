import '../../watch_party/media_source.dart';

class RoomModel {
  final int id;
  final int ownerId;
  final String ownerName;
  final String title;
  final String description;
  final String theme;
  final String inviteCode;
  final String videoUrl;
  final MediaSourceType sourceType;
  final int membersCount;
  final bool isPrivate;

  const RoomModel({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.title,
    required this.description,
    required this.theme,
    required this.inviteCode,
    required this.videoUrl,
    required this.sourceType,
    required this.membersCount,
    required this.isPrivate,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'] as int,
      ownerId: json['owner'] as int,
      ownerName: json['owner_name'] as String? ?? 'Создатель',
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      theme: json['theme'] as String? ?? 'movie',
      inviteCode: json['invite_code'] as String,
      videoUrl:
          json['media_url'] as String? ?? json['vk_video_url'] as String? ?? '',
      sourceType: MediaSourceType.fromApi(
        json['source_type'] as String?,
        fallbackUrl: json['media_url'] as String? ??
            json['vk_video_url'] as String? ??
            '',
      ),
      membersCount: json['members_count'] as int? ?? 1,
      isPrivate: json['is_private'] as bool? ?? false,
    );
  }
}

class RoomMemberModel {
  final int userId;
  final String username;
  final String nickname;
  final String avatarDataUrl;
  final bool isOwner;
  final bool isOnline;

  const RoomMemberModel({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.avatarDataUrl,
    required this.isOwner,
    required this.isOnline,
  });

  factory RoomMemberModel.fromJson(Map<String, dynamic> json) {
    return RoomMemberModel(
      userId: json['user_id'] as int,
      username: json['username'] as String,
      nickname: json['nickname'] as String? ?? json['username'] as String,
      avatarDataUrl: json['avatar_data_url'] as String? ?? '',
      isOwner: json['is_owner'] as bool? ?? false,
      isOnline: json['is_online'] as bool? ?? false,
    );
  }

  RoomMemberModel copyWith(
      {String? username,
      String? nickname,
      String? avatarDataUrl,
      bool? isOnline}) {
    return RoomMemberModel(
      userId: userId,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatarDataUrl: avatarDataUrl ?? this.avatarDataUrl,
      isOwner: isOwner,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

class ChatMessageModel {
  final int id;
  final int authorId;
  final String author;
  final String nickname;
  final String avatarDataUrl;
  final String text;
  final String imageDataUrl;
  final List<MessageReactionModel> reactions;

  const ChatMessageModel({
    required this.id,
    required this.authorId,
    required this.author,
    required this.nickname,
    required this.avatarDataUrl,
    required this.text,
    required this.imageDataUrl,
    required this.reactions,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as int,
      authorId: json['author_id'] as int? ?? 0,
      author: json['author'] as String,
      nickname: json['nickname'] as String? ?? json['author'] as String,
      avatarDataUrl: json['avatar_data_url'] as String? ?? '',
      text: json['text'] as String,
      imageDataUrl: json['image_data_url'] as String? ?? '',
      reactions: (json['reactions'] as List<dynamic>? ?? const [])
          .map((item) =>
              MessageReactionModel.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MessageReactionModel {
  final String emoji;
  final int count;
  final bool reacted;

  const MessageReactionModel(
      {required this.emoji, required this.count, required this.reacted});

  factory MessageReactionModel.fromJson(Map<String, dynamic> json) =>
      MessageReactionModel(
        emoji: json['emoji'] as String,
        count: json['count'] as int? ?? 0,
        reacted: json['reacted'] as bool? ?? false,
      );
}

class VideoStreamModel {
  final String url;
  final String title;
  final double durationSeconds;
  final String quality;
  final Map<String, String> headers;
  final MediaSourceType sourceType;

  const VideoStreamModel({
    required this.url,
    required this.title,
    required this.durationSeconds,
    required this.quality,
    required this.headers,
    required this.sourceType,
  });

  factory VideoStreamModel.fromJson(Map<String, dynamic> json) {
    return VideoStreamModel(
      url: json['url'] as String,
      title: json['title'] as String? ?? 'VK Видео',
      durationSeconds: (json['duration_seconds'] as num? ?? 0).toDouble(),
      quality: json['quality'] as String? ?? 'MP4',
      headers: (json['headers'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, value.toString())),
      sourceType: MediaSourceType.fromApi(json['source_type'] as String?),
    );
  }
}
