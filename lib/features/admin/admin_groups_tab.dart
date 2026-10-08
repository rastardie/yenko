import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/data/local_auth_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_table.dart';
import 'admin_widgets.dart';

/// People > Groups: a sortable, selectable table of groups (name,
/// description, members, permissions, type) in the style of Onboard's groups
/// tab. Each group grants an application role and/or admin permissions;
/// membership and permission changes apply to members immediately.
class AdminGroupsTab extends StatefulWidget {
  const AdminGroupsTab({
    super.key,
    required this.client,
    required this.session,
  });

  final AdminApiClient client;
  final LocalAuthSession session;

  @override
  State<AdminGroupsTab> createState() => _AdminGroupsTabState();
}

class _AdminGroupsTabState extends State<AdminGroupsTab>
    with AutomaticKeepAliveClientMixin {
  final _selected = <String>{};
  int _version = 0;

  @override
  bool get wantKeepAlive => true;

  void _changed() => setState(() {
    _version++;
    _selected.clear();
  });

  Future<void> _open(String groupId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AdminGroupPage(
          client: widget.client,
          session: widget.session,
          groupId: groupId,
        ),
      ),
    );
    if (mounted) _changed();
  }

  Future<void> _deleteSelected(List<AdminGroup> groups) async {
    final targets = groups
        .where((group) => _selected.contains(group.id) && !group.isSystem)
        .toList();
    if (targets.isEmpty) {
      showAdminMessage(context, 'System groups cannot be deleted.');
      return;
    }
    final ok = await confirmAdminAction(
      context,
      title:
          'Delete ${targets.length} ${targets.length == 1 ? 'group' : 'groups'}?',
      message:
          'Members lose the permissions these groups grant. This cannot be undone. System groups are skipped.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final result = await runWithProgress<AdminGroup>(
      context,
      label: 'Deleting groups…',
      items: targets,
      task: (group) => widget.client.deleteGroup(group.id),
    );
    if (!mounted) return;
    _changed();
    if (result != null) {
      showAdminMessage(
        context,
        '${result.done} of ${result.total} deleted${result.firstError == null ? '.' : '. ${result.firstError}'}',
      );
    }
  }

  Future<void> _create() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _NewGroupDialog(),
    );
    if (result == null || !mounted) return;
    final (groupName, groupDescription) = result;
    final created = await runAdminAction<AdminGroup>(
      context,
      () => widget.client.createGroup(
        name: groupName,
        description: groupDescription,
      ),
    );
    if (created == null || !mounted) return;
    _changed();
    await _open(created.id);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AdminLoader<List<AdminGroup>>(
      reloadKey: _version,
      load: widget.client.listGroups,
      builder: (context, groups, reload) {
        final selectedCount = groups
            .where((group) => _selected.contains(group.id))
            .length;
        // With rows ticked the toolbar gets crowded on a phone, so shorten it.
        final compact =
            selectedCount > 0 && MediaQuery.sizeOf(context).width < 700;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          compact
                              ? '${groups.length}'
                              : '${groups.length} ${groups.length == 1 ? 'group' : 'groups'}',
                          style: const TextStyle(
                            color: YenkoColors.charcoal,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        if (selectedCount > 0) ...[
                          AdminSelectionChip(
                            compact
                                ? '$selectedCount sel.'
                                : '$selectedCount selected',
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
                          onPressed: groups.isEmpty
                              ? null
                              : () => setState(() {
                                  if (_selected.isNotEmpty) {
                                    _selected.clear();
                                  } else {
                                    _selected.addAll(
                                      groups.map((group) => group.id),
                                    );
                                  }
                                }),
                          child: Text(
                            _selected.isEmpty
                                ? 'Select all'
                                : (compact ? 'Clear' : 'Clear selection'),
                          ),
                        ),
                        if (selectedCount > 0 &&
                            widget.session.can('groups:delete'))
                          compact
                              ? IconButton(
                                  tooltip: 'Delete selected',
                                  visualDensity: VisualDensity.compact,
                                  color: YenkoColors.red,
                                  onPressed: () => _deleteSelected(groups),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                                )
                              : TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: YenkoColors.red,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    minimumSize: const Size(0, 28),
                                    textStyle: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  onPressed: () => _deleteSelected(groups),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 15,
                                  ),
                                  label: const Text('Delete'),
                                ),
                      ],
                    ),
                  ),
                  if (widget.session.can('groups:create'))
                    SizedBox(
                      height: 30,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF9B900),
                          foregroundColor: YenkoColors.charcoal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: _create,
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: Text(
                          compact ? 'New' : 'New group',
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
              child: AdminTable<AdminGroup>(
                rows: groups,
                idOf: (group) => group.id,
                selected: _selected,
                onSelectionChanged: (next) => setState(() {
                  _selected
                    ..clear()
                    ..addAll(next);
                }),
                onTap: (group) => _open(group.id),
                onRefresh: reload,
                columns: [
                  AdminColumn(
                    label: 'GROUP NAME',
                    width: 150,
                    sortKey: (group) => group.name,
                    cell: (group) => AdminCellText(group.name, bold: true),
                  ),
                  AdminColumn(
                    label: 'DESCRIPTION',
                    width: 230,
                    sortKey: (group) => group.description,
                    cell: (group) => AdminCellText(
                      group.description.isEmpty ? '—' : group.description,
                      muted: true,
                    ),
                  ),
                  AdminColumn(
                    label: 'MEMBERS',
                    width: 80,
                    sortKey: (group) => group.memberCount,
                    cell: (group) => AdminCellText('${group.memberCount}'),
                  ),
                  AdminColumn(
                    label: 'PERMISSIONS',
                    width: 100,
                    sortKey: (group) => group.permissions.length,
                    cell: (group) =>
                        AdminCellText('${group.permissions.length}'),
                  ),
                  AdminColumn(
                    label: 'TYPE',
                    width: 85,
                    sortKey: (group) => group.isSystem ? 'System' : 'Custom',
                    cell: (group) => AdminCellChip(
                      group.isSystem ? 'System' : 'Custom',
                      color: group.isSystem
                          ? const Color(0xFFE07B00)
                          : YenkoColors.charcoal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One group: details, members and a permission checklist.
class AdminGroupPage extends StatelessWidget {
  const AdminGroupPage({
    super.key,
    required this.client,
    required this.session,
    required this.groupId,
  });

  final AdminApiClient client;
  final LocalAuthSession session;
  final String groupId;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: YenkoShowcaseBackdrop(
      useWatermark: true,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            ),
            Expanded(
              child: AdminLoader<(AdminGroup, List<AdminPermission>)>(
                load: () async {
                  final group = await client.getGroup(groupId);
                  final permissions = await client.listPermissions();
                  return (group, permissions);
                },
                builder: (context, data, reload) => _GroupBody(
                  client: client,
                  session: session,
                  group: data.$1,
                  permissions: data.$2,
                  reload: reload,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GroupBody extends StatefulWidget {
  const _GroupBody({
    required this.client,
    required this.session,
    required this.group,
    required this.permissions,
    required this.reload,
  });

  final AdminApiClient client;
  final LocalAuthSession session;
  final AdminGroup group;
  final List<AdminPermission> permissions;
  final Future<void> Function() reload;

  @override
  State<_GroupBody> createState() => _GroupBodyState();
}

class _GroupBodyState extends State<_GroupBody> {
  late Set<String> _selected = {...widget.group.permissions};
  bool _busy = false;

  bool get _permissionsChanged =>
      _selected.length != widget.group.permissions.length ||
      !_selected.containsAll(widget.group.permissions);

  @override
  void didUpdateWidget(_GroupBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.permissions.join(',') !=
        widget.group.permissions.join(',')) {
      _selected = {...widget.group.permissions};
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    final ok = await runAdminAction<bool>(context, () async {
      await action();
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      await widget.reload();
      if (mounted && success != null) showAdminMessage(context, success);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _editDetails() async {
    final group = widget.group;
    final name = TextEditingController(text: group.name);
    final description = TextEditingController(text: group.description);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Edit group',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              enabled: !group.isSystem,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Name',
                helperText: group.isSystem
                    ? 'System groups cannot be renamed'
                    : null,
              ),
            ),
            TextField(
              controller: description,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF9B900),
              foregroundColor: YenkoColors.charcoal,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final newName = name.text.trim();
    final newDescription = description.text.trim();
    // Dispose after the dialog's closing animation has finished with them.
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      name.dispose();
      description.dispose();
    });
    if (saved != true || !mounted) return;
    if (!group.isSystem &&
        newName == group.name &&
        newDescription == group.description) {
      return;
    }
    if (group.isSystem && newDescription == group.description) return;
    await _run(
      () => widget.client.updateGroup(
        group.id,
        name: group.isSystem || newName == group.name ? null : newName,
        description: newDescription == group.description
            ? null
            : newDescription,
      ),
      success: 'Group updated.',
    );
  }

  Future<void> _addMember() async {
    final user = await showAdminSheet<AdminUser>(
      context,
      builder: (_) => _UserPicker(
        client: widget.client,
        exclude: widget.group.members.map((m) => m.id).toSet(),
      ),
    );
    if (user == null || !mounted) return;
    await _run(
      () => widget.client.addGroupMember(widget.group.id, user.id),
      success: '${user.displayName} added.',
    );
  }

  Future<void> _removeMember(AdminMember member) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Remove ${member.displayName}?',
      message: 'They lose what ${widget.group.name} grants, immediately.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.client.removeGroupMember(widget.group.id, member.id),
      success: '${member.displayName} removed.',
    );
  }

  Future<void> _savePermissions() => _run(
    () => widget.client.setGroupPermissions(
      widget.group.id,
      _selected.toList()..sort(),
    ),
    success: 'Permissions saved.',
  );

  Future<void> _delete() async {
    final ok = await confirmAdminAction(
      context,
      title: 'Delete ${widget.group.name}?',
      message:
          'Its ${widget.group.memberCount} members lose the permissions it grants. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = await runAdminAction<bool>(context, () async {
      await widget.client.deleteGroup(widget.group.id);
      return true;
    });
    if (!mounted) return;
    if (done == true) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final session = widget.session;
    final canEditPermissions =
        session.can('groups:assign_permissions') && !group.isSuperAdmins;
    final canMembers = session.can('groups:assign_members');
    final byResource = <String, List<AdminPermission>>{};
    for (final permission in widget.permissions) {
      byResource.putIfAbsent(permission.resource, () => []).add(permission);
    }
    return RefreshIndicator(
      color: const Color(0xFFF9B900),
      onRefresh: widget.reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
        children: [
          YenkoScreenTitle(
            title: group.name,
            subtitle: group.isSystem ? 'System group' : 'Custom group',
            action: session.can('groups:update')
                ? IconButton(
                    onPressed: _busy ? null : _editDetails,
                    icon: const Icon(Icons.edit_outlined),
                  )
                : null,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(color: Color(0xFFF9B900)),
            ),
          if (group.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                group.description,
                style: const TextStyle(color: YenkoColors.gray, height: 1.35),
              ),
            ),
          if (group.isSuperAdmins)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: YenkoShowcaseCard(
                color: Color(0xFFFFF5D8),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Super Admins always hold every permission. Only a super admin can change who is in this group.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          AdminSectionTitle(
            'Members (${group.members.length})',
            trailing: canMembers
                ? TextButton.icon(
                    onPressed: _busy ? null : _addMember,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Add'),
                  )
                : null,
          ),
          if (group.members.isEmpty)
            const YenkoShowcaseCard(
              child: Text(
                'No members yet.',
                style: TextStyle(color: YenkoColors.gray),
              ),
            )
          else
            YenkoShowcaseCard(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                children: [
                  for (final member in group.members)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFFFE8A3),
                        child: Text(
                          member.displayName.isEmpty
                              ? '?'
                              : member.displayName.characters.first
                                    .toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: YenkoColors.charcoal,
                          ),
                        ),
                      ),
                      title: Text(
                        member.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        member.username == null
                            ? 'no sign-in name'
                            : '@${member.username}${member.status == 'active' ? '' : ' · ${member.status}'}',
                      ),
                      trailing: canMembers
                          ? IconButton(
                              tooltip: 'Remove',
                              onPressed: _busy
                                  ? null
                                  : () => _removeMember(member),
                              icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: YenkoColors.red,
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          AdminSectionTitle(
            'Permissions (${_selected.length})',
            trailing: canEditPermissions && _permissionsChanged
                ? FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF9B900),
                      foregroundColor: YenkoColors.charcoal,
                    ),
                    onPressed: _busy ? null : _savePermissions,
                    child: const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              canEditPermissions
                  ? 'You can only grant or revoke permissions you hold yourself; others are locked.'
                  : 'These are read-only for your account.',
              style: const TextStyle(fontSize: 12, color: YenkoColors.gray),
            ),
          ),
          for (final entry in byResource.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: YenkoShowcaseCard(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 2),
                      child: Text(
                        adminTitleCase(entry.key),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    for (final permission in entry.value)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        activeColor: const Color(0xFFF9B900),
                        checkColor: YenkoColors.charcoal,
                        value: _selected.contains(permission.key),
                        onChanged:
                            canEditPermissions &&
                                !_busy &&
                                session.can(permission.key)
                            ? (value) => setState(() {
                                value == true
                                    ? _selected.add(permission.key)
                                    : _selected.remove(permission.key);
                              })
                            : null,
                        title: Text(
                          adminTitleCase(permission.action),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          permission.description,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (!group.isSystem && session.can('groups:delete')) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: YenkoColors.red),
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete group'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Searchable list of people to add to a group.
class _UserPicker extends StatefulWidget {
  const _UserPicker({required this.client, required this.exclude});
  final AdminApiClient client;
  final Set<String> exclude;

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => setState(() => _search = value.trim()),
              decoration: const InputDecoration(
                hintText: 'Search people to add',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: AdminLoader<AdminPage<AdminUser>>(
              reloadKey: _search,
              load: () => widget.client.listUsers(
                search: _search,
                status: 'active',
                limit: 50,
              ),
              builder: (context, page, _) {
                final choices = page.items
                    .where((user) => !widget.exclude.contains(user.id))
                    .toList();
                if (choices.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nobody to add.',
                      style: TextStyle(color: YenkoColors.gray),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: choices.length,
                  itemBuilder: (context, index) {
                    final user = choices[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFFFE8A3),
                        child: Text(
                          user.displayName.isEmpty
                              ? '?'
                              : user.displayName.characters.first.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: YenkoColors.charcoal,
                          ),
                        ),
                      ),
                      title: Text(
                        user.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(user.handle),
                      onTap: () => Navigator.pop(context, user),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// Owns its text controllers so they outlive the dialog's closing animation.
class _NewGroupDialog extends StatefulWidget {
  const _NewGroupDialog();

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(
      'New group',
      style: TextStyle(fontWeight: FontWeight.w900),
    ),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (value) => (value ?? '').trim().length < 2
                ? 'Enter at least 2 characters'
                : null,
          ),
          TextFormField(
            controller: _description,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'What is this group for?',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF9B900),
          foregroundColor: YenkoColors.charcoal,
        ),
        onPressed: () {
          if (_formKey.currentState?.validate() ?? false) {
            Navigator.pop(context, (
              _name.text.trim(),
              _description.text.trim(),
            ));
          }
        },
        child: const Text('Create'),
      ),
    ],
  );
}
