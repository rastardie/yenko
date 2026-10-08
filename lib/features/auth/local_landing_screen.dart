import 'package:flutter/material.dart';

import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_widgets.dart';
import 'local_login_screen.dart';
import 'local_signup_screen.dart';

/// Local-development landing screen for AUTH_MODE=local-pin: existing users
/// sign in, new users sign up. Not shown in mock mode, and not a stand-in
/// for the production OIDC entry flow.
class LocalLandingScreen extends StatelessWidget {
  const LocalLandingScreen({
    super.key,
    required this.authClient,
    required this.onSignedIn,
  });

  final LocalAuthClient authClient;
  final void Function(LocalAuthSession session) onSignedIn;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        // Background matched to the supplied banner's cream so the full-bleed
        // hero image blends seamlessly into the rest of the screen.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFDEBC2), Color(0xFFFCE9C5), Color(0xFFF8F2E4)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Logo-free city watermark, kept on every screen. The banner (with its
        // own baked arch) sits on top, so the watermark fills the area below it.
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
        // Warm-cream scrim (matched to the banner) keeps the watermark a faint
        // backdrop and softens the seam below the full-bleed hero.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33FFF3D6), Color(0x88FCE9C5), Color(0xC8F8F2E4)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // The exact supplied banner (logo, tagline, promise strip
                    // and sub-line are baked into this one asset, including its
                    // own city-arch watermark), rendered full width.
                    Image.asset(
                      'assets/app/yenko_landing_banner.png',
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                      semanticLabel:
                          'YɛnKɔ — Your Journey, Simplified. '
                          'Offer for drivers, Book for riders, Share a fixed fare. '
                          'Fixed prices. No bidding. Public pickup junctions.',
                    ),
                    Container(
                      margin: EdgeInsets.fromLTRB(
                        constraints.maxWidth >= 640
                            ? (constraints.maxWidth - 420) / 2
                            : 24,
                        24,
                        constraints.maxWidth >= 640
                            ? (constraints.maxWidth - 420) / 2
                            : 24,
                        28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          YenkoPrimaryButton(
                            label: 'Sign in',
                            icon: Icons.login_rounded,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => LocalLoginScreen(
                                  authClient: authClient,
                                  onSignedIn: onSignedIn,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 52,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: YenkoColors.charcoal,
                                side: const BorderSide(
                                  color: Color(0xFFE1E4E8),
                                  width: 1.4,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => LocalSignupScreen(
                                    authClient: authClient,
                                    onSignedIn: onSignedIn,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.person_add_outlined),
                              label: const Text('New here? Sign up'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
