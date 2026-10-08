import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_section_page.dart';
import 'admin_widgets.dart';

const _pageSize = 50;

const _actionLabels = <String, String>{
  'admin.user.created': 'Created an account',
  'admin.user.updated': 'Edited an account',
  'admin.user.suspended': 'Suspended an account',
  'admin.user.restored': 'Restored an account',
  'admin.user.password_reset': 'Reset a password',
  'admin.user.approved': 'Approved an account',
  'admin.user.denied': 'Denied an account',
  'admin.user.deleted': 'Deleted an account',
  'admin.group.created': 'Created a group',
  'admin.group.updated': 'Edited a group',
  'admin.group.deleted': 'Deleted a group',
  'admin.group.member_added': 'Added a group member',
  'admin.group.member_removed': 'Removed a group member',
  'admin.group.permissions_set': 'Changed group permissions',
  'admin.trip.cancelled': 'Cancelled a trip',
  'admin.booking.confirmed': 'Confirmed a booking',
  'admin.booking.cancelled': 'Cancelled a booking',
  'trip.created': 'Trip published',
  'reservation.requested': 'Seat requested',
  'reservation.cancelled': 'Seat request cancelled',
};

String auditActionLabel(String action) =>
    _actionLabels[action] ?? adminTitleCase(action.replaceAll('.', ' '));

Color _badgeColor(String action) {
  if (action.contains('deleted') ||
      action.contains('denied') ||
      action.contains('suspended') ||
      action.contains('cancelled')) {
    return YenkoColors.red;
  }
  if (action.contains('password') ||
      action.contains('permissions') ||
      action.contains('member')) {
    return const Color(0xFFE07B00);
  }
  if (action.startsWith('admin.')) return YenkoColors.charcoal;
  return const Color(0xFF0B7AC4);
}

/// Audit log: every admin action and trip event, filterable by action and
/// paged, with the recorded details expandable. Secrets are never recorded.
class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key, required this.client});
  final AdminApiClient client;

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  String? _action;
  int _page = 0;
  int _version = 0;
  late final Future<List<String>> _actions = widget.client.auditActions();

  @override
  Widget build(BuildContext context) => AdminFullPage(
    title: 'Audit log',
    subtitle: 'Who did what, and when',
    actions: [
      IconButton(
        tooltip: 'Refresh',
        onPressed: () => setState(() => _version++),
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    child: AdminLoader<AdminPage<AdminAuditEvent>>(
      reloadKey: '$_action|$_page|$_version',
      load: () => widget.client.listAudit(
        action: _action,
        limit: _pageSize,
        offset: _page * _pageSize,
      ),
      builder: (context, data, reload) {
        final pages = (data.total / _pageSize).ceil().clamp(1, 1 << 20);
        return RefreshIndicator(
          color: const Color(0xFFF9B900),
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            children: [
              FutureBuilder<List<String>>(
                future: _actions,
                builder: (context, snapshot) =>
                    DropdownButtonFormField<String?>(
                      initialValue: _action,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Action',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All actions'),
                        ),
                        for (final action in snapshot.data ?? const <String>[])
                          DropdownMenuItem<String?>(
                            value: action,
                            child: Text(
                              auditActionLabel(action),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        _action = value;
                        _page = 0;
                      }),
                    ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${data.total} events',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Newer',
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(
                    'Page ${_page + 1}/$pages',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Older',
                    onPressed: _page + 1 < pages
                        ? () => setState(() => _page++)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              if (data.items.isEmpty)
                const YenkoWatermarkEmptyState(
                  icon: Icons.history_rounded,
                  title: 'No audit events',
                  message: 'Admin actions and trip events are recorded here.',
                )
              else
                for (final event in data.items)
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
                            12,
                          ),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          title: Row(
                            children: [
                              Flexible(
                                child: AdminPill(
                                  auditActionLabel(event.action),
                                  color: _badgeColor(event.action),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${adminWhen(event.createdAt)} · ${event.actorName ?? 'System'} · ${event.aggregateType}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F3EE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: SelectableText(
                                const JsonEncoder.withIndent('  ').convert({
                                  'entity':
                                      '${event.aggregateType}:${event.aggregateId}',
                                  if (event.metadata.isNotEmpty)
                                    'details': event.metadata,
                                }),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
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
