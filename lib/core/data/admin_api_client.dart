// The public constructor parameter names intentionally differ from their
// private storage fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when an admin API call fails. [message] comes from the server and is
/// safe to show; [status] is the HTTP status (0 when the server is unreachable).
class AdminApiException implements Exception {
  const AdminApiException(
    this.message, {
    this.status = 0,
    this.code,
    this.cancelled = false,
  });
  final String message;
  final int status;

  /// The server's machine-readable error code, e.g. `admin_action_required`.
  final String? code;

  /// True when the administrator dismissed the re-authentication prompt.
  final bool cancelled;

  bool get isForbidden => status == 403;

  @override
  String toString() => message;
}

int _int(Map<String, dynamic> json, String key) =>
    (json[key] as num? ?? 0).toInt();

DateTime _date(Object? value) =>
    DateTime.tryParse(value as String? ?? '')?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

List<String> _strings(Object? value) => (value as List? ?? const [])
    .map((item) => item.toString())
    .toList(growable: false);

class AdminGroupRef {
  const AdminGroupRef({required this.id, required this.name, this.role});
  factory AdminGroupRef.fromJson(Map<String, dynamic> json) => AdminGroupRef(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String?,
  );
  final String id;
  final String name;
  final String? role;
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.groups,
    required this.roles,
    required this.permissions,
    this.username,
    this.phone,
    this.homeArea,
    this.temporaryPassword,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: json['id'] as String,
    displayName: json['displayName'] as String? ?? 'Unnamed',
    username: json['username'] as String?,
    phone: json['phone'] as String?,
    homeArea: json['homeArea'] as String?,
    status: json['status'] as String? ?? 'active',
    createdAt: _date(json['createdAt']),
    groups: (json['groups'] as List? ?? const [])
        .map(
          (group) =>
              AdminGroupRef.fromJson(Map<String, dynamic>.from(group as Map)),
        )
        .toList(growable: false),
    roles: _strings(json['roles']),
    permissions: _strings(json['permissions']),
    temporaryPassword: json['temporaryPassword'] as String?,
  );

  final String id;
  final String displayName;
  final String? username;
  final String? phone;
  final String? homeArea;
  final String status;
  final DateTime createdAt;
  final List<AdminGroupRef> groups;
  final List<String> roles;
  final List<String> permissions;

  /// Present only in the response to creating a user without a chosen password.
  final String? temporaryPassword;

  bool get isSuspended => status == 'suspended';
  String get handle =>
      username != null ? '@$username' : (phone ?? 'no sign-in name');
}

class AdminMember {
  const AdminMember({
    required this.id,
    required this.displayName,
    required this.status,
    this.username,
  });
  factory AdminMember.fromJson(Map<String, dynamic> json) => AdminMember(
    id: json['id'] as String,
    displayName: json['displayName'] as String? ?? 'Unnamed',
    username: json['username'] as String?,
    status: json['status'] as String? ?? 'active',
  );
  final String id;
  final String displayName;
  final String? username;
  final String status;
}

class AdminGroup {
  const AdminGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.isSystem,
    required this.memberCount,
    required this.permissions,
    this.role,
    this.members = const [],
  });

  factory AdminGroup.fromJson(Map<String, dynamic> json) => AdminGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String?,
    description: json['description'] as String? ?? '',
    isSystem: json['isSystem'] == true,
    memberCount: _int(json, 'memberCount'),
    permissions: _strings(json['permissions']),
    members: (json['members'] as List? ?? const [])
        .map(
          (member) =>
              AdminMember.fromJson(Map<String, dynamic>.from(member as Map)),
        )
        .toList(growable: false),
  );

  final String id;
  final String name;
  final String? role;
  final String description;
  final bool isSystem;
  final int memberCount;
  final List<String> permissions;
  final List<AdminMember> members;

  bool get isSuperAdmins => isSystem && role == 'super_admin';
}

