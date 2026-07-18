import 'dart:async';

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
  final nickname = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  Timer? availabilityTimer;
  bool createAccount = true;
  bool loading = false;
  bool checking = false;
  bool? available;
  bool obscure = true;

  @override
  void initState() {
    super.initState();
    username.addListener(checkUsername);
    nickname.addListener(refreshPreview);
  }

  void refreshPreview() => setState(() {});

  void checkUsername() {
    setState(() {
      available = null;
      checking = createAccount && username.text.trim().length >= 3;
    });
    availabilityTimer?.cancel();
    if (!checking) return;
    availabilityTimer = Timer(const Duration(milliseconds: 420), () async {
      try {
        final result = await widget.api.usernameAvailable(username.text);
        if (mounted)
          setState(() {
            available = result;
            checking = false;
          });
      } on Object {
        if (mounted)
          setState(() {
            available = null;
            checking = false;
          });
      }
    });
  }

  Future<void> submit() async {
    if (username.text.trim().length < 3 ||
        password.text.length < 6 ||
        (createAccount && nickname.text.trim().length < 2)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Проверь поля: username от 3 символов, пароль от 6')));
      return;
    }
    setState(() => loading = true);
    try {
      if (createAccount) {
        await widget.api.register(
            nickname: nickname.text,
            username: username.text,
            password: password.text);
      } else {
        await widget.api
            .accountLogin(username: username.text, password: password.text);
      }
      if (mounted) widget.onAuthenticated();
    } on Object catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    availabilityTimer?.cancel();
    nickname.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: GlowScaffold(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        gradient: const LinearGradient(
                            colors: [pulsePink, pulsePurple, pulseBlue]),
                        boxShadow: [
                          BoxShadow(
                              color: pulsePurple.withValues(alpha: .35),
                              blurRadius: 30)
                        ],
                      ),
                      child: const Icon(Icons.play_arrow_rounded, size: 38),
                    ),
                    const SizedBox(height: 20),
                    Text(createAccount ? 'Создай профиль' : 'С возвращением',
                        style: const TextStyle(
                            fontSize: 30, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                        createAccount
                            ? 'Nickname можно повторять. @username — только твой.'
                            : 'Войди по уникальному @username',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60)),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: createAccount
                          ? _ProfilePreview(
                              nickname: nickname.text,
                              username: username.text,
                              checking: checking,
                              available: available)
                          : const SizedBox.shrink(),
                    ),
                    if (createAccount) const SizedBox(height: 12),
                    GlassCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        if (createAccount) ...[
                          TextField(
                              controller: nickname,
                              textInputAction: TextInputAction.next,
                              maxLength: 50,
                              decoration: const InputDecoration(
                                  labelText: 'Nickname',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                  counterText: '')),
                          const SizedBox(height: 9),
                        ],
                        TextField(
                            controller: username,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                                labelText: 'Username',
                                prefixText: '@',
                                suffixIcon: createAccount
                                    ? AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        child: checking
                                            ? const Padding(
                                                padding: EdgeInsets.all(13),
                                                child: SizedBox.square(
                                                    dimension: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2)))
                                            : available == null
                                                ? null
                                                : Icon(
                                                    available!
                                                        ? Icons
                                                            .check_circle_rounded
                                                        : Icons.cancel_rounded,
                                                    color: available!
                                                        ? const Color(
                                                            0xFF76F7B0)
                                                        : Colors.redAccent))
                                    : null)),
                        const SizedBox(height: 9),
                        TextField(
                            controller: password,
                            obscureText: obscure,
                            onSubmitted: (_) => submit(),
                            decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => obscure = !obscure),
                                    icon: Icon(obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined)))),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                            onPressed: loading ? null : submit,
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: Text(loading
                                ? 'Подключаем…'
                                : createAccount
                                    ? 'Создать аккаунт'
                                    : 'Войти'))),
                    TextButton(
                        onPressed: () => setState(() {
                              createAccount = !createAccount;
                              available = null;
                              checkUsername();
                            }),
                        child: Text(createAccount
                            ? 'Уже есть аккаунт? Войти'
                            : 'Нет аккаунта? Создать')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

class _ProfilePreview extends StatelessWidget {
  final String nickname;
  final String username;
  final bool checking;
  final bool? available;
  const _ProfilePreview(
      {required this.nickname,
      required this.username,
      required this.checking,
      required this.available});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .065),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color:
                    (available == true ? const Color(0xFF76F7B0) : pulsePurple)
                        .withValues(alpha: .35))),
        child: Row(children: [
          CircleAvatar(
              radius: 22,
              backgroundColor: pulsePurple.withValues(alpha: .38),
              child: Text(
                  (nickname.trim().isEmpty ? '?' : nickname.trim()[0])
                      .toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900))),
          const SizedBox(width: 11),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    nickname.trim().isEmpty ? 'Твой nickname' : nickname.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                    '@${username.trim().isEmpty ? 'username' : username.trim()}',
                    style: const TextStyle(fontSize: 12, color: Colors.white54))
              ])),
          AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                  checking
                      ? 'проверяем'
                      : available == true
                          ? 'свободен'
                          : available == false
                              ? 'занят'
                              : '',
                  style: TextStyle(
                      fontSize: 10,
                      color: available == true
                          ? const Color(0xFF76F7B0)
                          : Colors.white54))),
        ]),
      );
}
