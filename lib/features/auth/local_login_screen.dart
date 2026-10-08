import 'package:flutter/material.dart';

import '../../core/data/last_username_store.dart';
import '../../core/data/local_auth_client.dart';
import '../../core/security/biometric_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_widgets.dart';
import 'local_signup_screen.dart';
import 'social_auth_buttons.dart';

/// Local-development sign-in screen for AUTH_MODE=local-pin. Not shown in
/// mock mode, and not a stand-in for the production OIDC sign-in flow.
///
/// Biometric sign-in here only re-plays the last-used username/PIN after a
/// successful device biometric check; the device preference itself is set up
/// from Profile, matching [BiometricService]'s existing opt-in design.
class LocalLoginScreen extends StatefulWidget {
  const LocalLoginScreen({
    super.key,
    required this.authClient,
    required this.onSignedIn,
  });

  final LocalAuthClient authClient;
  final void Function(LocalAuthSession session) onSignedIn;

  @override
  State<LocalLoginScreen> createState() => _LocalLoginScreenState();
}

class _LocalLoginScreenState extends State<LocalLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLastUsername();
    _loadBiometricState();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadLastUsername() async {
    final last = await LastUsernameStore.read();
    if (last != null && mounted) {
      setState(() => _usernameController.text = last);
    }
  }

  Future<void> _loadBiometricState() async {
    await BiometricService.instance.initialize();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = BiometricService.instance.isAvailable;
      _biometricEnabled = BiometricService.instance.isEnabled;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _attemptLogin(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  /// Biometric sign-in only unlocks resubmitting the last-used username with
  /// the password or PIN already typed into this form; it does not store or
  /// recall the credential itself. If the field is empty, there is nothing to
  /// replay.
  Future<void> _biometricSignIn() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _errorMessage =
            'Enter your username and password once, then use biometrics next time.',
      );
      return;
    }
    final verified = await BiometricService.instance.enable();
    if (verified != BiometricEnableResult.enabled &&
        !BiometricService.instance.isEnabled) {
      setState(
        () => _errorMessage = 'Biometric verification was not completed.',
      );
      return;
    }
    await _attemptLogin(username: username, password: password);
  }

  Future<void> _attemptLogin({
    required String username,
    required String password,
  }) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final session = await widget.authClient.login(
        identity: username,
        password: password,
      );
      await LastUsernameStore.write(username);
      if (!mounted) return;
      widget.onSignedIn(session);
      // The landing screen pushed this route on top of the app's root. Once
      // onSignedIn swaps the root to the authenticated app, remove the pushed
      // auth routes so the app is revealed instead of staying on this screen.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on LocalAuthException catch (error) {
      setState(() => _errorMessage = error.message);
    } catch (_) {
      setState(
        () => _errorMessage = 'Could not reach the local API. Is it running?',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFE8A3),
                  YenkoColors.cream,
                  YenkoColors.cream,
                ],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: .16,
                child: Image.asset(
                  'assets/app/getting_started_city_watermark.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
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
                      Column(
                        children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                              child: BackButton(
                                color: YenkoColors.charcoal,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                              top: keyboardOpen ? 4 : 20,
                              bottom: keyboardOpen ? 8 : 20,
                            ),
                            child: YenkoLogo(height: keyboardOpen ? 36 : 56),
                          ),
                        ],
                      ),
                      Container(
                        margin: EdgeInsets.fromLTRB(
                          constraints.maxWidth >= 640
                              ? (constraints.maxWidth - 440) / 2
                              : 20,
                          0,
                          constraints.maxWidth >= 640
                              ? (constraints.maxWidth - 440) / 2
                              : 20,
                          20,
                        ),
                        padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Welcome back',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: YenkoColors.charcoal,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Sign in to continue',
                                style: TextStyle(
                                  color: YenkoColors.gray,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 22),
                              TextFormField(
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                decoration: const InputDecoration(
                                  labelText: 'Username or email',
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                  ),
                                ),
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                    ? 'Enter your username or email.'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                keyboardType: TextInputType.visiblePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Password or PIN',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                validator: (value) =>
                                    (value == null || value.isEmpty)
                                    ? 'Enter your password or PIN.'
                                    : null,
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: YenkoColors.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              YenkoPrimaryButton(
                                label: _isSubmitting
                                    ? 'Signing in…'
                                    : 'Sign in',
                                onPressed: _isSubmitting ? () {} : _submit,
                              ),
                              if (_biometricAvailable) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 50,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: YenkoColors.charcoal,
                                      side: const BorderSide(
                                        color: Color(0xFFE1E4E8),
                                      ),
                                      shape: const StadiumBorder(),
                                    ),
                                    onPressed: _isSubmitting
                                        ? null
                                        : _biometricSignIn,
                                    icon: const Icon(Icons.fingerprint_rounded),
                                    label: Text(
                                      _biometricEnabled
                                          ? 'Sign in with biometrics'
                                          : 'Enable & sign in with biometrics',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              Row(
                                children: const [
                                  Expanded(
                                    child: Divider(color: Color(0xFFE1E4E8)),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Text(
                                      'or sign in with',
                                      style: TextStyle(
                                        color: YenkoColors.gray,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(color: Color(0xFFE1E4E8)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SocialAuthButtons(
                                authClient: widget.authClient,
                                onSignedIn: widget.onSignedIn,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Don't have an account? ",
                                    style: TextStyle(
                                      color: YenkoColors.gray,
                                      fontSize: 13,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        Navigator.of(context).pushReplacement(
                                          MaterialPageRoute<void>(
                                            builder: (_) => LocalSignupScreen(
                                              authClient: widget.authClient,
                                              onSignedIn: widget.onSignedIn,
                                            ),
                                          ),
                                        ),
                                    child: const Text(
                                      'Sign up',
                                      style: TextStyle(
                                        color: YenkoColors.gold,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
}
