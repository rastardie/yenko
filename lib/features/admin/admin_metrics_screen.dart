import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_section_page.dart';
import 'admin_widgets.dart';

Color _utilizationColor(int pct) => pct >= 70
    ? YenkoColors.green
    : pct >= 40
    ? const Color(0xFFE07B00)
    : YenkoColors.red;

/// Dashboard: period metrics after Onboard's admin dashboard (today / week /
/// month / custom range). Ridership is counted in seats; "fare value" is what
/// booked seats are worth, because payments are not collected in the app yet.
class AdminMetricsScreen extends StatefulWidget {
  const AdminMetricsScreen({super.key, required this.client});
  final AdminApiClient client;

  @override
  State<AdminMetricsScreen> createState() => _AdminMetricsScreenState();
}

class _AdminMetricsScreenState extends State<AdminMetricsScreen> {
  String _period = 'week';
  DateTimeRange? _range;
  int _version = 0;

  Future<void> _selectPeriod(String? period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: _range,
        helpText: 'Trips departing between',
      );
      if (picked == null || !mounted) return;
      setState(() {
        _period = 'custom';
        _range = picked;
      });
      return;
    }
    setState(() => _period = period ?? 'week');
  }

  @override
  Widget build(BuildContext context) => AdminFullPage(
    title: 'Dashboard',
    subtitle: 'Trips, ridership and performance',
    actions: [
      IconButton(
        tooltip: 'Refresh',
        onPressed: () => setState(() => _version++),
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    child: AdminLoader<AdminMetrics>(
      reloadKey: '$_period|${_range?.start}|${_range?.end}|$_version',
      load: () => widget.client.metrics(
        period: _period,
        from: _range?.start,
        to: _range?.end,
      ),
      builder: (context, data, reload) {
        final trips = data.trips;
        final bookings = data.bookings;
        final users = data.users;
        final end = data.to.subtract(const Duration(days: 1));
        return RefreshIndicator(
          color: const Color(0xFFF9B900),
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            children: [
              AdminFilterBar(
                options: const {
                  'today': 'Today',
                  'week': 'This week',
                  'month': 'This month',
                  'custom': 'Custom',
                },
                selected: _period,
                onSelected: _selectPeriod,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 10),
                child: Text(
                  data.from.day == end.day && data.from.month == end.month
                      ? adminDay(data.from)
                      : '${adminDay(data.from)} – ${adminDay(end)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: YenkoColors.gray,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _Summary(
                      'Trips',
                      '${trips['total'] ?? 0}',
                      Icons.route_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Summary(
                      'Active people',
                      '${users['active'] ?? 0}',
                      Icons.people_alt_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Summary(
                      'Utilization',
                      '${trips['utilizationPct'] ?? 0}%',
                      Icons.speed_rounded,
                      color: _utilizationColor(trips['utilizationPct'] ?? 0),
                    ),
                  ),
                ],
              ),
              const AdminSectionTitle('Ridership'),
              _Card(
                children: [
                  _Line('Seats booked', '${trips['reserved'] ?? 0}'),
                  _Line('Seat capacity', '${trips['capacity'] ?? 0}'),
                  _Line(
                    'Cancelled seats',
                    '${bookings['cancelledSeats'] ?? 0}',
                    color: const Color(0xFFE07B00),
                  ),
                  _Line(
                    'Cancelled trips',
                    '${trips['cancelled'] ?? 0}',
                    color: YenkoColors.red,
                  ),
                  _Line(
                    'Open trips',
                    '${trips['open'] ?? 0}',
                    color: YenkoColors.green,
                  ),
                ],
              ),
              const AdminSectionTitle('Bookings'),
              _Card(
                children: [
                  _Line(
                    'All bookings',
                    '${bookings['total'] ?? 0}',
                    bold: true,
                  ),
                  _Line(
                    'Pending',
                    '${bookings['requested'] ?? 0}',
                    color: const Color(0xFFE07B00),
                  ),
                  _Line(
                    'Confirmed',
                    '${bookings['confirmed'] ?? 0}',
                    color: YenkoColors.green,
                  ),
                  _Line(
                    'Cancelled',
                    '${bookings['cancelled'] ?? 0}',
                    color: YenkoColors.red,
                  ),
                  _Line('On women-only trips', '${bookings['womenOnly'] ?? 0}'),
                ],
              ),
              const AdminSectionTitle('Fare value'),
              _Card(
                children: [
                  _Line(
                    'Booked seats are worth',
                    'GH₵ ${trips['fareValue'] ?? 0}',
                    bold: true,
                    color: YenkoColors.green,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'This is the fixed fare for booked seats. Payments are not collected in the app yet, so there is no collected or outstanding amount.',
                      style: TextStyle(fontSize: 11, color: YenkoColors.gray),
                    ),
                  ),
                ],
              ),
              const AdminSectionTitle('People'),
              _Card(
                children: [
                  _Line('Drivers', '${users['drivers'] ?? 0}'),
                  _Line('Joined in this period', '${users['joined'] ?? 0}'),
                  _Line(
                    'Waiting for approval',
                    '${users['pending'] ?? 0}',
                    color: const Color(0xFFE07B00),
                  ),
                  _Line(
                    'Suspended',
                    '${users['suspended'] ?? 0}',
                    color: YenkoColors.red,
                  ),
                ],
              ),
              const AdminSectionTitle('Driver performance'),
              if (data.drivers.isEmpty)
                const YenkoShowcaseCard(
                  child: Text(
                    'No trips in this period.',
                    style: TextStyle(color: YenkoColors.gray),
                  ),
                )
              else
                _Card(
                  children: [
                    for (final driver in data.drivers)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    driver.displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${driver.utilizationPct}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: _utilizationColor(
                                      driver.utilizationPct,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                value: driver.utilizationPct / 100,
                                backgroundColor: const Color(0xFFEDEDE8),
                                color: _utilizationColor(driver.utilizationPct),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${driver.trips} ${driver.trips == 1 ? 'trip' : 'trips'} · ${driver.reserved} of ${driver.capacity} seats booked'
                              '${driver.cancelledTrips > 0 ? ' · ${driver.cancelledTrips} cancelled' : ''}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: YenkoColors.gray,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              const AdminSectionTitle('Daily ridership'),
              _DailyChart(days: data.daily),
            ],
          ),
        );
      },
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary(
    this.label,
    this.value,
    this.icon, {
    this.color = YenkoColors.charcoal,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: YenkoColors.gray,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(
    this.label,
    this.value, {
    this.color = YenkoColors.charcoal,
    this.bold = false,
  });
  final String label;
  final String value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w900, color: color),
        ),
      ],
    ),
  );
}

/// Seats booked per day, as simple bars (no charting dependency).
class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.days});
  final List<AdminDayStat> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const YenkoShowcaseCard(
        child: Text(
          'No trips in this period.',
          style: TextStyle(color: YenkoColors.gray),
        ),
      );
    }
    final peak = days
        .map((day) => day.reserved)
        .fold<int>(1, (a, b) => a > b ? a : b);
    return YenkoShowcaseCard(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final day in days)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${day.reserved}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 22,
                      height: 8 + 90 * (day.reserved / peak),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9B900),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      day.day.substring(8),
                      style: const TextStyle(
                        fontSize: 10,
                        color: YenkoColors.gray,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${day.trips}t',
                      style: const TextStyle(
                        fontSize: 9,
                        color: YenkoColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
