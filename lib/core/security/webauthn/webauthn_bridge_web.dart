import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'webauthn_bridge.dart';

/// Real browser WebAuthn bridge. Only the browser half of each ceremony
/// lives here: convert server JSON options into the shapes
/// `navigator.credentials.create/get` expect, call the browser API, and
/// serialize the resulting attestation/assertion back to JSON for the
/// server to verify. See `webauthn_bridge.dart` for the full contract.
class _WebWebAuthnBridge implements WebAuthnBridge {
  _WebWebAuthnBridge();

  web.AbortController? _conditionalAbort;

  bool get _apiPresent {
    try {
      return globalContext.has('PublicKeyCredential');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<WebAuthnSupport> support() async {
    try {
      if (!_apiPresent) return WebAuthnSupport.unsupported;
      if (!web.window.isSecureContext) return WebAuthnSupport.unsupported;
      return WebAuthnSupport.supported;
    } catch (_) {
      return WebAuthnSupport.unsupported;
    }
  }

  @override
  Future<bool> isPlatformAuthenticatorAvailable() async {
    if (await support() != WebAuthnSupport.supported) return false;
    try {
      final available =
          await _isUserVerifyingPlatformAuthenticatorAvailable().toDart;
      return available.toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> createCredential(
    Map<String, dynamic> optionsJson,
  ) async {
    final publicKey = _buildCreationOptions(optionsJson);
    final credential = await web.window.navigator.credentials
        .create(web.CredentialCreationOptions(publicKey: publicKey))
        .toDart;
    if (credential == null) {
      throw StateError('Passkey creation was cancelled.');
    }
    return _registrationResponseToJson(credential as web.PublicKeyCredential);
  }

  @override
  Future<Map<String, dynamic>> getAssertion(
    Map<String, dynamic> optionsJson,
  ) async {
    final publicKey = _buildRequestOptions(optionsJson);
    final credential = await web.window.navigator.credentials
        .get(web.CredentialRequestOptions(publicKey: publicKey))
        .toDart;
    if (credential == null) {
      throw StateError('Passkey sign-in was cancelled.');
    }
    return _authenticationResponseToJson(
      credential as web.PublicKeyCredential,
    );
  }

  @override
  Future<bool> isConditionalMediationAvailable() async {
    try {
      if (await support() != WebAuthnSupport.supported) return false;
      final pkc = globalContext.getProperty('PublicKeyCredential'.toJS);
      if (pkc == null) return false;
      if (!(pkc as JSObject).has('isConditionalMediationAvailable')) {
        return false;
      }
      final available = await _isConditionalMediationAvailable().toDart;
      return available.toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> getAssertionConditional(
    Map<String, dynamic> optionsJson,
  ) async {
    abortConditional();
    final publicKey = _buildRequestOptions(optionsJson);
    final controller = web.AbortController();
    _conditionalAbort = controller;
    try {
      final opts = web.CredentialRequestOptions(publicKey: publicKey);
      (opts as JSObject)
        ..setProperty('mediation'.toJS, 'conditional'.toJS)
        ..setProperty('signal'.toJS, controller.signal);
      final credential = await web.window.navigator.credentials
          .get(opts)
          .toDart;
      if (credential == null) return null;
      return _authenticationResponseToJson(
        credential as web.PublicKeyCredential,
      );
    } catch (_) {
      return null;
    } finally {
      if (identical(_conditionalAbort, controller)) _conditionalAbort = null;
    }
  }

  @override
  void abortConditional() {
    final controller = _conditionalAbort;
    _conditionalAbort = null;
    if (controller == null) return;
    try {
      controller.abort();
    } catch (_) {}
  }

  @override
  void primePasskeyAutofill() {
    try {
      final inputs = web.document.querySelectorAll('input');
      for (var i = 0; i < inputs.length; i++) {
        final node = inputs.item(i);
        if (node == null) continue;
        final el = node as web.HTMLInputElement;
        final type = el.type.toLowerCase();
        if (type == 'password' || type == 'hidden') continue;
        final existing = el.autocomplete;
        if (existing.contains('webauthn')) continue;
        el.autocomplete = existing.isEmpty
            ? 'username webauthn'
            : '$existing webauthn';
      }
    } catch (_) {}
  }

  // ---- Options builders (JSON -> browser objects) ----

  web.PublicKeyCredentialCreationOptions _buildCreationOptions(
    Map<String, dynamic> json,
  ) {
    final rp = json['rp'] as Map<String, dynamic>;
    final user = json['user'] as Map<String, dynamic>;
    final options = web.PublicKeyCredentialCreationOptions(
      challenge: _b64urlToArrayBuffer(json['challenge'] as String),
      rp: web.PublicKeyCredentialRpEntity(
        name: rp['name'] as String,
        id: (rp['id'] as String?) ?? '',
      ),
      user: web.PublicKeyCredentialUserEntity(
        id: _b64urlToArrayBuffer(user['id'] as String),
        name: user['name'] as String,
        displayName: (user['displayName'] as String?) ?? '',
      ),
      pubKeyCredParams: _toParams(json['pubKeyCredParams'] as List),
    );
    if (json['timeout'] != null) {
      options.timeout = (json['timeout'] as num).toInt();
    }
    if (json['attestation'] != null) {
      options.attestation = json['attestation'] as String;
    }
    final exclude = json['excludeCredentials'] as List?;
    if (exclude != null && exclude.isNotEmpty) {
      options.excludeCredentials = _toDescriptors(exclude);
    }
    final authSel = json['authenticatorSelection'] as Map<String, dynamic>?;
    if (authSel != null) {
      final sel = web.AuthenticatorSelectionCriteria();
      if (authSel['residentKey'] != null) {
        sel.residentKey = authSel['residentKey'] as String;
      }
      if (authSel['userVerification'] != null) {
        sel.userVerification = authSel['userVerification'] as String;
      }
      if (authSel['authenticatorAttachment'] != null) {
        sel.authenticatorAttachment =
            authSel['authenticatorAttachment'] as String;
      }
      options.authenticatorSelection = sel;
    }
    return options;
  }

  web.PublicKeyCredentialRequestOptions _buildRequestOptions(
    Map<String, dynamic> json,
  ) {
    final options = web.PublicKeyCredentialRequestOptions(
      challenge: _b64urlToArrayBuffer(json['challenge'] as String),
    );
    if (json['timeout'] != null) {
      options.timeout = (json['timeout'] as num).toInt();
    }
    if (json['rpId'] != null) options.rpId = json['rpId'] as String;
    if (json['userVerification'] != null) {
      options.userVerification = json['userVerification'] as String;
    }
    final allow = json['allowCredentials'] as List?;
    if (allow != null && allow.isNotEmpty) {
      options.allowCredentials = _toDescriptors(allow);
    }
    return options;
  }

  JSArray<web.PublicKeyCredentialParameters> _toParams(List raw) {
    final list = raw
        .cast<Map<String, dynamic>>()
        .map(
          (p) => web.PublicKeyCredentialParameters(
            type: p['type'] as String,
            alg: (p['alg'] as num).toInt(),
          ),
        )
        .toList();
    return list.toJS;
  }

  JSArray<web.PublicKeyCredentialDescriptor> _toDescriptors(List raw) {
    final list = raw.cast<Map<String, dynamic>>().map((d) {
      final desc = web.PublicKeyCredentialDescriptor(
        type: (d['type'] as String?) ?? 'public-key',
        id: _b64urlToArrayBuffer(d['id'] as String),
      );
      final transports = d['transports'] as List?;
      if (transports != null && transports.isNotEmpty) {
        desc.transports = transports
            .map((t) => (t as String).toJS)
            .toList()
            .toJS;
      }
      return desc;
    }).toList();
    return list.toJS;
  }

  // ---- Response serializers (browser objects -> JSON) ----

  Map<String, dynamic> _registrationResponseToJson(
    web.PublicKeyCredential credential,
  ) {
    final response =
        credential.response as web.AuthenticatorAttestationResponse;
    final transports = _readTransports(response);
    return {
      'id': credential.id,
      'rawId': _arrayBufferToB64url(credential.rawId),
      'type': credential.type,
      'clientExtensionResults': <String, dynamic>{},
      'response': {
        'clientDataJSON': _arrayBufferToB64url(response.clientDataJSON),
        'attestationObject': _arrayBufferToB64url(response.attestationObject),
        'transports': ?transports,
      },
    };
  }

  Map<String, dynamic> _authenticationResponseToJson(
    web.PublicKeyCredential credential,
  ) {
    final response =
        credential.response as web.AuthenticatorAssertionResponse;
    final userHandle = response.userHandle;
    return {
      'id': credential.id,
      'rawId': _arrayBufferToB64url(credential.rawId),
      'type': credential.type,
      'clientExtensionResults': <String, dynamic>{},
      'response': {
        'clientDataJSON': _arrayBufferToB64url(response.clientDataJSON),
        'authenticatorData': _arrayBufferToB64url(response.authenticatorData),
        'signature': _arrayBufferToB64url(response.signature),
        if (userHandle != null)
          'userHandle': _arrayBufferToB64url(userHandle),
      },
    };
  }

  List<String>? _readTransports(
    web.AuthenticatorAttestationResponse response,
  ) {
    try {
      final transports = response.getTransports().toDart;
      final result = transports.map((t) => t.toDart).toList();
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  // ---- base64url <-> ArrayBuffer ----

  JSArrayBuffer _b64urlToArrayBuffer(String value) {
    final normalized = base64.normalize(
      value.replaceAll('-', '+').replaceAll('_', '/'),
    );
    final bytes = base64.decode(normalized);
    return bytes.buffer.toJS;
  }

  String _arrayBufferToB64url(JSArrayBuffer buffer) {
    final bytes = buffer.toDart.asUint8List();
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

@JS('PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable')
external JSPromise<JSBoolean>
_isUserVerifyingPlatformAuthenticatorAvailable();

@JS('PublicKeyCredential.isConditionalMediationAvailable')
external JSPromise<JSBoolean> _isConditionalMediationAvailable();

WebAuthnBridge makeWebAuthnBridge() => _WebWebAuthnBridge();
