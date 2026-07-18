import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../watch_party/api_client.dart';
import '../models/room.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'create_room_screen.dart';
import 'room_screen.dart';

class ShellScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;
  const ShellScreen(
      {super.key,
      required this.api,
      required this.onToggleTheme,
      required this.onLogout});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int index = 0;
  List<RoomModel> rooms = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    refreshRooms();
  }

  Future<void> refreshRooms() async {
    try {
      rooms = await widget.api.rooms();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openRoom(RoomModel room) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RoomScreen(api: widget.api, room: room)));
    refreshRooms();
  }

  Future<void> createRoom() async {
    final room = await Navigator.push<RoomModel>(context,
        MaterialPageRoute(builder: (_) => CreateRoomScreen(api: widget.api)));
    if (room != null && mounted) openRoom(room);
  }

  Future<void> joinByCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Войти по коду'),
        content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Войти'))
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      final room = await widget.api.joinRoom(code);
      if (mounted) openRoom(room);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не удалось войти: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomePage(
          api: widget.api,
          rooms: rooms,
          loading: loading,
          onRefresh: refreshRooms,
          onCreate: createRoom,
          onJoin: joinByCode,
          onOpen: openRoom),
      _SearchPage(rooms: rooms, onOpen: openRoom),
      CreateRoomScreen(api: widget.api, embedded: true, onCreated: openRoom),
      _RoomsPage(
          rooms: rooms,
          loading: loading,
          onRefresh: refreshRooms,
          onOpen: openRoom),
      _ProfilePage(
        api: widget.api,
        onToggleTheme: widget.onToggleTheme,
        onLogout: widget.onLogout,
      ),
    ];
    return Scaffold(
      body: GlowScaffold(
          child: SafeArea(child: IndexedStack(index: index, children: pages))),
      bottomNavigationBar: _CompactNavigation(
        index: index,
        onChanged: (value) => setState(() => index = value),
      ),
    );
  }
}

class _CompactNavigation extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _CompactNavigation({required this.index, required this.onChanged});

  static const items = [
    (Icons.home_rounded, 'Главная'),
    (Icons.search_rounded, 'Поиск'),
    (Icons.add_rounded, 'Создать'),
    (Icons.video_library_rounded, 'Комнаты'),
    (Icons.person_rounded, 'Профиль'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
            borderRadius: const BorderRadius.all(Radius.circular(22)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Flexible(
                      flex: i == index ? 3 : 1,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(17),
                        onTap: () => onChanged(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          height: 42,
                          padding: EdgeInsets.symmetric(
                              horizontal: i == index ? 12 : 8),
                          decoration: BoxDecoration(
                            color: i == index
                                ? pulsePurple.withValues(alpha: .28)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(
                                color: i == index
                                    ? const Color(0xFFCDB8FF)
                                        .withValues(alpha: .22)
                                    : Colors.transparent),
                          ),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(
                                      begin: .9, end: i == index ? 1.08 : .92),
                                  duration: const Duration(milliseconds: 220),
                                  builder: (_, scale, child) => Transform.scale(
                                      scale: scale, child: child),
                                  child: Icon(items[i].$1, size: 21),
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  child: i == index
                                      ? Padding(
                                          padding:
                                              const EdgeInsets.only(left: 7),
                                          child: Text(items[i].$2,
                                              maxLines: 1,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800)))
                                      : const SizedBox.shrink(),
                                ),
                              ]),
                        ),
                      ),
                    ),
                ]),
          ),
        ),
      );
}

