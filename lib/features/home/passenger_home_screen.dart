import 'package:flutter/material.dart';

import '../../core/data/trip_repository.dart';
import '../../core/models/trip.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/sign_out.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import '../../shared/widgets/yenko_widgets.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({
    super.key,
    required this.repository,
    required this.onOpenBooking,
    this.displayName,
  });
  final TripRepository repository;
  final VoidCallback onOpenBooking;

  /// The signed-in rider's full display name, used to greet them by first
  /// name. Null in mock mode, where there is no session.
  final String? displayName;

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  bool _womenOnly = false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      final trips = widget.repository.trips
          .where(
            (trip) =>
                trip.seatsAvailable > 0 && (!_womenOnly || trip.isWomenOnly),
          )
          .toList();
      return YenkoShowcaseBackdrop(
        goldHeader: true,
        useWatermark: true,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: YenkoLogo(height: 30),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.location_on_rounded, size: 18),
                  const SizedBox(width: 4),
                  const Text(
                    'Accra, Ghana',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  const Spacer(),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                  const YenkoSignOutButton(),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Hello, ${firstNameOf(widget.displayName)} 👋',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Where are you going today?',
                style: TextStyle(fontSize: 14, color: YenkoColors.charcoal),
              ),
              const SizedBox(height: 14),
              const _HomeSearchCard(),
              const SizedBox(height: 12),
              YenkoShowcaseButton(
                label: 'Search rides',
                icon: Icons.search_rounded,
                onPressed: () => setState(() {}),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.calendar_month_rounded,
                      label: 'My rides',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Wallet',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.favorite_border_rounded,
                      label: 'Saved places',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.more_horiz_rounded,
                      label: 'More',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Popular routes',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  TextButton(onPressed: () {}, child: const Text('See all')),
                ],
              ),
              const SizedBox(height: 4),
              const SizedBox(
                height: 106,
                child: Row(
                  children: [
                    Expanded(
                      child: _PopularRoute(
                        label: 'Accra → Tema',
                        price: 'from GH₵ 10',
                        icon: Icons.location_city_rounded,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _PopularRoute(
                        label: 'Accra → Kasoa',
                        price: 'from GH₵ 8',
                        icon: Icons.landscape_rounded,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _PopularRoute(
                        label: 'Accra → Kumasi',
                        price: 'from GH₵ 60',
                        icon: Icons.terrain_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trips.isEmpty
                          ? 'No rides found'
                          : '${trips.length} rides available',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  FilterChip(
                    selected: _womenOnly,
                    showCheckmark: false,
                    avatar: const Icon(Icons.female_rounded, size: 17),
                    label: const Text('Women-only'),
                    onSelected: (selected) =>
                        setState(() => _womenOnly = selected),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (trips.isEmpty)
                const YenkoWatermarkEmptyState(
                  icon: Icons.directions_car_outlined,
                  title: 'No rides in this window',
                  message: 'Try another route or check back shortly.',
                ),
              for (final trip in trips) ...[
                _RideResultCard(
                  trip: trip,
                  onView: () => _showRideDetails(context, trip),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
    },
  );

  Future<void> _showRideDetails(BuildContext context, Trip trip) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _RideDetailsSheet(
          trip: trip,
          onRequest: () async {
            Navigator.of(sheetContext).pop();
            try {
              await widget.repository.requestSeat(trip);
              if (!context.mounted) return;
              widget.onOpenBooking();
            } on StateError catch (error) {
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(error.message)));
            }
          },
        ),
      );
}

class _HomeSearchCard extends StatelessWidget {
  const _HomeSearchCard();

  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    child: Column(
      children: const [
        _SearchRow(
          dotColor: Color(0xFF18B879),
          icon: Icons.my_location_rounded,
          label: 'From',
          value: 'Current location',
        ),
        Divider(height: 18),
        _SearchRow(
          dotColor: Color(0xFFFF7A2A),
          icon: Icons.location_on_rounded,
          label: 'To',
          value: 'Where are you going?',
        ),
        Divider(height: 18),
        Row(
          children: [
            Expanded(
              child: _SearchMeta(
                icon: Icons.calendar_month_outlined,
                label: 'Today',
              ),
            ),
            Expanded(
              child: _SearchMeta(
                icon: Icons.person_outline_rounded,
                label: '1 passenger',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.dotColor,
    required this.icon,
    required this.label,
    required this.value,
  });
  final Color dotColor;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: dotColor.withValues(alpha: .13),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 17, color: dotColor),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: YenkoColors.gray),
            ),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      ),
      const Icon(Icons.swap_vert_rounded, color: YenkoColors.gray, size: 20),
    ],
  );
}

class _SearchMeta extends StatelessWidget {
  const _SearchMeta({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: YenkoColors.charcoal),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
    child: Column(
      children: [
        Icon(icon, size: 22, color: YenkoColors.charcoal),
        const SizedBox(height: 7),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _PopularRoute extends StatelessWidget {
  const _PopularRoute({
    required this.label,
    required this.price,
    required this.icon,
  });
  final String label;
  final String price;
  final IconData icon;
  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    padding: const EdgeInsets.all(10),
    color: const Color(0xFFFFFCF3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: Color(0xFFFFE6A1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: YenkoColors.charcoal, size: 18),
        ),
        const Spacer(),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
        ),
        Text(
          price,
          style: const TextStyle(color: YenkoColors.gray, fontSize: 10),
        ),
      ],
    ),
  );
}

class _RideResultCard extends StatelessWidget {
  const _RideResultCard({required this.trip, required this.onView});
  final Trip trip;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: const Color(0xFFFFE8A3),
          child: Text(
            trip.driverName.isEmpty ? '?' : trip.driverName.substring(0, 1),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: YenkoColors.charcoal,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trip.driverName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    'GH₵ ${trip.pricePerSeat}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '★ ${trip.driverRating} (${trip.driverTrips})',
                style: const TextStyle(fontSize: 11, color: YenkoColors.gray),
              ),
              const SizedBox(height: 7),
              Text(
                '${trip.from}  →  ${trip.to}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${trip.departureLabel} · ${trip.carDescription}',
                style: const TextStyle(fontSize: 11, color: YenkoColors.gray),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDF8EA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${trip.seatsAvailable} seats available',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF14744A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onView,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF9B900),
            foregroundColor: YenkoColors.charcoal,
            minimumSize: const Size(58, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text(
            'View',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _RideDetailsSheet extends StatelessWidget {
  const _RideDetailsSheet({required this.trip, required this.onRequest});
  final Trip trip;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .82,
    ),
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    decoration: const BoxDecoration(
      color: YenkoColors.cream,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SafeArea(
      top: false,
      child: ListView(
        children: [
          const Center(
            child: SizedBox(width: 42, child: Divider(thickness: 4)),
          ),
          const SizedBox(height: 10),
          const Text(
            'Ride details',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 18),
          YenkoShowcaseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFFFE8A3),
                      child: Text(
                        trip.driverName.isEmpty
                            ? '?'
                            : trip.driverName.substring(0, 1),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip.driverName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '★ ${trip.driverRating} · ${trip.driverTrips} rides',
                            style: const TextStyle(
                              color: YenkoColors.gray,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'GH₵ ${trip.pricePerSeat}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'per seat',
                  style: TextStyle(color: YenkoColors.gray),
                ),
                const Divider(height: 26),
                _SheetRoute(
                  icon: Icons.radio_button_checked_rounded,
                  color: YenkoColors.green,
                  label: trip.from,
                ),
                _SheetRoute(
                  icon: Icons.location_on_rounded,
                  color: YenkoColors.red,
                  label: trip.to,
                ),
                _SheetRoute(
                  icon: Icons.directions_bus_rounded,
                  color: YenkoColors.charcoal,
                  label: 'Meet at ${trip.pickupJunction}',
                ),
                const SizedBox(height: 8),
                Text(
                  '${trip.seatsAvailable} seats available · ${trip.carDescription}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          YenkoShowcaseButton(
            label: 'Book a seat',
            icon: Icons.event_seat_rounded,
            onPressed: onRequest,
          ),
        ],
      ),
    ),
  );
}

class _SheetRoute extends StatelessWidget {
  const _SheetRoute({
    required this.icon,
    required this.color,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

/// Returns the first word of [displayName] (the given name), or 'traveller'
/// when there is no signed-in session or the name is blank. Shared with
/// [DriverHomeScreen] so both role-specific home screens greet the signed-in
/// user the same way.
String firstNameOf(String? displayName) {
  final trimmed = displayName?.trim() ?? '';
  if (trimmed.isEmpty) return 'traveller';
  return trimmed.split(RegExp(r'\s+')).first;
}
