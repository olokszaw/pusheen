/// Converts a public VK Video page URL into VK's official embed player URL.
/// We never download, proxy or extract the media stream on our backend.
class VkVideo {
  final String ownerId;
  final String videoId;
  const VkVideo(this.ownerId, this.videoId);

  static VkVideo? parse(String url) {
    final value = url.trim();
    final match = RegExp(
      r'^https://(?:(?:m\.)?vkvideo\.ru|(?:m\.)?vk\.com)/video(-?\d+)_(\d+)(?:[/?#].*)?$',
    ).firstMatch(value);
    if (match != null) {
      return VkVideo(match.group(1)!, match.group(2)!);
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.host == 'vk.com' || uri.host == 'www.vk.com')) {
      return null;
    }
    final embedded = RegExp(r'^video(-?\d+)_(\d+)')
        .firstMatch(uri.queryParameters['z'] ?? '');
    return embedded == null
        ? null
        : VkVideo(embedded.group(1)!, embedded.group(2)!);
  }

  String get embedUrl =>
      'https://vk.com/video_ext.php?oid=$ownerId&id=$videoId&hd=2&autoplay=0';
}
