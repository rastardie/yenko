enum TripStatus { open, requested, confirmed, inProgress, completed, cancelled }

class Trip {
  const Trip({
    required this.id,
    required this.driverName,
    required this.driverRating,
    required this.driverTrips,
    required this.carDescription,
    required this.plateNumber,
    required this.from,
    required this.to,
    required this.pickupJunction,
    required this.departureLabel,
    required this.departureAt,
    required this.seatsAvailable,
    required this.pricePerSeat,
    this.isWomenOnly = false,
    this.status = TripStatus.open,
  });

  factory Trip.fromApi(Map<String, dynamic> json) {
    final driver = Map<String, dynamic>.from(
      json['driver'] as Map? ?? const {},
    );
    final vehicle = Map<String, dynamic>.from(
      json['vehicle'] as Map? ?? const {},
    );
    final departureAt = DateTime.parse(json['departureAt'] as String).toLocal();
    return Trip(
      id: json['id'] as String,
      driverName: driver['displayName'] as String? ?? 'YɛnKɔ driver',
      driverRating: (driver['rating'] as num? ?? 0).toDouble(),
      driverTrips: (driver['completedTrips'] as num? ?? 0).toInt(),
      carDescription: vehicle['description'] as String? ?? 'Verified vehicle',
      // Public discovery intentionally does not expose the vehicle plate.
      plateNumber: 'Shown after confirmation',
      from: json['from'] as String,
      to: json['to'] as String,
      pickupJunction: json['pickupJunction'] as String,
      departureLabel: _departureLabel(departureAt),
      departureAt: departureAt,
      seatsAvailable: (json['seatsAvailable'] as num).toInt(),
      pricePerSeat: (json['pricePerSeat'] as num).toInt(),
      isWomenOnly: json['isWomenOnly'] == true,
      status: _statusFromApi(json['status'] as String?),
    );
  }

  final String id;
  final String driverName;
  final double driverRating;
  final int driverTrips;
  final String carDescription;
  final String plateNumber;
  final String from;
  final String to;
  final String pickupJunction;
  final String departureLabel;
  final DateTime departureAt;
  final int seatsAvailable;
  final int pricePerSeat;
  final bool isWomenOnly;
  final TripStatus status;

  Trip copyWith({int? seatsAvailable, TripStatus? status}) => Trip(
    id: id,
    driverName: driverName,
    driverRating: driverRating,
    driverTrips: driverTrips,
    carDescription: carDescription,
    plateNumber: plateNumber,
    from: from,
    to: to,
    pickupJunction: pickupJunction,
    departureLabel: departureLabel,
    departureAt: departureAt,
    seatsAvailable: seatsAvailable ?? this.seatsAvailable,
    pricePerSeat: pricePerSeat,
    isWomenOnly: isWomenOnly,
    status: status ?? this.status,
  );

  static TripStatus _statusFromApi(String? value) => switch (value) {
    'requested' => TripStatus.requested,
    'confirmed' => TripStatus.confirmed,
    'in_progress' => TripStatus.inProgress,
    'completed' => TripStatus.completed,
    'cancelled' => TripStatus.cancelled,
    _ => TripStatus.open,
  };

  static String _departureLabel(DateTime departureAt) {
    final now = DateTime.now();
    final day = DateTime(departureAt.year, departureAt.month, departureAt.day);
    final today = DateTime(now.year, now.month, now.day);
    final prefix = day == today
        ? 'Today'
        : day == today.add(const Duration(days: 1))
        ? 'Tomorrow'
        : '${departureAt.day}/${departureAt.month}';
    final hour = departureAt.hour % 12 == 0 ? 12 : departureAt.hour % 12;
    final minute = departureAt.minute.toString().padLeft(2, '0');
    final period = departureAt.hour < 12 ? 'AM' : 'PM';
    return '$prefix, $hour:$minute $period';
  }
}

