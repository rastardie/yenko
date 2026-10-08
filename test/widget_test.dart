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
}
