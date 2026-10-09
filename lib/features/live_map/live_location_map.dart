import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/theme/app_theme.dart';

/// Renders a driver's live position on an OpenStreetMap tile layer via
/// flutter_map — no Google Maps API key required, so this works everywhere
/// (web/PWA today; also usable on native once/if a key is added later for
/// the Google Maps path, since this widget does not depend on that key at
/// all). See HANDOVER.md for why onb and ynk both keep an OSM path
/// alongside the native Google Maps view.
class LiveLocationMap extends StatelessWidget {
  const LiveLocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
    this.heading,
    this.pickupJunction,
  });

  final double latitude;
  final double longitude;
  final double? heading;

  /// Shown as a label under the marker, if provided.
  final String? pickupJunction;

  @override
  Widget build(BuildContext context) {
    final center = ll.LatLng(latitude, longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: 15),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.yenko.app',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 44,
                height: 44,
                child: Transform.rotate(
                  angle: ((heading ?? 0) * 3.1415926535 / 180),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: YenkoColors.gold,
                    size: 36,
                  ),
                ),
              ),
            ],
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('© OpenStreetMap contributors'),
            ],
          ),
        ],
      ),
    );
  }
}
