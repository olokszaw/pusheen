// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import '../../watch_party/vk_video.dart';

final Set<String> _registeredViewIds = <String>{};

Widget buildVkPlayer(String pageUrl, String viewId) {
  final video = VkVideo.parse(pageUrl);
  if (video == null) {
    return const Center(child: Text('Некорректная ссылка VK Видео'));
  }
  if (_registeredViewIds.add(viewId)) {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (_) {
      return html.IFrameElement()
        ..src = video.embedUrl
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture'
        ..allowFullscreen = true;
    });
  }
  return HtmlElementView(viewType: viewId);
}
