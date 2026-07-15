import 'package:flutter/material.dart';

const pulsePink = Color(0xFFFF5FA8);
const pulsePurple = Color(0xFF9A68FF);
const pulseBlue = Color(0xFF55B8FF);

ThemeData buildPulseTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0B0B18) : const Color(0xFFF2EFFF),
    colorScheme:
        ColorScheme.fromSeed(seedColor: pulsePurple, brightness: brightness),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor:
          dark ? Colors.white.withOpacity(.08) : Colors.white.withOpacity(.65),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(.16))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(.16))),
    ),
  );
}
