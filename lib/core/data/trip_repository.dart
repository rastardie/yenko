import 'package:flutter/foundation.dart';

import '../models/trip.dart';

/// UI-facing seam for local data now and an authenticated API implementation
/// later. The current app deliberately binds [InMemoryTripRepository].
abstract interface class TripRepository implements Listenable {
  List<Trip> get trips;
  List<Booking> get bookings;
  List<YenkoNotification> get notifications;
  List<DriverTripSummary> get driverTripSummaries;

  /// Pending (status `requested`) seat requests across every trip the
  /// signed-in driver owns. Empty for passengers and in any state where the
  /// signed-in account is not a driver.
  List<Booking> get pendingDriverReservations;
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

  /// Accepts a pending seat request on one of the signed-in driver's own
  /// trips. Throws [StateError] if the booking cannot be confirmed (not
  /// pending, trip no longer open, or not owned by this driver).
  Future<void> confirmReservation(Booking booking);

  /// Declines a pending seat request on one of the signed-in driver's own
  /// trips, releasing the held seat back to the trip. Throws [StateError]
  /// if the booking cannot be declined.
  Future<void> declineReservation(Booking booking);

  /// Confirmed bookings across every trip the signed-in driver owns, for
  /// following up on direct mobile money payment. Empty for passengers.
  List<Booking> get confirmedDriverReservations;

  /// The signed-in driver's own mobile money payout number, or null if not
  /// yet set. Null for passengers.
  DriverMomo? get myMomoDetails;

  /// Sets or clears the signed-in driver's mobile money payout number.
  /// Passing null for both arguments clears it. Throws [StateError] if the
  /// signed-in account is not a driver or the number fails validation.
  Future<void> setMomoDetails({String? momoNumber, String? momoNetwork});

  /// Passenger self-reports having sent mobile money payment directly to
  /// the driver for this confirmed booking, outside the app. Not verified
  /// by YɛnKɔ. Throws [StateError] if the booking is not the caller's own
  /// confirmed booking.
  Future<void> markPaymentSent(Booking booking);

  /// Driver self-reports having received the passenger's direct mobile
  /// money payment for this confirmed booking. Not verified by YɛnKɔ.
  /// Throws [StateError] if the booking is not on one of the caller's own
  /// trips, or is not confirmed.
  Future<void> markPaymentReceived(Booking booking);

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
  DriverMomo? _myMomo;

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
  List<Booking> get pendingDriverReservations => _bookings
      .where(
        (booking) =>
            booking.status == 'requested' && booking.trip.driverName == 'You',
      )
      .toList(growable: false);

  @override
  Booking? get activeBooking =>
      _bookings.where((booking) => booking.status == 'requested').firstOrNull;

  @override
  List<Booking> get confirmedDriverReservations => _bookings
      .where(
        (booking) =>
            booking.status == 'confirmed' && booking.trip.driverName == 'You',
      )
      .toList(growable: false);

  @override
  DriverMomo? get myMomoDetails => _myMomo;

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
  Future<void> confirmReservation(Booking booking) async {
    final bookingIndex = _bookings.indexWhere((item) => item.id == booking.id);
    if (bookingIndex < 0 || _bookings[bookingIndex].status != 'requested') {
      throw StateError('Only a pending seat request can be confirmed.');
    }
    final confirmed = booking.copyWith(status: 'confirmed');
    _bookings[bookingIndex] = _myMomo == null
        ? confirmed
        : Booking(
            id: confirmed.id,
            trip: confirmed.trip,
            seats: confirmed.seats,
            status: confirmed.status,
            paymentStatus: confirmed.paymentStatus,
            driverMomo: _myMomo,
            createdAt: confirmed.createdAt,
          );
    notifyListeners();
  }

  @override
  Future<void> declineReservation(Booking booking) async {
    final bookingIndex = _bookings.indexWhere((item) => item.id == booking.id);
    if (bookingIndex < 0 || _bookings[bookingIndex].status != 'requested') {
      throw StateError('Only a pending seat request can be declined.');
    }
    final tripIndex = _trips.indexWhere((trip) => trip.id == booking.trip.id);
    if (tripIndex >= 0) {
      _trips[tripIndex] = _trips[tripIndex].copyWith(
        seatsAvailable: _trips[tripIndex].seatsAvailable + booking.seats,
      );
    }
    _bookings[bookingIndex] = booking.copyWith(status: 'cancelled');
    notifyListeners();
  }

  @override
  Future<void> setMomoDetails({String? momoNumber, String? momoNetwork}) async {
    if (momoNumber == null && momoNetwork == null) {
      _myMomo = null;
      notifyListeners();
      return;
    }
    if (momoNumber == null ||
        !RegExp(r'^\+?[0-9]{9,15}$').hasMatch(momoNumber)) {
      throw StateError('Enter a valid mobile money number (9-15 digits).');
    }
    if (!{'mtn', 'telecel', 'airteltigo'}.contains(momoNetwork)) {
      throw StateError('Choose a mobile money network.');
    }
    _myMomo = DriverMomo(momoNumber: momoNumber, momoNetwork: momoNetwork!);
    notifyListeners();
  }

  @override
  Future<void> markPaymentSent(Booking booking) async {
    final bookingIndex = _bookings.indexWhere((item) => item.id == booking.id);
    if (bookingIndex < 0 || _bookings[bookingIndex].status != 'confirmed') {
      throw StateError('Only a confirmed booking can be marked as paid.');
    }
    _bookings[bookingIndex] = _bookings[bookingIndex].copyWith(
      paymentStatus: 'passenger_marked_paid',
    );
    notifyListeners();
  }

  @override
  Future<void> markPaymentReceived(Booking booking) async {
    final bookingIndex = _bookings.indexWhere((item) => item.id == booking.id);
    if (bookingIndex < 0 || _bookings[bookingIndex].status != 'confirmed') {
      throw StateError(
        'Only a confirmed booking can be marked as payment received.',
      );
    }
    _bookings[bookingIndex] = _bookings[bookingIndex].copyWith(
      paymentStatus: 'driver_confirmed_received',
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
