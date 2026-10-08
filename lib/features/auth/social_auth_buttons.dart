import 'package:flutter/material.dart';

import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';

/// The social sign-in options (Google, Apple, Facebook, X). Each provider needs
/// its native SDK token and server-side credentials to complete a real sign-in;
/// until an operator configures a provider the button reports its status from
/// the server rather than failing silently. When a provider is enabled and the
/// native token step is wired, the same button signs in or starts the
/// mandatory "username + legal name" step for a first-time account.
class SocialAuthButtons extends StatefulWidget {
  const SocialAuthButtons({
    super.key,
    required this.authClient,
    required this.onSignedIn,
  });

  final LocalAuthClient authClient;
  final void Function(LocalAuthSession session) onSignedIn;

  @override
  State<SocialAuthButtons> createState() => _SocialAuthButtonsState();
}

class _SocialAuthButtonsState extends State<SocialAuthButtons> {
  bool _busy = false;

  static const _providers = [
    (_Provider.google, 'Google', Icons.g_mobiledata_rounded),
    (_Provider.apple, 'Apple', Icons.apple),
    (_Provider.facebook, 'Facebook', Icons.facebook),
    (_Provider.twitter, 'X', Icons.close_rounded),
  ];

  Future<void> _tap(_Provider provider, String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // No native provider SDK is bundled yet, so there is no provider token to
      // send. Probe the server so the user sees the real status (e.g. "not
      // enabled" until credentials are configured) instead of a dead button.
      final session = await widget.authClient.socialAuth(
        provider: provider.name,
        token: '',
      );
      if (!mounted) return;
      widget.onSignedIn(session);
    } on LocalAuthException catch (error) {
      if (!mounted) return;
      _show(label, error.message);
    } catch (_) {
      if (!mounted) return;
      _show(label, 'Could not reach the server. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String label, String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Continue with $label'),
        content: Text(
          '$message\n\nSocial sign-in turns on once this provider is configured. '
          'Email sign-up works now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (provider, label, icon) in _providers) ...[
        _SocialButton(
          label: 'Continue with $label',
          icon: icon,
          onPressed: _busy ? null : () => _tap(provider, label),
        ),
        const SizedBox(height: 10),
      ],
    ],
  );
}

enum _Provider { google, apple, facebook, twitter }

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: YenkoColors.charcoal,
        side: const BorderSide(color: Color(0xFFE1E4E8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 24),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}