class AdminPermission {
  const AdminPermission({
    required this.key,
    required this.resource,
    required this.action,
    required this.description,
  });
  factory AdminPermission.fromJson(Map<String, dynamic> json) =>
      AdminPermission(
        key: json['key'] as String,
        resource: json['resource'] as String,
        action: json['action'] as String,
        description: json['description'] as String? ?? '',
      );
  final String key;
  final String resource;
  final String action;
  final String description;
}

class AdminBooking {
  const AdminBooking({
    required this.id,
    required this.passengerName,
    required this.seats,
    required this.status,
  });
  factory AdminBooking.fromJson(Map<String, dynamic> json) => AdminBooking(
    id: json['id'] as String,
    passengerName:
        (json['passenger'] as Map?)?['displayName'] as String? ?? 'Rider',
    seats: _int(json, 'seats'),
    status: json['status'] as String? ?? 'requested',
  );
  final String id;
  final String passengerName;
  final int seats;
  final String status;

  bool get canChange => status == 'requested' || status == 'confirmed';
}

class AdminTrip {
  const AdminTrip({
    required this.id,
    required this.driverName,
    required this.from,
    required this.to,
    required this.pickupJunction,
    required this.departureAt,
    required this.seatsAvailable,
    required this.pricePerSeat,
    required this.isWomenOnly,
    required this.status,
    required this.seatsBooked,
    required this.bookingCount,
    this.bookings = const [],
  });

  factory AdminTrip.fromJson(Map<String, dynamic> json) => AdminTrip(
    id: json['id'] as String,
    driverName: (json['driver'] as Map?)?['displayName'] as String? ?? 'Driver',
    from: json['from'] as String,
    to: json['to'] as String,
    pickupJunction: json['pickupJunction'] as String? ?? '',
    departureAt: _date(json['departureAt']),
    seatsAvailable: _int(json, 'seatsAvailable'),
    pricePerSeat: _int(json, 'pricePerSeat'),
    isWomenOnly: json['isWomenOnly'] == true,
    status: json['status'] as String? ?? 'open',
    seatsBooked: _int(json, 'seatsBooked'),
    bookingCount: _int(json, 'bookingCount'),
    bookings: (json['reservations'] as List? ?? const [])
        .map(
          (booking) =>
              AdminBooking.fromJson(Map<String, dynamic>.from(booking as Map)),
        )
        .toList(growable: false),
  );

  final String id;
  final String driverName;
  final String from;
  final String to;
  final String pickupJunction;
  final DateTime departureAt;
  final int seatsAvailable;
  final int pricePerSeat;
  final bool isWomenOnly;
  final String status;
  final int seatsBooked;
  final int bookingCount;
  final List<AdminBooking> bookings;

  bool get isOpen => status == 'open';
}

class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.action,
    required this.aggregateType,
    required this.aggregateId,
    required this.createdAt,
    required this.metadata,
    this.actorName,
  });

  factory AdminAuditEvent.fromJson(Map<String, dynamic> json) =>
      AdminAuditEvent(
        id: json['id'] as String,
        action: json['action'] as String,
        aggregateType: json['aggregateType'] as String? ?? '',
        aggregateId: json['aggregateId'] as String? ?? '',
        createdAt: _date(json['createdAt']),
        metadata: Map<String, dynamic>.from(
          json['metadata'] as Map? ?? const {},
        ),
        actorName: (json['actor'] as Map?)?['displayName'] as String?,
      );

  final String id;
  final String action;
  final String aggregateType;
  final String aggregateId;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;
  final String? actorName;
}

class AdminDashboard {
  const AdminDashboard({
    required this.users,
    required this.trips,
    required this.reservations,
    required this.groups,
  });

