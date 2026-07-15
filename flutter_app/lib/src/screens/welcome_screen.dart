import 'package:flutter/material.dart';

import '../../watch_party/api_client.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class WelcomeScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onToggleTheme;
  final VoidCallback onAuthenticated;
  const WelcomeScreen(
      {super.key,
      required this.api,
      required this.onToggleTheme,
      required this.onAuthenticated});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final name = TextEditingController();
  bool loading = false;

  Future<void> enter() async {
    final username = name.text.trim();
    if (username.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введи ник минимум из 2 символов')),
      );
      return;
    }
    setState(() => loading = true);
    try {
      await widget.api.login(username);
      if (!mounted) return;
      widget.onAuthenticated();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backend недоступен: $error')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlowScaffold(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                          colors: [pulsePink, pulsePurple, pulseBlue]),
                      boxShadow: [
                        BoxShadow(
                            color: pulsePurple.withOpacity(.45), blurRadius: 30)
                      ],
                    ),
                    child: const Icon(Icons.play_circle_fill_rounded,
                        color: Colors.white, size: 42),
                  ),
                  const SizedBox(height: 28),
                  const Text('Смотри. Чувствуй.\nБудь рядом.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 35,
                          height: 1.08,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  const Text(
                      'Фильмы, сериалы и видео вместе с друзьями — даже на расстоянии.',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.55, color: Colors.white70)),
                  const SizedBox(height: 28),
                  GlassCard(
                      child: TextField(
                          controller: name,
                          decoration: const InputDecoration(
                              labelText: 'Твоё имя',
                              prefixIcon: Icon(Icons.person_outline_rounded)))),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                          onPressed: loading ? null : enter,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(loading ? 'Подключаем…' : 'Продолжить'))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
