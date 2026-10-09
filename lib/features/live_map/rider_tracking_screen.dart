import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data/trip_repository.dart';
import '../../core/models/trip.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'live_location_map.dart';

/// Lets a passenger watch their driver's live position for a confirmed
/// booking. There is no websocket layer here (matching onb): this simply
/// polls [TripRepository.fetchLiveLocation] every 5 seconds while the
/// screen is open, same cadence as onb's rider_tracking_screen.dart.
class RiderTrackingScreen extends StatefulWidget {
  const RiderTrackingScreen({
    super.key,
    required this.repository,
    required this.booking,
  });

  final TripRepository repository;
  final Booking booking;

  @override
  State<RiderTrackingScreen> createState() => _RiderTrackingScreenState();
}

class _RiderTrackingScreenState extends State<RiderTrackingScreen> {
  LiveLocation? _location;
  String? _errorMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final location = await widget.repository.fetchLiveLocation(
        widget.booking,
      );
      if (!mounted) return;
      setState(() {
        _location = location;
        _errorMessage = null;
      });
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.booking.trip;
    final location = _location;
    return YenkoShowcaseBackdrop(
      useWatermark: true,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            YenkoScreenTitle(
              title: 'Track your ride',
              subtitle: '${trip.from} → ${trip.to}',
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              YenkoShowcaseCard(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: YenkoColors.red),
                ),
              )
            else if (location == null || !location.hasFix)
              YenkoShowcaseCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.satellite_alt_outlined, color: YenkoColors.gray),
                    SizedBox(height: 8),
                    Text(
                      'Waiting for your driver to start sharing their location…',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'This updates automatically every few seconds.',
                      style: TextStyle(fontSize: 12, color: YenkoColors.gray),
                    ),
                  ],
                ),
              )
            else ...[
              SizedBox(
                height: 320,
                child: LiveLocationMap(
                  latitude: location.latitude!,
                  longitude: location.longitude!,
                  heading: location.heading,
                  pickupJunction: trip.pickupJunction,
                ),
              ),
              const SizedBox(height: 12),
              YenkoShowcaseCard(
                child: Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: YenkoColors.gold),
                    const SizedBox(width: 8),
                    Text(
                      '${location.speedKmh?.toStringAsFixed(0) ?? '—'} km/h',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    Text(
                      _lastUpdatedLabel(location.updatedAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: YenkoColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _lastUpdatedLabel(DateTime? updatedAt) {
    if (updatedAt == null) return '';
    final secondsAgo = DateTime.now().difference(updatedAt).inSeconds;
    if (secondsAgo < 5) return 'Updated just now';
    return 'Updated ${secondsAgo}s ago';
  }
}
