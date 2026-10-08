/// Web stand-in: there is no secure hardware-backed biometric enrollment to
/// check in a browser, so biometric unlock is simply never available there.
/// Selected only on web via the conditional import in `biometric_service.dart`.
class BiometricBackend {
  Future<bool> hasEnrolledBiometrics() async => false;

  Future<bool> authenticate(String localizedReason) async => false;
}
