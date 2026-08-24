import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/models/room.dart';
import 'media_source.dart';

class ApiClient {
  static const _sessionCheckTimeout = Duration(seconds: 10);
  static const _loginTimeout = Duration(seconds: 15);
  static const _tokenKey = 'pulse_auth_token';
  static const _userIdKey = 'pulse_user_id';
  static const _usernameKey = 'pulse_username';
  static const _nicknameKey = 'pulse_nickname';
  static const _avatarKey = 'pulse_avatar';
  static const _defaultBaseUrl = 'https://pulse.izanagi.online';
  static const _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final String baseUrl;
  String? token;
  int? userId;
  String? username;
  String? nickname;
  String? avatarDataUrl;

  ApiClient({String? baseUrl})
      : baseUrl = (baseUrl ?? _configuredBaseUrl).trim().isEmpty
            ? _defaultBaseUrl
            : (baseUrl ?? _configuredBaseUrl).trim();

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Token $token',
      };

  String get websocketBaseUrl => baseUrl
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://');

  Future<bool> restoreSession() async {
    final preferences = await SharedPreferences.getInstance();
    final savedToken = preferences.getString(_tokenKey);
    final savedUserId = preferences.getInt(_userIdKey);
    final savedUsername = preferences.getString(_usernameKey);
    final savedNickname = preferences.getString(_nicknameKey);
    if (savedToken == null || savedUserId == null || savedUsername == null) {
      return false;
    }
    token = savedToken;
    userId = savedUserId;
    username = savedUsername;
    nickname = savedNickname ?? savedUsername;
    avatarDataUrl = preferences.getString(_avatarKey) ?? '';
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/profile/'),
            headers: headers,
          )
          .timeout(_sessionCheckTimeout);
      final data = _decodeMap(response);
      userId = data['user_id'] as int;
      username = data['username'] as String;
      nickname = data['nickname'] as String? ?? username;
      avatarDataUrl = data['avatar_data_url'] as String? ?? '';
      await saveSession();
      return true;
    } on Object {
      await logout();
      return false;
    }
  }

  Future<void> saveSession() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, token!);
    await preferences.setInt(_userIdKey, userId!);
    await preferences.setString(_usernameKey, username!);
    await preferences.setString(_nicknameKey, nickname ?? username!);
    await preferences.setString(_avatarKey, avatarDataUrl ?? '');
  }

  Future<void> logout() async {
    token = null;
    userId = null;
    username = null;
    nickname = null;
    avatarDataUrl = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    await preferences.remove(_userIdKey);
    await preferences.remove(_usernameKey);
    await preferences.remove(_nicknameKey);
    await preferences.remove(_avatarKey);
  }

  Future<void> login(String name) async {
    final preferences = await SharedPreferences.getInstance();
    var clientId = preferences.getString('pulse_client_id');
    if (clientId == null) {
      final random = Random.secure();
      clientId = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
          '${List.generate(8, (_) => random.nextInt(1 << 16).toRadixString(36).padLeft(4, '0')).join()}';
      await preferences.setString('pulse_client_id', clientId);
    }
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/demo-login/'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'username': name.trim(), 'client_id': clientId}),
        )
        .timeout(_loginTimeout);
    final data = _decodeMap(response);
    token = data['token'] as String;
    userId = data['user_id'] as int;
    username = data['username'] as String;
    nickname = data['nickname'] as String? ?? username;
    avatarDataUrl = data['avatar_data_url'] as String? ?? '';
    await saveSession();
  }

  Future<bool> usernameAvailable(String value) async {
    final response = await http.get(
        Uri.parse(
            '$baseUrl/api/auth/username-available/?username=${Uri.encodeQueryComponent(value.trim())}'),
        headers: headers);
    return _decodeMap(response)['available'] as bool? ?? false;
  }

  Future<void> register(
      {required String nickname,
      required String username,
      required String password}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register/'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'nickname': nickname.trim(),
            'username': username.trim(),
            'password': password
          }),
        )
        .timeout(_loginTimeout);
    _applyAuth(_decodeMap(response));
    await saveSession();
  }

  Future<void> accountLogin(
      {required String username, required String password}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login/'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username.trim(), 'password': password}),
        )
        .timeout(_loginTimeout);
    _applyAuth(_decodeMap(response));
    await saveSession();
  }

  void _applyAuth(Map<String, dynamic> data) {
    token = data['token'] as String;
    userId = data['user_id'] as int;
    username = data['username'] as String;
    nickname = data['nickname'] as String? ?? username;
    avatarDataUrl = data['avatar_data_url'] as String? ?? '';
  }

  Future<void> updateUsername(String value) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/profile/'),
      headers: headers,
      body: jsonEncode({'username': value.trim()}),
    );
    final data = _decodeMap(response);
    userId = data['user_id'] as int;
    username = data['username'] as String;
    await saveSession();
  }

  Future<void> updateProfile({String? nickname, String? avatarDataUrl}) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/profile/'),
      headers: headers,
      body: jsonEncode({
        if (nickname != null) 'nickname': nickname.trim(),
        if (avatarDataUrl != null) 'avatar_data_url': avatarDataUrl
      }),
    );
    final data = _decodeMap(response);
    userId = data['user_id'] as int;
    username = data['username'] as String;
    this.nickname = data['nickname'] as String? ?? username;
    this.avatarDataUrl = data['avatar_data_url'] as String? ?? '';
    await saveSession();
  }

  Future<List<FriendProfile>> friends({String? username}) async {
    final suffix = username == null || username.trim().isEmpty
        ? ''
        : '?username=${Uri.encodeQueryComponent(username.trim())}';
    final response = await http.get(
      Uri.parse('$baseUrl/api/friends/$suffix'),
      headers: headers,
    );
    final data = _decode(response) as List<dynamic>;
    return data
        .map((item) => FriendProfile.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<FriendProfile> addFriend(String username) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/friends/'),
      headers: headers,
      body: jsonEncode({'username': username.trim()}),
    );
    return FriendProfile.fromJson(_decodeMap(response));
  }

  Future<void> removeFriend(String username) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/friends/'),
      headers: headers,
      body: jsonEncode({'username': username.trim()}),
    );
    if (response.statusCode != 204) _decodeMap(response);
  }

  Future<List<RoomModel>> rooms() async {
    final response =
        await http.get(Uri.parse('$baseUrl/api/rooms/'), headers: headers);
    final data = _decode(response) as List<dynamic>;
    return data
        .map((item) => RoomModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<RoomModel> createRoom({
    required String videoUrl,
    required MediaSourceType sourceType,
    required bool isPrivate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/rooms/'),
      headers: headers,
      body: jsonEncode({
        'title': '',
        'vk_video_url': videoUrl,
        'media_url': videoUrl,
        'source_type': sourceType.apiValue,
        'is_private': isPrivate,
      }),
    );
    return RoomModel.fromJson(_decodeMap(response));
  }

  Future<RoomModel> uploadRoomVideo({
    required int roomId,
    required XFile video,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/rooms/$roomId/upload/'),
    );
    if (token != null) request.headers['Authorization'] = 'Token $token';
    request.files.add(http.MultipartFile(
      'video',
      http.ByteStream(video.openRead()),
      await video.length(),
      filename: video.name,
      contentType: MediaType.parse(video.mimeType ?? 'video/mp4'),
    ));
    final response = await http.Response.fromStream(await request.send());
    return RoomModel.fromJson(_decodeMap(response));
  }

  String roomInviteUrl(String inviteCode) =>
      '$baseUrl/join/${Uri.encodeComponent(inviteCode.toUpperCase())}';

  Future<RoomModel> joinRoom(String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/rooms/join/'),
      headers: headers,
      body: jsonEncode({'invite_code': code.trim().toUpperCase()}),
    );
    return RoomModel.fromJson(_decodeMap(response));
  }

  Future<List<RoomMemberModel>> roomMembers(int roomId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/rooms/$roomId/members/'),
      headers: headers,
    );
    final data = _decode(response) as List<dynamic>;
    return data
        .map((item) => RoomMemberModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<VideoStreamModel> roomStream(int roomId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/rooms/$roomId/stream/'),
      headers: headers,
    );
    return VideoStreamModel.fromJson(_decodeMap(response));
  }

  Future<List<ChatMessageModel>> roomMessages(int roomId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/rooms/$roomId/messages/'),
      headers: headers,
    );
    final data = _decode(response) as List<dynamic>;
    return data
        .map((item) => ChatMessageModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  dynamic _decode(http.Response response) {
    final body = utf8.decode(response.bodyBytes).trim();
    dynamic value;
    try {
      value = jsonDecode(body);
    } on FormatException {
      final normalizedBody = body.toLowerCase();
      final isHtml = normalizedBody.startsWith('<!doctype html') ||
          normalizedBody.startsWith('<html');
      final message = isHtml
          ? response.statusCode == 404
              ? 'Сервер ещё не обновлён: нужный API-адрес не найден.'
              : 'Сервер вернул веб-страницу вместо ответа приложения.'
          : 'Сервер вернул некорректный ответ.';
      throw ApiException(response.statusCode, message);
    }
    if (response.statusCode >= 400) {
      final detail = value is Map
          ? value['detail']?.toString() ?? value.toString()
          : value.toString();
      throw ApiException(response.statusCode, detail);
    }
    return value;
  }

  Map<String, dynamic> _decodeMap(http.Response response) =>
      _decode(response) as Map<String, dynamic>;
}

class FriendProfile {
  final int userId;
  final String username;
  final String nickname;
  final String avatarDataUrl;
  final bool isFriend;

  const FriendProfile({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.avatarDataUrl,
    required this.isFriend,
  });

  factory FriendProfile.fromJson(Map<String, dynamic> json) => FriendProfile(
        userId: json['user_id'] as int,
        username: json['username'] as String,
        nickname: json['nickname'] as String? ?? json['username'] as String,
        avatarDataUrl: json['avatar_data_url'] as String? ?? '',
        isFriend: json['is_friend'] as bool? ?? false,
      );
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}
