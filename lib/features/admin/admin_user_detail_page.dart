import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_section_page.dart';
import 'admin_user_forms.dart';
import 'admin_widgets.dart';

enum _UserMenu { modify, resetPassword, toggleStatus, delete }

/// One person: details, groups, effective permissions and the actions the
/// caller is permitted to take. Mirrors Onboard's member detail page.
class AdminUserDetailPage extends StatefulWidget {
  const AdminUserDetailPage({
    super.key,
    required this.client,
    required this.session,
    required this.userId,
  });

  final AdminApiClient client;
  final LocalAuthSession session;
  final String userId;

  @override
  State<AdminUserDetailPage> createState() => _AdminUserDetailPageState();
}

class _AdminUserDetailPageState extends State<AdminUserDetailPage> {
  int _version = 0;
  bool _busy = false;

  void _reload() => setState(() => _version++);

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    final ok = await runAdminAction<bool>(context, () async {
      await action();
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) {
      _reload();
      if (success != null) showAdminMessage(context, success);
    }
  }

  Future<void> _modify(AdminUser user) async {
    if (await editUserDetails(context, widget.client, user) && mounted) {
      _reload();
    }
  }

  Future<void> _resetPassword(AdminUser user) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Reset password?',
      message:
          'A new one-time password is generated and ${user.displayName} is signed out everywhere.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    String? temporary;
    final done = await runAdminAction<bool>(context, () async {
      temporary = await widget.client.resetPassword(user.id);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    final secret = temporary;
    if (done == true && secret != null) {
      await showSecretDialog(
        context,
        title: 'Password reset',
        message: 'Give ${user.displayName} this temporary password to sign in.',
        secret: secret,
      );
    }
  }

  Future<void> _toggleStatus(AdminUser user) async {
    final suspend = !user.isSuspended;
    final ok = await confirmAdminAction(
      context,
      title: suspend
          ? 'Suspend ${user.displayName}?'
          : 'Activate ${user.displayName}?',
      message: suspend
          ? 'They are signed out everywhere immediately and cannot sign in until restored.'
          : 'They will be able to sign in again.',
      confirmLabel: suspend ? 'Suspend' : 'Activate',
      destructive: suspend,
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.client.updateUser(
        user.id,
        status: suspend ? 'suspended' : 'active',
      ),
      success: suspend ? 'Suspended.' : 'Activated.',
    );
  }

  Future<void> _delete(AdminUser user) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Delete ${user.displayName}?',
      message:
          'Their sign-in is removed permanently and they lose all group access. '
          'Trips and bookings they took part in stay on record. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = await runAdminAction<bool>(context, () async {
      await widget.client.deleteUser(user.id);
      return true;
    });
    if (!mounted) return;
    if (done == true) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _decide(AdminUser user, {required bool approve}) async {
    if (!approve) {
      final ok = await confirmAdminAction(
        context,
        title: 'Deny ${user.displayName}?',
        message: 'Their request is removed. They can sign up again later.',
        confirmLabel: 'Deny',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    if (approve) {
      await _run(
        () => widget.client.approveUser(user.id),
        success: '${user.displayName} approved.',
      );
      return;
    }
    setState(() => _busy = true);
    final done = await runAdminAction<bool>(context, () async {
      await widget.client.denyUser(user.id);
      return true;
    });
    if (!mounted) return;
    if (done == true) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _addToGroup(AdminUser user) async {
    final groups = await runAdminAction<List<AdminGroup>>(
      context,
      widget.client.listGroups,
    );
    if (groups == null || !mounted) return;
    final taken = user.groups.map((group) => group.id).toSet();
    final choices = groups.where((group) => !taken.contains(group.id)).toList();
    if (choices.isEmpty) {
      showAdminMessage(context, 'This person is already in every group.');
      return;
    }
    final picked = await showDialog<AdminGroup>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text(
          'Add to group',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        children: [
          for (final group in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, group),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (group.description.isNotEmpty)
                    Text(
                      group.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: YenkoColors.gray,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _run(
      () => widget.client.addGroupMember(picked.id, user.id),
      success: 'Added to ${picked.name}.',
    );
  }

  Future<void> _removeFromGroup(AdminUser user, AdminGroupRef group) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Remove from ${group.name}?',
      message:
          '${user.displayName} will lose the access this group grants, immediately.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.client.removeGroupMember(group.id, user.id),
      success: 'Removed from ${group.name}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AdminLoader<AdminUser>(
      reloadKey: _version,
      load: () => widget.client.getUser(widget.userId),
      frame: (context, child) => AdminFullPage(
        title: 'Person',
        subtitle: 'Back to users',
        child: child,
      ),
      builder: (context, user, reload) {
        final isSelf = user.id == session.userId;
        final canMembers =
            session.can('groups:assign_members') && session.can('groups:read');
        final menu = <PopupMenuEntry<_UserMenu>>[
          if (session.can('users:update'))
            const PopupMenuItem(value: _UserMenu.modify, child: Text('Modify')),
          if (session.can('users:reset_credentials'))
            const PopupMenuItem(
              value: _UserMenu.resetPassword,
              child: Text('Reset password'),
            ),
          if (session.can('users:manage_status') &&
              !isSelf &&
              user.status != 'pending') ...[
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _UserMenu.toggleStatus,
              child: Text(user.isSuspended ? 'Activate' : 'Suspend'),
            ),
          ],
          if (session.can('users:delete') && !isSelf) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _UserMenu.delete,
              child: Text(
                'Delete',
                style: TextStyle(
                  color: YenkoColors.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ];
        return AdminFullPage(
          title: user.displayName,
          subtitle: 'Back to users',
          actions: [
            if (menu.isNotEmpty)
              PopupMenuButton<_UserMenu>(
                tooltip: 'Actions',
                enabled: !_busy,
                onSelected: (action) => switch (action) {
                  _UserMenu.modify => _modify(user),
                  _UserMenu.resetPassword => _resetPassword(user),
                  _UserMenu.toggleStatus => _toggleStatus(user),
                  _UserMenu.delete => _delete(user),
                },
                itemBuilder: (_) => menu,
              ),
          ],
          child: RefreshIndicator(
            color: const Color(0xFFF9B900),
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
              children: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(color: Color(0xFFF9B900)),
                  ),
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: user.isSuspended
                            ? const Color(0xFFF2D6D7)
                            : const Color(0xFFFFE8A3),
                        child: Text(
                          user.displayName.isEmpty
                              ? '?'
                              : user.displayName.characters.first.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: YenkoColors.charcoal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        user.displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        user.handle,
                        style: const TextStyle(color: YenkoColors.gray),
                      ),
                      const SizedBox(height: 8),
                      AdminPill(
                        adminTitleCase(user.status),
                        color: adminAccent(user.status),
                      ),
                    ],
                  ),
                ),
                if (user.status == 'pending' &&
                    session.can('users:approve')) ...[
                  const SizedBox(height: 14),
                  YenkoShowcaseCard(
                    color: const Color(0xFFFFF0D6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Waiting for approval',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'They cannot sign in until you approve this account.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: YenkoColors.red,
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _decide(user, approve: false),
                                child: const Text('Deny'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: YenkoColors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _decide(user, approve: true),
                                child: const Text('Approve'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const AdminSectionTitle('Details'),
                YenkoShowcaseCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      _Row('Username', user.username ?? '—'),
                      _Row('Full name', user.displayName),
                      _Row('Phone', user.phone ?? '—'),
                      _Row('Home area', user.homeArea ?? '—'),
                      _Row(
                        'Roles',
                        user.roles.isEmpty
                            ? '—'
                            : user.roles.map(adminTitleCase).join(', '),
                      ),
                      _Row('Member since', adminWhen(user.createdAt)),
                    ],
                  ),
                ),
                const AdminSectionTitle('Groups'),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final group in user.groups)
                      InputChip(
                        label: Text(
                          group.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        backgroundColor: adminAccent(
                          group.role ?? '',
                        ).withValues(alpha: .12),
                        side: BorderSide.none,
                        onDeleted: canMembers && !_busy
                            ? () => _removeFromGroup(user, group)
                            : null,
                      ),
                    if (canMembers)
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: const Text(
                          'Add to group',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        onPressed: _busy ? null : () => _addToGroup(user),
                      ),
                  ],
                ),
                if (user.permissions.isNotEmpty)
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'Effective permissions (${user.permissions.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final key in user.permissions)
                              AdminPill(key, color: YenkoColors.charcoal),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              color: YenkoColors.gray,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
