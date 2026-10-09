import 'dart:async';

import 'package:geolocator/geolocator.dart';

// The public constructor parameter name (onFix) intentionally differs from
// its private storage field (_onFix), matching the pattern already used in
// local_api_trip_repository.dart.
// ignore_for_file: prefer_initializing_formals

/// Streams the device's GPS fixes while a driver's trip is under way, and
/// posts each throttled fix to [onFix]. Device accuracy for *speed* is
/// unreliable on many Android devices at low speeds — it frequently reads
/// exactly 0 even while moving — so this falls back to a distance/time
/// computation between consecutive fixes whenever the OS-reported speed is
/// zero, matching onb's `_resolveSpeedKmh` behaviour.
///
/// This never talks to the network itself; [onFix] is injected so the
/// caller decides how to post it (so a widget test can inject a fake and
/// never touch HTTP).
class LiveLocationTracker {
  LiveLocationTracker({
    required Future<void> Function(LiveLocationFix fix) onFix,
    this.postInterval = const Duration(seconds: 5),
    this.permissionWatchdogTimeout = const Duration(seconds: 20),
  }) : _onFix = onFix;

  final Future<void> Function(LiveLocationFix fix) _onFix;

  /// A GPS fix only triggers a backend post at most this often, even if the
  /// device emits fixes more frequently — matches onb's throttle, chosen to
  /// balance ride-tracking freshness against battery/data usage.
  final Duration postInterval;

  /// If no GPS fix at all arrives within this long after starting, the
  /// permission/service state is assumed to be broken (e.g. silently
  /// revoked) and [onPermissionWatchdogTimeout] fires once, so the UI can
  /// prompt the driver to check their settings instead of waiting forever.
  final Duration permissionWatchdogTimeout;

  /// Called at most once per [start] call if no fix arrives within
  /// [permissionWatchdogTimeout]. Optional — set after construction.
  void Function()? onPermissionWatchdogTimeout;

  StreamSubscription<Position>? _subscription;
  Timer? _watchdog;
  Position? _lastPosition;
  DateTime? _lastPostAt;
  bool _gotFirstFix = false;

  bool get isTracking => _subscription != null;

  /// Requests location permission if needed, then starts streaming fixes.
  /// Returns false (without starting) if permission is denied or location
  /// services are off, so the caller can show an explanatory message
  /// instead of silently doing nothing.
  Future<bool> start() async {
    if (isTracking) return true;

    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    _gotFirstFix = false;
    _lastPosition = null;
    _lastPostAt = null;
    _watchdog = Timer(permissionWatchdogTimeout, () {
      if (!_gotFirstFix) onPermissionWatchdogTimeout?.call();
    });

    _subscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'YɛnKɔ',
          notificationText: 'Sharing your live location for this trip',
          enableWakeLock: true,
        ),
      ),
    ).listen(_handlePosition, onError: (_) {});
    return true;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _watchdog?.cancel();
    _watchdog = null;
    _lastPosition = null;
    _lastPostAt = null;
  }

  void _handlePosition(Position position) {
    _gotFirstFix = true;
    _watchdog?.cancel();

    final speedKmh = _resolveSpeedKmh(position);
    _lastPosition = position;

    final now = DateTime.now();
    final lastPostAt = _lastPostAt;
    if (lastPostAt != null && now.difference(lastPostAt) < postInterval) {
      return;
    }
    _lastPostAt = now;

    unawaited(
      _onFix(
        LiveLocationFix(
          latitude: position.latitude,
          longitude: position.longitude,
          speedKmh: speedKmh,
          heading: position.heading,
        ),
      ),
    );
  }

  /// The OS-reported speed reads exactly 0 on many Android devices even
  /// while genuinely moving at low speed (a known device/driver quirk, not
  /// a bug here). When that happens and a previous fix exists, this
  /// computes an effective speed from the great-circle distance travelled
  /// since the previous fix divided by the elapsed time instead — the same
  /// fallback onb's `_resolveSpeedKmh` uses.
  double _resolveSpeedKmh(Position position) => resolveSpeedKmh(
    osSpeedMetersPerSecond: position.speed,
    latitude: position.latitude,
    longitude: position.longitude,
    timestamp: position.timestamp,
    previousLatitude: _lastPosition?.latitude,
    previousLongitude: _lastPosition?.longitude,
    previousTimestamp: _lastPosition?.timestamp,
  );
}

/// A single resolved GPS fix, ready to post to the backend.
class LiveLocationFix {
  const LiveLocationFix({
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.heading,
  });

  final double latitude;
  final double longitude;
  final double speedKmh;
  final double heading;
}

/// Pure speed-resolution logic, pulled out of [LiveLocationTracker] so it
/// can be unit-tested without a real GPS stream. See
/// [LiveLocationTracker._resolveSpeedKmh] for the rationale: the OS-reported
/// speed often reads exactly 0 even while moving, so this falls back to a
/// distance/time computation between the current and previous fix.
double resolveSpeedKmh({
  required double osSpeedMetersPerSecond,
  required double latitude,
  required double longitude,
  required DateTime timestamp,
  double? previousLatitude,
  double? previousLongitude,
  DateTime? previousTimestamp,
}) {
  final osSpeedKmh = osSpeedMetersPerSecond * 3.6;
  if (osSpeedKmh > 0) return osSpeedKmh;

  if (previousLatitude == null ||
      previousLongitude == null ||
      previousTimestamp == null) {
    return 0;
  }
  final elapsedSeconds =
      timestamp.difference(previousTimestamp).inMilliseconds / 1000;
  if (elapsedSeconds <= 0) return 0;

  final distanceMeters = Geolocator.distanceBetween(
    previousLatitude,
    previousLongitude,
    latitude,
    longitude,
  );
  final computed = (distanceMeters / elapsedSeconds) * 3.6;
  // A GPS fix jitter of a few meters between two fixes that are seconds
  // apart can imply an implausible instantaneous speed; cap it rather than
  // reporting a spike that would alarm a rider watching the map.
  return computed > 180 ? 0 : computed;
}
