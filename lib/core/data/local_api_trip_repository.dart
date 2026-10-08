import 'dart:convert';
import 'dart:math';

// The public constructor parameter names intentionally differ from their
// private storage fields, so callers retain an ergonomic API.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/trip.dart';
import 'trip_repository.dart';

/// Android/iOS local-development adapter. Authenticates with the backend's
/// phone/PIN login (AUTH_MODE=local-pin) and sends the resulting bearer
/// token on every request; production will use the same client against a
/// real deployment, still gated by OIDC on the server for non-local modes.
class LocalApiTripRepository extends ChangeNotifier implements TripRepository {
  LocalApiTripRepository({
    required String baseUrl,
    required String accessToken,
    required String role,
    http.Client? client,
  }) : _baseUri = Uri.parse(baseUrl),
       _accessToken = accessToken,
       _role = role,
       _client = client ?? http.Client(),
       _ownsClient = client == null;
  final Uri _baseUri;
  final String _accessToken;
  final String _role;
  final http.Client _client;
  final bool _ownsClient;
  final List<Trip> _trips = [];
  final List<Booking> _bookings = [];
  final List<YenkoNotification> _notifications = [];
  final List<DriverTripSummary> _driverTripSummaries = [];
  final _random = Random.secure();

  Map<String, String> get _authHeaders => {
    'Authorization': 'Bearer $_accessToken',
  };

  bool get _isDriver => _role == 'driver';
  bool get _isPassenger => _role == 'passenger';

  @override
  List<Trip> get trips => List.unmodifiable(_trips);

  @override
  List<Booking> get bookings => List.unmodifiable(_bookings);

  @override
  List<YenkoNotification> get notifications =>
      List.unmodifiable(_notifications);

  @override
  List<DriverTripSummary> get driverTripSummaries =>
      List.unmodifiable(_driverTripSummaries);

  @override
  Booking? get activeBooking => _bookings.isEmpty ? null : _bookings.first;

  @override
  Future<void> initialize() => _loadAll(notify: true);

  Future<void> refresh() => _loadAll(notify: true);

  @override
  Future<void> requestSeat(Trip trip) async {
    if (!_isPassenger) {
      throw StateError('Only a passenger account can request a seat.');
    }
    await _request(
      method: 'POST',
      path: '/v1/trips/${Uri.encodeComponent(trip.id)}/reservations',
      payload: const {'seats': 1},
      headers: {..._authHeaders, 'Idempotency-Key': _idempotencyKey()},
    );
    await _loadAll(notify: true);
  }

  @override
  Future<void> cancelBooking(Booking booking) async {
    if (!_isPassenger) {
      throw StateError('Only a passenger account can cancel a booking.');
    }
    await _request(
      method: 'DELETE',
      path: '/v1/me/reservations/${Uri.encodeComponent(booking.id)}',
      headers: _authHeaders,
    );
    await _loadAll(notify: true);
  }

  @override
  Future<void> postTrip({
    required String from,
    required String to,
    required String pickupJunction,
    required int seats,
    required int pricePerSeat,
    required bool womenOnly,
  }) async {
    if (!_isDriver) {
      throw StateError('Only a driver account can post a trip.');
    }
    await _request(
      method: 'POST',
      path: '/v1/trips',
      payload: {
        'from': from,
        'to': to,
        'pickupJunction': pickupJunction,
        'departureAt': DateTime.now()
            .add(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
        'seatsAvailable': seats,
        'pricePerSeat': pricePerSeat,
        'isWomenOnly': womenOnly,
      },
      headers: _authHeaders,
    );
    await _loadAll(notify: true);
  }

  @override
  Future<void> markNotificationsRead() async {
    if (!_isPassenger) return;
    await _request(
      method: 'POST',
      path: '/v1/me/notifications/read',
      headers: _authHeaders,
    );
    for (var index = 0; index < _notifications.length; index += 1) {
      _notifications[index] = _notifications[index].copyWith(read: true);
    }
    notifyListeners();
  }

  Future<void> _loadAll({required bool notify}) async {
    final tripsResponse = await _request(method: 'GET', path: '/v1/trips');
    final reservationsResponse = _isPassenger
        ? await _request(
            method: 'GET',
            path: '/v1/me/reservations',
            headers: _authHeaders,
          )
        : <String, dynamic>{'data': const []};
    final notificationsResponse = _isPassenger
        ? await _request(
            method: 'GET',
            path: '/v1/me/notifications',
            headers: _authHeaders,
          )
        : <String, dynamic>{'data': const []};
    final driverTripsResponse = _isDriver
        ? await _request(
            method: 'GET',
            path: '/v1/driver/trips',
            headers: _authHeaders,
          )
        : <String, dynamic>{'data': const []};
    _replace(_trips, _records(tripsResponse).map(Trip.fromApi));
    _replace(_bookings, _records(reservationsResponse).map(Booking.fromApi));
    _replace(
      _notifications,
      _records(notificationsResponse).map(YenkoNotification.fromApi),
    );
    _replace(
      _driverTripSummaries,
      _records(driverTripsResponse).map(DriverTripSummary.fromApi),
    );
    if (notify) {
      notifyListeners();
    }
  }

  Iterable<Map<String, dynamic>> _records(Map<String, dynamic> body) =>
      (body['data'] as List<dynamic>? ?? const []).whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      );

  void _replace<T>(List<T> target, Iterable<T> values) {
    target
      ..clear()
      ..addAll(values);
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    Map<String, dynamic>? payload,
    Map<String, String> headers = const {},
  }) async {
    final uri = _baseUri.resolve(path);
    final requestHeaders = {'Accept': 'application/json', ...headers};
    http.Response response;
    final body = payload == null ? null : jsonEncode(payload);
    if (body != null) requestHeaders['Content-Type'] = 'application/json';
    switch (method) {
      case 'GET':
        response = await _client
            .get(uri, headers: requestHeaders)
            .timeout(const Duration(seconds: 10));
      case 'POST':
        response = await _client
            .post(uri, headers: requestHeaders, body: body)
            .timeout(const Duration(seconds: 10));
      case 'DELETE':
        response = await _client
            .delete(uri, headers: requestHeaders, body: body)
            .timeout(const Duration(seconds: 10));
      default:
        throw StateError('Unsupported HTTP method: $method');
    }
    final raw = utf8.decode(response.bodyBytes);
    final decoded = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('The local API returned an invalid response.');
    }
    final responseBody = Map<String, dynamic>.from(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = responseBody['error'];
      final message = error is Map ? error['message']?.toString() : null;
      throw StateError(message ?? 'The local API request failed.');
    }
    return responseBody;
  }

  String _idempotencyKey() =>
      'mobile-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
