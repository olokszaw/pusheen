import 'package:flutter/material.dart';

import '../watch_party/api_client.dart';
import 'screens/shell_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';

class PulseApp extends StatefulWidget {
  const PulseApp({super.key});

  @override
  State<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends State<PulseApp> {
  final ApiClient api = ApiClient();
  ThemeMode themeMode = ThemeMode.dark;
  bool restoringSession = true;
  bool authenticated = false;

  @override
  void initState() {
    super.initState();
    restoreSession();
  }

  Future<void> restoreSession() async {
    final restored = await api.restoreSession();
    if (!mounted) return;
    setState(() {
      authenticated = restored;
      restoringSession = false;
    });
  }

  void toggleTheme() {
    setState(() {
      themeMode =
          themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pulse',
      theme: buildPulseTheme(Brightness.light),
      darkTheme: buildPulseTheme(Brightness.dark),
      themeMode: themeMode,
      home: restoringSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : authenticated
              ? ShellScreen(
                  api: api,
                  onToggleTheme: toggleTheme,
                  onLogout: () => setState(() => authenticated = false),
                )
              : WelcomeScreen(
                  api: api,
                  onToggleTheme: toggleTheme,
                  onAuthenticated: () => setState(() => authenticated = true),
                ),
    );
  }
}
