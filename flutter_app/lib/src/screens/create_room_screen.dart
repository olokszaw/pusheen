import 'package:flutter/material.dart';

import '../../watch_party/api_client.dart';
import '../models/room.dart';
import '../widgets/glass.dart';

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
  final title = TextEditingController();
  final videoUrl = TextEditingController();
  bool isPrivate = false;
  bool allowGuests = false;
  bool loading = false;

  @override
  void dispose() {
    title.dispose();
    videoUrl.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (title.text.trim().isEmpty) return message('Введи название комнаты');
    final uri = Uri.tryParse(videoUrl.text.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return message('Вставь корректную ссылку на страницу видео');
    }
    setState(() => loading = true);
    try {
      final room = await widget.api.createRoom(
        title: title.text.trim(),
        description: '',
        theme: 'movie',
        videoUrl: videoUrl.text.trim(),
        isPrivate: isPrivate,
        allowGuestsControl: allowGuests,
      );
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
          TextField(
              controller: title,
              decoration: const InputDecoration(
                  labelText: 'Название комнаты',
                  prefixIcon: Icon(Icons.edit_outlined))),
        ])),
        const SizedBox(height: 16),
        GlassCard(
            child: Column(children: [
          TextField(
              controller: videoUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Ссылка VK Видео',
                  hintText: 'https://vkvideo.ru/video-123_456',
                  prefixIcon: Icon(Icons.link_rounded))),
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
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: allowGuests,
              onChanged: (value) => setState(() => allowGuests = value),
              secondary: const Icon(Icons.tune_rounded),
              title: const Text('Разрешить гостям управлять')),
        ])),
        const SizedBox(height: 14),
        SizedBox(
            height: 54,
            child: FilledButton.icon(
                onPressed: loading ? null : submit,
                icon: const Icon(Icons.add_rounded),
                label: Text(loading ? 'Создаём…' : 'Создать комнату'))),
      ],
    );
    return widget.embedded
        ? body
        : Scaffold(body: GlowScaffold(child: SafeArea(child: body)));
  }
}
