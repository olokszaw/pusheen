/// Converts a public VK Video page URL into VK's official embed player URL.
/// We never download, proxy or extract the media stream on our backend.
class VkVideo {
  final String ownerId;
  final String videoId;
  const VkVideo(this.ownerId, this.videoId);

  static VkVideo? parse(String url) {
    final value = Uri.decodeFull(url.trim());
    final match = RegExp(
      r'^https://(?:m\.)?(?:vkvideo\.ru|vk\.com)/video(-?\d+)_(\d+)(?:\?.*)?$',
    ).firstMatch(value);
    if (match != null) {
      return VkVideo(match.group(1)!, match.group(2)!);
    }
    final uri = Uri.tryParse(value);
    final zValue = uri?.queryParameters['z'];
    final zMatch = zValue == null
        ? null
        : RegExp(r'^video(-?\d+)_(\d+)').firstMatch(zValue);
    if (zMatch != null &&
        (uri!.host == 'vk.com' || uri.host == 'm.vk.com')) {
      return VkVideo(zMatch.group(1)!, zMatch.group(2)!);
    }
    return null;
  }

  String get embedUrl =>
      'https://vk.com/video_ext.php?oid=$ownerId&id=$videoId&hd=2&autoplay=0';
}
