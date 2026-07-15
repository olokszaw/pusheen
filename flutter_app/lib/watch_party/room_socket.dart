import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'playback_state.dart';

class RoomSocket {
  final WebSocketChannel _channel;
  RoomSocket._(this._channel);

  factory RoomSocket.connect(
      {required String websocketBaseUrl,
      required int roomId,
      required String token}) {
    return RoomSocket._(WebSocketChannel.connect(
        Uri.parse('$websocketBaseUrl/ws/rooms/$roomId/?token=$token')));
  }

  Stream<Map<String, dynamic>> get events => _channel.stream
      .map((event) => jsonDecode(event as String) as Map<String, dynamic>);

  void ownerCommand(
      {required String action,
      required bool isPlaying,
      required double positionSeconds,
      String? vkVideoUrl}) {
    _channel.sink.add(jsonEncode({
      'type': 'playback_command',
      'action': action,
      'is_playing': isPlaying,
      'position_seconds': positionSeconds,
      if (vkVideoUrl != null) 'vk_video_url': vkVideoUrl
    }));
  }

  void sendChat(String text) =>
      _channel.sink.add(jsonEncode({'type': 'chat_message', 'text': text}));
  void requestState() =>
      _channel.sink.add(jsonEncode({'type': 'request_state'}));
  Future<void> close() => _channel.sink.close();
}

PlaybackState playbackFromEvent(Map<String, dynamic> event) {
  final receivedAt = DateTime.now();
  final serverUpdatedAt =
      DateTime.parse(event['server_updated_at'] as String).toUtc();
  final serverSentAt = DateTime.parse(
    event['server_sent_at'] as String? ?? event['server_updated_at'] as String,
  ).toUtc();
  final isPlaying = event['is_playing'] as bool;
  var position = (event['position_seconds'] as num).toDouble();
  if (isPlaying) {
    final elapsedOnServer = serverSentAt.difference(serverUpdatedAt);
    if (!elapsedOnServer.isNegative) {
      position += elapsedOnServer.inMilliseconds / 1000;
    }
  }
  return PlaybackState(
    isPlaying: isPlaying,
    positionSeconds: position,
    serverUpdatedAt: serverUpdatedAt,
    receivedAt: receivedAt,
    vkVideoUrl: event['vk_video_url'] as String? ?? '',
  );
}
