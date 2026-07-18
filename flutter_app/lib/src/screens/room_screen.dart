import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_emoji_icon/fluentui_emoji_icon.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../watch_party/api_client.dart';
import '../../watch_party/media_source.dart';
import '../../watch_party/playback_state.dart';
import '../../watch_party/room_socket.dart';
import '../models/room.dart';
import '../widgets/glass.dart';

class RoomScreen extends StatefulWidget {
  final ApiClient api;
  final RoomModel room;
  const RoomScreen({super.key, required this.api, required this.room});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final chatInput = TextEditingController();
  final chatFocus = FocusNode();
  final chatScroll = ScrollController();
  final displayedPosition = ValueNotifier<double>(0);
  final sendButtonFocus =
      FocusNode(skipTraversal: true, canRequestFocus: false);
  final List<_ChatLine> messages = [];
  final ImagePicker imagePicker = ImagePicker();
  final Set<String> browserTriedFrames = <String>{};
  RoomSocket? socket;
  StreamSubscription<Map<String, dynamic>>? subscription;
  bool connected = false;
  bool isOwner = false;
  bool isPlaying = false;
  bool isSeeking = false;
  double? edgeSwipeStartX;
  double edgeSwipeDistance = 0;
  double position = 0;
  DateTime? updatedAt;
  late String videoUrl;
  late MediaSourceType sourceType;
  List<RoomMemberModel> members = const [];
  VideoPlayerController? player;
  WebViewController? browserPlayer;
  VideoStreamModel? stream;
  PlaybackState? latestState;
  Timer? syncTimer;
  bool playerLoading = true;
  String? playerError;
  bool browserMode = false;
  bool browserPageLoading = false;
  bool browserVideoReady = false;
  String? browserPageHost;
  DateTime browserIgnoreEventsUntil = DateTime.fromMillisecondsSinceEpoch(0);
  double duration = 1;
  bool controlsVisible = true;
  double volume = 1;
  Timer? controlsTimer;
  Timer? actionOverlayTimer;
  Timer? participantGlowTimer;
  IconData? actionOverlayIcon;
  int actionOverlayKey = 0;
  double participantButtonOpacity = .32;

