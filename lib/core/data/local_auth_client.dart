import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of a successful username/password (or quick PIN) login against the
/// local API's AUTH_MODE=local-pin flow.
class LocalAuthSession {
  const LocalAuthSession({
    required this.accessToken,
    required this.role,
    required this.displayName,
    this.userId = '',
    this.roles = const [],
    this.permissions = const [],
  });

  final String accessToken;

  /// Primary role (staff roles outrank driver, which outranks passenger).
  final String role;
  final String displayName;
  final String userId;
  final List<String> roles;

  /// Fine-grained admin permissions granted by the user's groups, e.g.
  /// `users:read`. Empty for ordinary riders and drivers.
  final List<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  /// True when one of the account's groups opens the Admin area
  /// (`admin:access`, held by Super Admins and Admins by default). Only these
  /// accounts get the Admin menu; the server refuses everyone else.
  bool get hasAdminAccess => permissions.contains('admin:access');

  /// True for accounts whose primary role is a staff role rather than
  /// rider/driver; they land in the admin console.
  bool get isStaff => role != 'driver' && role != 'passenger';
}

/// Thrown when login/signup fails with a message safe to show to the user
/// (the server already avoids leaking whether an identity exists).
class LocalAuthException implements Exception {
  const LocalAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Signup succeeded but an administrator must approve the account before it
/// can sign in (the server's signup approval policy).
class LocalAuthPendingApproval implements Exception {
  const LocalAuthPendingApproval(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Calls the local API's `/v1/auth/login` and `/v1/auth/signup` endpoints.
/// Used only in local development (AppConfig.useLocalApi); production
/// authentication is OIDC and is handled separately.
class LocalAuthClient {
  LocalAuthClient({required String baseUrl, http.Client? client})
    : _baseUri = Uri.parse(baseUrl),
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  Future<LocalAuthSession> login({
    required String identity,
    required String password,
  }) => _authRequest(
    path: '/v1/auth/login',
    payload: {'identity': identity, 'password': password},
    successStatus: 200,
  );

  Future<LocalAuthSession> signup({
    required String displayName,
    required String username,
    required String password,
    required String role,
    String? homeArea,
  }) => _authRequest(
    path: '/v1/auth/signup',
    payload: {
      'displayName': displayName,
      'username': username,
      'password': password,
      'role': role,
      if (homeArea != null && homeArea.isNotEmpty) 'homeArea': homeArea,
    },
    successStatus: 201,
    acceptPending: true,
  );

  /// Email + password signup. The full legal name (as on the national ID) is
  /// mandatory and self-attested; a username is optional here (it is only
  /// required for social signups). On success a session is returned and the
  /// account should verify its email next.
  Future<LocalAuthSession> emailSignup({
    required String email,
    required String password,
    required String legalSurname,
    required String legalGivenNames,
    required String role,
    String? displayName,
    String? username,
    String? homeArea,
  }) => _authRequest(
    path: '/v1/auth/email/signup',
    payload: {
      'email': email,
      'password': password,
      'legalSurname': legalSurname,
      'legalGivenNames': legalGivenNames,
      'role': role,
      if (displayName != null && displayName.isNotEmpty)
        'displayName': displayName,
      if (username != null && username.isNotEmpty) 'username': username,
      if (homeArea != null && homeArea.isNotEmpty) 'homeArea': homeArea,
    },
    successStatus: 201,
    acceptPending: true,
  );

  /// Sign in or sign up through a social provider. [token] is the provider
  /// credential obtained by the app's native SDK; the server verifies it. For a
  /// first-time signup a username and full legal name are mandatory.
  Future<LocalAuthSession> socialAuth({
    required String provider,
    required String token,
    String? username,
    String? legalSurname,
    String? legalGivenNames,
    String? displayName,
    String role = 'passenger',
  }) => _authRequest(
    path: '/v1/auth/social',
    payload: {
      'provider': provider,
      'token': token,
      'role': role,
      if (username != null && username.isNotEmpty) 'username': username,
      if (legalSurname != null && legalSurname.isNotEmpty)
        'legalSurname': legalSurname,
      if (legalGivenNames != null && legalGivenNames.isNotEmpty)
        'legalGivenNames': legalGivenNames,
      if (displayName != null && displayName.isNotEmpty)
        'displayName': displayName,
    },
    successStatus: 200,
    acceptPending: true,
  );

  /// Requests a fresh email verification code for the signed-in account.
  /// In development (no mail provider) the response carries a `devCode`.
  Future<Map<String, dynamic>> requestEmailVerification(
    String accessToken,
  ) async {
    final body = await _postJson(
      path: '/v1/auth/email-verification/request',
      payload: const {},
      accessToken: accessToken,
    );
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Confirms the signed-in account's email with the 6-digit code.
  Future<void> confirmEmailVerification(String accessToken, String code) async {
    await _postJson(
      path: '/v1/auth/email-verification/confirm',
      payload: {'code': code},
      accessToken: accessToken,
    );
  }

  /// Best-effort server-side sign out, revoking the session so the token stops
  /// working immediately. Failures are ignored: the app forgets the token
  /// either way.
  Future<void> logout(String accessToken) async {
    try {
      await _client
          .post(
            _baseUri.resolve('/v1/auth/logout'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignored by design; see the doc comment.
    }
  }

  Future<LocalAuthSession> _authRequest({
    required String path,
    required Map<String, dynamic> payload,
    required int successStatus,
    bool acceptPending = false,
  }) async {
    final response = await _client
        .post(
          _baseUri.resolve(path),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));
    final raw = utf8.decode(response.bodyBytes);
    final decoded = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (decoded is! Map) {
      throw const LocalAuthException(
        'The local API returned an invalid response.',
      );
    }
    final body = Map<String, dynamic>.from(decoded);

    if (acceptPending && response.statusCode == 202) {
      final data = body['data'];
      throw LocalAuthPendingApproval(
        data is Map
            ? data['message']?.toString() ??
                  'Your account is waiting for approval.'
            : 'Your account is waiting for approval.',
      );
    }
    if (response.statusCode != successStatus) {
      final error = body['error'];
      final message = error is Map ? error['message']?.toString() : null;
      throw LocalAuthException(message ?? 'The request failed.');
    }

    final data = Map<String, dynamic>.from(body['data'] as Map);
    final user = Map<String, dynamic>.from(data['user'] as Map);
    List<String> strings(Object? value) => (value as List? ?? const [])
        .map((item) => item.toString())
        .toList(growable: false);
    return LocalAuthSession(
      accessToken: data['accessToken'] as String,
      role: user['role'] as String,
      displayName: user['displayName'] as String,
      userId: user['id'] as String? ?? '',
      roles: strings(user['roles']),
      permissions: strings(user['permissions']),
    );
  }

  Future<Map<String, dynamic>> _postJson({
    required String path,
    required Map<String, dynamic> payload,
    String? accessToken,
  }) async {
    final response = await _client
        .post(
          _baseUri.resolve(path),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));
    final raw = utf8.decode(response.bodyBytes);
    final decoded = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (decoded is! Map) {
      throw const LocalAuthException(
        'The local API returned an invalid response.',
      );
    }
    final body = Map<String, dynamic>.from(decoded);
    if (response.statusCode >= 400) {
      final error = body['error'];
      final message = error is Map ? error['message']?.toString() : null;
      throw LocalAuthException(message ?? 'The request failed.');
    }
    return body;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
