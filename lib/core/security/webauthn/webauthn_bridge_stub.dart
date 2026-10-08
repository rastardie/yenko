import 'webauthn_bridge.dart';

/// Non-web stand-in: there is no browser WebAuthn API outside a browser, so
/// passkeys are simply never available here. Native biometric unlock is
/// handled separately by `BiometricService`/`biometric_backend_io.dart`.
/// Selected only on non-web platforms via the conditional import in
/// `webauthn_bridge.dart`.
class _StubWebAuthnBridge implements WebAuthnBridge {
  const _StubWebAuthnBridge();

  @override
  Future<WebAuthnSupport> support() async => WebAuthnSupport.unsupported;

  @override
  Future<bool> isPlatformAuthenticatorAvailable() async => false;

  @override
  Future<Map<String, dynamic>> createCredential(
    Map<String, dynamic> optionsJson,
  ) async => throw UnsupportedError('WebAuthn is only available on web.');

  @override
  Future<Map<String, dynamic>> getAssertion(
    Map<String, dynamic> optionsJson,
  ) async => throw UnsupportedError('WebAuthn is only available on web.');

  @override
  Future<bool> isConditionalMediationAvailable() async => false;

  @override
  Future<Map<String, dynamic>?> getAssertionConditional(
    Map<String, dynamic> optionsJson,
  ) async => null;

  @override
  void abortConditional() {}

  @override
  void primePasskeyAutofill() {}
}

WebAuthnBridge makeWebAuthnBridge() => const _StubWebAuthnBridge();
