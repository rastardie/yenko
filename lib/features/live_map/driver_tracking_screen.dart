import 'package:flutter/material.dart';

import '../../core/data/trip_repository.dart';
import '../../core/models/trip.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'live_location_tracker.dart';

/// Lets a driver start/stop sharing their live GPS location for one of
/// their own trips that has at least one confirmed booking. There is no
/// websocket layer — the rider's app polls for this (see
/// RiderTrackingScreen) — so this screen's only job is to keep posting
/// throttled fixes while it is open.
///
/// Unlike onb (where a Trip has exactly one driver and one rider), a
/// YɛnKɔ trip can have several confirmed passengers; sharing location here
/// applies to all of them at once (see migration 013).
class DriverTrackingScreen extends StatefulWidget {
  const DriverTrackingScreen({
    super.key,
    required this.repository,
    required this.trip,
  });

  final TripRepository repository;
  final Trip trip;

  @override
  State<DriverTrackingScreen> createState() => _DriverTrackingScreenState();
}

class _DriverTrackingScreenState extends State<DriverTrackingScreen> {
  late final LiveLocationTracker _tracker = LiveLocationTracker(
    onFix: _postFix,
  );
  bool _sharing = false;
  String? _statusMessage;
  LiveLocationFix? _lastFix;

  @override
  void initState() {
    super.initState();
    _tracker.onPermissionWatchdogTimeout = () {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'No GPS fix yet. Check that location services are on and permission is granted.';
      });
    };
  }

  @override
  void dispose() {
    _tracker.stop();
    super.dispose();
  }

  Future<void> _postFix(LiveLocationFix fix) async {
    try {
      await widget.repository.shareLiveLocation(
        tripId: widget.trip.id,
        latitude: fix.latitude,
        longitude: fix.longitude,
        speedKmh: fix.speedKmh,
        heading: fix.heading,
      );
      if (!mounted) return;
      setState(() {
        _lastFix = fix;
        _statusMessage = null;
      });
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = error.message);
    }
  }

  Future<void> _toggleSharing() async {
    if (_sharing) {
      await _tracker.stop();
      setState(() {
        _sharing = false;
        _statusMessage = null;
      });
      return;
    }
    final started = await _tracker.start();
    if (!mounted) return;
    if (!started) {
      setState(
        () => _statusMessage =
            'Location permission is required to share your position with riders.',
      );
      return;
    }
    setState(() {
      _sharing = true;
      _statusMessage = 'Waiting for a GPS fix…';
    });
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return YenkoShowcaseBackdrop(
      useWatermark: true,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            YenkoScreenTitle(
              title: 'Share your location',
              subtitle: '${trip.from} → ${trip.to}',
            ),
            const SizedBox(height: 16),
            YenkoShowcaseCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _sharing
                            ? Icons.gps_fixed_rounded
                            : Icons.gps_off_rounded,
                        color: _sharing
                            ? YenkoColors.green
                            : YenkoColors.gray,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _sharing ? 'Sharing live location' : 'Not sharing',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: YenkoColors.gray,
                      ),
                    ),
                  ],
                  if (_lastFix != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_lastFix!.latitude.toStringAsFixed(5)}, ${_lastFix!.longitude.toStringAsFixed(5)} · ${_lastFix!.speedKmh.toStringAsFixed(0)} km/h',
                      style: const TextStyle(
                        fontSize: 12,
                        color: YenkoColors.gray,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _toggleSharing,
                      style: FilledButton.styleFrom(
                        backgroundColor: _sharing
                            ? YenkoColors.red
                            : const Color(0xFFF9B900),
                        foregroundColor: _sharing
                            ? Colors.white
                            : YenkoColors.charcoal,
                      ),
                      icon: Icon(
                        _sharing
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline_rounded,
                      ),
                      label: Text(
                        _sharing ? 'Stop sharing' : 'Start sharing',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Riders with a confirmed seat on this trip will see your live position while you share it. YɛnKɔ does not record a location history.',
              style: TextStyle(fontSize: 11, color: YenkoColors.gray),
            ),
          ],
        ),
      ),
    );
  }
}