  @override
  void initState() {
    super.initState();
    videoUrl = widget.room.videoUrl;
    sourceType = widget.room.sourceType;
    isOwner = widget.api.userId == widget.room.ownerId;
    initializePlayer();
    showControlsTemporarily();
    loadMessages().whenComplete(connect);
    syncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (browserMode) {
        requestBrowserState();
        return;
      }
      final controller = player;
      if (isOwner &&
          connected &&
          !isSeeking &&
          controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        playback(
          'sync',
          at: controller.value.position.inMilliseconds / 1000,
        );
      }
    });
  }

  Future<void> loadMessages() async {
    try {
      final history = await widget.api.roomMessages(widget.room.id);
      if (!mounted) return;
      setState(() {
        messages
          ..clear()
          ..addAll(history.map(_ChatLine.fromModel));
      });
      scrollChatToBottom(animate: false);
    } on Object {
      // Realtime chat still works if history cannot be loaded.
    }
  }

  Future<void> initializePlayer() async {
    if (sourceType == MediaSourceType.web) {
      await initializeWebSource();
    } else {
      await initializeVkSource();
    }
  }

  Future<void> initializeVkSource() async {
    try {
      final resolved = await widget.api.roomStream(widget.room.id);
      await initializeDirectStream(resolved);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        playerLoading = false;
        playerError = error.toString();
      });
    }
  }

  Future<void> initializeWebSource() async {
    try {
      final resolved = await widget.api.roomStream(widget.room.id);
      await initializeDirectStream(resolved);
    } on Object catch (error) {
      if (!mounted) return;
      // WEB is a separate provider: only it may fall back to an embedded page.
      // VK failures are never rendered as the VK website.
      if (!kIsWeb && (error is! ApiException || error.statusCode == 502)) {
        await initializeBrowserPlayer();
        return;
      }
      setState(() {
        playerLoading = false;
        playerError = error.toString();
      });
    }
  }

  Future<void> initializeDirectStream(VideoStreamModel resolved) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(resolved.url),
      httpHeaders: resolved.headers,
    );
    await controller.initialize();
    controller.addListener(updatePlayerPosition);
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {
      stream = resolved;
      player = controller;
      browserMode = false;
      duration = controller.value.duration.inMilliseconds / 1000;
      if (duration <= 0) duration = resolved.durationSeconds.clamp(1, 86400);
      playerLoading = false;
      playerError = null;
    });
    final state = latestState;
    if (state != null) await applyRemoteState(state);
  }

  Future<void> initializeBrowserPlayer() async {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        javaScriptCanOpenWindowsAutomatically: false,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'PulsePlayer',
        onMessageReceived: handleBrowserPlayerMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: handleBrowserNavigation,
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            browserPageLoading = true;
            browserVideoReady = false;
          });
        },
        onPageFinished: (url) {
          if (!mounted) return;
          setState(() {
            browserPageLoading = false;
            browserPageHost = Uri.tryParse(url)?.host;
          });
          installBrowserPlayerBridge();
        },
      ));
    setState(() {
      browserMode = true;
      browserPlayer = controller;
      playerLoading = false;
      playerError = null;
      stream = null;
      duration = 1;
      position = 0;
      displayedPosition.value = 0;
    });
    await controller.loadRequest(Uri.parse(videoUrl));
  }

  NavigationDecision handleBrowserNavigation(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final uri = Uri.tryParse(request.url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return NavigationDecision.prevent;
    }
    if (isBlockedAdHost(uri.host)) return NavigationDecision.prevent;
    final trusted = browserPageHost;
    if (!browserVideoReady || trusted == null || trusted.isEmpty) {
      return NavigationDecision.navigate;
    }
    final sameSite = uri.host == trusted ||
        uri.host.endsWith('.$trusted') ||
        trusted.endsWith('.${uri.host}');
    return sameSite ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  bool isBlockedAdHost(String value) {
    final host = value.toLowerCase();
    const blocked = <String>{
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'adservice.google.com',
      'adnxs.com',
      'popads.net',
      'popcash.net',
    };
    return blocked.any((item) => host == item || host.endsWith('.$item'));
  }

  Future<void> installBrowserPlayerBridge() async {
    await browserPlayer?.runJavaScript(r'''
      (() => {
        if (window.__pulseBridgeInstalled) return;
        window.__pulseBridgeInstalled = true;

        // Lightweight page cleanup. This blocks popunders and removes common
        // ad containers without touching the actual video or bypassing the
        // website's access controls.
        try {
          window.open = () => null;
        } catch (_) {}

        const adPattern = /(doubleclick|googlesyndication|adservice|adnxs|popunder|popads|advert|banner-?ad|(^|[-_])ads?([-_]|$))/i;
        const cleanAds = () => {
          document.querySelectorAll(
            'iframe, img, [id*="advert" i], [class*="advert" i], '
            + '[id^="ad_" i], [class~="ads" i], [class*="popunder" i]'
          ).forEach(element => {
            const marker = [
              element.id || '',
              element.className || '',
              element.getAttribute && (element.getAttribute('src') || ''),
              element.getAttribute && (element.getAttribute('data-src') || '')
            ].join(' ');
            if (adPattern.test(marker)) element.remove();
          });
        };
        cleanAds();
        new MutationObserver(cleanAds).observe(document.documentElement, {
          childList: true,
          subtree: true
        });
        document.addEventListener('click', event => {
          const link = event.target && event.target.closest
            ? event.target.closest('a[target="_blank"]')
            : null;
          if (link) {
            event.preventDefault();
            event.stopImmediatePropagation();
          }
        }, true);

        const findVideo = () => {
          const videos = Array.from(document.querySelectorAll('video'));
          return videos.sort((a, b) =>
            (b.clientWidth * b.clientHeight) - (a.clientWidth * a.clientHeight)
          )[0] || null;
        };

        const findPlayerFrame = () => {
          const frames = Array.from(document.querySelectorAll('iframe'))
            .map(frame => {
              const rect = frame.getBoundingClientRect();
              return {
                src: frame.src || frame.getAttribute('src') || '',
                area: Math.max(0, rect.width) * Math.max(0, rect.height)
              };
            })
            .filter(item => {
              if (!item.src || item.area < 20000 || adPattern.test(item.src)) {
                return false;
              }
              try {
                const url = new URL(item.src, location.href);
                return url.protocol === 'http:' || url.protocol === 'https:';
              } catch (_) {
                return false;
              }
            })
            .sort((a, b) => b.area - a.area);
          return frames[0] || null;
        };

        const emit = (eventName) => {
          const video = findVideo();
          if (!video) {
            const frame = findPlayerFrame();
            PulsePlayer.postMessage(JSON.stringify({
              ready: false,
              event: eventName,
              frameUrl: frame ? new URL(frame.src, location.href).href : null
            }));
            return;
          }
          if (!video.__pulseAttached) {
            video.__pulseAttached = true;
            ['play', 'pause', 'seeked', 'loadedmetadata', 'durationchange'].forEach(
              name => video.addEventListener(name, () => emit(name))
            );
          }
          document.documentElement.style.width = '100%';
          document.documentElement.style.height = '100%';
          document.documentElement.style.margin = '0';
          document.documentElement.style.overflow = 'hidden';
          document.body.style.width = '100%';
          document.body.style.height = '100%';
          document.body.style.margin = '0';
          document.body.style.overflow = 'hidden';
          document.body.style.background = '#000';
          const viewWidth = document.documentElement.clientWidth || window.innerWidth;
          const viewHeight = document.documentElement.clientHeight || window.innerHeight;
          video.style.position = 'fixed';
          video.playsInline = true;
          video.controls = false;
          video.removeAttribute('controls');
          video.style.inset = '0';
          // Do not use vw/vh here. On iOS they can keep the pre-keyboard
          // viewport size after Flutter shrinks the platform view.
          video.style.width = `${viewWidth}px`;
          video.style.height = `${viewHeight}px`;
          video.style.maxWidth = 'none';
          video.style.maxHeight = 'none';
          video.style.objectFit = 'contain';
          video.style.zIndex = '2147483647';
          video.style.background = '#000';
          PulsePlayer.postMessage(JSON.stringify({
            ready: true,
            event: eventName,
            position: Number.isFinite(video.currentTime) ? video.currentTime : 0,
            duration: Number.isFinite(video.duration) ? video.duration : 0,
            playing: !video.paused && !video.ended
          }));
        };

        window.__pulseEmit = emit;
        window.__pulseFindVideo = findVideo;
        window.__pulseFitVideo = () => emit('resize');
        window.addEventListener('resize', window.__pulseFitVideo);
        if (window.visualViewport) {
          window.visualViewport.addEventListener('resize', window.__pulseFitVideo);
        }
        if (window.ResizeObserver) {
          new ResizeObserver(window.__pulseFitVideo).observe(document.documentElement);
        }
        emit('ready');
      })();
    ''');
  }

  void handleBrowserPlayerMessage(JavaScriptMessage message) {
    if (!mounted) return;
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final ready = data['ready'] == true;
      if (!ready) {
        if (browserVideoReady) setState(() => browserVideoReady = false);
        final frameUrl = data['frameUrl']?.toString();
        if (frameUrl != null && frameUrl.isNotEmpty) {
          unawaited(openEmbeddedPlayer(frameUrl));
        }
        return;
      }
      final nextPosition = (data['position'] as num?)?.toDouble() ?? position;
      final nextDuration = (data['duration'] as num?)?.toDouble() ?? duration;
      final nextPlaying = data['playing'] == true;
      final event = data['event']?.toString() ?? 'tick';
      final readinessChanged = !browserVideoReady;
      browserVideoReady = true;
      position = nextPosition.clamp(0, nextDuration > 0 ? nextDuration : 86400);
      displayedPosition.value = position;
      if (nextDuration > 0) duration = nextDuration;
      if (readinessChanged || isPlaying != nextPlaying) {
        setState(() => isPlaying = nextPlaying);
      }
      if (readinessChanged && !isOwner && latestState != null) {
        unawaited(applyRemoteState(latestState!, forceSeek: true));
      }
      if (!isOwner || !connected || isSeeking) return;
      final isOwnControlEcho = DateTime.now().isBefore(
            browserIgnoreEventsUntil,
          ) &&
          (event == 'play' || event == 'pause' || event == 'seeked');
      if (isOwnControlEcho) return;
      if (event == 'play') {
        playback('play', at: position);
      } else if (event == 'pause') {
        playback('pause', at: position);
      } else if (event == 'seeked') {
        playback('seek', at: position);
      } else if (event == 'tick' && nextPlaying) {
        playback('sync', at: position);
      }
    } on Object {
      // A page can send malformed bridge data; keep the room usable.
    }
  }

  Future<void> openEmbeddedPlayer(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !browserTriedFrames.add(uri.toString())) {
      return;
    }
    await browserPlayer?.loadRequest(uri);
  }

  Future<void> requestBrowserState() async {
    await browserPlayer?.runJavaScript(
      "window.__pulseEmit && window.__pulseEmit('tick');",
    );
  }

  Future<void> controlBrowserPlayer({
    double? seek,
    bool? shouldPlay,
  }) async {
    if (isOwner && (seek != null || shouldPlay != null)) {
      browserIgnoreEventsUntil = DateTime.now().add(
        const Duration(milliseconds: 900),
      );
    }
    final seekScript =
        seek == null ? '' : 'video.currentTime = ${seek.toStringAsFixed(3)};';
    final playScript = shouldPlay == null
        ? ''
        : shouldPlay
            ? 'video.play().catch(() => {});'
            : 'video.pause();';
    await browserPlayer?.runJavaScript('''
      (() => {
        const video = window.__pulseFindVideo
          ? window.__pulseFindVideo()
          : document.querySelector('video');
        if (!video) return;
        $seekScript
        $playScript
      })();
    ''');
  }

  void updatePlayerPosition() {
    final controller = player;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    if (isSeeking) return;
    final next = controller.value.position.inMilliseconds / 1000;
    if ((next - position).abs() >= .2) {
      position = next.clamp(0, duration);
      displayedPosition.value = position;
    }
    if (isPlaying != controller.value.isPlaying) {
      setState(() => isPlaying = controller.value.isPlaying);
    }
  }

  Future<void> connect() async {
    final channel = RoomSocket.connect(
      websocketBaseUrl: widget.api.websocketBaseUrl,
      roomId: widget.room.id,
      token: widget.api.token!,
    );
    socket = channel;
    subscription = channel.events.listen(handleEvent, onError: (_) {
      if (mounted) setState(() => connected = false);
    });
  }

  void handleEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    switch (event['type']) {
      case 'playback_state':
        final state = playbackFromEvent(event);
        final command = event['command'] as String? ?? 'state';
        final previousUpdatedAt = updatedAt;
        if (previousUpdatedAt != null &&
            state.serverUpdatedAt.isBefore(previousUpdatedAt)) {
          return;
        }
        latestState = state;
        final ownerFromServer = event['is_owner'] as bool? ?? false;
        // The server broadcasts an owner's command back to every connection,
        // including the owner. Reapplying that delayed echo seeks the local
        // player slightly backwards and makes audio/video repeat.
        final ignoreOwnerEcho = ownerFromServer && command != 'state';
        setState(() {
          connected = true;
          isOwner = ownerFromServer;
          if (!ignoreOwnerEcho) isPlaying = state.isPlaying;
          if (!ignoreOwnerEcho && !isSeeking) {
            position = state.positionAt(DateTime.now()).clamp(0, 86400);
            displayedPosition.value = position;
          }
          updatedAt = state.serverUpdatedAt;
          if (state.vkVideoUrl.isNotEmpty) {
            videoUrl = state.vkVideoUrl;
            sourceType = MediaSourceType.detect(videoUrl);
          }
        });
        if (!ignoreOwnerEcho) {
          unawaited(applyRemoteState(
            state,
            forceSeek: command == 'seek' || command == 'pause',
          ));
        }
      case 'chat_message':
        final followLatest = shouldFollowLatestMessage;
        setState(() => messages.add(_ChatLine.fromJson(event)));
        if (followLatest) scrollChatToBottom();
      case 'message_reaction':
        final messageId = event['message_id'] as int?;
        final emoji = event['emoji'] as String?;
        final index = messages.indexWhere((message) => message.id == messageId);
        if (index >= 0 && emoji != null) {
          setState(() => messages[index] = messages[index].withReaction(
                emoji: emoji,
                count: event['count'] as int? ?? 0,
                reacted: event['reacted'] as bool? ?? false,
              ));
        }
      case 'presence':
        handlePresence(event);
      case 'error':
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(event['detail']?.toString() ?? 'Ошибка комнаты')));
    }
  }

  void handlePresence(Map<String, dynamic> event) {
    final followLatest = shouldFollowLatestMessage;
    final userId = event['user_id'] as int;
    final username = event['username'] as String? ?? 'Участник';
    final nickname = event['nickname'] as String? ?? username;
    final avatarDataUrl = event['avatar_data_url'] as String? ?? '';
    final memberIsOwner = event['is_owner'] as bool? ?? false;
    final isOnline = event['is_online'] as bool? ?? false;
    final changed = event['changed'] as bool? ?? false;
    setState(() {
      final index = members.indexWhere((member) => member.userId == userId);
      if (index >= 0) {
        members[index] = members[index].copyWith(
          username: username,
          nickname: nickname,
          avatarDataUrl: avatarDataUrl,
          isOnline: isOnline,
        );
      } else {
        members = [
          ...members,
          RoomMemberModel(
            userId: userId,
            username: username,
            nickname: nickname,
            avatarDataUrl: avatarDataUrl,
            isOwner: memberIsOwner,
            isOnline: isOnline,
          ),
        ];
      }
      if (changed && userId != widget.api.userId) {
        messages.add(_ChatLine.system(
          isOnline ? '$nickname вошёл в комнату' : '$nickname вышел из комнаты',
        ));
        participantButtonOpacity = 1;
      }
    });
    if (changed && userId != widget.api.userId) {
      participantGlowTimer?.cancel();
      participantGlowTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => participantButtonOpacity = .28);
      });
    }
    if (changed && userId != widget.api.userId && followLatest) {
      scrollChatToBottom();
    }
  }

  Future<void> applyRemoteState(
    PlaybackState state, {
    bool forceSeek = false,
  }) async {
    if (browserMode) {
      if (!browserVideoReady || isOwner) return;
      final target =
          state.positionAt(DateTime.now()).clamp(0, duration).toDouble();
      final drift = target - position;
      final shouldSeek = forceSeek || drift > 1.25 || drift < -2.5;
      await controlBrowserPlayer(
        seek: shouldSeek ? target : null,
        shouldPlay: state.isPlaying,
      );
      return;
    }
    final controller = player;
    if (controller == null || !controller.value.isInitialized) return;
    if (isOwner && isSeeking) return;
    final target = state.positionAt(DateTime.now()).clamp(0, duration);
    final current = controller.value.position.inMilliseconds / 1000;
    final drift = target - current;
    // While playing, small negative drift is normally network latency. Seeking
    // backwards for every sync packet causes repeated words and visible jumps.
    if (forceSeek || drift > 1.25 || drift < -2.5) {
      await controller.seekTo(Duration(milliseconds: (target * 1000).round()));
    }
    if (state.isPlaying && !controller.value.isPlaying) {
      await controller.play();
    } else if (!state.isPlaying && controller.value.isPlaying) {
      await controller.pause();
    }
  }

  void playback(String action, {double? at}) {
    if (!isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Управлять просмотром может только создатель')));
      return;
    }
    socket?.ownerCommand(
      action: action,
      isPlaying: action == 'play' ||
          ((action == 'seek' || action == 'sync') && isPlaying),
      positionSeconds: at ?? position,
    );
  }

  Future<void> seekTo(double target) async {
    if (!isOwner) return;
    final previousPosition = position;
    final safeTarget = target.clamp(0, duration).toDouble();
    position = safeTarget;
    displayedPosition.value = safeTarget;
    if (browserMode) {
      await controlBrowserPlayer(seek: safeTarget);
    } else {
      await player?.seekTo(
        Duration(milliseconds: (safeTarget * 1000).round()),
      );
    }
    playback('seek', at: safeTarget);
    showAction(safeTarget < previousPosition
        ? Icons.replay_10_rounded
        : Icons.forward_10_rounded);
  }

  void startSeeking(double value) {
    if (!isOwner) return;
    isSeeking = true;
    position = value.clamp(0, duration);
    displayedPosition.value = position;
    controlsTimer?.cancel();
    showControlsTemporarily();
  }

  void updateSeeking(double value) {
    if (!isOwner) return;
    position = value.clamp(0, duration);
    displayedPosition.value = position;
  }

  Future<void> finishSeeking(double value) async {
    if (!isOwner) return;
    final target = value.clamp(0, duration).toDouble();
    if (browserMode) {
      await controlBrowserPlayer(seek: target);
    } else {
      await player?.seekTo(Duration(milliseconds: (target * 1000).round()));
    }
    if (!mounted) return;
    position = target;
    displayedPosition.value = target;
    isSeeking = false;
    playback('seek', at: target);
    showAction(Icons.fast_forward_rounded);
  }

  Future<void> togglePlayback() async {
    if (!isOwner) return;
    if (browserMode) {
      if (!browserVideoReady) return;
      final nextPlaying = !isPlaying;
      await controlBrowserPlayer(shouldPlay: nextPlaying);
      setState(() => isPlaying = nextPlaying);
      playback(nextPlaying ? 'play' : 'pause', at: position);
      showAction(nextPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded);
      return;
    }
    final controller = player;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      playback('pause', at: controller.value.position.inMilliseconds / 1000);
      showAction(Icons.pause_rounded);
    } else {
      await controller.play();
      playback('play', at: controller.value.position.inMilliseconds / 1000);
      showAction(Icons.play_arrow_rounded);
    }
  }

  void sendMessage() {
    final text = chatInput.text.trim();
    if (text.isNotEmpty) {
      socket?.sendChat(text);
      chatInput.clear();
      scrollChatToBottom();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) chatFocus.requestFocus();
      });
    }
  }

  Future<void> sendPhoto() async {
    final photo = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 76,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Фото слишком большое. Выбери изображение до 2 МБ.')),
        );
      return;
    }
    final extension =
        photo.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    socket?.sendChat('',
        imageDataUrl: 'data:image/$extension;base64,${base64Encode(bytes)}');
    scrollChatToBottom();
    if (mounted) chatFocus.requestFocus();
  }

  void showControlsTemporarily() {
    controlsTimer?.cancel();
    if (mounted) setState(() => controlsVisible = true);
    controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !isSeeking) setState(() => controlsVisible = false);
    });
  }

  void showAction(IconData icon) {
    actionOverlayTimer?.cancel();
    setState(() {
      actionOverlayIcon = icon;
      actionOverlayKey++;
    });
    actionOverlayTimer = Timer(const Duration(milliseconds: 620), () {
      if (mounted) setState(() => actionOverlayIcon = null);
    });
    showControlsTemporarily();
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1);
    await player?.setVolume(volume);
    if (mounted) setState(() {});
    showAction(
        volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded);
  }

  void toggleReaction(_ChatLine message, String emoji) {
    if (message.id <= 0 || message.systemEvent) return;
    socket?.toggleReaction(message.id, emoji);
  }

  Future<void> showReactionMenu(_ChatLine message) async {
    if (message.systemEvent) return;
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .3),
      builder: (_) => SafeArea(
        child: Center(
          heightFactor: 1,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final item in const [
                '😂',
                '😍',
                '😮',
                '😭',
                '🔥',
                '👏',
                '❤️',
                '👍',
                '🍿',
                '🚀'
              ])
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, item),
                  child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: _FluentEmoji(item, size: 27)),
                ),
            ]),
          ),
        ),
      ),
    );
    if (emoji != null) toggleReaction(message, emoji);
  }

  void handleEdgePointerDown(PointerDownEvent event) {
    final width = MediaQuery.sizeOf(context).width;
    edgeSwipeStartX =
        event.position.dx >= width - 36 ? event.position.dx : null;
    edgeSwipeDistance = 0;
  }

  void handleEdgePointerMove(PointerMoveEvent event) {
    if (edgeSwipeStartX == null) return;
    edgeSwipeDistance += event.delta.dx;
  }

  void handleEdgePointerUp(PointerUpEvent event) {
    final shouldOpen = edgeSwipeStartX != null && edgeSwipeDistance < -56;
    edgeSwipeStartX = null;
    edgeSwipeDistance = 0;
    if (shouldOpen) showParticipants();
  }

  bool get shouldFollowLatestMessage {
    if (!chatScroll.hasClients) return true;
    return chatScroll.position.maxScrollExtent - chatScroll.position.pixels <
        72;
  }

  void scrollChatToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !chatScroll.hasClients) return;
      final target = chatScroll.position.maxScrollExtent;
      if (animate) {
        chatScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        chatScroll.jumpTo(target);
      }
    });
  }

  void insertEmoji(String emoji) {
    final value = chatInput.value;
    final start =
        value.selection.isValid ? value.selection.start : value.text.length;
    final end =
        value.selection.isValid ? value.selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, emoji);
    chatInput.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) chatFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    socket?.close();
    syncTimer?.cancel();
    controlsTimer?.cancel();
    actionOverlayTimer?.cancel();
    participantGlowTimer?.cancel();
    player?.removeListener(updatePlayerPosition);
    player?.dispose();
    chatInput.dispose();
    chatFocus.dispose();
    chatScroll.dispose();
    displayedPosition.dispose();
    sendButtonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: handleEdgePointerDown,
        onPointerMove: handleEdgePointerMove,
        onPointerUp: handleEdgePointerUp,
        child: GlowScaffold(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: LayoutBuilder(builder: (context, constraints) {
                  final playerControlsHeight = keyboardOpen ? 68.0 : 84.0;
                  final desiredPlayerHeight =
                      constraints.maxWidth * 9 / 16 + playerControlsHeight;
                  final rawPlayerCap = keyboardOpen
                      ? constraints.maxHeight * .34
                      : constraints.maxHeight - 260;
                  final minimumPlayerHeight = keyboardOpen ? 165.0 : 150.0;
                  final playerCap = rawPlayerCap < minimumPlayerHeight
                      ? minimumPlayerHeight
                      : rawPlayerCap;
                  final playerHeight = desiredPlayerHeight < playerCap
                      ? desiredPlayerHeight
                      : playerCap;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      keyboardOpen ? 5 : 10,
                      16,
                      keyboardOpen ? 6 : 12,
                    ),
                    child: Column(children: [
                      buildRoomHeader(compact: keyboardOpen),
                      SizedBox(height: keyboardOpen ? 5 : 10),
                      AnimatedContainer(
                        height: playerHeight,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: buildPlayerCard(compact: keyboardOpen),
                      ),
                      SizedBox(height: keyboardOpen ? 6 : 10),
                      Expanded(child: buildChatPanel()),
                    ]),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildRoomHeader({bool compact = false}) {
    return SizedBox(
      height: compact ? 34 : 38,
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        const Spacer(),
        _MiniGlassButton(
          icon: Icons.link_rounded,
          label: 'Ссылка',
          onTap: copyVideoLink,
        ),
        const SizedBox(width: 7),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 500),
          opacity: participantButtonOpacity,
          child: _MiniGlassButton(
            icon: Icons.group_rounded,
            onTap: showParticipants,
          ),
        ),
      ]),
    );
  }

  Widget buildPlayerCard({bool compact = false}) {
    final buttonConstraints =
        compact ? const BoxConstraints.tightFor(width: 38, height: 34) : null;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => controlsVisible
                ? setState(() => controlsVisible = false)
                : showControlsTemporarily(),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              child: Stack(fit: StackFit.expand, children: [
                buildManagedPlayer(),
                IgnorePointer(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                              scale: Tween(begin: .72, end: 1.0).animate(
                                  CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutBack)),
                              child: child)),
                      child: actionOverlayIcon == null
                          ? const SizedBox.shrink()
                          : Container(
                              key: ValueKey(actionOverlayKey),
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .48),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: .18))),
                              child: Icon(actionOverlayIcon, size: 32),
                            ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              height: compact ? 68 : 84,
              child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 240),
                  opacity: controlsVisible ? 1 : .16,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        10, compact ? 0 : 2, 10, compact ? 2 : 6),
                    child: Column(children: [
                      SizedBox(
                        height: compact ? 28 : 34,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: compact ? 4.5 : 5,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: compact ? 8 : 9,
                            ),
                            overlayShape: RoundSliderOverlayShape(
                              overlayRadius: compact ? 16 : 18,
                            ),
                          ),
                          child: ValueListenableBuilder<double>(
                            valueListenable: displayedPosition,
                            builder: (context, value, child) => Slider(
                              value: value.clamp(0, duration),
                              min: 0,
                              max: duration,
                              onChangeStart: isOwner ? startSeeking : null,
                              onChanged: isOwner ? updateSeeking : null,
                              onChangeEnd: isOwner ? finishSeeking : null,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Row(children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: buttonConstraints,
                            padding: EdgeInsets.zero,
                            onPressed:
                                isOwner ? () => seekTo(position - 10) : null,
                            icon: const Icon(Icons.replay_10_rounded),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: buttonConstraints,
                            padding: EdgeInsets.zero,
                            onPressed: isOwner ? togglePlayback : null,
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              size: compact ? 30 : 32,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: buttonConstraints,
                            padding: EdgeInsets.zero,
                            onPressed:
                                isOwner ? () => seekTo(position + 10) : null,
                            icon: const Icon(Icons.forward_10_rounded),
                          ),
                          const Spacer(),
                          PopupMenuButton<double>(
                            tooltip: 'Громкость',
                            padding: EdgeInsets.zero,
                            icon: Icon(
                                volume == 0
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                size: 20),
                            onSelected: setVolume,
                            itemBuilder: (_) => [
                              for (final value in const [
                                0.0,
                                .25,
                                .5,
                                .75,
                                1.0
                              ])
                                PopupMenuItem(
                                    value: value,
                                    child: Text('${(value * 100).round()}%')),
                            ],
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: isOwner ? showTimecodeEditor : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: ValueListenableBuilder<double>(
                                valueListenable: displayedPosition,
                                builder: (context, value, child) => Text(
                                  formatTime(value),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            sourceType == MediaSourceType.web
                                ? (stream?.quality ?? 'WEB')
                                : (stream?.quality ?? 'VK'),
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFFC9B5FF)),
                          ),
                        ]),
                      ),
                    ]),
                  )),
            )),
      ]),
    );
  }

  Widget buildChatPanel() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      child: Column(children: [
        const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 3, bottom: 5),
              child: Text('Чат',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            )),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text('Начни разговор',
                      style: TextStyle(fontSize: 12, color: Colors.white38)))
              : Scrollbar(
                  controller: chatScroll,
                  child: ListView.builder(
                    controller: chatScroll,
                    padding: const EdgeInsets.only(top: 2, right: 3, bottom: 2),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.manual,
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        buildChatMessage(messages[index]),
                  ),
                ),
        ),
        const SizedBox(height: 5),
        Row(key: const ValueKey('chat-composer'), children: [
          IconButton(
            tooltip: 'Фото',
            visualDensity: VisualDensity.compact,
            onPressed: sendPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 21),
          ),
          Expanded(
            child: TextField(
              key: const ValueKey('chat-input'),
              controller: chatInput,
              focusNode: chatFocus,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              onEditingComplete: () {},
              onSubmitted: (_) => sendMessage(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Сообщение…',
                filled: true,
                fillColor: Colors.white.withValues(alpha: .055),
                contentPadding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                suffixIcon: IconButton(
                  focusNode: sendButtonFocus,
                  tooltip: 'Отправить',
                  onPressed: sendMessage,
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget buildChatMessage(_ChatLine message) {
    if (message.systemEvent) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: .07))),
          child: Text(message.text,
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ),
      );
    }
    final ownMessage = message.authorId == widget.api.userId ||
        message.author == widget.api.username;
    return Align(
      alignment: ownMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => showReactionMenu(message),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            gradient: ownMessage
                ? LinearGradient(colors: [
                    const Color(0xFF7650C9).withValues(alpha: .42),
                    const Color(0xFF4D7FC8).withValues(alpha: .22)
                  ])
                : null,
            color: ownMessage ? null : Colors.white.withValues(alpha: .07),
            borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(15),
                topRight: const Radius.circular(15),
                bottomLeft: Radius.circular(ownMessage ? 15 : 5),
                bottomRight: Radius.circular(ownMessage ? 5 : 15)),
            border: Border.all(
                color: ownMessage
                    ? const Color(0xFFCDB8FF).withValues(alpha: .28)
                    : Colors.white.withValues(alpha: .09)),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _MiniAvatar(
                      dataUrl: message.avatarDataUrl,
                      label: message.nickname,
                      radius: 9),
                  const SizedBox(width: 5),
                  Text(message.nickname,
                      style: const TextStyle(
                          fontSize: 9, color: Color(0xFFC9B5FF))),
                  const SizedBox(width: 4),
                  Text('@${message.author}',
                      style:
                          const TextStyle(fontSize: 8, color: Colors.white30)),
                ]),
                if (message.imageDataUrl.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  _ChatImage(dataUrl: message.imageDataUrl),
                ],
                if (message.text.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  _FluentText(message.text,
                      style: const TextStyle(fontSize: 13, height: 1.25)),
                ],
                if (message.reactions.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(spacing: 4, runSpacing: 3, children: [
                    for (final reaction in message.reactions)
                      InkWell(
                        borderRadius: BorderRadius.circular(13),
                        onTap: () => toggleReaction(message, reaction.emoji),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: reaction.reacted
                                  ? const Color(0xFF7650C9)
                                      .withValues(alpha: .38)
                                  : Colors.black.withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                  color: reaction.reacted
                                      ? const Color(0xFFCDB8FF)
                                          .withValues(alpha: .35)
                                      : Colors.white.withValues(alpha: .08))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            _FluentEmoji(reaction.emoji, size: 16),
                            const SizedBox(width: 3),
                            Text('${reaction.count}',
                                style: const TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.w800))
                          ]),
                        ),
                      ),
                  ]),
                ],
              ]),
        ),
      ),
    );
  }

  Widget buildLegacy(BuildContext context) {
    return Scaffold(
      body: GlowScaffold(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Row(key: const ValueKey('chat-composer'), children: [
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(widget.room.title,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800)),
                            Text(
                                connected ? 'Синхронизировано' : 'Подключение…',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: connected
                                        ? const Color(0xFF8EFFBF)
                                        : Colors.orangeAccent))
                          ])),
                      IconButton(
                          onPressed: copyCode,
                          icon: const Icon(Icons.ios_share_rounded)),
                      IconButton(
                          onPressed: showParticipants,
                          icon: const Icon(Icons.groups_rounded)),
                    ]),
                    const SizedBox(height: 12),
                    GlassCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(22)),
                                child: buildManagedPlayer())),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          child: Column(children: [
                            Slider(
                              value: position.clamp(0, duration),
                              min: 0,
                              max: duration,
                              onChanged: isOwner
                                  ? (value) => setState(() => position = value)
                                  : null,
                              onChangeEnd: isOwner ? seekTo : null,
                            ),
                            Row(children: [
                              IconButton(
                                  onPressed: isOwner
                                      ? () => seekTo(position - 10)
                                      : null,
                                  icon: const Icon(Icons.replay_10_rounded)),
                              IconButton(
                                  onPressed: isOwner ? togglePlayback : null,
                                  icon: Icon(
                                      isPlaying
                                          ? Icons.pause_circle_filled_rounded
                                          : Icons.play_circle_fill_rounded,
                                      size: 34)),
                              IconButton(
                                  onPressed: isOwner
                                      ? () => seekTo(position + 10)
                                      : null,
                                  icon: const Icon(Icons.forward_10_rounded)),
                              const Spacer(),
                              Text(formatTime(position),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 10),
                              Chip(label: Text(stream?.quality ?? 'MP4')),
                            ]),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    const Text('Чат комнаты',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (messages.isEmpty)
                      const GlassCard(
                          child: Text('Сообщений пока нет. Напиши первым.')),
                    ...messages.map((message) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                            padding: const EdgeInsets.all(11),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(message.author,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFFC9B5FF))),
                                  const SizedBox(height: 3),
                                  Text(message.text)
                                ])))),
                    Row(children: [
                      PopupMenuButton<String>(
                        tooltip: 'Добавить эмодзи',
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        onSelected: insertEmoji,
                        itemBuilder: (context) => [
                          for (final emoji in const [
                            '😀',
                            '😂',
                            '😍',
                            '😎',
                            '😭',
                            '😱',
                            '🔥',
                            '❤️',
                            '👍',
                            '🍿'
                          ])
                            PopupMenuItem(value: emoji, child: Text(emoji)),
                        ],
                      ),
                      Expanded(
                          child: TextField(
                              key: const ValueKey('chat-input'),
                              controller: chatInput,
                              focusNode: chatFocus,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.send,
                              onEditingComplete: () {},
                              onSubmitted: (_) => sendMessage(),
                              onTapOutside: (_) {},
                              decoration: InputDecoration(
                                  hintText: 'Сообщение…',
                                  suffixIcon: IconButton(
                                      focusNode: sendButtonFocus,
                                      onPressed: sendMessage,
                                      icon: const Icon(Icons.send_rounded))))),
                    ]),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildManagedPlayer() {
    if (playerLoading) {
      return const ColoredBox(
        color: Color(0xFF11111A),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (playerError != null) {
      return ColoredBox(
        color: const Color(0xFF11111A),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Не удалось загрузить управляемый поток\n$playerError',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (browserMode && browserPlayer != null) {
      return Stack(children: [
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: !isOwner && browserVideoReady,
            child: WebViewWidget(controller: browserPlayer!),
          ),
        ),
        if (browserPageLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ]);
    }
    final controller = player!;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  String formatTime(double value) {
    final seconds = value.round();
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> showTimecodeEditor() async {
    if (!isOwner) return;
    final totalSeconds = position.round();
    final minutesController =
        TextEditingController(text: '${totalSeconds ~/ 60}');
    final secondsController =
        TextEditingController(text: '${totalSeconds % 60}');

    final target = await showDialog<double>(
      context: context,
      barrierColor: Colors.black.withOpacity(.38),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Перейти к таймкоду',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Выбери минуты и секунды',
                  style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: minutesController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Минуты'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(':', style: TextStyle(fontSize: 24)),
              ),
              Expanded(
                child: TextField(
                  controller: secondsController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: const InputDecoration(labelText: 'Секунды'),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final minutes = int.tryParse(minutesController.text) ?? 0;
                  final seconds =
                      (int.tryParse(secondsController.text) ?? 0).clamp(0, 59);
                  Navigator.pop(
                    dialogContext,
                    (minutes * 60 + seconds).toDouble(),
                  );
                },
                child: const Text('Перейти'),
              ),
            ]),
          ]),
        ),
      ),
    );

    minutesController.dispose();
    secondsController.dispose();
    if (target != null && mounted) await seekTo(target);
  }

  void copyCode() {
    Clipboard.setData(ClipboardData(text: widget.room.inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Код ${widget.room.inviteCode} скопирован')));
  }

  void copyVideoLink() {
    Clipboard.setData(ClipboardData(text: videoUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Ссылка на видео скопирована'),
          duration: Duration(seconds: 1)),
    );
  }

  Future<void> showParticipants() async {
    try {
      members = await widget.api.roomMembers(widget.room.id);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить участников: $error')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => participantButtonOpacity = 1);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Участники',
      barrierColor: Colors.black.withValues(alpha: .3),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => Align(
        alignment: Alignment.centerRight,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: FractionallySizedBox(
              widthFactor: MediaQuery.sizeOf(context).width < 600 ? .88 : .36,
              heightFactor: .96,
              child: Material(
                color: Colors.transparent,
                child: GlassCard(
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(28)),
                  child: Column(children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Участники',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w900))),
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded)),
                    ]),
                    const SizedBox(height: 8),
                    Expanded(
                        child: ListView.separated(
                      itemCount: members.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 5),
                      itemBuilder: (_, index) {
                        final member = members[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .045),
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: .07))),
                          child: Row(children: [
                            _MiniAvatar(
                                dataUrl: member.avatarDataUrl,
                                label: member.nickname,
                                radius: 20),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    Flexible(
                                        child: Text(member.nickname,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800))),
                                    if (member.userId == widget.api.userId)
                                      Container(
                                          margin:
                                              const EdgeInsets.only(left: 5),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: .08),
                                              borderRadius:
                                                  BorderRadius.circular(7)),
                                          child: const Text('вы',
                                              style: TextStyle(
                                                  fontSize: 8,
                                                  color: Colors.white54)))
                                  ]),
                                  Text(
                                      '@${member.username}${member.isOwner ? ' · создатель' : ''}',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.white54)),
                                ])),
                            _OnlineIndicator(online: member.isOnline),
                          ]),
                        );
                      },
                    )),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: animation, child: child)),
    );
    if (mounted) setState(() => participantButtonOpacity = .28);
  }
}