class Booking {
  Booking({
    required this.id,
    required this.trip,
    required this.seats,
    this.status = 'requested',
    this.paymentStatus = 'unpaid',
    this.driverMomo,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Booking.fromApi(Map<String, dynamic> json) => Booking(
    id: json['id'] as String,
    trip: Trip.fromApi(Map<String, dynamic>.from(json['trip'] as Map)),
    seats: (json['seats'] as num? ?? 1).toInt(),
    status: json['status'] as String? ?? 'requested',
    paymentStatus: json['paymentStatus'] as String? ?? 'unpaid',
    driverMomo: json['driverMomo'] is Map
        ? DriverMomo.fromApi(Map<String, dynamic>.from(json['driverMomo'] as Map))
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
  );

  final String id;
  final Trip trip;
  final int seats;
  final String status;

  /// `unpaid` / `passenger_marked_paid` / `driver_confirmed_received`. This
  /// is a self-reported status only — YɛnKɔ never verifies a direct mobile
  /// money payment between a passenger and driver. See [DriverMomo].
  final String paymentStatus;

  /// The driver's mobile money payout number, present only once this
  /// booking is confirmed. The passenger pays this number directly, outside
  /// the app (e.g. via USSD or the network's own app); YɛnKɔ never collects
  /// or moves money itself.
  final DriverMomo? driverMomo;
  final DateTime createdAt;

  int get totalPrice => seats * trip.pricePerSeat;

  Booking copyWith({String? status, String? paymentStatus}) => Booking(
    id: id,
    trip: trip,
    seats: seats,
    status: status ?? this.status,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    driverMomo: driverMomo,
    createdAt: createdAt,
  );
}

/// A driver's self-registered mobile money payout number and network. Never
/// verified by YɛnKɔ; see [Booking.paymentStatus].
class DriverMomo {
  const DriverMomo({required this.momoNumber, required this.momoNetwork});

  factory DriverMomo.fromApi(Map<String, dynamic> json) => DriverMomo(
    momoNumber: json['momoNumber'] as String,
    momoNetwork: json['momoNetwork'] as String,
  );

  final String momoNumber;
  final String momoNetwork;

  String get networkLabel => switch (momoNetwork) {
    'mtn' => 'MTN MoMo',
    'telecel' => 'Telecel Cash',
    'airteltigo' => 'AirtelTigo Money',
    _ => momoNetwork,
  };
}

class YenkoNotification {
  const YenkoNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  factory YenkoNotification.fromApi(Map<String, dynamic> json) =>
      YenkoNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'YɛnKɔ update',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        read: json['read'] == true,
      );

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  YenkoNotification copyWith({bool? read}) => YenkoNotification(
    id: id,
    title: title,
    body: body,
    createdAt: createdAt,
    read: read ?? this.read,
  );
}

class DriverTripSummary {
  const DriverTripSummary({
    required this.trip,
    required this.seatsBooked,
    required this.bookingCount,
  });

  factory DriverTripSummary.fromApi(Map<String, dynamic> json) =>
      DriverTripSummary(
        trip: Trip.fromApi(Map<String, dynamic>.from(json['trip'] as Map)),
        seatsBooked: (json['seatsBooked'] as num? ?? 0).toInt(),
        bookingCount: (json['bookingCount'] as num? ?? 0).toInt(),
      );

  final Trip trip;
  final int seatsBooked;
  final int bookingCount;
  int get expectedFare => seatsBooked * trip.pricePerSeat;
}

/// The most recent GPS fix reported by the driver for a confirmed booking.
/// All fields are null until the driver has posted at least one fix for
/// that trip — see migration 013 and HANDOVER.md. There is no websocket
/// layer; the rider's app polls for this.
class LiveLocation {
  const LiveLocation({
    this.latitude,
    this.longitude,
    this.speedKmh,
    this.heading,
    this.updatedAt,
  });

  factory LiveLocation.fromApi(Map<String, dynamic> json) => LiveLocation(
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    speedKmh: (json['speedKmh'] as num?)?.toDouble(),
    heading: (json['heading'] as num?)?.toDouble(),
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String).toLocal(),
  );

  final double? latitude;
  final double? longitude;
  final double? speedKmh;
  final double? heading;
  final DateTime? updatedAt;

  bool get hasFix => latitude != null && longitude != null;
}