  factory AdminDashboard.fromJson(Map<String, dynamic> json) {
    Map<String, int> counts(String key) => {
      for (final entry in Map<String, dynamic>.from(
        json[key] as Map? ?? const {},
      ).entries)
        entry.key: (entry.value as num? ?? 0).toInt(),
    };
    return AdminDashboard(
      users: counts('users'),
      trips: counts('trips'),
      reservations: counts('reservations'),
      groups: (json['groups'] as List? ?? const [])
          .map((group) => Map<String, dynamic>.from(group as Map))
          .map(
            (group) =>
                MapEntry(group['name'] as String, _int(group, 'members')),
          )
          .toList(growable: false),
    );
  }

  final Map<String, int> users;
  final Map<String, int> trips;
  final Map<String, int> reservations;
  final List<MapEntry<String, int>> groups;
}

/// Counts for the admin home. A section is null when the account may not see it.
class AdminSummary {
  const AdminSummary({
    this.usersActive,
    this.usersPending,
    this.tripsOpen,
    this.bookingsRequested,
    this.groups,
  });

  factory AdminSummary.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? section(String key) =>
        json[key] is Map ? Map<String, dynamic>.from(json[key] as Map) : null;
    final users = section('users');
    return AdminSummary(
      usersActive: users == null ? null : _int(users, 'active'),
      usersPending: users == null ? null : _int(users, 'pending'),
      tripsOpen: section('trips') == null
          ? null
          : _int(section('trips')!, 'open'),
      bookingsRequested: section('bookings') == null
          ? null
          : _int(section('bookings')!, 'requested'),
      groups: section('groups') == null
          ? null
          : _int(section('groups')!, 'total'),
    );
  }

  final int? usersActive;
  final int? usersPending;
  final int? tripsOpen;
  final int? bookingsRequested;
  final int? groups;
}

class AdminDriverStat {
  const AdminDriverStat({
    required this.displayName,
    required this.trips,
    required this.cancelledTrips,
    required this.capacity,
    required this.reserved,
    required this.utilizationPct,
  });
  factory AdminDriverStat.fromJson(Map<String, dynamic> json) =>
      AdminDriverStat(
        displayName: json['displayName'] as String? ?? 'Driver',
        trips: _int(json, 'trips'),
        cancelledTrips: _int(json, 'cancelledTrips'),
        capacity: _int(json, 'capacity'),
        reserved: _int(json, 'reserved'),
        utilizationPct: _int(json, 'utilizationPct'),
      );
  final String displayName;
  final int trips;
  final int cancelledTrips;
  final int capacity;
  final int reserved;
  final int utilizationPct;
}

class AdminDayStat {
  const AdminDayStat({
    required this.day,
    required this.trips,
    required this.reserved,
  });
  factory AdminDayStat.fromJson(Map<String, dynamic> json) => AdminDayStat(
    day: json['day'] as String,
    trips: _int(json, 'trips'),
    reserved: _int(json, 'reserved'),
  );
  final String day;
  final int trips;
  final int reserved;
}

/// Period metrics for the dashboard screen.
class AdminMetrics {
  const AdminMetrics({
    required this.period,
    required this.from,
    required this.to,
    required this.trips,
    required this.bookings,
    required this.users,
    required this.drivers,
    required this.daily,
  });

