/// Converts a public VK Video page URL into VK's official embed player URL.
/// We never download, proxy or extract the media stream on our backend.
class VkVideo {
  final String ownerId;
  final String videoId;
  const VkVideo(this.ownerId, this.videoId);

  static VkVideo? parse(String url) {
    final match =
        RegExp(r'^https://(?:m\.)?vkvideo\.ru/video(-?\d+)_(\d+)(?:\?.*)?$')
            .firstMatch(url.trim());
    return match == null ? null : VkVideo(match.group(1)!, match.group(2)!);
  }

  String get embedUrl =>
      'https://vk.com/video_ext.php?oid=$ownerId&id=$videoId&hd=2&autoplay=0';
}
