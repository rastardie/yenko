import 'package:flutter/material.dart';

import '../../core/data/trip_repository.dart';
import '../../core/models/trip.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/sign_out.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import '../../shared/widgets/yenko_widgets.dart';
import '../live_map/driver_tracking_screen.dart';
import 'passenger_home_screen.dart' show firstNameOf;

/// The driver-facing home/dashboard screen. Shown instead of
/// [PassengerHomeScreen] when the signed-in account's primary role is
/// `driver`. Surfaces the driver's own posted trips (`driverTripSummaries`),
/// pending seat requests to accept/decline (`pendingDriverReservations`),
/// and confirmed bookings awaiting direct mobile money payment
/// (`confirmedDriverReservations`). See HANDOVER.md, 2026-10-08 session.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({
    super.key,
    required this.repository,
    required this.onOfferRide,
    this.displayName,
  });

  final TripRepository repository;

  /// Switches the bottom-nav selection to the "Offer a ride" tab.
  final VoidCallback onOfferRide;

  /// The signed-in driver's full display name, used to greet them by first
  /// name. Null in mock mode, where there is no session.
  final String? displayName;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  // Presentational only — there is no backend "driver availability" field
  // yet, so this toggle does not persist anywhere. See class doc comment.
  bool _online = true;

  Future<void> _respond(
    BuildContext context, {
    required Future<void> action,
    required String successMessage,
  }) async {
    try {
      await action;
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      final summaries = widget.repository.driverTripSummaries;
      final pending = widget.repository.pendingDriverReservations;
      final awaitingPayment = widget.repository.confirmedDriverReservations
          .where((booking) => booking.paymentStatus != 'driver_confirmed_received')
          .toList();
      final confirmedTripIds = widget.repository.confirmedDriverReservations
          .map((booking) => booking.trip.id)
          .toSet();
      final activeSummaries = summaries
          .where(
            (summary) =>
                summary.trip.status == TripStatus.open ||
                summary.trip.status == TripStatus.confirmed ||
                summary.trip.status == TripStatus.inProgress,
          )
          .toList();
      final completedTrips = summaries
          .where((summary) => summary.trip.status == TripStatus.completed)
          .length;
      final todaysFare = activeSummaries.fold<int>(
        0,
        (total, summary) => total + summary.expectedFare,
      );

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
                'Ready to pick up riders today?',
                style: TextStyle(fontSize: 14, color: YenkoColors.charcoal),
              ),
              const SizedBox(height: 16),
              _OnlineToggleCard(
                online: _online,
                onChanged: (value) => setState(() => _online = value),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.event_seat_rounded,
                      label: 'Active trips',
                      value: '${activeSummaries.length}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.payments_outlined,
                      label: 'Expected fare',
                      value: 'GH₵ $todaysFare',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Completed',
                      value: '$completedTrips',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              YenkoShowcaseButton(
                label: 'Offer a new ride',
                icon: Icons.add_road_rounded,
                onPressed: widget.onOfferRide,
              ),
              const SizedBox(height: 22),
              if (pending.isNotEmpty) ...[
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Seat requests',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE8A3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${pending.length} pending',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: YenkoColors.charcoal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final booking in pending) ...[
                  _SeatRequestCard(
                    booking: booking,
                    onAccept: () => _respond(
                      context,
                      action: widget.repository.confirmReservation(booking),
                      successMessage: 'Seat request accepted.',
                    ),
                    onDecline: () => _respond(
                      context,
                      action: widget.repository.declineReservation(booking),
                      successMessage: 'Seat request declined.',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 10),
              ],
              if (awaitingPayment.isNotEmpty) ...[
                const Text(
                  'Payments to confirm',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 10),
                for (final booking in awaitingPayment) ...[
                  _PaymentToConfirmCard(
                    booking: booking,
                    onMarkReceived: () => _respond(
                      context,
                      action: widget.repository.markPaymentReceived(booking),
                      successMessage: 'Payment confirmed as received.',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 10),
              ],
              const Text(
                'Your posted rides',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 10),
              if (activeSummaries.isEmpty)
                const YenkoWatermarkEmptyState(
                  icon: Icons.directions_car_outlined,
                  title: 'No rides posted yet',
                  message: 'Offer a ride to start taking passenger requests.',
                ),
              for (final summary in activeSummaries) ...[
                _DriverTripCard(
                  summary: summary,
                  repository: widget.repository,
                  canShareLocation: confirmedTripIds.contains(summary.trip.id),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _OnlineToggleCard extends StatelessWidget {
  const _OnlineToggleCard({required this.online, required this.onChanged});
  final bool online;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: online ? const Color(0xFFDDF8EA) : const Color(0xFFF1F1F1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.power_settings_new_rounded,
            color: online ? YenkoColors.green : YenkoColors.gray,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                online ? "You're online" : "You're offline",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
              Text(
                online
                    ? 'Riders can see rides you post.'
                    : 'Go online to start offering rides.',
                style: const TextStyle(fontSize: 12, color: YenkoColors.gray),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: online,
          activeThumbColor: YenkoColors.green,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
    child: Column(
      children: [
        Icon(icon, size: 20, color: YenkoColors.charcoal),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: YenkoColors.gray),
        ),
      ],
    ),
  );
}

class _DriverTripCard extends StatelessWidget {
  const _DriverTripCard({
    required this.summary,
    required this.repository,
    required this.canShareLocation,
  });
  final DriverTripSummary summary;
  final TripRepository repository;

  /// True once at least one booking on this trip is confirmed — there is
  /// nobody to share a position with before that. See migration 013.
  final bool canShareLocation;

  @override
  Widget build(BuildContext context) {
    final trip = summary.trip;
    return YenkoShowcaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${trip.from}  →  ${trip.to}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
              Text(
                'GH₵ ${trip.pricePerSeat}/seat',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${trip.departureLabel} · Meet at ${trip.pickupJunction}',
            style: const TextStyle(fontSize: 11, color: YenkoColors.gray),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDF8EA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${summary.seatsBooked} booked · ${trip.seatsAvailable} open',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF14744A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${summary.bookingCount} request${summary.bookingCount == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 11, color: YenkoColors.gray),
              ),
              const Spacer(),
              Text(
                'Expected GH₵ ${summary.expectedFare}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
              ),
            ],
          ),
          if (canShareLocation) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DriverTrackingScreen(
                      repository: repository,
                      trip: trip,
                    ),
                  ),
                ),
                icon: const Icon(Icons.my_location_rounded, size: 16),
                label: const Text('Share live location'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeatRequestCard extends StatelessWidget {
  const _SeatRequestCard({
    required this.booking,
    required this.onAccept,
    required this.onDecline,
  });

  final Booking booking;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final trip = booking.trip;
    return YenkoShowcaseCard(
      color: const Color(0xFFFFF5D8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${trip.from}  →  ${trip.to}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
              Text(
                '${booking.seats} seat · GH₵ ${booking.totalPrice}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${trip.departureLabel} · Meet at ${trip.pickupJunction}',
            style: const TextStyle(fontSize: 11, color: YenkoColors.gray),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDecline,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: const Text('Decline'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: YenkoColors.red,
                    side: const BorderSide(color: YenkoColors.red),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: const Text('Accept'),
                  style: FilledButton.styleFrom(
                    backgroundColor: YenkoColors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A confirmed booking awaiting the driver's "payment received"
/// confirmation. The passenger pays this driver's mobile money number
/// directly, outside the app — this card only lets the driver self-report
/// the outcome; nothing here verifies a real transaction. See
/// [TripRepository.markPaymentReceived] and HANDOVER.md.
class _PaymentToConfirmCard extends StatelessWidget {
  const _PaymentToConfirmCard({
    required this.booking,
    required this.onMarkReceived,
  });
  final Booking booking;
  final VoidCallback onMarkReceived;

  @override
  Widget build(BuildContext context) {
    final trip = booking.trip;
    final passengerMarkedPaid = booking.paymentStatus == 'passenger_marked_paid';
    return YenkoShowcaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${trip.from}  →  ${trip.to}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
              Text(
                '${booking.seats} seat · GH₵ ${booking.totalPrice}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: passengerMarkedPaid
                  ? const Color(0xFFDDF8EA)
                  : const Color(0xFFFFF5D8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              passengerMarkedPaid
                  ? 'Passenger says they paid'
                  : 'Waiting for passenger to pay',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: passengerMarkedPaid
                    ? const Color(0xFF14744A)
                    : YenkoColors.charcoal,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onMarkReceived,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
              label: const Text("I've received this payment"),
              style: FilledButton.styleFrom(
                backgroundColor: YenkoColors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
