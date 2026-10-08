import 'package:flutter/material.dart';

/// Brief full-screen startup splash showing the supplied YɛnKɔ banner.
///
/// On Android 12+ the OS first shows its own system splash (the launcher icon
/// masked to a circle) and that cannot be a wide banner — this Flutter splash
/// takes over the instant the engine is ready, so the banner is what users see
/// while the app finishes loading, on every device.
class YenkoSplashScreen extends StatelessWidget {
  const YenkoSplashScreen({super.key});

  /// Matched to the banner's cream edges so the image blends into the screen.
  static const _cream = Color(0xFFFDEBC2);

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: _cream,
    body: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFDEBC2), Color(0xFFFCE9C5), Color(0xFFF8F2E4)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Logo-free city watermark, centered, kept on every screen.
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: .15,
              child: Image(
                image: AssetImage(
                  'assets/app/getting_started_city_watermark.png',
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Image(
              image: AssetImage('assets/app/yenko_landing_banner.png'),
              fit: BoxFit.fitWidth,
              semanticLabel: 'YɛnKɔ — Your Journey, Simplified',
            ),
          ),
        ),
        Align(
          alignment: Alignment(0, 0.78),
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              valueColor: AlwaysStoppedAnimation(Color(0xFFE5A900)),
            ),
          ),
        ),
      ],
    ),
  );
}
