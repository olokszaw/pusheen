import 'dart:ui';

import 'package:flutter/material.dart';

class GlowScaffold extends StatelessWidget {
  final Widget child;
  const GlowScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
            top: -120, left: -100, child: _orb(const Color(0xFF7148DC), 280)),
        Positioned(
            bottom: -130,
            right: -100,
            child: _orb(const Color(0xFFE54D9C), 260)),
        Positioned(
            top: 280, right: -100, child: _orb(const Color(0xFF287AC4), 180)),
        child,
      ],
    );
  }

  Widget _orb(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
      child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: color.withOpacity(.48))),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xFF171722).withValues(alpha: .78)
                : Colors.white.withOpacity(.68),
            borderRadius: borderRadius,
            border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: .085)
                    : const Color(0x225C4A85)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: Padding(
                padding: padding,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