class _ChatLine {
  final int id;
  final int authorId;
  final String author;
  final String nickname;
  final String avatarDataUrl;
  final String text;
  final String imageDataUrl;
  final List<MessageReactionModel> reactions;
  final bool systemEvent;

  const _ChatLine(
      {required this.id,
      required this.authorId,
      required this.author,
      required this.nickname,
      required this.avatarDataUrl,
      required this.text,
      required this.imageDataUrl,
      required this.reactions,
      this.systemEvent = false});

  factory _ChatLine.fromModel(ChatMessageModel model) => _ChatLine(
      id: model.id,
      authorId: model.authorId,
      author: model.author,
      nickname: model.nickname,
      avatarDataUrl: model.avatarDataUrl,
      text: model.text,
      imageDataUrl: model.imageDataUrl,
      reactions: model.reactions);

  factory _ChatLine.fromJson(Map<String, dynamic> json) => _ChatLine(
        id: json['id'] as int? ?? 0,
        authorId: json['author_id'] as int? ?? 0,
        author: json['author'] as String? ?? 'user',
        nickname: json['nickname'] as String? ??
            json['author'] as String? ??
            'Участник',
        avatarDataUrl: json['avatar_data_url'] as String? ?? '',
        text: json['text'] as String? ?? '',
        imageDataUrl: json['image_data_url'] as String? ?? '',
        reactions: (json['reactions'] as List<dynamic>? ?? const [])
            .map((item) =>
                MessageReactionModel.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  factory _ChatLine.system(String text) => _ChatLine(
      id: -1,
      authorId: -1,
      author: '',
      nickname: '',
      avatarDataUrl: '',
      text: text,
      imageDataUrl: '',
      reactions: const [],
      systemEvent: true);

  _ChatLine withReaction(
      {required String emoji, required int count, required bool reacted}) {
    final updated = [...reactions.where((item) => item.emoji != emoji)];
    if (count > 0)
      updated.add(
          MessageReactionModel(emoji: emoji, count: count, reacted: reacted));
    return _ChatLine(
        id: id,
        authorId: authorId,
        author: author,
        nickname: nickname,
        avatarDataUrl: avatarDataUrl,
        text: text,
        imageDataUrl: imageDataUrl,
        reactions: updated,
        systemEvent: systemEvent);
  }
}

const _fluentEmojiMap = <String, FluentData>{
  '😂': Fluents.flFaceWithTearsOfJoy,
  '😍': Fluents.flSmilingFaceWithHeartEyes,
  '😮': Fluents.flAstonishedFace,
  '😭': Fluents.flLoudlyCryingFace,
  '🔥': Fluents.flFire,
  '👏': Fluents.flClappingHands,
  '❤️': Fluents.flRedHeart,
  '❤': Fluents.flRedHeart,
  '👍': Fluents.flThumbsUp,
  '🍿': Fluents.flPopcorn,
  '🚀': Fluents.flRocket,
};

class _FluentEmoji extends StatelessWidget {
  final String emoji;
  final double size;
  const _FluentEmoji(this.emoji, {this.size = 20});
  @override
  Widget build(BuildContext context) {
    final fluent = _fluentEmojiMap[emoji];
    return fluent == null
        ? Text(emoji, style: TextStyle(fontSize: size))
        : FluentUiEmojiIcon(fl: fluent, w: size, h: size);
  }
}

class _FluentText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _FluentText(this.text, {this.style});
  @override
  Widget build(BuildContext context) {
    final keys = _fluentEmojiMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final spans = <InlineSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      String? found;
      var index = rest.length;
      for (final key in keys) {
        final candidate = rest.indexOf(key);
        if (candidate >= 0 && candidate < index) {
          index = candidate;
          found = key;
        }
      }
      if (found == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (index > 0) spans.add(TextSpan(text: rest.substring(0, index)));
      spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child:
                  _FluentEmoji(found, size: (style?.fontSize ?? 14) * 1.25))));
      rest = rest.substring(index + found.length);
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _MiniGlassButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  const _MiniGlassButton({required this.icon, required this.onTap, this.label});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 10),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .065),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withValues(alpha: .1))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label!,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700))
            ]
          ]),
        ),
      );
}

