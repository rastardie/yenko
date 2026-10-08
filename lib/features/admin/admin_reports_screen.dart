import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_bookings_tab.dart';
import 'admin_section_page.dart';
import 'admin_widgets.dart';

/// CSV field escaping. Also neutralizes spreadsheet formula injection: a value
/// starting with = + - @ is prefixed with an apostrophe so Excel/Sheets treat
/// it as text (names and routes are user-supplied).
String csvField(String value) {
  var text = value;
  if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) text = "'$text";
  return text.contains(RegExp('[",\n\r]'))
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

String _two(int value) => value.toString().padLeft(2, '0');

/// The itemized booking report as CSV, in the column order staff expect.
String bookingsToCsv(List<AdminBookingRow> rows) {
  const header = [
    'No.',
    'Rider',
    'Username',
    'Driver',
    'Date',
    'Time',
    'From',
    'To',
    'Pickup',
    'Seats',
    'Fare (GHS)',
    'Status',
    'Women only',
    'Booked at',
    'Booking ref',
  ];
  final lines = <String>[header.map(csvField).join(',')];
  for (final (index, row) in rows.indexed) {
    final day = row.departureAt;
    final booked = row.createdAt;
    lines.add(
      [
        '${index + 1}',
        row.passengerName,
        row.passengerUsername ?? '',
        row.driverName,
        '${day.year}-${_two(day.month)}-${_two(day.day)}',
        '${_two(day.hour)}:${_two(day.minute)}',
        row.from,
        row.to,
        row.pickupJunction,
        '${row.seats}',
        '${row.fare}',
        adminBookingLabel(row.status),
        row.isWomenOnly ? 'Yes' : 'No',
        '${booked.year}-${_two(booked.month)}-${_two(booked.day)} ${_two(booked.hour)}:${_two(booked.minute)}',
        row.id,
      ].map(csvField).join(','),
    );
  }
  return lines.join('\r\n');
}

enum _GroupBy { rider, driver }

/// Reports > Bookings: an itemized booking report with filters, totals,
/// per-rider or per-driver grouping and CSV export, after Onboard's booking
/// report. Fares are what riders owe for booked seats; payments are not
/// collected in the app yet.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key, required this.client});
  final AdminApiClient client;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  String? _status;
  DateTimeRange? _range;
  _GroupBy _groupBy = _GroupBy.rider;
  int _version = 0;
  List<AdminBookingRow> _loaded = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      helpText: 'Trips departing between',
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  Future<void> _exportCsv() async {
    if (_loaded.isEmpty) {
      showAdminMessage(context, 'Nothing to export for these filters.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: bookingsToCsv(_loaded)));
    if (mounted) {
      showAdminMessage(
        context,
        'Copied ${_loaded.length} rows as CSV. Paste into Excel or Sheets.',
      );
    }
  }

  String _rangeLabel() {
    final range = _range;
    if (range == null) return 'All dates';
    String day(DateTime value) =>
        '${value.day} ${adminDay(value).split(' ').last}';
    return range.start == range.end
        ? day(range.start)
        : '${day(range.start)} – ${day(range.end)}';
  }

  @override
  Widget build(BuildContext context) => AdminFullPage(
    title: 'Booking reports',
    subtitle: 'Itemized bookings, totals and export',
    actions: [
      IconButton(
        tooltip: 'Refresh',
        onPressed: () => setState(() => _version++),
        icon: const Icon(Icons.refresh_rounded),
      ),
      PopupMenuButton<String>(
        tooltip: 'Export',
        icon: const Icon(Icons.file_download_outlined),
        onSelected: (_) => _exportCsv(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'csv', child: Text('Copy as CSV')),
        ],
      ),
    ],
    child: AdminLoader<AdminBookingPage>(
      reloadKey: '$_search|$_status|${_range?.start}|${_range?.end}|$_version',
      load: () async {
        final page = await widget.client.bookingReport(
          status: _status,
          search: _search,
          from: _range?.start,
          to: _range?.end,
        );
        _loaded = page.items;
        return page;
      },
      builder: (context, page, reload) {
        final groups = <String, List<AdminBookingRow>>{};
        for (final row in page.items) {
          final key = _groupBy == _GroupBy.rider
              ? row.passengerName
              : row.driverName;
          groups.putIfAbsent(key, () => []).add(row);
        }
        final ordered = groups.entries.toList()
          ..sort((a, b) => b.value.length.compareTo(a.value.length));
        return RefreshIndicator(
          color: const Color(0xFFF9B900),
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (value) =>
                          setState(() => _search = value.trim()),
                      decoration: const InputDecoration(
                        hintText: 'Search rider, driver or route…',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(_rangeLabel()),
                  ),
                  if (_range != null)
                    IconButton(
                      tooltip: 'Clear dates',
                      onPressed: () => setState(() => _range = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ],
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
              Row(
                children: [
                  const Text(
                    'Group by',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  const SizedBox(width: 10),
                  SegmentedButton<_GroupBy>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: const Color(0xFFF9B900),
                      selectedForegroundColor: YenkoColors.charcoal,
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: _GroupBy.rider,
                        label: Text('Rider'),
                      ),
                      ButtonSegment(
                        value: _GroupBy.driver,
                        label: Text('Driver'),
                      ),
                    ],
                    selected: {_groupBy},
                    onSelectionChanged: (selected) =>
                        setState(() => _groupBy = selected.first),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (ordered.isEmpty)
                const YenkoWatermarkEmptyState(
                  icon: Icons.assignment_outlined,
                  title: 'No bookings match',
                  message: 'Change the dates or filters to see more.',
                )
              else
                for (final (index, entry) in ordered.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: YenkoShowcaseCard(
                      padding: EdgeInsets.zero,
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            14,
                            0,
                            14,
                            10,
                          ),
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: const Color(0xFFFFE8A3),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                color: YenkoColors.charcoal,
                              ),
                            ),
                          ),
                          title: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${entry.value.length} ${entry.value.length == 1 ? 'booking' : 'bookings'} · '
                            'GH₵ ${entry.value.where((row) => row.status != 'cancelled').fold<int>(0, (sum, row) => sum + row.fare)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          children: [
                            for (final row in entry.value)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${row.from} → ${row.to}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            '${adminWhen(row.departureAt)} · ${_groupBy == _GroupBy.rider ? 'with ${row.driverName}' : row.passengerName}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: YenkoColors.gray,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        AdminPill(
                                          adminBookingLabel(row.status),
                                          color: adminAccent(row.status),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${row.seats} × · GH₵ ${row.fare}',
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
                          ],
                        ),
                      ),
                    ),
                  ),
              if (page.total > page.items.length)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Center(
                    child: Text(
                      'Showing the first ${page.items.length} of ${page.total} bookings. Narrow the dates to see the rest.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: YenkoColors.gray,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
