import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Makes "sign out" available to every screen below it, including pushed
/// routes, without threading a callback through each constructor. It is only
/// provided while someone is signed in to the local API, so mock mode and the
/// sign-in screens show no sign-out control.
class SignOutScope extends InheritedWidget {
  const SignOutScope({
    super.key,
    required this.onSignOut,
    required super.child,
  });

  final Future<void> Function() onSignOut;

  static SignOutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SignOutScope>();

  @override
  bool updateShouldNotify(SignOutScope oldWidget) =>
      onSignOut != oldWidget.onSignOut;
}

/// Asks for confirmation, then signs out. Returns true if the user signed out.
Future<bool> confirmSignOut(BuildContext context) async {
  final scope = SignOutScope.maybeOf(context);
  if (scope == null) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(
        Icons.power_settings_new_rounded,
        color: YenkoColors.red,
        size: 30,
      ),
      title: const Text(
        'Sign out?',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: const Text(
        'You will need to sign in again to use YɛnKɔ on this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Stay signed in'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: YenkoColors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await scope.onSignOut();
  return true;
}

/// The power icon shown in every screen header while signed in.
class YenkoSignOutButton extends StatelessWidget {
  const YenkoSignOutButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (SignOutScope.maybeOf(context) == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Sign out',
      onPressed: () => confirmSignOut(context),
      icon: const Icon(Icons.power_settings_new_rounded, size: 22),
    );
  }
}
