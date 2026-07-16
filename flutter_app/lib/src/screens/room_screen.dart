import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void initState() {
    super.initState();
    videoUrl = widget.room.videoUrl;
    sourceType = widget.room.sourceType;
    isOwner = widget.api.userId == widget.room.ownerId;
    initializePlayer();
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
          ..addAll(history.map((item) => _ChatLine(item.author, item.text)));
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
        setState(() => messages.add(_ChatLine(
            event['author'] as String? ?? 'Участник',
            event['text'] as String? ?? '')));
        if (followLatest) scrollChatToBottom();
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
    final memberIsOwner = event['is_owner'] as bool? ?? false;
    final isOnline = event['is_online'] as bool? ?? false;
    final changed = event['changed'] as bool? ?? false;
    setState(() {
      final index = members.indexWhere((member) => member.userId == userId);
      if (index >= 0) {
        members[index] = members[index].copyWith(
          username: username,
          isOnline: isOnline,
        );
      } else {
        members = [
          ...members,
          RoomMemberModel(
            userId: userId,
            username: username,
            isOwner: memberIsOwner,
            isOnline: isOnline,
          ),
        ];
      }
      if (changed && userId != widget.api.userId) {
        messages.add(_ChatLine(
          'Система',
          isOnline ? '$username вошёл в комнату' : '$username вышел из комнаты',
        ));
      }
    });
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
  }

  void startSeeking(double value) {
    if (!isOwner) return;
    isSeeking = true;
    position = value.clamp(0, duration);
    displayedPosition.value = position;
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
  }

  Future<void> togglePlayback() async {
    if (!isOwner) return;
    if (browserMode) {
      if (!browserVideoReady) return;
      final nextPlaying = !isPlaying;
      await controlBrowserPlayer(shouldPlay: nextPlaying);
      setState(() => isPlaying = nextPlaying);
      playback(nextPlaying ? 'play' : 'pause', at: position);
      return;
    }
    final controller = player;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      playback('pause', at: controller.value.position.inMilliseconds / 1000);
    } else {
      await controller.play();
      playback('play', at: controller.value.position.inMilliseconds / 1000);
    }
  }

  void sendMessage() {
    final text = chatInput.text.trim();
    if (text.isNotEmpty) {
      socket?.sendChat(text);
      chatInput.clear();
      scrollChatToBottom();
    }
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
      height: compact ? 38 : 42,
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.room.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                connected ? 'Синхронизировано' : 'Подключение…',
                style: TextStyle(
                  fontSize: 10,
                  color:
                      connected ? const Color(0xFF8EFFBF) : Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Поделиться кодом',
          onPressed: copyCode,
          icon: const Icon(Icons.ios_share_rounded),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Участники',
          onPressed: showParticipants,
          icon: const Icon(Icons.groups_rounded),
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
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: buildManagedPlayer(),
          ),
        ),
        SizedBox(
          height: compact ? 68 : 84,
          child: Padding(
            padding:
                EdgeInsets.fromLTRB(10, compact ? 0 : 2, 10, compact ? 2 : 6),
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
                    onPressed: isOwner ? () => seekTo(position - 10) : null,
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
                    onPressed: isOwner ? () => seekTo(position + 10) : null,
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                  const Spacer(),
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
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    sourceType == MediaSourceType.web
                        ? (stream?.quality ?? 'WEB')
                        : (stream?.quality ?? 'VK'),
                    style:
                        const TextStyle(fontSize: 10, color: Color(0xFFC9B5FF)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget buildChatPanel() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      child: Column(children: [
        const Row(children: [
          Text(
            'Чат комнаты',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ]),
        const SizedBox(height: 5),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text(
                    'Сообщений пока нет. Напиши первым.',
                    style: TextStyle(color: Colors.white60),
                  ),
                )
              : Scrollbar(
                  controller: chatScroll,
                  child: ListView.builder(
                    controller: chatScroll,
                    padding: const EdgeInsets.only(top: 2, right: 4),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        buildChatMessage(messages[index]),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Row(key: const ValueKey('chat-composer'), children: [
          PopupMenuButton<String>(
            tooltip: 'Добавить эмодзи',
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.emoji_emotions_outlined, size: 22),
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
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              onEditingComplete: () {},
              onSubmitted: (_) => sendMessage(),
              onTapOutside: (_) => chatFocus.unfocus(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Сообщение…',
                contentPadding: const EdgeInsets.fromLTRB(14, 11, 4, 11),
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
    final ownMessage = message.author == widget.api.username;
    return Align(
      alignment: ownMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: ownMessage
              ? const Color(0xFF7650C9).withValues(alpha: .34)
              : Colors.white.withValues(alpha: .075),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ownMessage
                ? const Color(0xFFCDB8FF).withValues(alpha: .35)
                : Colors.white.withValues(alpha: .10),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.author,
              style: const TextStyle(fontSize: 9, color: Color(0xFFC9B5FF)),
            ),
            const SizedBox(height: 1),
            Text(message.text, style: const TextStyle(fontSize: 13)),
          ],
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
        if (!browserPageLoading && !browserVideoReady)
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Ищем основной видеоплеер на странице…',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassCard(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Участники комнаты',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          for (final member in members)
            ListTile(
              leading: CircleAvatar(
                child: Icon(member.isOwner
                    ? Icons.workspace_premium_rounded
                    : Icons.person_rounded),
              ),
              title: Text(member.username),
              subtitle: Text(
                '${member.isOwner ? 'Создатель' : 'Участник'} · '
                '${member.isOnline ? 'в сети' : 'вышел'}',
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: member.isOnline ? Colors.greenAccent : Colors.grey,
                  ),
                ),
                if (member.userId == widget.api.userId) ...[
                  const SizedBox(width: 8),
                  const Chip(label: Text('Вы')),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}

class _ChatLine {
  final String author;
  final String text;
  const _ChatLine(this.author, this.text);
}