class _HomePage extends StatelessWidget {
  final ApiClient api;
  final List<RoomModel> rooms;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final ValueChanged<RoomModel> onOpen;
  const _HomePage(
      {required this.api,
      required this.rooms,
      required this.loading,
      required this.onRefresh,
      required this.onCreate,
      required this.onJoin,
      required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
          children: [
            Row(children: [
              CircleAvatar(
                  radius: 23,
                  backgroundColor: pulsePurple.withOpacity(.45),
                  child: const Icon(Icons.person_rounded)),
              const SizedBox(width: 11),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Привет, ${api.nickname ?? api.username ?? 'друг'}!',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Text('В сети',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF8EFFBF)))
                  ])),
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none_rounded)),
            ]),
            const SizedBox(height: 22),
            GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Начать просмотр\nвместе',
                        style: TextStyle(
                            fontSize: 26,
                            height: 1.12,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                        'Создай комнату, вставь VK Видео и пригласи друзей.'),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                          child: FilledButton.icon(
                              onPressed: onCreate,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Создать'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton.icon(
                              onPressed: onJoin,
                              icon: const Icon(Icons.key_rounded),
                              label: const Text('По коду')))
                    ]),
                  ]),
            ),
            const SizedBox(height: 25),
            const Text('Мои активные комнаты',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (rooms.isEmpty)
              const GlassCard(child: Text('Комнат пока нет. Создай первую.'))
            else
              SizedBox(
                  height: 205,
                  child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: rooms.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 11),
                      itemBuilder: (_, i) => _RoomCard(
                          room: rooms[i], onTap: () => onOpen(rooms[i])))),
          ]),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomModel room;
  final VoidCallback onTap;
  const _RoomCard({required this.room, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: GlassCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 105,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                gradient: LinearGradient(
                    colors: [Color(0xFF324E83), Color(0xFFE1689E)]),
              ),
              child: const Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      size: 42, color: Colors.white)),
            ),
            Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      '${room.membersCount} участников · ${room.isPrivate ? 'Приватная' : 'Публичная'}',
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white70)),
                  const SizedBox(height: 7),
                  Text('Код ${room.inviteCode}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFC9B5FF))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomsPage extends StatelessWidget {
  final List<RoomModel> rooms;
  final bool loading;
  final Future<void> Function() onRefresh;
  final ValueChanged<RoomModel> onOpen;
  const _RoomsPage(
      {required this.rooms,
      required this.loading,
      required this.onRefresh,
      required this.onOpen});
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Мои комнаты',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else
            ...rooms.map(
              (room) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  onTap: () => onOpen(room),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        const CircleAvatar(child: Icon(Icons.movie_rounded)),
                    title: Text(room.title),
                    subtitle: Text(
                        'Код ${room.inviteCode} · ${room.membersCount} участников'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchPage extends StatelessWidget {
  final List<RoomModel> rooms;
  final ValueChanged<RoomModel> onOpen;
  const _SearchPage({required this.rooms, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Поиск',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        const TextField(
            decoration: InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'Комнаты и видео')),
        const SizedBox(height: 20),
        ...rooms.map(
          (room) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              onTap: () => onOpen(room),
              child: Text(room.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfilePage extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;
  const _ProfilePage({
    required this.api,
    required this.onToggleTheme,
    required this.onLogout,
  });

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  Future<void> logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text(
          'На этом устройстве потребуется снова ввести ник для входа.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.logout();
    if (mounted) widget.onLogout();
  }

  Future<void> editUsername() async {
    final controller = TextEditingController(text: widget.api.nickname);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изменить ник'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(labelText: 'Новый ник'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim() == widget.api.nickname) return;
    try {
      await widget.api.updateProfile(nickname: value);
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить ник: $error')),
      );
    }
  }

  Future<void> editAvatar() async {
    final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 76,
        maxWidth: 900,
        maxHeight: 900);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Изображение слишком большое')));
      return;
    }
    final value = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    await widget.api.updateProfile(avatarDataUrl: value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(18), children: [
        const SizedBox(height: 12),
        Center(
            child: GestureDetector(
                onTap: editAvatar,
                child: Stack(clipBehavior: Clip.none, children: [
                  CircleAvatar(
                      radius: 44,
                      backgroundImage: _profileImage(widget.api.avatarDataUrl),
                      child: (widget.api.avatarDataUrl ?? '').isEmpty
                          ? const Icon(Icons.person_rounded, size: 42)
                          : null),
                  Positioned(
                      right: -3,
                      bottom: -3,
                      child: CircleAvatar(
                          radius: 15,
                          backgroundColor: pulsePurple,
                          child: const Icon(Icons.photo_camera_outlined,
                              size: 15))),
                ]))),
        const SizedBox(height: 12),
        Center(
            child: Text(widget.api.nickname ?? 'Пользователь',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800))),
        const SizedBox(height: 4),
        Center(
            child: Text(
                '@${widget.api.username ?? 'username'} · ID ${widget.api.userId ?? '—'}',
                style: const TextStyle(fontSize: 12, color: Colors.white54))),
        const SizedBox(height: 24),
        GlassCard(
            child: Column(children: [
          ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Изменить ник'),
              subtitle: Text(widget.api.nickname ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: editUsername),
          ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Тема интерфейса'),
              trailing: IconButton(
                  onPressed: widget.onToggleTheme,
                  icon: const Icon(Icons.brightness_6_rounded))),
          const ListTile(
              leading: Icon(Icons.notifications_none),
              title: Text('Уведомления'),
              trailing: Icon(Icons.chevron_right)),
          const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Приватность'),
              trailing: Icon(Icons.chevron_right)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text(
              'Выйти из аккаунта',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: logout,
          ),
        ]))
      ]);

  ImageProvider? _profileImage(String? dataUrl) {
    if (dataUrl == null || !dataUrl.contains(',')) return null;
    try {
      return MemoryImage(
          Uint8List.fromList(base64Decode(dataUrl.split(',').last)));
    } on Object {
      return null;
    }
  }
}
