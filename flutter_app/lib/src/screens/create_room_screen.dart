import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../watch_party/api_client.dart';
import '../../watch_party/media_source.dart';
import '../models/room.dart';
import '../widgets/glass.dart';
import 'video_browser_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  final ApiClient api;
  final bool embedded;
  final ValueChanged<RoomModel>? onCreated;
  const CreateRoomScreen(
      {super.key, required this.api, this.embedded = false, this.onCreated});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final videoUrl = TextEditingController();
  bool isPrivate = false;
  bool loading = false;
  MediaSourceType sourceType = MediaSourceType.vk;
  final picker = ImagePicker();
  XFile? galleryVideo;

  @override
  void dispose() {
    videoUrl.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final uri = Uri.tryParse(videoUrl.text.trim());
    if (galleryVideo == null &&
        (uri == null ||
            !uri.hasAuthority ||
            (uri.scheme != 'https' && uri.scheme != 'http'))) {
      return message('Вставь корректную ссылку на страницу видео');
    }
    setState(() => loading = true);
    try {
      var room = await widget.api.createRoom(
        videoUrl: galleryVideo == null ? videoUrl.text.trim() : '',
        sourceType: galleryVideo == null ? sourceType : MediaSourceType.upload,
        isPrivate: isPrivate,
      );
      if (galleryVideo != null) {
        room = await widget.api.uploadRoomVideo(
          roomId: room.id,
          video: galleryVideo!,
        );
      }
      if (!mounted) return;
      if (widget.embedded && widget.onCreated != null) {
        widget.onCreated!(room);
      } else {
        Navigator.pop(context, room);
      }
    } catch (error) {
      message('Не удалось создать комнату: $error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> pickGalleryVideo() async {
    try {
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (!mounted || video == null) return;
      setState(() {
        galleryVideo = video;
        videoUrl.clear();
      });
    } catch (error) {
      message('Не удалось выбрать видео: $error');
    }
  }

  Future<void> openVideoBrowser() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const VideoBrowserScreen()),
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    setState(() {
      sourceType = MediaSourceType.web;
      videoUrl.text = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      children: [
        Row(children: [
          if (!widget.embedded)
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded)),
          const Expanded(
              child: Text('Новая комната',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 18),
        GlassCard(
            child: Column(children: [
          Row(children: [
            Expanded(
              child: _ProviderButton(
                selected: sourceType == MediaSourceType.vk,
                logo: const _VkLogo(),
                onTap: () => setState(() {
                  sourceType = MediaSourceType.vk;
                  videoUrl.clear();
                  galleryVideo = null;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProviderButton(
                selected: sourceType == MediaSourceType.web,
                logo: const _GoogleLogo(),
                onTap: () => setState(() {
                  sourceType = MediaSourceType.web;
                  videoUrl.clear();
                  galleryVideo = null;
                }),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: videoUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  hintText: 'Вставь ссылку на видео',
                  prefixIcon: Icon(Icons.link_rounded))),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loading ? null : pickGalleryVideo,
              icon: const Icon(Icons.video_library_rounded),
              label: Text(galleryVideo == null
                  ? 'Выбрать видео из галереи'
                  : 'Выбрано: ${galleryVideo!.name}'),
            ),
          ),
          if (sourceType == MediaSourceType.web) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: openVideoBrowser,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Найти через Google'),
              ),
            ),
          ],
        ])),
        const SizedBox(height: 12),
        GlassCard(
            child: Column(children: [
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isPrivate,
              onChanged: (value) => setState(() => isPrivate = value),
              secondary:
                  Icon(isPrivate ? Icons.lock_rounded : Icons.public_rounded),
              title:
                  Text(isPrivate ? 'Приватная комната' : 'Публичная комната')),
        ])),
        const SizedBox(height: 14),
        _GlassCreateButton(
          loading: loading,
          onTap: loading ? null : submit,
        ),
      ],
    );
    return widget.embedded
        ? body
        : Scaffold(body: GlowScaffold(child: SafeArea(child: body)));
  }
}

class _ProviderButton extends StatelessWidget {
  final bool selected;
  final Widget logo;
  final VoidCallback onTap;
  const _ProviderButton(
      {required this.selected, required this.logo, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 66,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? .13 : .045),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFFCDB8FF).withValues(alpha: .55)
                  : Colors.white.withValues(alpha: .09),
            ),
          ),
          child: AnimatedScale(
              scale: selected ? 1.08 : .94,
              duration: const Duration(milliseconds: 180),
              child: Center(child: logo)),
        ),
      );
}

class _VkLogo extends StatelessWidget {
  const _VkLogo();
  @override
  Widget build(BuildContext context) => const Text(
        'VK',
        style: TextStyle(
          color: Color(0xFFEDE4FF),
          fontSize: 25,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: -2,
        ),
      );
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();
  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (rect) => const LinearGradient(colors: [
          Color(0xFF4285F4),
          Color(0xFF34A853),
          Color(0xFFFBBC05),
          Color(0xFFEA4335),
        ]).createShader(rect),
        child: const Text('G',
            style: TextStyle(
                color: Colors.white,
                fontSize: 35,
                fontWeight: FontWeight.w900)),
      );
}

class _GlassCreateButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _GlassCreateButton({required this.loading, required this.onTap});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .55 : 1,
        child: GlassCard(
          padding: EdgeInsets.zero,
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (loading)
                  const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  const Icon(Icons.add_rounded),
                const SizedBox(width: 8),
                Text(loading ? 'Создаём…' : 'Создать комнату',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      );
}
