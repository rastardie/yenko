import 'package:flutter_test/flutter_test.dart';
import 'package:yenko_app/features/live_map/live_location_tracker.dart';

void main() {
  test('uses the OS-reported speed directly when it is nonzero', () {
    final speed = resolveSpeedKmh(
      osSpeedMetersPerSecond: 10, // 36 km/h
      latitude: 5.65,
      longitude: -0.19,
      timestamp: DateTime(2026, 1, 1, 12, 0, 5),
      previousLatitude: 5.6499,
      previousLongitude: -0.1901,
      previousTimestamp: DateTime(2026, 1, 1, 12, 0, 0),
    );
    expect(speed, closeTo(36, 0.01));
  });

  test('falls back to a distance/time computation when the OS speed reads 0', () {
    // ~111m north at the equator per 0.001 degree of latitude; 5 seconds
    // elapsed should resolve to roughly 80 km/h.
    final speed = resolveSpeedKmh(
      osSpeedMetersPerSecond: 0,
      latitude: 0.001,
      longitude: 0,
      timestamp: DateTime(2026, 1, 1, 12, 0, 5),
      previousLatitude: 0,
      previousLongitude: 0,
      previousTimestamp: DateTime(2026, 1, 1, 12, 0, 0),
    );
    expect(speed, greaterThan(60));
    expect(speed, lessThan(100));
  });

  test('returns 0 with no previous fix to compute a fallback from', () {
    final speed = resolveSpeedKmh(
      osSpeedMetersPerSecond: 0,
      latitude: 5.65,
      longitude: -0.19,
      timestamp: DateTime(2026, 1, 1, 12, 0, 5),
    );
    expect(speed, 0);
  });

  test('returns 0 when the previous fix has the same or a later timestamp', () {
    final speed = resolveSpeedKmh(
      osSpeedMetersPerSecond: 0,
      latitude: 5.65,
      longitude: -0.19,
      timestamp: DateTime(2026, 1, 1, 12, 0, 0),
      previousLatitude: 5.64,
      previousLongitude: -0.18,
      previousTimestamp: DateTime(2026, 1, 1, 12, 0, 5),
    );
    expect(speed, 0);
  });

  test('caps implausible spikes from GPS jitter back to 0', () {
    // ~1.1km apart in 1 second implies ~4000 km/h — clearly jitter, not a
    // real speed, so it should be capped rather than reported.
    final speed = resolveSpeedKmh(
      osSpeedMetersPerSecond: 0,
      latitude: 0.01,
      longitude: 0,
      timestamp: DateTime(2026, 1, 1, 12, 0, 1),
      previousLatitude: 0,
      previousLongitude: 0,
      previousTimestamp: DateTime(2026, 1, 1, 12, 0, 0),
    );
    expect(speed, 0);
  });
}
