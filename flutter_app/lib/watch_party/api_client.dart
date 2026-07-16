import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../src/models/room.dart';

class ApiClient {
  static const _tokenKey = 'pulse_auth_token';
  static const _userIdKey = 'pulse_user_id';
  static const _usernameKey = 'pulse_username';
  static const _avatarKey = 'pulse_avatar';
  static const _defaultBaseUrl =
      'https://trio-anderson-istanbul-definition.trycloudflare.com';
  static const _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final String baseUrl;
  String? token;
  int? userId;
  String? username;
  String avatar = '';

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
    final savedAvatar = preferences.getString(_avatarKey) ?? '';
    if (savedToken == null || savedUserId == null || savedUsername == null) {
      return false;
    }
    token = savedToken;
    userId = savedUserId;
    username = savedUsername;
    avatar = savedAvatar;
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/profile/'),
        headers: headers,
      );
      final profile = _decodeMap(response);
      userId = profile['user_id'] as int;
      username = profile['username'] as String;
      avatar = profile['avatar'] as String? ?? '';
      await saveSession();
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await logout();
        return false;
      }
      rethrow;
    } catch (_) {
      // Keep a valid-looking local session when the server is temporarily
      // unreachable. Normal API calls will show the connectivity error.
      return true;
    }
  }

  Future<void> saveSession() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, token!);
    await preferences.setInt(_userIdKey, userId!);
    await preferences.setString(_usernameKey, username!);
    await preferences.setString(_avatarKey, avatar);
  }

  Future<void> logout() async {
    token = null;
    userId = null;
    username = null;
    avatar = '';
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    await preferences.remove(_userIdKey);
    await preferences.remove(_usernameKey);
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
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/demo-login/'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': name.trim(), 'client_id': clientId}),
    );
    final data = _decodeMap(response);
    token = data['token'] as String;
    userId = data['user_id'] as int;
    username = data['username'] as String;
    avatar = data['avatar'] as String? ?? '';
    await saveSession();
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
    avatar = data['avatar'] as String? ?? avatar;
    await saveSession();
  }

  Future<void> updateAvatar(String value) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/profile/'),
      headers: headers,
      body: jsonEncode({'avatar': value}),
    );
    final data = _decodeMap(response);
    avatar = data['avatar'] as String? ?? '';
    await saveSession();
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
    required String title,
    required String description,
    required String theme,
    required String videoUrl,
    required bool isPrivate,
    required bool allowGuestsControl,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/rooms/'),
      headers: headers,
      body: jsonEncode({
        'title': title,
        'description': description,
        'theme': theme,
        'vk_video_url': videoUrl,
        'is_private': isPrivate,
        'allow_guests_control': allowGuestsControl,
      }),
    );
    return RoomModel.fromJson(_decodeMap(response));
  }

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

  Future<VideoStreamModel> roomStream(int roomId, {String? quality}) async {
    final uri = Uri.parse('$baseUrl/api/rooms/$roomId/stream/').replace(
      queryParameters: quality == null ? null : {'quality': quality},
    );
    final response = await http.get(
      uri,
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
    final dynamic value = jsonDecode(utf8.decode(response.bodyBytes));
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

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}
