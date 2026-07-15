class PlaybackState {
  final bool isPlaying;
  final double positionSeconds;
  final DateTime serverUpdatedAt;
  final DateTime receivedAt;
  final String vkVideoUrl;
  const PlaybackState(
      {required this.isPlaying,
      required this.positionSeconds,
      required this.serverUpdatedAt,
      required this.receivedAt,
      required this.vkVideoUrl});

  /// Uses elapsed time since receipt, so different client system clocks do not
  /// affect synchronization.
  double positionAt(DateTime now) => isPlaying
      ? positionSeconds + now.difference(receivedAt).inMilliseconds / 1000
      : positionSeconds;
}
