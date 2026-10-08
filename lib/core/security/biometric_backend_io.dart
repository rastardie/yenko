import 'package:local_auth/local_auth.dart';

/// Native (Android/iOS/desktop) biometric backend. `local_auth` has no web
/// implementation, so this file is only selected on non-web platforms via
/// the conditional import in `biometric_service.dart`.
class BiometricBackend {
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> hasEnrolledBiometrics() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    if (!canCheck) return false;
    final enrolled = await _localAuth.getAvailableBiometrics();
    return enrolled.isNotEmpty;
  }

  Future<bool> authenticate(String localizedReason) => _localAuth.authenticate(
    localizedReason: localizedReason,
    biometricOnly: true,
    persistAcrossBackgrounding: true,
  );
}
