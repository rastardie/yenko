/// Browser WebAuthn (passkey) bridge contract, implemented separately for
/// web (real `navigator.credentials` calls) and non-web (a no-op stub,
/// since `local_auth` already covers native biometrics and there is no
/// WebAuthn API outside a browser). Selected via the conditional import
/// below, matching the pattern already used for `biometric_backend_io.dart`
/// / `biometric_backend_web.dart`.
///
/// This bridge only performs the browser half of the WebAuthn ceremony
/// (building options, calling the browser API, serializing the result back
/// to JSON). The server half — generating a challenge, verifying the
/// signed assertion/attestation, and establishing a session — lives in the
/// backend; see HANDOVER.md for the registration/authentication endpoints.
library;

import 'webauthn_bridge_stub.dart'
    if (dart.library.js_interop) 'webauthn_bridge_web.dart';

enum WebAuthnSupport { supported, unsupported }

abstract class WebAuthnBridge {
  Future<WebAuthnSupport> support();
  Future<bool> isPlatformAuthenticatorAvailable();

  /// Runs `navigator.credentials.create()` from server-issued registration
  /// options (already decoded from JSON) and returns the attestation
  /// response as JSON, ready to send back to the server for verification.
  Future<Map<String, dynamic>> createCredential(
    Map<String, dynamic> optionsJson,
  );

  /// Runs `navigator.credentials.get()` from server-issued authentication
  /// options and returns the assertion response as JSON.
  Future<Map<String, dynamic>> getAssertion(Map<String, dynamic> optionsJson);

  Future<bool> isConditionalMediationAvailable();

  /// Same as [getAssertion], but using conditional UI (autofill) mediation;
  /// returns null if the user did not pick a passkey from the autofill
  /// suggestion (not an error).
  Future<Map<String, dynamic>?> getAssertionConditional(
    Map<String, dynamic> optionsJson,
  );

  /// Cancels an in-flight conditional (autofill) ceremony, if any.
  void abortConditional();

  /// Marks eligible text inputs with the `webauthn` autocomplete token so
  /// the browser can offer a conditional passkey autofill suggestion.
  void primePasskeyAutofill();
}

WebAuthnBridge createWebAuthnBridge() => makeWebAuthnBridge();
