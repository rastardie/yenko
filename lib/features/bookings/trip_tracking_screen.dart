import 'package:flutter/material.dart';

import '../../core/data/trip_repository.dart';
import '../../core/models/trip.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';

class TripTrackingScreen extends StatelessWidget {
  const TripTrackingScreen({super.key, required this.repository});
  final TripRepository repository;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) {
      final bookings = repository.bookings;
      return YenkoShowcaseBackdrop(
        useWatermark: true,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            children: [
              YenkoScreenTitle(
                title: 'My rides',
                subtitle: bookings.isEmpty
                    ? 'Your booked seats will appear here.'
                    : '${bookings.length} ride${bookings.length == 1 ? '' : 's'} saved',
                action: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
              const SizedBox(height: 16),
              const _RideStatusTabs(),
              const SizedBox(height: 16),
              if (bookings.isEmpty)
                const YenkoWatermarkEmptyState(
                  icon: Icons.event_seat_outlined,
                  title: 'No rides booked yet',
                  message:
                      'Discover a ride, reserve a seat, and every detail will stay here for you.',
                ),
              for (final booking in bookings) ...[
                _BookingCard(booking: booking, repository: repository),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _RideStatusTabs extends StatelessWidget {
  const _RideStatusTabs();
  @override
  Widget build(BuildContext context) => Row(
    children: const [
      _StatusTab(label: 'Upcoming', selected: true),
      SizedBox(width: 8),
      _StatusTab(label: 'Completed'),
      SizedBox(width: 8),
      _StatusTab(label: 'Cancelled'),
    ],
  );
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({required this.label, this.selected = false});
  final String label;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFF9B900) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: selected
          ? const [BoxShadow(color: Color(0x12000000), blurRadius: 6)]
          : null,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: YenkoColors.charcoal,
      ),
    ),
  );
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.repository});
  final Booking booking;
  final TripRepository repository;

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: Text(
          'This will release ${booking.seats} seat${booking.seats == 1 ? '' : 's'} for other riders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep ride'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: YenkoColors.red),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await repository.cancelBooking(booking);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your seat request was cancelled.')),
      );
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = booking.trip;
    final requested = booking.status == 'requested';
    return YenkoShowcaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: requested
                      ? const Color(0xFFDDF8EA)
                      : const Color(0xFFF1F1F1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  requested ? Icons.check_rounded : Icons.cancel_outlined,
                  color: requested ? YenkoColors.green : YenkoColors.gray,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  requested ? 'Upcoming ride' : 'Cancelled',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                trip.departureLabel,
                style: const TextStyle(fontSize: 11, color: YenkoColors.gray),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Column(
                children: [
                  Icon(
                    Icons.radio_button_checked_rounded,
                    color: YenkoColors.green,
                    size: 17,
                  ),
                  SizedBox(height: 17),
                  SizedBox(
                    height: 22,
                    child: VerticalDivider(color: Color(0xFFBDE7D5)),
                  ),
                  Icon(
                    Icons.location_on_rounded,
                    color: YenkoColors.red,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.from,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Text(
                      trip.to,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 26),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFFFE8A3),
                child: Text(
                  trip.driverName.isEmpty
                      ? '?'
                      : trip.driverName.substring(0, 1),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: YenkoColors.charcoal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.driverName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '★ ${trip.driverRating} (${trip.driverTrips})',
                      style: const TextStyle(
                        fontSize: 11,
                        color: YenkoColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.phone_outlined, size: 20),
              ),
              if (requested)
                FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF9B900),
                    foregroundColor: YenkoColors.charcoal,
                    minimumSize: const Size(56, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text(
                    'View',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${booking.seats} seat · GH₵ ${booking.totalPrice}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                'Ref ${booking.id.substring(0, 8).toUpperCase()}',
                style: const TextStyle(fontSize: 10, color: YenkoColors.gray),
              ),
            ],
          ),
          if (requested) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _cancel(context),
                icon: const Icon(Icons.cancel_outlined, size: 17),
                label: const Text('Cancel ride'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: YenkoColors.red,
                  side: const BorderSide(color: YenkoColors.red),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
