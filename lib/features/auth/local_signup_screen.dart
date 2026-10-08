import 'package:flutter/material.dart';

import '../../core/data/last_username_store.dart';
import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_widgets.dart';
import 'email_signup_screen.dart';
import 'local_login_screen.dart';
import 'social_auth_buttons.dart';

final _usernamePattern = RegExp(r'^[a-z0-9_.-]{3,32}$');

/// Local-development sign-up screen for AUTH_MODE=local-pin. New accounts
/// default to the passenger role, matching the backend's signup behavior;
/// not shown in mock mode, and not a stand-in for the production OIDC flow.
class LocalSignupScreen extends StatefulWidget {
  const LocalSignupScreen({
    super.key,
    required this.authClient,
    required this.onSignedIn,
  });

  final LocalAuthClient authClient;
  final void Function(LocalAuthSession session) onSignedIn;

  @override
  State<LocalSignupScreen> createState() => _LocalSignupScreenState();
}

class _LocalSignupScreenState extends State<LocalSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _homeAreaController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String _role = 'passenger';
  String? _errorMessage;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _homeAreaController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final username = _usernameController.text.trim().toLowerCase();
      final session = await widget.authClient.signup(
        displayName: _displayNameController.text.trim(),
        username: username,
        password: _passwordController.text,
        role: _role,
        homeArea: _homeAreaController.text.trim(),
      );
      await LastUsernameStore.write(username);
      if (!mounted) return;
      widget.onSignedIn(session);
      // Reveal the authenticated app by removing the pushed auth routes.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on LocalAuthPendingApproval catch (pending) {
      await LastUsernameStore.write(
        _usernameController.text.trim().toLowerCase(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.hourglass_bottom_rounded, size: 30),
          title: const Text(
            'Waiting for approval',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(pending.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
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
                              top: keyboardOpen ? 4 : 16,
                              bottom: keyboardOpen ? 6 : 16,
                            ),
                            child: YenkoLogo(height: keyboardOpen ? 34 : 52),
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
                                'Create your account',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: YenkoColors.charcoal,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Join YɛnKɔ to find or offer shared rides.',
                                style: TextStyle(
                                  color: YenkoColors.gray,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 20),
                              // New signups most often come through social or
                              // email, so these lead the screen; the username
                              // form stays below for anyone who prefers it.
                              SocialAuthButtons(
                                authClient: widget.authClient,
                                onSignedIn: widget.onSignedIn,
                              ),
                              SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: YenkoColors.charcoal,
                                    side: const BorderSide(
                                      color: Color(0xFFE1E4E8),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                  ),
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => EmailSignupScreen(
                                              authClient: widget.authClient,
                                              onSignedIn: widget.onSignedIn,
                                            ),
                                          ),
                                        ),
                                  icon: const Icon(
                                    Icons.mail_outline_rounded,
                                    size: 24,
                                  ),
                                  label: const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Continue with email',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
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
                                      'or with a username',
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
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _displayNameController,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) {
                                    return 'Enter your name.';
                                  }
                                  if (trimmed.length > 120) {
                                    return 'Name is too long.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'I want to',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: YenkoColors.charcoal,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<String>(
                                style: SegmentedButton.styleFrom(
                                  selectedBackgroundColor: YenkoColors.gold,
                                  selectedForegroundColor: YenkoColors.charcoal,
                                  visualDensity: VisualDensity.compact,
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: 'passenger',
                                    label: Text('Find a ride'),
                                    icon: Icon(
                                      Icons.person_search_rounded,
                                      size: 18,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 'driver',
                                    label: Text('Offer rides'),
                                    icon: Icon(
                                      Icons.directions_car_filled_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ],
                                selected: {_role},
                                onSelectionChanged: (selection) =>
                                    setState(() => _role = selection.first),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _role == 'driver'
                                    ? 'You can post trips. Vehicle details are added when you post your first trip.'
                                    : 'You can request seats on trips drivers post.',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: YenkoColors.gray,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _homeAreaController,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Home area (optional)',
                                  hintText: 'e.g. East Legon, Adenta',
                                  prefixIcon: Icon(Icons.home_outlined),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.newUsername,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  hintText: 'lowercase, numbers, . _ -',
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                  ),
                                ),
                                validator: (value) {
                                  final trimmed =
                                      value?.trim().toLowerCase() ?? '';
                                  if (!_usernamePattern.hasMatch(trimmed)) {
                                    return '3-32 lowercase letters, numbers, or . _ -';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                keyboardType: TextInputType.visiblePassword,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  hintText: 'At least 8 characters',
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
                                validator: (value) {
                                  final length = value?.length ?? 0;
                                  if (length < 8 || length > 128) {
                                    return 'Password must be at least 8 characters.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscurePassword,
                                keyboardType: TextInputType.visiblePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: const InputDecoration(
                                  labelText: 'Confirm password',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                ),
                                validator: (value) =>
                                    (value != _passwordController.text)
                                    ? 'Passwords do not match.'
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
                                    ? 'Creating account…'
                                    : 'Sign up',
                                onPressed: _isSubmitting ? () {} : _submit,
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Already have an account? ',
                                    style: TextStyle(
                                      color: YenkoColors.gray,
                                      fontSize: 13,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        Navigator.of(context).pushReplacement(
                                          MaterialPageRoute<void>(
                                            builder: (_) => LocalLoginScreen(
                                              authClient: widget.authClient,
                                              onSignedIn: widget.onSignedIn,
                                            ),
                                          ),
                                        ),
                                    child: const Text(
                                      'Sign in',
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
