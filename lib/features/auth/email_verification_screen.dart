import 'package:flutter/material.dart';

import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_widgets.dart';

/// Confirms the email address of a freshly created account with a 6-digit code.
/// The account is already signed in; verification can also be skipped for now
/// (the backend allows an unverified email until a stricter policy is set).
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.authClient,
    required this.session,
    required this.onSignedIn,
  });

  final LocalAuthClient authClient;
  final LocalAuthSession session;
  final void Function(LocalAuthSession session) onSignedIn;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _code = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _devCode;

  @override
  void initState() {
    super.initState();
    _requestCode();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    try {
      final data = await widget.authClient.requestEmailVerification(
        widget.session.accessToken,
      );
      if (!mounted) return;
      // In development (no mail provider) the server returns the code so the
      // flow can be exercised; show it as a hint.
      final dev = data['devCode'];
      if (dev is String) setState(() => _devCode = dev);
    } catch (_) {
      // Non-fatal: the user can still request another code.
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authClient.confirmEmailVerification(
        widget.session.accessToken,
        code,
      );
      if (!mounted) return;
      widget.onSignedIn(widget.session);
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
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFE8A3), YenkoColors.cream, YenkoColors.cream],
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
                const SizedBox(height: 24),
                const YenkoLogo(height: 48),
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Verify your email',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: YenkoColors.charcoal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Enter the 6-digit code we sent to your email.',
                        style: TextStyle(color: YenkoColors.gray, fontSize: 13),
                      ),
                      if (_devCode != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Development code: $_devCode',
                          style: const TextStyle(
                            color: YenkoColors.gold,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Verification code',
                          prefixIcon: Icon(Icons.pin_outlined),
                          counterText: '',
                        ),
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
                        label: _submitting ? 'Verifying…' : 'Verify email',
                        onPressed: _submitting ? () {} : _confirm,
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _submitting ? null : _requestCode,
                        child: const Text('Resend code'),
                      ),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => widget.onSignedIn(widget.session),
                        child: const Text('Skip for now'),
                      ),
                    ],
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
