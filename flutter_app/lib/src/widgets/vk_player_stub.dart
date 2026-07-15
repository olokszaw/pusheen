import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../watch_party/vk_video.dart';

Widget buildVkPlayer(String pageUrl, String viewId) {
  final video = VkVideo.parse(pageUrl);
  if (video == null)
    return const Center(child: Text('Некорректная ссылка VK Видео'));
  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(video.embedUrl));
  return WebViewWidget(controller: controller);
}
