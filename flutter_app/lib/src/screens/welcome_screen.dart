import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../watch_party/api_client.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class WelcomeScreen extends StatefulWidget {
  final ApiClient api;
  final VoidCallback onToggleTheme;
  final VoidCallback onAuthenticated;

  const WelcomeScreen({
    super.key,
    required this.api,
    required this.onToggleTheme,
    required this.onAuthenticated,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static final _usernamePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]{2,29}$');

  final nickname = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  Timer? availabilityTimer;
  bool createAccount = true;
  bool loading = false;
  bool checking = false;
  bool? available;
  bool obscure = true;

  String get normalizedUsername => username.text.trim();
  bool get usernameHasValue => normalizedUsername.isNotEmpty;
  bool get usernameIsValid => _usernamePattern.hasMatch(normalizedUsername);

  @override
  void initState() {
    super.initState();
    username.addListener(checkUsername);
    nickname.addListener(refreshPreview);
  }

  void refreshPreview() {
    if (mounted) setState(() {});
  }

  void checkUsername() {
    availabilityTimer?.cancel();
    final shouldCheck = createAccount && usernameIsValid;
    setState(() {
      available = null;
      checking = shouldCheck;
    });
    if (!shouldCheck) return;

    final requestedUsername = normalizedUsername;
    availabilityTimer = Timer(const Duration(milliseconds: 420), () async {
      try {
        final result = await widget.api.usernameAvailable(requestedUsername);
        if (!mounted || normalizedUsername != requestedUsername) return;
        setState(() {
          available = result;
          checking = false;
        });
      } on Object {
        if (!mounted || normalizedUsername != requestedUsername) return;
        setState(() {
          available = null;
          checking = false;
        });
      }
    });
  }

  void switchMode(bool value) {
    if (createAccount == value || loading) return;
    FocusScope.of(context).unfocus();
    availabilityTimer?.cancel();
    setState(() {
      createAccount = value;
      checking = false;
      available = null;
    });
    if (value) checkUsername();
  }

  Future<void> submit() async {
    if (!usernameIsValid) {
      _showMessage(
          'Username: 3–30 символов, первая — английская буква. Можно использовать цифры и _.');
      return;
    }
    if (password.text.length < 6 ||
        (createAccount && nickname.text.trim().length < 2)) {
      _showMessage(createAccount
          ? 'Nickname — минимум 2 символа, пароль — минимум 6.'
          : 'Пароль должен содержать минимум 6 символов.');
      return;
    }
    if (createAccount && available == false) {
      _showMessage('Этот username уже занят.');
      return;
    }

    setState(() => loading = true);
    try {
      if (createAccount) {
        await widget.api.register(
          nickname: nickname.text,
          username: normalizedUsername,
          password: password.text,
        );
      } else {
        await widget.api.accountLogin(
          username: normalizedUsername,
          password: password.text,
        );
      }
      if (mounted) widget.onAuthenticated();
    } on Object catch (error) {
      if (mounted) _showMessage('$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          gradient: const LinearGradient(
                            colors: [pulsePink, pulsePurple, pulseBlue],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: pulsePurple.withValues(alpha: .35),
                              blurRadius: 30,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow_rounded, size: 38),
                      ),
                      const SizedBox(height: 20),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .08),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            )),
                            child: child,
                          ),
                        ),
                        child: Text(
                          createAccount ? 'Создай профиль' : 'С возвращением',
                          key: ValueKey(createAccount),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _AuthModeSwitcher(
                        createAccount: createAccount,
                        onChanged: switchMode,
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: Column(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 240),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: SizeTransition(
                                    sizeFactor: animation,
                                    alignment: Alignment.topCenter,
                                    child: child,
                                  ),
                                ),
                                child: createAccount
                                    ? Column(
                                        key: const ValueKey('nickname-field'),
                                        children: [
                                          TextField(
                                            controller: nickname,
                                            textInputAction:
                                                TextInputAction.next,
                                            maxLength: 50,
                                            decoration: const InputDecoration(
                                              labelText: 'Nickname',
                                              prefixIcon:
                                                  Icon(Icons.badge_outlined),
                                              counterText: '',
                                            ),
                                          ),
                                          const SizedBox(height: 9),
                                        ],
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('no-nickname-field'),
                                      ),
                              ),
                              TextField(
                                controller: username,
                                autocorrect: false,
                                enableSuggestions: false,
                                textCapitalization: TextCapitalization.none,
                                textInputAction: TextInputAction.next,
                                maxLength: 30,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[A-Za-z0-9_]')),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  prefixText: '@',
                                  counterText: '',
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: SizeTransition(
                                    sizeFactor: animation,
                                    alignment: Alignment.topCenter,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, -.08),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                                ),
                                child: createAccount && usernameHasValue
                                    ? Padding(
                                        key: ValueKey(
                                            'preview-$normalizedUsername'),
                                        padding: const EdgeInsets.only(top: 8),
                                        child: _ProfilePreview(
                                          nickname: nickname.text,
                                          username: normalizedUsername,
                                          valid: usernameIsValid,
                                          checking: checking,
                                          available: available,
                                        ),
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('no-preview'),
                                      ),
                              ),
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
                                        : Icons.visibility_off_outlined),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: loading ? null : submit,
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: loading
                                ? const SizedBox.square(
                                    key: ValueKey('loading'),
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_forward_rounded,
                                    key: ValueKey('arrow'),
                                  ),
                          ),
                          label:
                              Text(createAccount ? 'Создать аккаунт' : 'Войти'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _AuthModeSwitcher extends StatelessWidget {
  final bool createAccount;
  final ValueChanged<bool> onChanged;

  const _AuthModeSwitcher({
    required this.createAccount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        height: 46,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .11)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / 2;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: createAccount ? width : 0,
                  width: width,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          pulsePurple.withValues(alpha: .72),
                          pulseBlue.withValues(alpha: .42),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: pulsePurple.withValues(alpha: .18),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    _ModeButton(
                      text: 'Уже есть аккаунт',
                      selected: !createAccount,
                      onTap: () => onChanged(false),
                    ),
                    _ModeButton(
                      text: 'Создать аккаунт',
                      selected: createAccount,
                      onTap: () => onChanged(true),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
}

class _ModeButton extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
              child: Text(text),
            ),
          ),
        ),
      );
}

class _ProfilePreview extends StatelessWidget {
  final String nickname;
  final String username;
  final bool valid;
  final bool checking;
  final bool? available;

  const _ProfilePreview({
    required this.nickname,
    required this.username,
    required this.valid,
    required this.checking,
    required this.available,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = !valid
        ? Colors.orangeAccent
        : available == true
            ? const Color(0xFF76F7B0)
            : available == false
                ? Colors.redAccent
                : Colors.white38;
    final statusText = !valid
        ? 'Начни с английской буквы'
        : checking
            ? 'Проверяем…'
            : available == true
                ? 'Username свободен'
                : available == false
                    ? 'Username занят'
                    : 'Проверка недоступна';
    final displayName =
        nickname.trim().isEmpty ? 'Твой nickname' : nickname.trim();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: .24)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: pulsePurple.withValues(alpha: .35),
            child: Text(
              (displayName == 'Твой nickname' ? '?' : displayName[0])
                  .toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '@$username',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: checking
                ? const SizedBox.square(
                    key: ValueKey('checking'),
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    key: ValueKey(statusText),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        valid && available == true
                            ? Icons.check_circle_rounded
                            : valid && available == false
                                ? Icons.cancel_rounded
                                : Icons.info_outline_rounded,
                        size: 15,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 104),
                        child: Text(
                          statusText,
                          maxLines: 2,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.1,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
