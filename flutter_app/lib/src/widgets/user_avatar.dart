import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  final String dataUrl;
  final String name;
  final double size;

  const UserAvatar({
    super.key,
    required this.dataUrl,
    required this.name,
    this.size = 34,
  });

  Uint8List? get bytes {
    final separator = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:image/') || separator < 0) return null;
    try {
      return base64Decode(dataUrl.substring(separator + 1));
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = bytes;
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: imageBytes == null
            ? ColoredBox(
                color: const Color(0xFF65449E),
                child: Center(
                  child: Text(
                    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: size * .42,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            : Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFF65449E),
                  child: Icon(Icons.person_rounded, color: Colors.white),
                ),
              ),
      ),
    );
  }
}
