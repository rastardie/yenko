import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/sign_out.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_audit_screen.dart';
import 'admin_bookings_tab.dart';
import 'admin_groups_tab.dart';
import 'admin_metrics_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_section_page.dart';
import 'admin_trips_tab.dart';
import 'admin_user_forms.dart';
import 'admin_users_tab.dart';
import 'admin_widgets.dart';
import '../../shared/widgets/yenko_widgets.dart';

const _stripColor = YenkoColors.charcoal;
const _gold = Color(0xFFF9B900);

/// The Admin bottom-navigation destination, laid out like Onboard's embedded
/// admin screen:
///
///  * a dark strip with the primary section pills (People / Operations) and,
///    beneath them, action pills (Dashboard / Reports / Audit);
///  * a white panel with a row of summary tiles and the pending-approval alert;
///  * inside each section, a row of small sub-tab pills
///    (People: Users | Groups, Operations: Trips | Bookings).
///
/// Only sections and pills the account's permissions allow are shown; the
/// server enforces the same permissions on every call.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.client, required this.session});

  final AdminApiClient client;
  final LocalAuthSession session;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _Section {
  _Section({
    required this.label,
    required this.icon,
    required this.tabs,
    required TickerProvider vsync,
  }) : controller = TabController(length: tabs.length, vsync: vsync);

  final String label;
  final IconData icon;
  final List<AdminSubTab> tabs;
  final TabController controller;
}

