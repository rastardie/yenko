import 'package:flutter/foundation.dart';

import '../models/trip.dart';

/// UI-facing seam for local data now and an authenticated API implementation
/// later. The current app deliberately binds [InMemoryTripRepository].
abstract interface class TripRepository implements Listenable {
  List<Trip> get trips;
  List<Booking> get bookings;
  List<YenkoNotification> get notifications;
  List<DriverTripSummary> get driverTripSummaries;
  Booking? get activeBooking;

  Future<void> initialize();
  Future<void> requestSeat(Trip trip);
  Future<void> cancelBooking(Booking booking);
  Future<void> postTrip({
    required String from,
    required String to,
    required String pickupJunction,
    required int seats,
    required int pricePerSeat,
    required bool womenOnly,
  });
  Future<void> markNotificationsRead();
}

class InMemoryTripRepository extends ChangeNotifier implements TripRepository {
  InMemoryTripRepository() : _trips = List.of(_seedTrips);

  static final List<Trip> _seedTrips = [
    Trip(
      id: 'trip-kwame',
      driverName: 'Kwame Mensah',
      driverRating: 4.8,
      driverTrips: 32,
      carDescription: 'Toyota Corolla',
      plateNumber: 'GR-1234-23',
      from: 'East Legon Hills',
      to: 'Circle',
      pickupJunction: 'Madina Market junction',
      departureLabel: 'Today, 7:30 AM',
      departureAt: DateTime.now().add(const Duration(minutes: 18)),
      seatsAvailable: 3,
      pricePerSeat: 15,
    ),
    Trip(
      id: 'trip-ama',
      driverName: 'Ama Owusu',
      driverRating: 4.9,
      driverTrips: 18,
      carDescription: 'Hyundai Elantra',
      plateNumber: 'GR-6421-24',
      from: 'Adenta',
      to: 'Ridge',
      pickupJunction: '37 Station',
      departureLabel: 'Today, 7:45 AM',
      departureAt: DateTime.now().add(const Duration(minutes: 33)),
      seatsAvailable: 2,
      pricePerSeat: 18,
      isWomenOnly: true,
    ),
  ];

  final List<Trip> _trips;
  final List<Booking> _bookings = [];
  final List<YenkoNotification> _notifications = [];

  @override
  List<Trip> get trips => List.unmodifiable(_trips);

  @override
  List<Booking> get bookings => List.unmodifiable(_bookings);

  @override
  List<YenkoNotification> get notifications =>
      List.unmodifiable(_notifications);

  @override
  List<DriverTripSummary> get driverTripSummaries => _trips
      .where((trip) => trip.driverName == 'You')
      .map((trip) {
        final matches = _bookings
            .where((booking) => booking.trip.id == trip.id)
            .toList();
        return DriverTripSummary(
          trip: trip,
          seatsBooked: matches.fold(
            0,
            (total, booking) => total + booking.seats,
          ),
          bookingCount: matches.length,
        );
      })
      .toList(growable: false);

  @override
  Booking? get activeBooking =>
      _bookings.where((booking) => booking.status == 'requested').firstOrNull;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestSeat(Trip trip) async {
    if (trip.seatsAvailable < 1) {
      throw StateError('This trip has no seats remaining.');
    }
    final updatedTrip = trip.copyWith(seatsAvailable: trip.seatsAvailable - 1);
    final index = _trips.indexWhere((item) => item.id == trip.id);
    if (index < 0) throw StateError('This trip is no longer available.');
    _trips[index] = updatedTrip;
    _bookings.insert(
      0,
      Booking(id: 'booking-${trip.id}', trip: updatedTrip, seats: 1),
    );
    _notifications.insert(
      0,
      YenkoNotification(
        id: 'notification-${DateTime.now().microsecondsSinceEpoch}',
        title: 'Seat request received',
        body: 'Your request for ${trip.from} to ${trip.to} is saved.',
        createdAt: DateTime.now(),
        read: false,
      ),
    );
    notifyListeners();
  }

  @override
  Future<void> cancelBooking(Booking booking) async {
    if (booking.status != 'requested') {
      throw StateError('Only a pending seat request can be cancelled.');
    }
    final tripIndex = _trips.indexWhere((trip) => trip.id == booking.trip.id);
    if (tripIndex < 0 || _trips[tripIndex].status != TripStatus.open) {
      throw StateError('This trip can no longer be cancelled.');
    }
    _trips[tripIndex] = _trips[tripIndex].copyWith(
      seatsAvailable: _trips[tripIndex].seatsAvailable + booking.seats,
    );
    final bookingIndex = _bookings.indexWhere((item) => item.id == booking.id);
    if (bookingIndex < 0) throw StateError('Booking not found.');
    _bookings[bookingIndex] = booking.copyWith(status: 'cancelled');
    _notifications.insert(
      0,
      YenkoNotification(
        id: 'notification-${DateTime.now().microsecondsSinceEpoch}',
        title: 'Seat request cancelled',
        body:
            'Your request for ${booking.trip.from} to ${booking.trip.to} was cancelled.',
        createdAt: DateTime.now(),
        read: false,
      ),
    );
    notifyListeners();
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
    _trips.insert(
      0,
      Trip(
        id: 'trip-${DateTime.now().microsecondsSinceEpoch}',
        driverName: 'You',
        driverRating: 0,
        driverTrips: 0,
        carDescription: 'Your verified car',
        plateNumber: 'Pending',
        from: from,
        to: to,
        pickupJunction: pickupJunction,
        departureLabel: 'Today, 7:30 AM',
        departureAt: DateTime.now().add(const Duration(minutes: 30)),
        seatsAvailable: seats,
        pricePerSeat: pricePerSeat,
        isWomenOnly: womenOnly,
      ),
    );
    notifyListeners();
  }

  @override
  Future<void> markNotificationsRead() async {
    for (var index = 0; index < _notifications.length; index += 1) {
      _notifications[index] = _notifications[index].copyWith(read: true);
    }
    notifyListeners();
  }
}
