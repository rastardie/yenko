import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'sign_out.dart';
import 'yenko_widgets.dart';

/// Showcase-derived visual primitives shared by the main in-app surfaces.
/// The watermark is a crop of the user-supplied Getting Started artwork and
/// is intentionally kept low-opacity so it never competes with live content.
class YenkoShowcaseBackdrop extends StatelessWidget {
  const YenkoShowcaseBackdrop({
    super.key,
    required this.child,
    this.useWatermark = false,
    this.goldHeader = false,
  });

  final Widget child;
  final bool useWatermark;
  final bool goldHeader;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: goldHeader
                ? const [
                    Color(0xFFFFE49A),
                    YenkoColors.cream,
                    YenkoColors.cream,
                  ]
                : const [
                    Color(0xFFFFF8E9),
                    YenkoColors.cream,
                    YenkoColors.cream,
                  ],
            stops: const [0, .32, 1],
          ),
        ),
      ),
      if (useWatermark)
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: .15,
              child: Image.asset(
                'assets/app/getting_started_city_watermark.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
        ),
      // Keeps all live content readable while the watermark remains full-bleed.
      if (useWatermark)
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33FFF8E9), Color(0x88F8F7F3), Color(0xB8F8F7F3)],
            ),
          ),
        ),
      child,
    ],
  );
}

class YenkoShowcaseCard extends StatelessWidget {
  const YenkoShowcaseCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    elevation: 2,
    shadowColor: const Color(0x1A0E1726),
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class YenkoShowcaseButton extends StatelessWidget {
  const YenkoShowcaseButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: const Color(0xFFF9B900),
        foregroundColor: YenkoColors.charcoal,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      ),
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 19),
      label: Text(label),
    ),
  );
}

class YenkoScreenTitle extends StatelessWidget {
  const YenkoScreenTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.showSignOut = true,
    this.showLogo = true,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  /// Appends the confirm-and-sign-out button (shown only while signed in).
  final bool showSignOut;

  /// Shows the YɛnKɔ logo above the title, as on every page.
  final bool showLogo;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showLogo)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: YenkoLogo(height: 30),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: YenkoColors.charcoal,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: YenkoColors.gray,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?action,
          if (showSignOut) const YenkoSignOutButton(),
        ],
      ),
    ],
  );
}

class YenkoWatermarkEmptyState extends StatelessWidget {
  const YenkoWatermarkEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: .06,
          child: Image.asset(
            'assets/app/getting_started_city_watermark.png',
            height: 175,
            fit: BoxFit.contain,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE8A3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: YenkoColors.charcoal),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: YenkoColors.gray, height: 1.35),
            ),
          ],
        ),
      ],
    ),
  );
}