class _AdminScreenState extends State<AdminScreen>
    with TickerProviderStateMixin {
  late final List<_Section> _sections;
  late final TabController _primary;
  int _generation = 0;
  int _summaryVersion = 0;

  LocalAuthSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    final people = <AdminSubTab>[
      if (_session.can('users:read'))
        AdminSubTab(
          label: 'Users',
          icon: Icons.person_outline_rounded,
          builder: (_) =>
              AdminUsersTab(client: widget.client, session: _session),
        ),
      if (_session.can('groups:read'))
        AdminSubTab(
          label: 'Groups',
          icon: Icons.groups_2_outlined,
          builder: (_) =>
              AdminGroupsTab(client: widget.client, session: _session),
        ),
    ];
    final operations = <AdminSubTab>[
      if (_session.can('trips:read'))
        AdminSubTab(
          label: 'Trips',
          icon: Icons.route_outlined,
          builder: (_) =>
              AdminTripsTab(client: widget.client, session: _session),
        ),
      if (_session.can('reservations:read'))
        AdminSubTab(
          label: 'Bookings',
          icon: Icons.confirmation_number_outlined,
          builder: (_) =>
              AdminBookingsTab(client: widget.client, session: _session),
        ),
    ];
    _sections = [
      if (people.isNotEmpty)
        _Section(
          label: 'People',
          icon: Icons.people_outline,
          tabs: people,
          vsync: this,
        ),
      if (operations.isNotEmpty)
        _Section(
          label: 'Operations',
          icon: Icons.event_note_outlined,
          tabs: operations,
          vsync: this,
        ),
    ];
    _primary = TabController(length: _sections.length, vsync: this);
  }

  @override
  void dispose() {
    _primary.dispose();
    for (final section in _sections) {
      section.controller.dispose();
    }
    super.dispose();
  }

  /// Switches to [section] and, when given, the sub-tab called [tab].
  void _open(String section, [String? tab]) {
    final index = _sections.indexWhere((item) => item.label == section);
    if (index < 0) return;
    _primary.animateTo(index);
    final sub = _sections[index];
    final subIndex = sub.tabs.indexWhere((item) => item.label == tab);
    if (subIndex >= 0) sub.controller.animateTo(subIndex);
  }

  void _refresh() => setState(() {
    _generation++;
    _summaryVersion++;
  });

  Future<void> _push(Widget page) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() => _summaryVersion++);
  }

  Future<void> _reviewPending() async {
    await showAdminSheet<void>(
      context,
      builder: (_) => PendingApprovalsSheet(client: widget.client),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canDashboard = _session.can('dashboard:read');
    final canReports = _session.can('reports:read');
    final canAudit = _session.can('audit:read');
    final hasAccess =
        _sections.isNotEmpty || canDashboard || canReports || canAudit;
    return YenkoShowcaseBackdrop(
      useWatermark: true,
      child: SafeArea(
        bottom: false,
        child: !hasAccess
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: YenkoWatermarkEmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'No admin access',
                    message: 'Your groups do not grant any admin permissions.',
                  ),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 6, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: YenkoLogo(height: 30),
                              ),
                              const Text(
                                'Admin dashboard',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _session.displayName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: YenkoColors.gray,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  AdminPill(
                                    adminTitleCase(_session.role),
                                    color: adminAccent(_session.role),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const YenkoSignOutButton(),
                        PopupMenuButton<String>(
                          tooltip: 'More',
                          onSelected: (value) {
                            switch (value) {
                              case 'refresh':
                                _refresh();
                              case 'audit':
                                _push(AdminAuditScreen(client: widget.client));
                              case 'signout':
                                confirmSignOut(context);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'refresh',
                              child: ListTile(
                                leading: Icon(Icons.refresh_rounded),
                                title: Text('Refresh'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            if (canAudit)
                              const PopupMenuItem(
                                value: 'audit',
                                child: ListTile(
                                  leading: Icon(Icons.fact_check_outlined),
                                  title: Text('Audit log'),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'signout',
                              child: ListTile(
                                leading: Icon(Icons.power_settings_new_rounded),
                                title: Text('Sign out'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Dark strip: primary section pills, then the action pills.
                  Container(
                    color: _stripColor,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_sections.isNotEmpty)
                          _PrimaryTabBar(
                            controller: _primary,
                            sections: _sections,
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canDashboard)
                                  _ActionPill(
                                    icon: Icons.dashboard_outlined,
                                    label: 'Dashboard',
                                    onTap: () => _push(
                                      AdminMetricsScreen(client: widget.client),
                                    ),
                                  ),
                                if (canReports)
                                  _ActionPill(
                                    icon: Icons.receipt_long_outlined,
                                    label: 'Reports',
                                    onTap: () => _push(
                                      AdminReportsScreen(client: widget.client),
                                    ),
                                  ),
                                if (canAudit)
                                  _ActionPill(
                                    icon: Icons.fact_check_outlined,
                                    label: 'Audit',
                                    onTap: () => _push(
                                      AdminAuditScreen(client: widget.client),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: const BoxDecoration(
                        color: Color(0xF5FFFFFF),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Material(
                        color: Colors.transparent,
                        child: Column(
                          children: [
                            _SummaryBand(
                              client: widget.client,
                              session: _session,
                              version: _summaryVersion,
                              onOpen: _open,
                              onReview: _reviewPending,
                            ),
                            Expanded(
                              child: _sections.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text(
                                          'Use Dashboard, Reports or Audit above.',
                                          style: TextStyle(
                                            color: YenkoColors.gray,
                                          ),
                                        ),
                                      ),
                                    )
                                  : TabBarView(
                                      controller: _primary,
                                      children: [
                                        for (final section in _sections)
                                          KeyedSubtree(
                                            key: ValueKey(
                                              '${section.label}-$_generation',
                                            ),
                                            child: _SubTabbedSection(
                                              section: section,
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Primary section pills on the dark strip (Onboard's AdminTabBar).
class _PrimaryTabBar extends StatelessWidget {
  const _PrimaryTabBar({required this.controller, required this.sections});

  final TabController controller;
  final List<_Section> sections;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.animation!,
    builder: (context, _) => SizedBox(
      height: 42,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
        child: Row(
          children: [
            for (var i = 0; i < sections.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => controller.animateTo(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      height: 32,
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: controller.index == i ? 0.30 : 0.24,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: controller.index == i ? 0.82 : 0.58,
                          ),
                          width: controller.index == i ? 1.5 : 1.25,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(sections[i].icon, size: 15, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            sections[i].label,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: controller.index == i
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Small navigation action on the dark strip (Onboard's AdminActionPill).
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: SizedBox(
      width: 98,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.46),
                width: 1.25,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Summary tiles plus the pending-approval alert at the top of the white panel.
class _SummaryBand extends StatelessWidget {
  const _SummaryBand({
    required this.client,
    required this.session,
    required this.version,
    required this.onOpen,
    required this.onReview,
  });

  final AdminApiClient client;
  final LocalAuthSession session;
  final int version;
  final void Function(String section, [String? tab]) onOpen;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    if (!session.can('users:read') &&
        !session.can('trips:read') &&
        !session.can('reservations:read') &&
        !session.can('groups:read')) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<AdminSummary>(
      key: ValueKey(version),
      future: client.summary(),
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary == null) {
          return SizedBox(
            height: 6,
            child: snapshot.connectionState == ConnectionState.waiting
                ? const LinearProgressIndicator(color: _gold, minHeight: 2)
                : null,
          );
        }
        final tiles = <_Tile>[
          if (summary.usersActive != null && session.can('users:read'))
            _Tile(
              Icons.people_outlined,
              '${summary.usersActive}',
              'Members',
              () => onOpen('People', 'Users'),
            ),
          if (summary.tripsOpen != null && session.can('trips:read'))
            _Tile(
              Icons.route_outlined,
              '${summary.tripsOpen}',
              'Open trips',
              () => onOpen('Operations', 'Trips'),
            ),
          if (summary.bookingsRequested != null &&
              session.can('reservations:read'))
            _Tile(
              Icons.hourglass_bottom_rounded,
              '${summary.bookingsRequested}',
              'To confirm',
              () => onOpen('Operations', 'Bookings'),
            ),
          if (summary.groups != null && session.can('groups:read'))
            _Tile(
              Icons.groups_2_outlined,
              '${summary.groups}',
              'Groups',
              () => onOpen('People', 'Groups'),
            ),
        ];
        final pending = session.can('users:approve')
            ? (summary.usersPending ?? 0)
            : 0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Column(
            children: [
              if (tiles.isNotEmpty)
                Row(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                ),
              if (pending > 0) ...[
                const SizedBox(height: 6),
                _PendingAlert(count: pending, onTap: onReview),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.value, this.label, this.onTap);

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF8FAFC),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE7EBF0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFFE07B00)),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: YenkoColors.charcoal,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                color: YenkoColors.gray,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PendingAlert extends StatelessWidget {
  const _PendingAlert({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE07B00).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFE07B00).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.notifications_active_rounded,
              color: Color(0xFFE07B00),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count account${count == 1 ? '' : 's'} awaiting approval',
                style: const TextStyle(
                  color: YenkoColors.charcoal,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Text(
              'Review',
              style: TextStyle(
                color: Color(0xFFE07B00),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFE07B00),
              size: 18,
            ),
          ],
        ),
      ),
    ),
  );
}

/// One primary section: a row of sub-tab pills over a swipeable body.
class _SubTabbedSection extends StatelessWidget {
  const _SubTabbedSection({required this.section});

  final _Section section;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            for (var i = 0; i < section.tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _SubTabPill(
                controller: section.controller,
                index: i,
                label: section.tabs[i].label,
              ),
            ],
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: section.controller,
          children: [
            for (final tab in section.tabs) Builder(builder: tab.builder),
          ],
        ),
      ),
    ],
  );
}

/// Onboard's AdminSubTabPill in YɛnKɔ colours.
class _SubTabPill extends StatelessWidget {
  const _SubTabPill({
    required this.controller,
    required this.index,
    required this.label,
  });

  final TabController controller;
  final int index;
  final String label;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => controller.animateTo(index),
    child: AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final selected = controller.index == index;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? YenkoColors.charcoal : const Color(0xFFFFF1CC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? YenkoColors.charcoal : const Color(0xFFE2C15A),
              width: selected ? 1 : 1.25,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : YenkoColors.charcoal,
            ),
          ),
        );
      },
    ),
  );
}