  factory AdminMetrics.fromJson(Map<String, dynamic> json) {
    Map<String, int> counts(String key) => {
      for (final entry in Map<String, dynamic>.from(
        json[key] as Map? ?? const {},
      ).entries)
        entry.key: (entry.value as num? ?? 0).toInt(),
    };
    final range = Map<String, dynamic>.from(json['range'] as Map? ?? const {});
    return AdminMetrics(
      period: json['period'] as String? ?? 'week',
      from: _date(range['from']),
      to: _date(range['to']),
      trips: counts('trips'),
      bookings: counts('bookings'),
      users: counts('users'),
      drivers: (json['drivers'] as List? ?? const [])
          .map(
            (item) => AdminDriverStat.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      daily: (json['daily'] as List? ?? const [])
          .map(
            (item) =>
                AdminDayStat.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
    );
  }

  final String period;
  final DateTime from;
  final DateTime to;
  final Map<String, int> trips;
  final Map<String, int> bookings;
  final Map<String, int> users;
  final List<AdminDriverStat> drivers;
  final List<AdminDayStat> daily;
}

class AdminBookingRow {
  const AdminBookingRow({
    required this.id,
    required this.seats,
    required this.status,
    required this.fare,
    required this.createdAt,
    required this.tripId,
    required this.from,
    required this.to,
    required this.pickupJunction,
    required this.departureAt,
    required this.tripStatus,
    required this.isWomenOnly,
    required this.passengerName,
    required this.driverName,
    this.passengerUsername,
  });

  factory AdminBookingRow.fromJson(Map<String, dynamic> json) {
    final trip = Map<String, dynamic>.from(json['trip'] as Map? ?? const {});
    final passenger = Map<String, dynamic>.from(
      json['passenger'] as Map? ?? const {},
    );
    final driver = Map<String, dynamic>.from(
      json['driver'] as Map? ?? const {},
    );
    return AdminBookingRow(
      id: json['id'] as String,
      seats: _int(json, 'seats'),
      status: json['status'] as String? ?? 'requested',
      fare: _int(json, 'fare'),
      createdAt: _date(json['createdAt']),
      tripId: trip['id'] as String? ?? '',
      from: trip['from'] as String? ?? '',
      to: trip['to'] as String? ?? '',
      pickupJunction: trip['pickupJunction'] as String? ?? '',
      departureAt: _date(trip['departureAt']),
      tripStatus: trip['status'] as String? ?? 'open',
      isWomenOnly: trip['isWomenOnly'] == true,
      passengerName: passenger['displayName'] as String? ?? 'Rider',
      passengerUsername: passenger['username'] as String?,
      driverName: driver['displayName'] as String? ?? 'Driver',
    );
  }

  final String id;
  final int seats;
  final String status;
  final int fare;
  final DateTime createdAt;
  final String tripId;
  final String from;
  final String to;
  final String pickupJunction;
  final DateTime departureAt;
  final String tripStatus;
  final bool isWomenOnly;
  final String passengerName;
  final String? passengerUsername;
  final String driverName;

  bool get canConfirm => status == 'requested' && tripStatus == 'open';
  bool get canCancel => status == 'requested' || status == 'confirmed';
}

class AdminBookingPage {
  const AdminBookingPage(this.items, this.total, this.totals);
  final List<AdminBookingRow> items;
  final int total;
  final Map<String, int> totals;
}

/// Asks the administrator for their password or PIN. Returns null if they
/// cancel. [error] explains why a previous attempt was refused.
typedef AdminCredentialPrompt = Future<String?> Function({String? error});

/// A page of results plus the total number of matches on the server.
class AdminPage<T> {
  const AdminPage(this.items, this.total);
  final List<T> items;
  final int total;
}

/// Calls the `/v1/admin/*` endpoints with the signed-in user's bearer token.
/// The server decides what each account may do; the app only hides controls
/// the account's permissions do not allow.
class AdminApiClient {
  AdminApiClient({
    required String baseUrl,
    required String accessToken,
    http.Client? client,
    AdminCredentialPrompt? promptCredential,
  }) : _baseUri = Uri.parse(baseUrl),
       _accessToken = accessToken,
       _promptCredential = promptCredential,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri _baseUri;
  final String _accessToken;
  final AdminCredentialPrompt? _promptCredential;
  final http.Client _client;
  final bool _ownsClient;
  String? _actionToken;
  DateTime? _actionExpiry;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  /// Admin writes carry a short-lived "admin action" token obtained by
  /// re-entering the password or PIN (Onboard's confirm-administrator-action
  /// step). The token is reused until it nears expiry, then asked for again.
  Future<String> _actionTokenFor() async {
    final cached = _actionToken;
    final expiry = _actionExpiry;
    if (cached != null &&
        expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(seconds: 20)))) {
      return cached;
    }
    final prompt = _promptCredential;
    if (prompt == null) {
      throw const AdminApiException(
        'Confirming this action needs your password, which is unavailable here.',
      );
    }
    String? error;
    while (true) {
      final credential = await prompt(error: error);
      if (credential == null || credential.isEmpty) {
        throw const AdminApiException('Action cancelled.', cancelled: true);
      }
      try {
        final body = await _send(
          'POST',
          '/v1/auth/admin-action-token',
          body: {'password': credential},
        );
        final data = _data(body);
        _actionToken = data['token'] as String;
        _actionExpiry =
            DateTime.tryParse(data['expiresAt'] as String? ?? '') ??
            DateTime.now().add(const Duration(minutes: 4));
        return _actionToken!;
      } on AdminApiException catch (failure) {
        if (failure.status != 401) rethrow;
        error = failure.message;
      }
    }
  }

