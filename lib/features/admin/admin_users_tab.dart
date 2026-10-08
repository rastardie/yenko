import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_user_detail_page.dart';
import 'admin_table.dart';
import 'admin_user_forms.dart';
import 'admin_widgets.dart';

enum _BulkAction { activate, suspend, resetPasswords, delete }

/// People > Users: a sortable, selectable table in the style of Onboard's
/// members table, with bulk actions, a pending-approval banner and a detail
/// page per person. Controls are shown per the caller's permissions; the
/// server enforces them and asks for the password on every write.
class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key, required this.client, required this.session});

  final AdminApiClient client;
  final LocalAuthSession session;

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  final _selected = <String>{};
  String _search = '';
  String? _status;
  int _version = 0;
  List<AdminUser> _users = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _version++;
    _selected.clear();
  });

  Future<void> _addUser() async {
    final created = await showAdminSheet<AdminUser>(
      context,
      builder: (_) => NewUserSheet(client: widget.client),
    );
    if (created == null || !mounted) return;
    _changed();
    final temporaryPassword = created.temporaryPassword;
    if (temporaryPassword != null) {
      await showSecretDialog(
        context,
        title: 'Account created',
        message:
            '${created.displayName} can sign in as ${created.handle} with this temporary password.',
        secret: temporaryPassword,
      );
    } else if (mounted) {
      showAdminMessage(context, '${created.displayName} was added.');
    }
  }

  Future<void> _openDetail(AdminUser user) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AdminUserDetailPage(
          client: widget.client,
          session: widget.session,
          userId: user.id,
        ),
      ),
    );
    if (mounted) _changed();
  }

  Future<void> _bulk(_BulkAction action, List<AdminUser> targets) async {
    final self = widget.session.userId;
    final skipSelf =
        action == _BulkAction.suspend || action == _BulkAction.delete;
    final eligible = targets
        .where((user) => !(skipSelf && user.id == self))
        .toList();
    if (eligible.isEmpty) {
      showAdminMessage(context, 'You cannot do that to your own account.');
      return;
    }
    final (verb, message) = switch (action) {
      _BulkAction.activate => (
        'Activate',
        'They will be able to sign in again.',
      ),
      _BulkAction.suspend => (
        'Suspend',
        'They are signed out everywhere immediately and cannot sign in until restored.',
      ),
      _BulkAction.resetPasswords => (
        'Reset passwords for',
        'New one-time passwords are generated and everyone is signed out.',
      ),
      _BulkAction.delete => (
        'Delete',
        'Their sign-in is removed permanently. People with open trips or bookings are skipped.',
      ),
    };
    final ok = await confirmAdminAction(
      context,
      title:
          '$verb ${eligible.length} ${eligible.length == 1 ? 'person' : 'people'}?',
      message: message,
      confirmLabel: verb.split(' ').first,
      destructive: action != _BulkAction.activate,
    );
    if (!ok || !mounted) return;

    final passwords = <String, String>{};
    final result = await runWithProgress<AdminUser>(
      context,
      label: '$verb…',
      items: eligible,
      task: (user) async {
        switch (action) {
          case _BulkAction.activate:
            await widget.client.updateUser(user.id, status: 'active');
          case _BulkAction.suspend:
            await widget.client.updateUser(user.id, status: 'suspended');
          case _BulkAction.resetPasswords:
            final temporary = await widget.client.resetPassword(user.id);
            if (temporary != null) passwords[user.displayName] = temporary;
          case _BulkAction.delete:
            await widget.client.deleteUser(user.id);
        }
      },
    );
    if (!mounted) return;
    _changed();
    if (result == null) return;
    final skipped = targets.length - eligible.length;
    showAdminMessage(
      context,
      '${result.done} of ${result.total} done'
      '${skipped > 0 ? ' ($skipped skipped: your own account)' : ''}'
      '${result.firstError != null ? '. ${result.firstError}' : '.'}',
    );
    if (passwords.isNotEmpty && mounted) {
      await showSecretDialog(
        context,
        title: 'Temporary passwords',
        message: 'Give each person their password to sign in.',
        secret: passwords.entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join('\n'),
      );
    }
  }

  Future<void> _rowMenu(AdminUser user, Offset position) async {
    final session = widget.session;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final isSelf = user.id == session.userId;
    final canStatus = session.can('users:manage_status');
    PopupMenuItem<Object> item(
      Object value,
      IconData icon,
      String label,
      Color color,
    ) => PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: value == _BulkAction.delete ? Colors.red.shade900 : null,
              ),
            ),
          ),
        ],
      ),
    );
    final chosen = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (session.can('users:update'))
          item('modify', Icons.edit_rounded, 'Modify', Colors.grey.shade700),
        if (session.can('users:reset_credentials'))
          item(
            _BulkAction.resetPasswords,
            Icons.lock_reset_rounded,
            'Reset Password',
            Colors.orange.shade700,
          ),
        if (canStatus && user.status == 'active' && !isSelf)
          item(
            _BulkAction.suspend,
            Icons.block_rounded,
            'Suspend',
            Colors.red.shade700,
          ),
        if (canStatus && user.status == 'suspended')
          item(
            _BulkAction.activate,
            Icons.check_circle_outline,
            'Activate',
            Colors.green.shade700,
          ),
        if (session.can('users:delete') && !isSelf) ...[
          const PopupMenuDivider(),
          item(
            _BulkAction.delete,
            Icons.delete_forever_rounded,
            'Delete',
            Colors.red.shade900,
          ),
        ],
      ],
    );
    if (!mounted || chosen == null) return;
    if (chosen == 'modify') {
      if (await editUserDetails(context, widget.client, user) && mounted) {
        _changed();
      }
    } else if (chosen is _BulkAction) {
      await _bulk(chosen, [user]);
    }
  }

  /// Onboard's "Manage Users" hub: one place for add / modify / reset /
  /// suspend / activate / delete. Acts on the ticked rows, or asks who.
  Future<void> _manage() async {
    final session = widget.session;
    final count = _selected.length;
    final choice = await showAdminSheet<String>(
      context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manage Users',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: YenkoColors.charcoal,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count == 0
                    ? 'Choose an action. You will select the users before it runs.'
                    : '$count selected ${count == 1 ? 'user' : 'users'} will be affected. You can change the selection from the Users list.',
                style: const TextStyle(fontSize: 12, color: YenkoColors.gray),
              ),
              const SizedBox(height: 14),
              if (session.can('users:create'))
                AdminManageTile(
                  icon: Icons.person_add_rounded,
                  title: 'Add New User',
                  subtitle: 'Create a new user account',
                  onTap: () => Navigator.pop(sheetContext, 'add'),
                ),
              if (session.can('users:update'))
                AdminManageTile(
                  icon: Icons.edit_rounded,
                  title: 'Modify User',
                  subtitle: count > 1
                      ? 'Modify requires one selected user'
                      : 'Change name and home area',
                  onTap: () => Navigator.pop(sheetContext, 'modify'),
                ),
              if (session.can('users:reset_credentials'))
                AdminManageTile(
                  icon: Icons.lock_reset_rounded,
                  title: 'Reset Password',
                  subtitle: 'Reset passwords for the selected users',
                  onTap: () => Navigator.pop(sheetContext, 'reset'),
                ),
              if (session.can('users:manage_status')) ...[
                AdminManageTile(
                  icon: Icons.block_rounded,
                  title: 'Disable / Suspend User',
                  subtitle: 'Suspend the selected users',
                  onTap: () => Navigator.pop(sheetContext, 'suspend'),
                ),
                AdminManageTile(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Enable / Activate User',
                  subtitle: 'Activate the selected users',
                  onTap: () => Navigator.pop(sheetContext, 'activate'),
                ),
              ],
              if (session.can('users:delete'))
                AdminManageTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete User',
                  subtitle: 'Permanently remove the selected users',
                  color: Colors.red,
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'add') {
      await _addUser();
      return;
    }
    final self = widget.session.userId;
    bool applies(AdminUser user) => switch (choice) {
      'suspend' => user.status == 'active' && user.id != self,
      'activate' => user.status == 'suspended',
      'delete' => user.id != self,
      _ => true,
    };
    final (verb, confirm) = switch (choice) {
      'modify' => ('modify', 'Modify user'),
      'reset' => ('reset passwords', 'Reset passwords'),
      'suspend' => ('suspend', 'Suspend users'),
      'activate' => ('activate', 'Activate users'),
      _ => ('delete', 'Delete users'),
    };
    List<AdminUser>? targets;
    if (_selected.isNotEmpty) {
      targets = _users
          .where((user) => _selected.contains(user.id) && applies(user))
          .toList();
      if (targets.isEmpty) {
        showAdminMessage(
          context,
          'None of the selected users can be $verb${verb.endsWith('e') ? 'd' : 'ed'}. Review the selection and try again.',
        );
        return;
      }
    } else {
      final candidates = _users.where(applies).toList();
      if (candidates.isEmpty) {
        showAdminMessage(context, 'No users are available for this action.');
        return;
      }
      targets = await pickUsers(
        context,
        title: choice == 'modify'
            ? 'Select one user to modify'
            : 'Select users to $verb',
        users: candidates,
        confirmLabel: confirm,
        single: choice == 'modify',
      );
      if (targets == null || !mounted) return;
    }
    if (choice == 'modify') {
      if (targets.length != 1) {
        showAdminMessage(
          context,
          'Modify User applies to one user at a time. Clear the extra selections, then select exactly one user.',
        );
        return;
      }
      if (await editUserDetails(context, widget.client, targets.single) &&
          mounted) {
        _changed();
      }
      return;
    }
    await _bulk(switch (choice) {
      'reset' => _BulkAction.resetPasswords,
      'suspend' => _BulkAction.suspend,
      'activate' => _BulkAction.activate,
      _ => _BulkAction.delete,
    }, targets);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = widget.session;
    return AdminLoader<AdminPage<AdminUser>>(
      reloadKey: '$_search|$_status|$_version',
      load: () =>
          widget.client.listUsers(search: _search, status: _status, limit: 200),
      builder: (context, page, reload) {
        final users = page.items;
        _users = users;
        final selectedUsers = users
            .where((user) => _selected.contains(user.id))
            .toList();
        final allSelected =
            users.isNotEmpty && selectedUsers.length == users.length;
        PopupMenuItem<_BulkAction> actionItem(
          _BulkAction action,
          IconData icon,
          String label,
          Color color,
        ) => PopupMenuItem(
          value: action,
          child: Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color),
                ),
              ),
            ],
          ),
        );
        final actions = <PopupMenuEntry<_BulkAction>>[
          if (session.can('users:manage_status')) ...[
            actionItem(
              _BulkAction.activate,
              Icons.check_circle_outline_rounded,
              'Activate selected',
              Colors.green,
            ),
            actionItem(
              _BulkAction.suspend,
              Icons.block_rounded,
              'Suspend selected',
              Colors.red,
            ),
          ],
          if (session.can('users:reset_credentials'))
            actionItem(
              _BulkAction.resetPasswords,
              Icons.lock_reset_rounded,
              'Reset passwords',
              const Color(0xFFE07B00),
            ),
          if (session.can('users:delete')) ...[
            const PopupMenuDivider(),
            actionItem(
              _BulkAction.delete,
              Icons.delete_forever_rounded,
              'Delete selected',
              Colors.red.shade900,
            ),
          ],
        ];
        // With rows ticked the toolbar gets crowded on a phone, so shorten it.
        final compact =
            _selected.isNotEmpty && MediaQuery.sizeOf(context).width < 700;
        final manageable =
            session.can('users:create') ||
            session.can('users:update') ||
            session.can('users:reset_credentials') ||
            session.can('users:manage_status') ||
            session.can('users:delete');
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 13),
                onSubmitted: (value) => setState(() {
                  _search = value.trim();
                  _selected.clear();
                }),
                decoration: InputDecoration(
                  hintText: 'Search name, username, phone…',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 12,
                  ),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AdminFilterBar(
                options: const {
                  null: 'All',
                  'active': 'Active',
                  'pending': 'Pending',
                  'suspended': 'Suspended',
                },
                selected: _status,
                onSelected: (value) => setState(() {
                  _status = value;
                  _selected.clear();
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          compact
                              ? '${page.total}'
                              : '${page.total} ${page.total == 1 ? 'person' : 'people'}',
                          style: const TextStyle(
                            color: YenkoColors.charcoal,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        if (_selected.isNotEmpty) ...[
                          AdminSelectionChip(
                            compact
                                ? '${selectedUsers.length} sel.'
                                : '${selectedUsers.length} selected',
                          ),
                        ],
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFE07B00),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 28),
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: users.isEmpty
                              ? null
                              : () => setState(() {
                                  if (allSelected || _selected.isNotEmpty) {
                                    _selected.clear();
                                  } else {
                                    _selected.addAll(
                                      users.map((user) => user.id),
                                    );
                                  }
                                }),
                          child: Text(
                            _selected.isEmpty
                                ? 'Select all'
                                : (compact ? 'Clear' : 'Clear selection'),
                          ),
                        ),
                        if (_selected.isNotEmpty && actions.isNotEmpty) ...[
                          PopupMenuButton<_BulkAction>(
                            tooltip: 'Actions for selected users',
                            onSelected: (action) =>
                                _bulk(action, selectedUsers),
                            itemBuilder: (_) => actions,
                            child: Container(
                              height: 30,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(
                                    0xFFF9B900,
                                  ).withValues(alpha: .85),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!compact) ...[
                                    const Icon(
                                      Icons.playlist_add_check_rounded,
                                      size: 15,
                                      color: Color(0xFFE07B00),
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                  const Text(
                                    'Actions',
                                    style: TextStyle(
                                      color: YenkoColors.charcoal,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: YenkoColors.charcoal,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (manageable)
                    SizedBox(
                      height: 30,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF9B900),
                          foregroundColor: YenkoColors.charcoal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: _manage,
                        icon: const Icon(
                          Icons.manage_accounts_rounded,
                          size: 14,
                        ),
                        label: Text(
                          compact ? 'Manage' : 'Manage Users',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: users.isEmpty
                  ? const Center(
                      child: YenkoWatermarkEmptyState(
                        icon: Icons.person_search_rounded,
                        title: 'No people found',
                        message: 'Try a different search or filter.',
                      ),
                    )
                  : AdminTable<AdminUser>(
                      rows: users,
                      idOf: (user) => user.id,
                      initialSortColumn: 1,
                      selected: _selected,
                      onSelectionChanged: (next) => setState(() {
                        _selected
                          ..clear()
                          ..addAll(next);
                      }),
                      onTap: _openDetail,
                      onLongPress: _rowMenu,
                      onRefresh: reload,
                      columns: [
                        AdminColumn(
                          label: 'USERNAME',
                          width: 105,
                          sortKey: (user) => user.username ?? '',
                          cell: (user) => AdminCellText(
                            user.username ?? '—',
                            muted: user.username == null,
                          ),
                        ),
                        AdminColumn(
                          label: 'FULL NAME',
                          width: 135,
                          sortKey: (user) => user.displayName,
                          cell: (user) => AdminNameCell(
                            user.displayName,
                            dim: user.isSuspended,
                          ),
                        ),
                        AdminColumn(
                          label: 'GROUPS',
                          width: 150,
                          sortKey: (user) =>
                              user.groups.map((group) => group.name).join(', '),
                          cell: (user) => AdminCellText(
                            user.groups.isEmpty
                                ? '—'
                                : user.groups
                                      .map((group) => group.name)
                                      .join(', '),
                            muted: user.groups.isEmpty,
                          ),
                        ),
                        AdminColumn(
                          label: 'TEL',
                          width: 115,
                          sortKey: (user) => user.phone ?? '',
                          cell: (user) => AdminCellText(
                            user.phone ?? '—',
                            muted: user.phone == null,
                          ),
                        ),
                        AdminColumn(
                          label: 'SUBURB',
                          width: 105,
                          sortKey: (user) => user.homeArea ?? '',
                          cell: (user) => AdminCellText(
                            user.homeArea ?? '—',
                            muted: user.homeArea == null,
                          ),
                        ),
                        AdminColumn(
                          label: 'STATUS',
                          width: 90,
                          sortKey: (user) => user.status,
                          cell: (user) => AdminCellChip(
                            adminTitleCase(user.status),
                            color: adminAccent(user.status),
                          ),
                        ),
                        AdminColumn(
                          label: 'ROLE',
                          width: 105,
                          sortKey: (user) => adminPrimaryRole(user.roles),
                          cell: (user) {
                            final role = adminPrimaryRole(user.roles);
                            return role == 'passenger'
                                ? const AdminCellText('Rider')
                                : AdminCellChip(
                                    adminTitleCase(role),
                                    color: adminAccent(role),
                                  );
                          },
                        ),
                      ],
                    ),
            ),
            if (page.total > users.length)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Showing ${users.length} of ${page.total}. Refine your search to see others.',
                  style: const TextStyle(fontSize: 11, color: YenkoColors.gray),
                ),
              ),
          ],
        );
      },
    );
  }
}
