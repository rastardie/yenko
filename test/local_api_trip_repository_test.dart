import 'dart:convert';
import 'dart:io';

import 'package:yenko_app/core/data/local_api_trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'loads trips, bookings, notifications, and driver summaries from the local API',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = http.Client();
      final trip = {
        'id': '11111111-1111-4111-8111-111111111111',
        'driver': {
          'displayName': 'Kwame Mensah',
          'rating': 4.8,
          'completedTrips': 32,
          'verificationStatus': 'demo',
        },
        'vehicle': {
          'description': 'Toyota Corolla',
          'verificationStatus': 'demo',
        },
        'from': 'East Legon Hills',
        'to': 'Circle',
        'pickupJunction': 'Madina Market junction',
        'departureAt': DateTime.now()
            .add(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
        'seatsAvailable': 3,
        'pricePerSeat': 15,
        'isWomenOnly': false,
        'status': 'open',
      };
      try {
        server.listen((request) async {
          final data = switch (request.uri.path) {
            '/v1/trips' => [trip],
            '/v1/me/reservations' => [],
            '/v1/me/notifications' => [],
            '/v1/driver/trips' => [],
            _ => null,
          };
          request.response
            ..statusCode = data == null ? HttpStatus.notFound : HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'data': data ?? []}));
          await request.response.close();
        });
        final repository = LocalApiTripRepository(
          baseUrl:
              'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
          accessToken: 'test-access-token',
          role: 'passenger',
          client: client,
        );

        await repository.initialize();

        expect(repository.trips, hasLength(1));
        expect(repository.bookings, isEmpty);
        expect(repository.notifications, isEmpty);
        expect(repository.driverTripSummaries, isEmpty);
        expect(repository.trips.single.driverName, 'Kwame Mensah');
        expect(repository.trips.single.plateNumber, 'Shown after confirmation');
        repository.dispose();
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );
}
