import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/data/local_auth_client.dart';
import '../../core/data/trip_repository.dart';
import '../../core/theme/app_theme.dart';
import '../admin/admin_screen.dart';
import '../admin/admin_widgets.dart' show adminTitleCase;
import '../bookings/trip_tracking_screen.dart';
import '../home/driver_home_screen.dart';
import '../home/passenger_home_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../trips/post_trip_screen.dart';

enum _TabId { admin, home, offer, rides, messages, profile }

class _TabSpec {
  const _TabSpec(this.id, this.label, this.icon, this.selectedIcon, this.page);
  final _TabId id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class YenkoRootScreen extends StatefulWidget {
  const YenkoRootScreen({
    super.key,
    required this.repository,
    this.session,
    this.adminClient,
  });

  final TripRepository repository;

  /// The signed-in local-API session. Null in mock mode, where every rider and
  /// driver tab is shown and there is no admin console.
  final LocalAuthSession? session;

  /// Present when the account holds at least one admin permission.
  final AdminApiClient? adminClient;

  @override
  State<YenkoRootScreen> createState() => _YenkoRootScreenState();
}

class _YenkoRootScreenState extends State<YenkoRootScreen> {
  var _index = 0;

  List<_TabSpec> _tabs() {
    final session = widget.session;
    final adminClient = widget.adminClient;
    // Like Onboard, admins keep the regular tabs and get Admin as the last
    // bottom-navigation destination.
    final admin = session != null && adminClient != null
        ? _TabSpec(
            _TabId.admin,
            'Admin',
            Icons.admin_panel_settings_outlined,
            Icons.admin_panel_settings_rounded,
            AdminScreen(client: adminClient, session: session),
          )
        : null;

    // Mock mode (no session) keeps the original full tab set — there is no
    // role to branch on. Signed-in local-API sessions get a role-specific
    // home + offer arrangement instead: drivers get a dashboard plus the
    // "Offer a ride" tab; passengers get ride search/discovery and no Offer
    // tab (posting a ride is a driver action, not a casual rider one). See
    // HANDOVER.md, 2026-10-08 session.
    final isDriver = session?.role == 'driver';

    final homeTab = isDriver
        ? _TabSpec(
            _TabId.home,
            'Home',
            Icons.home_outlined,
            Icons.home_rounded,
            DriverHomeScreen(
              repository: widget.repository,
              onOfferRide: () => _goTo(_TabId.offer),
              displayName: session?.displayName,
            ),
          )
        : _TabSpec(
            _TabId.home,
            'Home',
            Icons.home_outlined,
            Icons.home_rounded,
            PassengerHomeScreen(
              repository: widget.repository,
              onOpenBooking: () => _goTo(_TabId.rides),
              displayName: session?.displayName,
            ),
          );

    final offerTab = (session == null || isDriver)
        ? _TabSpec(
            _TabId.offer,
            'Offer',
            Icons.search_rounded,
            Icons.search_rounded,
            PostTripScreen(
              repository: widget.repository,
              onTripPosted: () => _goTo(_TabId.profile),
            ),
          )
        : null;

    return [
      homeTab,
      ?offerTab,
      _TabSpec(
        _TabId.rides,
        'Rides',
        Icons.directions_car_outlined,
        Icons.directions_car_filled_rounded,
        TripTrackingScreen(repository: widget.repository),
      ),
      _TabSpec(
        _TabId.messages,
        'Messages',
        Icons.chat_bubble_outline_rounded,
        Icons.chat_bubble_rounded,
        NotificationsScreen(repository: widget.repository),
      ),
      _TabSpec(
        _TabId.profile,
        'Profile',
        Icons.person_outline_rounded,
        Icons.person_rounded,
        ProfileScreen(
          repository: widget.repository,
          displayName: widget.session?.displayName,
          roleLabel: widget.session == null
              ? null
              : adminTitleCase(widget.session!.role),
        ),
      ),
      ?admin,
    ];
  }

  void _goTo(_TabId id) {
    final index = _tabs().indexWhere((tab) => tab.id == id);
    if (index >= 0) setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final selected = _index.clamp(0, tabs.length - 1);
    return Scaffold(
      body: IndexedStack(
        index: selected,
        children: [for (final tab in tabs) tab.page],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 70,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
          ),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                _NavItem(
                  index: i,
                  selectedIndex: selected,
                  icon: tabs[i].icon,
                  selectedIcon: tabs[i].selectedIcon,
                  label: tabs[i].label,
                  onTap: (index) => setState(() => _index = index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });
  final int index;
  final int selectedIndex;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final selected = index == selectedIndex;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              size: 22,
              color: selected ? const Color(0xFFF4B000) : YenkoColors.gray,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? const Color(0xFFF4B000) : YenkoColors.gray,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