  void _forgetActionToken() {
    _actionToken = null;
    _actionExpiry = null;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retriedAction = false,
  }) async {
    final isActionWrite = path.startsWith('/v1/admin/') && method != 'GET';
    final actionToken = isActionWrite ? await _actionTokenFor() : null;
    try {
      final uri = _baseUri
          .resolve(path)
          .replace(queryParameters: query?.isEmpty ?? true ? null : query);
      final request = http.Request(method, uri);
      request.headers['Accept'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $_accessToken';
      if (actionToken != null) {
        request.headers['x-admin-action'] = actionToken;
      }
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamed).timeout(
        const Duration(seconds: 10),
      );
      final raw = utf8.decode(response.bodyBytes);
      final decoded = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
      if (decoded is! Map) {
        throw AdminApiException(
          'The server returned an invalid response.',
          status: response.statusCode,
        );
      }
      final map = Map<String, dynamic>.from(decoded);
      if (response.statusCode >= 400) {
        final error = map['error'];
        final message = error is Map ? error['message']?.toString() : null;
        final code = error is Map ? error['code']?.toString() : null;
        // A 401 from the re-authentication endpoint means "wrong password",
        // anywhere else it means the session itself has ended.
        final wrongCredential = path == '/v1/auth/admin-action-token';
        throw AdminApiException(
          response.statusCode == 401 && !wrongCredential
              ? 'Your session has ended. Sign in again.'
              : (message ?? 'The request failed.'),
          status: response.statusCode,
          code: code,
        );
      }
      return map;
    } on AdminApiException catch (failure) {
      // The token can expire between the prompt and the write; ask once more.
      if (failure.code == 'admin_action_required' &&
          isActionWrite &&
          !retriedAction) {
        _forgetActionToken();
        return _send(
          method,
          path,
          query: query,
          body: body,
          retriedAction: true,
        );
      }
      rethrow;
    } catch (_) {
      throw const AdminApiException(
        'Could not reach the YɛnKɔ server. Check your connection and try again.',
      );
    }
  }

  Map<String, dynamic> _data(Map<String, dynamic> body) =>
      Map<String, dynamic>.from(body['data'] as Map);

  AdminPage<T> _page<T>(
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) parse,
  ) {
    final items = (body['data'] as List? ?? const [])
        .map((item) => parse(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    return AdminPage(items, (body['total'] as num? ?? items.length).toInt());
  }

  Future<AdminSummary> summary() async =>
      AdminSummary.fromJson(_data(await _send('GET', '/v1/admin/summary')));

  Future<AdminMetrics> metrics({
    String period = 'week',
    DateTime? from,
    DateTime? to,
  }) async => AdminMetrics.fromJson(
    _data(
      await _send(
        'GET',
        '/v1/admin/metrics',
        query: {
          'period': period,
          if (period == 'custom' && from != null) 'from': _day(from),
          if (period == 'custom' && to != null) 'to': _day(to),
        },
      ),
    ),
  );

  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<AdminBookingPage> _bookings(
    String path, {
    String? status,
    String? search,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final body = await _send(
      'GET',
      path,
      query: {
        'status': ?status,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (from != null) 'from': _day(from),
        if (to != null) 'to': _day(to),
        'limit': '$limit',
      },
    );
    final items = (body['data'] as List? ?? const [])
        .map(
          (row) =>
              AdminBookingRow.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
    final totals = {
      for (final entry in Map<String, dynamic>.from(
        body['totals'] as Map? ?? const {},
      ).entries)
        entry.key: (entry.value as num? ?? 0).toInt(),
    };
    return AdminBookingPage(
      items,
      (body['total'] as num? ?? items.length).toInt(),
      totals,
    );
  }

  Future<AdminBookingPage> listBookings({
    String? status,
    String? search,
    int limit = 100,
  }) => _bookings(
    '/v1/admin/bookings',
    status: status,
    search: search,
    limit: limit,
  );

  Future<AdminBookingPage> bookingReport({
    String? status,
    String? search,
    DateTime? from,
    DateTime? to,
  }) => _bookings(
    '/v1/admin/reports/bookings',
    status: status,
    search: search,
    from: from,
    to: to,
    limit: 1000,
  );

  Future<void> confirmBooking(String id) async =>
      _send('POST', '/v1/admin/bookings/${Uri.encodeComponent(id)}/confirm');

  Future<void> cancelBooking(String id) async =>
      _send('POST', '/v1/admin/bookings/${Uri.encodeComponent(id)}/cancel');

  Future<AdminUser> approveUser(String id) async => AdminUser.fromJson(
    _data(
      await _send('POST', '/v1/admin/users/${Uri.encodeComponent(id)}/approve'),
    ),
  );

  Future<void> denyUser(String id) async =>
      _send('POST', '/v1/admin/users/${Uri.encodeComponent(id)}/deny');

  Future<void> deleteUser(String id) async =>
      _send('DELETE', '/v1/admin/users/${Uri.encodeComponent(id)}');

  Future<List<String>> auditActions() async =>
      ((await _send('GET', '/v1/admin/audit-logs/actions'))['data'] as List)
          .map((item) => item.toString())
          .toList();

  Future<AdminDashboard> dashboard() async =>
      AdminDashboard.fromJson(_data(await _send('GET', '/v1/admin/dashboard')));

  Future<AdminPage<AdminUser>> listUsers({
    String? search,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async => _page(
    await _send(
      'GET',
      '/v1/admin/users',
      query: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'status': ?status,
        'limit': '$limit',
        'offset': '$offset',
      },
    ),
    AdminUser.fromJson,
  );

  Future<AdminUser> getUser(String id) async => AdminUser.fromJson(
    _data(await _send('GET', '/v1/admin/users/${Uri.encodeComponent(id)}')),
  );

  Future<AdminUser> createUser({
    required String displayName,
    required String username,
    String? password,
    String? phone,
    String? quickPin,
    String? homeArea,
    List<String> groupIds = const [],
  }) async => AdminUser.fromJson(
    _data(
      await _send(
        'POST',
        '/v1/admin/users',
        body: {
          'displayName': displayName,
          'username': username,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (quickPin != null && quickPin.isNotEmpty) 'quickPin': quickPin,
          if (password != null && password.isNotEmpty) 'password': password,
          if (homeArea != null && homeArea.isNotEmpty) 'homeArea': homeArea,
          'groupIds': groupIds,
        },
      ),
    ),
  );

  Future<AdminUser> updateUser(
    String id, {
    String? displayName,
    String? homeArea,
    String? status,
  }) async => AdminUser.fromJson(
    _data(
      await _send(
        'PATCH',
        '/v1/admin/users/${Uri.encodeComponent(id)}',
        body: {
          'displayName': ?displayName,
          'homeArea': ?homeArea,
          'status': ?status,
        },
      ),
    ),
  );

  /// Returns the temporary password when the server generated one, else null.
  Future<String?> resetPassword(String id, {String? password}) async {
    final data = _data(
      await _send(
        'POST',
        '/v1/admin/users/${Uri.encodeComponent(id)}/reset-password',
        body: {'password': ?password},
      ),
    );
    return data['temporaryPassword'] as String?;
  }

  Future<List<AdminGroup>> listGroups() async =>
      ((await _send('GET', '/v1/admin/groups'))['data'] as List)
          .map(
            (group) =>
                AdminGroup.fromJson(Map<String, dynamic>.from(group as Map)),
          )
          .toList(growable: false);

  Future<AdminGroup> getGroup(String id) async => AdminGroup.fromJson(
    _data(await _send('GET', '/v1/admin/groups/${Uri.encodeComponent(id)}')),
  );

  Future<List<AdminPermission>> listPermissions() async =>
      ((await _send('GET', '/v1/admin/permissions'))['data'] as List)
          .map(
            (item) => AdminPermission.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);

  Future<AdminGroup> createGroup({
    required String name,
    String description = '',
    List<String> permissions = const [],
  }) async => AdminGroup.fromJson(
    _data(
      await _send(
        'POST',
        '/v1/admin/groups',
        body: {
          'name': name,
          'description': description,
          'permissions': permissions,
        },
      ),
    ),
  );

  Future<AdminGroup> updateGroup(
    String id, {
    String? name,
    String? description,
  }) async => AdminGroup.fromJson(
    _data(
      await _send(
        'PATCH',
        '/v1/admin/groups/${Uri.encodeComponent(id)}',
        body: {'name': ?name, 'description': ?description},
      ),
    ),
  );

  Future<void> deleteGroup(String id) async =>
      _send('DELETE', '/v1/admin/groups/${Uri.encodeComponent(id)}');

  Future<AdminGroup> setGroupPermissions(
    String id,
    List<String> permissions,
  ) async => AdminGroup.fromJson(
    _data(
      await _send(
        'PUT',
        '/v1/admin/groups/${Uri.encodeComponent(id)}/permissions',
        body: {'permissions': permissions},
      ),
    ),
  );

  Future<AdminGroup> addGroupMember(String groupId, String userId) async =>
      AdminGroup.fromJson(
        _data(
          await _send(
            'POST',
            '/v1/admin/groups/${Uri.encodeComponent(groupId)}/members',
            body: {'userId': userId},
          ),
        ),
      );

  Future<AdminGroup> removeGroupMember(
    String groupId,
    String userId,
  ) async => AdminGroup.fromJson(
    _data(
      await _send(
        'DELETE',
        '/v1/admin/groups/${Uri.encodeComponent(groupId)}/members/${Uri.encodeComponent(userId)}',
      ),
    ),
  );

  Future<AdminPage<AdminTrip>> listTrips({
    String? status,
    int limit = 100,
    int offset = 0,
  }) async => _page(
    await _send(
      'GET',
      '/v1/admin/trips',
      query: {'status': ?status, 'limit': '$limit', 'offset': '$offset'},
    ),
    AdminTrip.fromJson,
  );

  Future<AdminTrip> getTrip(String id) async => AdminTrip.fromJson(
    _data(await _send('GET', '/v1/admin/trips/${Uri.encodeComponent(id)}')),
  );

  Future<AdminTrip> cancelTrip(String id) async => AdminTrip.fromJson(
    _data(
      await _send('POST', '/v1/admin/trips/${Uri.encodeComponent(id)}/cancel'),
    ),
  );

  Future<AdminPage<AdminAuditEvent>> listAudit({
    String? action,
    int limit = 50,
    int offset = 0,
  }) async => _page(
    await _send(
      'GET',
      '/v1/admin/audit-logs',
      query: {'action': ?action, 'limit': '$limit', 'offset': '$offset'},
    ),
    AdminAuditEvent.fromJson,
  );
}
