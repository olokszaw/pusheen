class RoomModel {
  final int id;
  final int ownerId;
  final String ownerName;
  final String title;
  final String description;
  final String theme;
  final String inviteCode;
  final String videoUrl;
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
      videoUrl: json['vk_video_url'] as String? ?? '',
      membersCount: json['members_count'] as int? ?? 1,
      isPrivate: json['is_private'] as bool? ?? false,
    );
  }
}

class RoomMemberModel {
  final int userId;
  final String username;
  final bool isOwner;
  final bool isOnline;

  const RoomMemberModel({
    required this.userId,
    required this.username,
    required this.isOwner,
    required this.isOnline,
  });

  factory RoomMemberModel.fromJson(Map<String, dynamic> json) {
    return RoomMemberModel(
      userId: json['user_id'] as int,
      username: json['username'] as String,
      isOwner: json['is_owner'] as bool? ?? false,
      isOnline: json['is_online'] as bool? ?? false,
    );
  }

  RoomMemberModel copyWith({String? username, bool? isOnline}) {
    return RoomMemberModel(
      userId: userId,
      username: username ?? this.username,
      isOwner: isOwner,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

class ChatMessageModel {
  final int id;
  final String author;
  final String text;

  const ChatMessageModel({
    required this.id,
    required this.author,
    required this.text,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as int,
      author: json['author'] as String,
      text: json['text'] as String,
    );
  }
}

class VideoStreamModel {
  final String url;
  final String title;
  final double durationSeconds;
  final String quality;

  const VideoStreamModel({
    required this.url,
    required this.title,
    required this.durationSeconds,
    required this.quality,
  });

  factory VideoStreamModel.fromJson(Map<String, dynamic> json) {
    return VideoStreamModel(
      url: json['url'] as String,
      title: json['title'] as String? ?? 'VK Видео',
      durationSeconds: (json['duration_seconds'] as num? ?? 0).toDouble(),
      quality: json['quality'] as String? ?? 'MP4',
    );
  }
}
