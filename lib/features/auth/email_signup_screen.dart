import 'package:flutter/material.dart';

import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_widgets.dart';
import 'email_verification_screen.dart';

final _usernamePattern = RegExp(r'^[a-z0-9_.-]{3,32}$');
final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Email + password signup. Collects the full legal name as it appears on the
/// national ID (self-attested for now) and, on success, moves to email
/// verification. Username is optional here (only social signups require one).
class EmailSignupScreen extends StatefulWidget {
  const EmailSignupScreen({
    super.key,
    required this.authClient,
    required this.onSignedIn,
  });

  final LocalAuthClient authClient;
  final void Function(LocalAuthSession session) onSignedIn;

  @override
  State<EmailSignupScreen> createState() => _EmailSignupScreenState();
}

class _EmailSignupScreenState extends State<EmailSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _givenNames = TextEditingController();
  final _surname = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _driver = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _givenNames.dispose();
    _surname.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = await widget.authClient.emailSignup(
        email: _email.text.trim(),
        password: _password.text,
        legalGivenNames: _givenNames.text.trim(),
        legalSurname: _surname.text.trim(),
        username: _username.text.trim().toLowerCase(),
        role: _driver ? 'driver' : 'passenger',
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => EmailVerificationScreen(
            authClient: widget.authClient,
            session: session,
            onSignedIn: widget.onSignedIn,
          ),
        ),
      );
    } on LocalAuthPendingApproval catch (pending) {
      if (!mounted) return;
      setState(() => _submitting = false);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Almost there'),
          content: Text(pending.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context)
                ..pop()
                ..pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on LocalAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not reach the server. Please try again.';
      });
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
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
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
                    padding: EdgeInsets.only(bottom: keyboardOpen ? 6 : 14),
                    child: YenkoLogo(height: keyboardOpen ? 32 : 48),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
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
                            'Sign up with email',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: YenkoColors.charcoal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Use your full name exactly as it appears on your national ID.',
                            style: TextStyle(
                              color: YenkoColors.gray,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (v) =>
                                (v == null || !_emailPattern.hasMatch(v.trim()))
                                ? 'Enter a valid email address.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _givenNames,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Given names (as on ID)',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter your given names.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _surname,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Surname (as on ID)',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter your surname.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Username (optional)',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            validator: (v) {
                              final value = v?.trim().toLowerCase() ?? '';
                              if (value.isEmpty) return null;
                              return _usernamePattern.hasMatch(value)
                                  ? null
                                  : '3-32 lowercase letters, numbers or ._-';
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v == null || v.length < 8)
                                ? 'Use at least 8 characters.'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Expanded(
                                child: Text('I want to offer rides (driver)'),
                              ),
                              Switch(
                                value: _driver,
                                activeThumbColor: YenkoColors.gold,
                                onChanged: _submitting
                                    ? null
                                    : (value) =>
                                          setState(() => _driver = value),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: YenkoColors.red,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          YenkoPrimaryButton(
                            label: _submitting
                                ? 'Creating account…'
                                : 'Create account',
                            onPressed: _submitting ? () {} : _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
