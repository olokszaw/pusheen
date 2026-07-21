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
            // Keep the background visible: this is acrylic, not an opaque card.
            // Hover/splash glare is removed from InkWell below instead.
            color: dark
                ? const Color(0xFF141421).withValues(alpha: .30)
                : Colors.white.withValues(alpha: .30),
            borderRadius: borderRadius,
            border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: .20)
                    : const Color(0x225C4A85)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .22),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
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
