import 'package:flutter_test/flutter_test.dart';
import 'package:yenko_app/core/data/trip_repository.dart';
import 'package:yenko_app/main.dart';

void main() {
  testWidgets(
    'shows the showcase-styled ride discovery experience by default',
    (tester) async {
      await tester.pumpWidget(const YenkoApp());
      await tester.pumpAndSettle();

      expect(find.text('Hello, traveller 👋'), findsOneWidget);
      expect(find.text('Where are you going today?'), findsOneWidget);
      expect(find.text('Search rides'), findsOneWidget);
    },
  );

  testWidgets('opens the ride-offer screen from the redesigned navigation', (
    tester,
  ) async {
    await tester.pumpWidget(const YenkoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Offer'));
    await tester.pumpAndSettle();

    expect(find.text('Offer a ride'), findsOneWidget);
    expect(find.text('Your route'), findsOneWidget);
  });

  test(
    'confirms a requested seat through the repository state machine',
    () async {
      final repository = InMemoryTripRepository();
      final offeredTrip = repository.trips.first;

      await repository.requestSeat(offeredTrip);

      expect(repository.activeBooking, isNotNull);
      expect(repository.activeBooking!.trip.id, offeredTrip.id);
      expect(
        repository.activeBooking!.trip.seatsAvailable,
        offeredTrip.seatsAvailable - 1,
      );

      await repository.cancelBooking(repository.activeBooking!);

      expect(repository.activeBooking, isNull);
      expect(repository.bookings.single.status, 'cancelled');
      expect(repository.trips.first.seatsAvailable, offeredTrip.seatsAvailable);
    },
  );

  test(
    'a driver can accept or decline a pending seat request on their own trip',
    () async {
      final repository = InMemoryTripRepository();
      await repository.postTrip(
        from: 'East Legon',
        to: 'Circle',
        pickupJunction: '37 Station',
        seats: 2,
        pricePerSeat: 20,
        womenOnly: false,
      );
      final ownTrip = repository.trips.first;
      await repository.requestSeat(ownTrip);

      expect(repository.pendingDriverReservations, hasLength(1));
      final pending = repository.pendingDriverReservations.single;

      await repository.confirmReservation(pending);
      expect(repository.pendingDriverReservations, isEmpty);
      expect(repository.bookings.single.status, 'confirmed');

      // A second request, this time declined, should release its seat.
      final refreshedTrip = repository.trips.first;
      await repository.requestSeat(refreshedTrip);
      final secondPending = repository.pendingDriverReservations.single;
      final seatsBeforeDecline = repository.trips.first.seatsAvailable;

      await repository.declineReservation(secondPending);
      expect(repository.pendingDriverReservations, isEmpty);
      expect(
        repository.trips.first.seatsAvailable,
        seatsBeforeDecline + secondPending.seats,
      );
    },
  );

  test('setMomoDetails rejects an invalid number and accepts a valid one', () async {
    final repository = InMemoryTripRepository();
    await expectLater(
      repository.setMomoDetails(momoNumber: 'not-a-number', momoNetwork: 'mtn'),
      throwsStateError,
    );
    expect(repository.myMomoDetails, isNull);

    await repository.setMomoDetails(
      momoNumber: '+233244000111',
      momoNetwork: 'mtn',
    );
    expect(repository.myMomoDetails!.momoNumber, '+233244000111');
    expect(repository.myMomoDetails!.networkLabel, 'MTN MoMo');

    await repository.setMomoDetails();
    expect(repository.myMomoDetails, isNull);
  });

  test(
    'a confirmed booking carries the driver momo and both sides can self-report payment',
    () async {
      final repository = InMemoryTripRepository();
      await repository.setMomoDetails(
        momoNumber: '+233244000111',
        momoNetwork: 'mtn',
      );
      await repository.postTrip(
        from: 'East Legon',
        to: 'Circle',
        pickupJunction: '37 Station',
        seats: 2,
        pricePerSeat: 20,
        womenOnly: false,
      );
      final ownTrip = repository.trips.first;
      await repository.requestSeat(ownTrip);
      final pending = repository.pendingDriverReservations.single;

      await repository.confirmReservation(pending);
      final confirmed = repository.bookings.single;
      expect(confirmed.status, 'confirmed');
      expect(confirmed.paymentStatus, 'unpaid');
      expect(confirmed.driverMomo?.momoNumber, '+233244000111');

      await expectLater(
        repository.markPaymentReceived(confirmed),
        completes,
      );
      expect(repository.bookings.single.paymentStatus, 'driver_confirmed_received');

      await expectLater(
        repository.markPaymentSent(repository.bookings.single),
        completes,
      );
    },
  );
}
