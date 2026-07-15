import 'package:flutter/material.dart';

import '../../watch_party/api_client.dart';
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
  final title = TextEditingController(text: 'Вечер кино');
  final description = TextEditingController();
  final videoUrl = TextEditingController();
  String theme = 'movie';
  bool isPrivate = false;
  bool allowGuests = false;
  bool loading = false;

  @override
  void dispose() {
    title.dispose();
    description.dispose();
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
        description: description.text.trim(),
        theme: theme,
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

  Future<void> browseVideo() async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const VideoBrowserScreen()),
    );
    if (selected == null || !mounted) return;
    setState(() => videoUrl.text = selected);
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
          TextField(
              controller: title,
              decoration: const InputDecoration(
                  labelText: 'Название комнаты',
                  prefixIcon: Icon(Icons.edit_outlined))),
          const SizedBox(height: 12),
          TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Описание',
                  prefixIcon: Icon(Icons.subject_rounded))),
        ])),
        const SizedBox(height: 16),
        const Text('Тема комнаты',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 9),
        Wrap(spacing: 7, runSpacing: 7, children: [
          _themeChip('movie', Icons.movie_rounded, 'Кино'),
          _themeChip('memes', Icons.sentiment_very_satisfied_rounded, 'Мемы'),
          _themeChip('games', Icons.sports_esports_rounded, 'Игры'),
          _themeChip('music', Icons.music_note_rounded, 'Музыка'),
          _themeChip('series', Icons.live_tv_rounded, 'Сериалы'),
          _themeChip('horror', Icons.nightlight_round, 'Ужасы'),
        ]),
        const SizedBox(height: 16),
        GlassCard(
            child: Column(children: [
          TextField(
              controller: videoUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Ссылка на страницу видео',
                  prefixIcon: Icon(Icons.link_rounded))),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: browseVideo,
              icon: const Icon(Icons.travel_explore_rounded),
              label: const Text('Найти через Google'),
            ),
          ),
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

  Widget _themeChip(String value, IconData icon, String label) {
    return ChoiceChip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      selected: theme == value,
      onSelected: (_) => setState(() => theme = value),
    );
  }
}