class _MiniAvatar extends StatelessWidget {
  final String dataUrl;
  final String label;
  final double radius;
  const _MiniAvatar(
      {required this.dataUrl, required this.label, required this.radius});
  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    if (dataUrl.contains(',')) {
      try {
        bytes = base64Decode(dataUrl.split(',').last);
      } on Object {
        bytes = null;
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF7650C9).withValues(alpha: .45),
      backgroundImage: bytes == null ? null : MemoryImage(bytes),
      child: bytes == null
          ? Text((label.trim().isEmpty ? '?' : label.trim()[0]).toUpperCase(),
              style: TextStyle(
                  fontSize: radius * .72, fontWeight: FontWeight.w900))
          : null,
    );
  }
}

class _ChatImage extends StatelessWidget {
  final String dataUrl;
  const _ChatImage({required this.dataUrl});
  @override
  Widget build(BuildContext context) {
    late Uint8List bytes;
    try {
      bytes = base64Decode(dataUrl.split(',').last);
    } on Object {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () => showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Фото',
          barrierColor: Colors.black.withValues(alpha: .88),
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => SafeArea(
                  child: Stack(children: [
                Center(
                    child: InteractiveViewer(
                        minScale: .7,
                        maxScale: 5,
                        child: Image.memory(bytes, fit: BoxFit.contain))),
                Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton.filledTonal(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded)))
              ])),
          transitionBuilder: (_, animation, __, child) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                  scale: Tween(begin: .94, end: 1.0).animate(animation),
                  child: child))),
      child: Hero(
          tag: 'chat-photo-${dataUrl.hashCode}',
          child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 210, maxWidth: 320),
                  child: Image.memory(bytes, fit: BoxFit.cover)))),
    );
  }
}

class _OnlineIndicator extends StatefulWidget {
  final bool online;
  const _OnlineIndicator({required this.online});
  @override
  State<_OnlineIndicator> createState() => _OnlineIndicatorState();
}

class _OnlineIndicatorState extends State<_OnlineIndicator> {
  bool showLabel = true;
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => showLabel = false);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    widget.online ? const Color(0xFF76F7B0) : Colors.white24)),
        if (showLabel && widget.online)
          const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('В сети',
                  style: TextStyle(fontSize: 8, color: Color(0xFF76F7B0))))
      ]));
}
