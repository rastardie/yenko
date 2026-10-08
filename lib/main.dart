import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/data/admin_api_client.dart';
import 'core/data/local_api_trip_repository.dart';
import 'core/data/local_auth_client.dart';
import 'core/data/trip_repository.dart';
import 'core/security/biometric_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/local_landing_screen.dart';
import 'features/startup/yenko_splash_screen.dart';
import 'features/admin/admin_widgets.dart' show showAdminActionPrompt;
import 'features/navigation/yenko_root_screen.dart';
import 'shared/widgets/sign_out.dart';
import 'shared/widgets/yenko_showcase_widgets.dart';
import 'shared/widgets/yenko_widgets.dart';

void main() => runApp(const YenkoApp());

class YenkoApp extends StatefulWidget {
  const YenkoApp({super.key, this.repository});

  final TripRepository? repository;

  @override
  State<YenkoApp> createState() => _YenkoAppState();
}

class _YenkoAppState extends State<YenkoApp> {
  TripRepository? _repository;
  Future<void>? _startup;
  LocalAuthClient? _authClient;
  LocalAuthSession? _session;
  AdminApiClient? _adminClient;
  final _navigatorKey = GlobalKey<NavigatorState>();

  /// Shows the banner splash briefly at launch, then reveals the app. The OS
  /// system splash (an icon) cannot be a wide banner, so this guarantees the
  /// banner is seen at startup on every device.
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    if (widget.repository != null) {
      _repository = widget.repository;
      _startup = _repository!.initialize();
    } else if (AppConfig.useLocalApi) {
      _authClient = LocalAuthClient(baseUrl: AppConfig.localApiBaseUrl);
      // Web passkey registration needs a client to call the WebAuthn
      // endpoints on; native biometric unlock never touches this. See
      // BiometricService's class doc comment.
      BiometricService.instance.authClient = _authClient;
    } else {
      _repository = InMemoryTripRepository();
      _startup = _repository!.initialize();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _splashDone = true);
      });
    });
  }

  void _onSignedIn(LocalAuthSession session) {
    final repository = LocalApiTripRepository(
      baseUrl: AppConfig.localApiBaseUrl,
      accessToken: session.accessToken,
      role: session.role,
    );
    _adminClient?.dispose();
    final adminClient = session.hasAdminAccess
        ? AdminApiClient(
            baseUrl: AppConfig.localApiBaseUrl,
            accessToken: session.accessToken,
            promptCredential: ({String? error}) async {
              final context = _navigatorKey.currentContext;
              return context == null
                  ? null
                  : showAdminActionPrompt(context, error: error);
            },
          )
        : null;
    setState(() {
      _session = session;
      _adminClient = adminClient;
      _repository = repository;
      _startup = repository.initialize();
    });
  }

  void _retryStartup() {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _startup = repository.initialize());
  }

  void _returnToLanding() {
    if (_repository is ChangeNotifier) {
      (_repository as ChangeNotifier).dispose();
    }
    _adminClient?.dispose();
    setState(() {
      _repository = null;
      _startup = null;
      _session = null;
      _adminClient = null;
    });
  }

  Future<void> _signOut() async {
    final token = _session?.accessToken;
    // Close any admin pages pushed on top before swapping the root screen.
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _returnToLanding();
    if (token != null) await _authClient?.logout(token);
  }

  @override
  void dispose() {
    _authClient?.dispose();
    _adminClient?.dispose();
    if (_repository is ChangeNotifier) {
      (_repository as ChangeNotifier).dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'YɛnKɔ',
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigatorKey,
    theme: YenkoTheme.light,
    // While signed in to the local API every screen, including pushed admin
    // pages, can offer a confirmed sign-out.
    builder: (context, child) => _session == null || child == null
        ? (child ?? const SizedBox.shrink())
        : SignOutScope(onSignOut: _signOut, child: child),
    home: !_splashDone
        ? const YenkoSplashScreen()
        : _repository == null
        ? LocalLandingScreen(authClient: _authClient!, onSignedIn: _onSignedIn)
        : FutureBuilder<void>(
            future: _startup,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _StartupState(
                  icon: Icons.directions_car_outlined,
                  message: 'Preparing your trips…',
                );
              }
              if (snapshot.hasError) {
                return _StartupState(
                  icon: Icons.cloud_off_rounded,
                  title: 'We could not load your rides',
                  message:
                      'Check that the local API is running, then try again. Your account remains signed in on this device.',
                  onRetry: _retryStartup,
                  onReturnToLanding: AppConfig.useLocalApi
                      ? _returnToLanding
                      : null,
                );
              }
              return YenkoRootScreen(
                repository: _repository!,
                session: _session,
                adminClient: _adminClient,
              );
            },
          ),
  );
}

class _StartupState extends StatelessWidget {
  const _StartupState({
    required this.icon,
    required this.message,
    this.title = 'Preparing your rides',
    this.onRetry,
    this.onReturnToLanding,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onReturnToLanding;

  @override
  Widget build(BuildContext context) => YenkoShowcaseBackdrop(
    useWatermark: true,
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: YenkoShowcaseCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const YenkoLogo(height: 40),
                const SizedBox(height: 18),
                Container(
                  width: 62,
                  height: 62,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE8A3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 30, color: YenkoColors.charcoal),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: YenkoColors.gray, height: 1.35),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 22),
                  YenkoShowcaseButton(
                    label: 'Try again',
                    icon: Icons.refresh_rounded,
                    onPressed: onRetry!,
                  ),
                ],
                if (onReturnToLanding != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: onReturnToLanding,
                    child: const Text('Return to sign in'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
