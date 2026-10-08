import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_widgets.dart';

/// Operations > Bookings: every seat booking with totals, searchable and
/// filterable by status. Staff with reservations:manage can confirm a pending
/// booking or cancel a live one (the seat returns to the trip and the rider
/// and driver are notified).
class AdminBookingsTab extends StatefulWidget {
  const AdminBookingsTab({
    super.key,
    required this.client,
    required this.session,
  });

  final AdminApiClient client;
  final LocalAuthSession session;

  @override
  State<AdminBookingsTab> createState() => _AdminBookingsTabState();
}

class _AdminBookingsTabState extends State<AdminBookingsTab>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  String _search = '';
  String? _status;
  int _version = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _change(AdminBookingRow booking, String action) async {
    final cancel = action == 'cancel';
    if (cancel) {
      final ok = await confirmAdminAction(
        context,
        title: 'Cancel this booking?',
        message:
            "${booking.passengerName}'s ${booking.seats} ${booking.seats == 1 ? 'seat' : 'seats'} on ${booking.from} → ${booking.to} "
            'will be released and both the rider and driver are notified.',
        confirmLabel: 'Cancel booking',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    final done = await runAdminAction<bool>(context, () async {
      cancel
          ? await widget.client.cancelBooking(booking.id)
          : await widget.client.confirmBooking(booking.id);
      return true;
    });
    if (!mounted || done != true) return;
    setState(() => _version++);
    showAdminMessage(
      context,
      cancel ? 'Booking cancelled.' : 'Booking confirmed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final canManage = widget.session.can('reservations:manage');
    return AdminLoader<AdminBookingPage>(
      reloadKey: '$_search|$_status|$_version',
      load: () => widget.client.listBookings(status: _status, search: _search),
      builder: (context, page, reload) => RefreshIndicator(
        color: const Color(0xFFF9B900),
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
          children: [
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => setState(() => _search = value.trim()),
              decoration: InputDecoration(
                hintText: 'Search rider, driver or route…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            AdminFilterBar(
              options: const {
                null: 'All',
                'requested': 'Pending',
                'confirmed': 'Confirmed',
                'cancelled': 'Cancelled',
              },
              selected: _status,
              onSelected: (value) => setState(() => _status = value),
            ),
            const SizedBox(height: 10),
            AdminTotalsStrip(totals: page.totals),
            const SizedBox(height: 10),
            if (page.items.isEmpty)
              const YenkoWatermarkEmptyState(
                icon: Icons.confirmation_number_outlined,
                title: 'No bookings',
                message: 'Seat requests from riders appear here.',
              )
            else
              for (final booking in page.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: YenkoShowcaseCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${booking.from} → ${booking.to}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${adminWhen(booking.departureAt)} · ${booking.passengerName} with ${booking.driverName}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: YenkoColors.gray,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  AdminPill(
                                    adminBookingLabel(booking.status),
                                    color: adminAccent(booking.status),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${booking.seats} ${booking.seats == 1 ? 'seat' : 'seats'} · GH₵ ${booking.fare}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (canManage &&
                            (booking.canConfirm || booking.canCancel))
                          PopupMenuButton<String>(
                            tooltip: 'Booking actions',
                            onSelected: (action) => _change(booking, action),
                            itemBuilder: (_) => [
                              if (booking.canConfirm)
                                const PopupMenuItem(
                                  value: 'confirm',
                                  child: Text('Confirm'),
                                ),
                              if (booking.canCancel)
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
                ),
            if (page.total > page.items.length)
              Center(
                child: Text(
                  'Showing ${page.items.length} of ${page.total}. Refine your search to see others.',
                  style: const TextStyle(fontSize: 12, color: YenkoColors.gray),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Booking status as staff call it ("requested" is shown as "Pending").
String adminBookingLabel(String status) =>
    status == 'requested' ? 'Pending' : adminTitleCase(status);

/// Compact totals shown above booking lists and reports.
class AdminTotalsStrip extends StatelessWidget {
  const AdminTotalsStrip({super.key, required this.totals});
  final Map<String, int> totals;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Bookings', '${totals['bookings'] ?? 0}', YenkoColors.charcoal),
      ('Pending', '${totals['requested'] ?? 0}', const Color(0xFFE07B00)),
      ('Confirmed', '${totals['confirmed'] ?? 0}', YenkoColors.green),
      ('Cancelled', '${totals['cancelled'] ?? 0}', YenkoColors.red),
      ('Seats', '${totals['seats'] ?? 0}', YenkoColors.charcoal),
      ('Fare', 'GH₵ ${totals['fare'] ?? 0}', YenkoColors.charcoal),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (label, value, color) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: YenkoShowcaseCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        color: YenkoColors.gray,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
