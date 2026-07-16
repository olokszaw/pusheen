enum MediaSourceType {
  vk('vk'),
  web('web');

  final String apiValue;
  const MediaSourceType(this.apiValue);

  static MediaSourceType fromApi(String? value, {String fallbackUrl = ''}) {
    if (value == web.apiValue) return web;
    if (value == vk.apiValue) return vk;
    return detect(fallbackUrl);
  }

  static MediaSourceType detect(String value) {
    final uri = Uri.tryParse(value.trim());
    final host = uri?.host.toLowerCase() ?? '';
    final isVkHost = host == 'vkvideo.ru' ||
        host == 'm.vkvideo.ru' ||
        host == 'vk.com' ||
        host == 'm.vk.com';
    final isVk = isVkHost &&
        (RegExp(r'^/video-?\d+_\d+$').hasMatch(uri?.path ?? '') ||
            RegExp(r'^video-?\d+_\d+')
                .hasMatch(uri?.queryParameters['z'] ?? ''));
    return isVk ? vk : web;
  }
}
