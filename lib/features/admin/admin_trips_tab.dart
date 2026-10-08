import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_widgets.dart';

/// Trips: operational view of every trip, with cancellation for staff who
/// hold trips:cancel. Cancelling notifies the driver and every booked rider.
class AdminTripsTab extends StatefulWidget {
  const AdminTripsTab({super.key, required this.client, required this.session});

  final AdminApiClient client;
  final LocalAuthSession session;

  @override
  State<AdminTripsTab> createState() => _AdminTripsTabState();
}

class _AdminTripsTabState extends State<AdminTripsTab>
    with AutomaticKeepAliveClientMixin {
  String? _status;
  int _version = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: AdminFilterBar(
            options: const {
              null: 'All',
              'open': 'Open',
              'cancelled': 'Cancelled',
              'completed': 'Completed',
            },
            selected: _status,
            onSelected: (value) => setState(() => _status = value),
          ),
        ),
        Expanded(
          child: AdminLoader<AdminPage<AdminTrip>>(
            reloadKey: '$_status|$_version',
            load: () => widget.client.listTrips(status: _status),
            builder: (context, page, reload) => RefreshIndicator(
              color: const Color(0xFFF9B900),
              onRefresh: reload,
              child: page.items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(18),
                      children: const [
                        YenkoWatermarkEmptyState(
                          icon: Icons.route_outlined,
                          title: 'No trips',
                          message: 'Trips posted by drivers appear here.',
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
                      children: [
                        for (final entry in _byDay(page.items).entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${entry.value.length} ${entry.value.length == 1 ? 'trip' : 'trips'} · ${entry.value.fold<int>(0, (sum, trip) => sum + trip.seatsBooked)} ${entry.value.fold<int>(0, (sum, trip) => sum + trip.seatsBooked) == 1 ? 'seat' : 'seats'} booked',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: YenkoColors.gray,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final trip in entry.value)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _TripCard(
                                trip: trip,
                                onTap: () => showAdminSheet<void>(
                                  context,
                                  builder: (_) => _TripSheet(
                                    client: widget.client,
                                    session: widget.session,
                                    tripId: trip.id,
                                    onChanged: () => setState(() => _version++),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

Map<String, List<AdminTrip>> _byDay(List<AdminTrip> trips) {
  final grouped = <String, List<AdminTrip>>{};
  for (final trip in trips) {
    grouped.putIfAbsent(adminDay(trip.departureAt), () => []).add(trip);
  }
  return grouped;
}

/// One trip: route, departure, driver, status and an occupancy bar.
class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onTap});
  final AdminTrip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final capacity = trip.seatsAvailable + trip.seatsBooked;
    final full = capacity > 0 && trip.seatsAvailable == 0;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: YenkoShowcaseCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.from} → ${trip.to}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (full)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: AdminPill('Full', color: YenkoColors.red),
                  ),
                AdminPill(
                  adminTitleCase(trip.status),
                  color: adminAccent(trip.status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${adminTime(trip.departureAt)} · ${trip.driverName}',
              style: const TextStyle(fontSize: 12, color: YenkoColors.gray),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: capacity == 0 ? 0 : trip.seatsBooked / capacity,
                backgroundColor: const Color(0xFFEDEDE8),
                color: full ? YenkoColors.red : const Color(0xFFF9B900),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _Fact(
                  Icons.event_seat_outlined,
                  '${trip.seatsBooked}/$capacity seats booked',
                ),
                _Fact(
                  Icons.confirmation_number_outlined,
                  '${trip.bookingCount} ${trip.bookingCount == 1 ? 'booking' : 'bookings'}',
                ),
                _Fact(Icons.payments_outlined, 'GH₵ ${trip.pricePerSeat}'),
                if (trip.isWomenOnly)
                  const _Fact(Icons.female_rounded, 'Women only'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: YenkoColors.gray),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _TripSheet extends StatefulWidget {
  const _TripSheet({
    required this.client,
    required this.session,
    required this.tripId,
    required this.onChanged,
  });

  final AdminApiClient client;
  final LocalAuthSession session;
  final String tripId;
  final VoidCallback onChanged;

  @override
  State<_TripSheet> createState() => _TripSheetState();
}

class _TripSheetState extends State<_TripSheet> {
  int _version = 0;
  bool _busy = false;

  Future<void> _changeBooking(AdminBooking booking, String action) async {
    final cancel = action == 'cancel';
    if (cancel) {
      final ok = await confirmAdminAction(
        context,
        title: 'Cancel this booking?',
        message:
            "${booking.passengerName}'s ${booking.seats} ${booking.seats == 1 ? 'seat is' : 'seats are'} released and the rider and driver are notified.",
        confirmLabel: 'Cancel booking',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final done = await runAdminAction<bool>(context, () async {
      cancel
          ? await widget.client.cancelBooking(booking.id)
          : await widget.client.confirmBooking(booking.id);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (done == true) {
      widget.onChanged();
      setState(() => _version++);
      showAdminMessage(
        context,
        cancel ? 'Booking cancelled.' : 'Booking confirmed.',
      );
    }
  }

  Future<void> _cancel(AdminTrip trip) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Cancel this trip?',
      message:
          '${trip.from} → ${trip.to} will be cancelled along with its ${trip.bookingCount} ${trip.bookingCount == 1 ? 'open booking' : 'open bookings'}. '
          'The driver and every booked rider are notified. This cannot be undone.',
      confirmLabel: 'Cancel trip',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = await runAdminAction<AdminTrip>(
      context,
      () => widget.client.cancelTrip(trip.id),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (done != null) {
      widget.onChanged();
      setState(() => _version++);
      showAdminMessage(context, 'Trip cancelled.');
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: AdminLoader<AdminTrip>(
        reloadKey: _version,
        load: () => widget.client.getTrip(widget.tripId),
        builder: (context, trip, _) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.from} → ${trip.to}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                AdminPill(
                  adminTitleCase(trip.status),
                  color: adminAccent(trip.status),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Line(Icons.schedule_rounded, adminWhen(trip.departureAt)),
            _Line(Icons.person_outline_rounded, 'Driver: ${trip.driverName}'),
            _Line(Icons.place_outlined, 'Pickup: ${trip.pickupJunction}'),
            _Line(
              Icons.payments_outlined,
              'GH₵ ${trip.pricePerSeat} per seat · ${trip.seatsAvailable} seats free',
            ),
            if (trip.isWomenOnly)
              const _Line(Icons.female_rounded, 'Women-only trip'),
            if (widget.session.can('reservations:read')) ...[
              AdminSectionTitle('Bookings (${trip.bookings.length})'),
              if (trip.bookings.isEmpty)
                const Text(
                  'No bookings.',
                  style: TextStyle(color: YenkoColors.gray),
                )
              else
                for (final booking in trip.bookings)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.confirmation_number_outlined),
                    title: Text(
                      booking.passengerName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${booking.seats} ${booking.seats == 1 ? 'seat' : 'seats'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AdminPill(
                          adminTitleCase(booking.status),
                          color: adminAccent(booking.status),
                        ),
                        if (widget.session.can('reservations:manage') &&
                            trip.isOpen &&
                            booking.canChange)
                          PopupMenuButton<String>(
                            tooltip: 'Booking actions',
                            enabled: !_busy,
                            onSelected: (action) =>
                                _changeBooking(booking, action),
                            itemBuilder: (_) => [
                              if (booking.status == 'requested')
                                const PopupMenuItem(
                                  value: 'confirm',
                                  child: Text('Confirm'),
                                ),
                              const PopupMenuItem(
                                value: 'cancel',
                                child: Text(
                                  'Cancel booking',
                                  style: TextStyle(
                                    color: YenkoColors.red,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
            ],
            if (trip.isOpen && widget.session.can('trips:cancel')) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: YenkoColors.red,
                ),
                onPressed: _busy ? null : () => _cancel(trip),
                icon: const Icon(Icons.cancel_outlined),
                label: Text(_busy ? 'Cancelling…' : 'Cancel trip'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: YenkoColors.gray),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
