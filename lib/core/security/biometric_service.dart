import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local_auth_client.dart';
import 'biometric_backend_io.dart'
    if (dart.library.js_interop) 'biometric_backend_web.dart';
import 'webauthn/webauthn_bridge.dart';

/// The outcome of a user attempting to enable optional biometric unlock.
enum BiometricEnableResult { enabled, unavailable, verificationFailed }

/// Device-local biometric enrollment preference, plus (on web only) real
/// server-verified WebAuthn passkeys.
///
/// Native (Android/iOS): this never represents server authentication or
/// identity verification. It is disabled by default and can only be enabled
/// after the operating system has confirmed an enrolled biometric. Only the
/// boolean preference is persisted; biometric templates remain in the
/// device secure hardware/OS. The actual sign-in replay (re-submitting the
/// typed username/password after a successful device check) is handled by
/// the login screen, not this class.
///
/// Web/PWA: there is no OS-level secure storage to cache a password in, so
/// a different mechanism is used — real WebAuthn passkeys, verified by the
/// backend with @simplewebauthn/server (see migration 012). A successful
/// passkey assertion *is* the authentication; [authenticateWebAuthn] returns
/// a full session on success.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  static const _preferenceKey = 'yenko_biometric_unlock_enabled';
  static const _credentialIdsKey = 'yenko_webauthn_credential_ids';

  final BiometricBackend _backend = BiometricBackend();

  /// Browser WebAuthn bridge (real on web, no-op stub on native).
  final WebAuthnBridge webAuthnBridge = createWebAuthnBridge();

  /// Set once by the app's auth flow so this singleton can call the
  /// WebAuthn backend endpoints without every call site threading a client
  /// through. Only used on web; native biometric unlock never touches the
  /// network, matching the design above.
  LocalAuthClient? authClient;

  /// Set by a one-time flow (e.g. right after a password sign-in) so
  /// [registerWebAuthn] can call the backend without every call site
  /// threading a token through. Native biometric flows never need this.
  String? _lastAccessToken;

  bool _available = false;
  bool _enabled = false;

  bool get isAvailable => _available;
  bool get isEnabled => _enabled;

  /// Reads the saved preference and verifies that a fingerprint or Face ID is
  /// currently enrolled, not merely that the device supports biometrics. On
  /// web this checks platform-authenticator (passkey) availability instead;
  /// see `biometric_backend_web.dart` for why `local_auth` itself is unused
  /// there, and [registerWebAuthn]/[authenticateWebAuthn] for the real web
  /// flow.
  Future<void> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _enabled = preferences.getBool(_preferenceKey) ?? false;
      _available = kIsWeb
          ? await webAuthnBridge.isPlatformAuthenticatorAvailable()
          : await _backend.hasEnrolledBiometrics();
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

  /// Prompts the device biometric check without touching the enrollment
  /// preference. Use this for every sign-in attempt after biometrics are
  /// already enabled; use [enable] only for the one-time opt-in itself.
  /// Returns `false` immediately (no prompt) if biometrics are disabled or
  /// unavailable, so callers do not need to check [isEnabled] separately.
  Future<bool> authenticate({
    String reason = 'Confirm your identity to continue',
  }) async {
    if (!_enabled) return false;
    if (!_available) return false;
    try {
      return await _backend.authenticate(reason);
    } catch (_) {
      return false;
    }
  }

  // --- Web (PWA) passkey flows ---
  //
  // Unlike native, these are real server-verified ceremonies: a successful
  // call to [authenticateWebAuthn] already establishes a session, it does
  // not just unlock a locally-cached credential.

  /// Registers a new passkey for the signed-in account. Requires
  /// [authClient] to have been set by the app's auth flow first.
  Future<BiometricEnableResult> registerWebAuthn({String? deviceLabel}) async {
    if (!kIsWeb) return BiometricEnableResult.unavailable;
    final client = authClient;
    if (client == null) return BiometricEnableResult.unavailable;
    if (await webAuthnBridge.support() != WebAuthnSupport.supported) {
      return BiometricEnableResult.unavailable;
    }
    try {
      // The caller must supply the signed-in access token via authClient's
      // last-used token path; see ProfileScreen for how this is invoked.
      final accessToken = _lastAccessToken;
      if (accessToken == null) return BiometricEnableResult.unavailable;
      final options = await client.webAuthnRegistrationOptions(accessToken);
      final attestation = await webAuthnBridge.createCredential(options);
      await client.webAuthnRegistrationVerify(
        accessToken,
        attestation,
        deviceLabel: deviceLabel,
      );
      await _rememberCredentialId(attestation['id']);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_preferenceKey, true);
      _enabled = true;
      _available = true;
      return BiometricEnableResult.enabled;
    } catch (_) {
      return BiometricEnableResult.verificationFailed;
    }
  }

  /// Signs in with a previously registered passkey. Returns the resulting
  /// session on success, or null if the ceremony was cancelled or failed —
  /// never throws, so callers can fall back to the password form.
  Future<LocalAuthSession?> authenticateWebAuthn() async {
    if (!kIsWeb) return null;
    final client = authClient;
    if (client == null) return null;
    if (await webAuthnBridge.support() != WebAuthnSupport.supported) {
      return null;
    }
    try {
      final options = await client.webAuthnAuthenticationOptions();
      final ids = await _rememberedCredentialIds();
      if (ids.isNotEmpty) {
        options['allowCredentials'] = [
          for (final id in ids)
            {'type': 'public-key', 'id': id, 'transports': ['internal']},
        ];
      }
      final assertion = await webAuthnBridge.getAssertion(options);
      final session = await client.webAuthnAuthenticationVerify(assertion);
      await _rememberCredentialId(assertion['id']);
      return session;
    } catch (_) {
      return null;
    }
  }

  /// Lets a one-time flow (e.g. right after a password sign-in) record the
  /// access token this instance should use for the next [registerWebAuthn]
  /// call.
  void rememberAccessTokenForWebAuthnSetup(String accessToken) {
    _lastAccessToken = accessToken;
  }

  Future<void> _rememberCredentialId(Object? id) async {
    if (id is! String || id.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_credentialIdsKey) ?? <String>[];
    if (!ids.contains(id)) {
      ids.add(id);
      await preferences.setStringList(_credentialIdsKey, ids);
    }
  }

  Future<List<String>> _rememberedCredentialIds() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_credentialIdsKey) ?? const <String>[];
  }
}
