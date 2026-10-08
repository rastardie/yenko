import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_backend_io.dart'
    if (dart.library.js_interop) 'biometric_backend_web.dart';

/// The outcome of a user attempting to enable optional biometric unlock.
enum BiometricEnableResult { enabled, unavailable, verificationFailed }

/// Device-local biometric enrollment preference.
///
/// This never represents server authentication or identity verification. It is
/// disabled by default and can only be enabled after the operating system has
/// confirmed an enrolled biometric. Only the boolean preference is persisted;
/// biometric templates remain in the device secure hardware/OS.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  static const _preferenceKey = 'yenko_biometric_unlock_enabled';

  final BiometricBackend _backend = BiometricBackend();
  bool _available = false;
  bool _enabled = false;

  bool get isAvailable => _available;
  bool get isEnabled => _enabled;

  /// Reads the saved preference and verifies that a fingerprint or Face ID is
  /// currently enrolled, not merely that the device supports biometrics.
  /// On the web this is always unavailable; see `biometric_backend_web.dart`.
  Future<void> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _enabled = preferences.getBool(_preferenceKey) ?? false;
      _available = await _backend.hasEnrolledBiometrics();
    } catch (_) {
      // A missing plugin in widget tests or a device error must never make the
      // application unavailable. The user can retry from Profile later.
      _available = false;
    }
  }

  /// Requires a successful device biometric prompt before storing the opt-in.
  Future<BiometricEnableResult> enable() async {
    await initialize();
    if (!_available) return BiometricEnableResult.unavailable;

    try {
      final verified = await _backend.authenticate(
        'Confirm your identity to enable biometric unlock',
      );
      if (!verified) return BiometricEnableResult.verificationFailed;

      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_preferenceKey, true);
      _enabled = true;
      return BiometricEnableResult.enabled;
    } catch (_) {
      return BiometricEnableResult.verificationFailed;
    }
  }

  /// Disabling is always available, including after biometric enrollment has
  /// changed on the device, so a stale preference cannot lock out the app.
  Future<void> disable() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey, false);
    _enabled = false;
  }
}
