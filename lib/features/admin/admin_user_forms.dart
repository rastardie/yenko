import 'package:flutter/material.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import 'admin_widgets.dart';

/// "Add a person": the same essentials as rider sign-up (name, username,
/// phone, password, quick PIN, home area) plus the groups to put them in.
class NewUserSheet extends StatefulWidget {
  const NewUserSheet({super.key, required this.client});
  final AdminApiClient client;

  @override
  State<NewUserSheet> createState() => _NewUserSheetState();
}

class _NewUserSheetState extends State<NewUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _homeArea = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _quickPin = TextEditingController();
  final _confirmPin = TextEditingController();
  final _selectedGroupIds = <String>{};
  late final Future<List<AdminGroup>> _groups = widget.client.listGroups();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _username,
      _phone,
      _homeArea,
      _password,
      _confirmPassword,
      _quickPin,
      _confirmPin,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await widget.client.createUser(
        displayName: _name.text.trim(),
        username: _username.text.trim().toLowerCase(),
        phone: _phone.text.trim(),
        password: _password.text,
        quickPin: _quickPin.text,
        homeArea: _homeArea.text.trim(),
        groupIds: _selectedGroupIds.toList(),
      );
      if (mounted) Navigator.pop(context, user);
    } on AdminApiException catch (error) {
      if (mounted && !error.cancelled) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 11,
        letterSpacing: .8,
        color: YenkoColors.gray,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const Text(
              'Add a person',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            const Text(
              'Everyone is a rider by default. Choose extra groups to give them more.',
              style: TextStyle(fontSize: 12, color: YenkoColors.gray),
            ),
            _section('Account details'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name *'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _username,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username *',
                helperText: '3–32 letters, numbers, . _ -',
              ),
              validator: (value) =>
                  RegExp(
                    r'^[a-zA-Z0-9_.-]{3,32}$',
                  ).hasMatch((value ?? '').trim())
                  ? null
                  : 'Use 3–32 letters, numbers, . _ -',
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                helperText: 'International format, e.g. +233200000000',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                return text.isEmpty || RegExp(r'^\+\d{7,15}$').hasMatch(text)
                    ? null
                    : 'Use +233… format';
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _homeArea,
              decoration: const InputDecoration(
                labelText: 'Home area (optional)',
              ),
            ),
            _section('Sign-in'),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password (optional)',
                helperText: 'Leave empty to generate a one-time password',
              ),
              validator: (value) =>
                  (value ?? '').isNotEmpty && value!.length < 8
                  ? 'At least 8 characters'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmPassword,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (value) =>
                  value != _password.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _quickPin,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quick PIN (optional)',
                helperText: '4–20 digits; works as a sign-in too',
              ),
              validator: (value) {
                final text = value ?? '';
                return text.isEmpty || (text.length >= 4 && text.length <= 20)
                    ? null
                    : '4–20 characters';
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirmPin,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Confirm quick PIN'),
              validator: (value) =>
                  value != _quickPin.text ? 'PINs do not match' : null,
            ),
            _section('Groups'),
            FutureBuilder<List<AdminGroup>>(
              future: _groups,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(color: Color(0xFFF9B900)),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    snapshot.error is AdminApiException
                        ? (snapshot.error as AdminApiException).message
                        : 'Groups could not be loaded.',
                    style: const TextStyle(
                      color: YenkoColors.gray,
                      fontSize: 12,
                    ),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final group in snapshot.requireData.where(
                      (group) => group.role != 'passenger',
                    ))
                      FilterChip(
                        label: Text(
                          group.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        selected: _selectedGroupIds.contains(group.id),
                        selectedColor: const Color(0xFFFFE8A3),
                        onSelected: (selected) => setState(() {
                          selected
                              ? _selectedGroupIds.add(group.id)
                              : _selectedGroupIds.remove(group.id);
                        }),
                      ),
                  ],
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: YenkoColors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            YenkoShowcaseButton(
              label: _saving ? 'Adding…' : 'Add person',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: _saving ? () {} : _submit,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Accounts waiting for approval, with Approve / Deny per person and
/// Approve all (Onboard's "Pending membership requests").
class PendingApprovalsSheet extends StatefulWidget {
  const PendingApprovalsSheet({super.key, required this.client});
  final AdminApiClient client;

  @override
  State<PendingApprovalsSheet> createState() => _PendingApprovalsSheetState();
}

class _PendingApprovalsSheetState extends State<PendingApprovalsSheet> {
  int _version = 0;
  bool _busy = false;

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
    setState(() => _busy = true);
    final done = await runAdminAction<bool>(context, () async {
      approve
          ? await widget.client.approveUser(user.id)
          : await widget.client.denyUser(user.id);
      return true;
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (done == true) _version++;
    });
  }

  Future<void> _approveAll(List<AdminUser> users) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Approve ${users.length} accounts?',
      message: 'They will be able to sign in straight away.',
      confirmLabel: 'Approve all',
    );
    if (!ok || !mounted) return;
    final result = await runWithProgress<AdminUser>(
      context,
      label: 'Approving…',
      items: users,
      task: (user) => widget.client.approveUser(user.id),
    );
    if (!mounted) return;
    setState(() => _version++);
    if (result != null) {
      showAdminMessage(context, '${result.done} of ${result.total} approved.');
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: AdminLoader<AdminPage<AdminUser>>(
        reloadKey: _version,
        load: () => widget.client.listUsers(status: 'pending', limit: 100),
        builder: (context, page, _) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pending requests',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                if (page.items.length > 1)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: YenkoColors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _busy ? null : () => _approveAll(page.items),
                    child: const Text(
                      'Approve all',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (page.items.isEmpty)
              const YenkoWatermarkEmptyState(
                icon: Icons.verified_outlined,
                title: 'All caught up',
                message: 'No accounts are waiting for approval.',
              )
            else
              for (final user in page.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: YenkoShowcaseCard(
                    color: const Color(0xFFFAFAF7),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                user.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            for (final group in user.groups.where(
                              (group) => group.role != 'passenger',
                            ))
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: AdminPill(
                                  group.name,
                                  color: adminAccent(group.role ?? ''),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          '${user.handle} · requested ${adminWhen(user.createdAt)}${user.homeArea == null ? '' : ' · ${user.homeArea}'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: YenkoColors.gray,
                          ),
                        ),
                        const SizedBox(height: 8),
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
                ),
          ],
        ),
      ),
    ),
  );
}

/// "Modify User": edit a person's full name and home area. Returns true when
/// something was saved. Shared by the user detail page and Manage Users.
Future<bool> editUserDetails(
  BuildContext context,
  AdminApiClient client,
  AdminUser user,
) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _EditUserDialog(user: user),
  );
  if (result == null || !context.mounted) return false;
  final (newName, newArea) = result;
  final nameChanged = newName.isNotEmpty && newName != user.displayName;
  final areaChanged = newArea != (user.homeArea ?? '');
  if (!nameChanged && !areaChanged) return false;
  final updated = await runAdminAction<AdminUser>(
    context,
    () => client.updateUser(
      user.id,
      displayName: nameChanged ? newName : null,
      homeArea: areaChanged ? newArea : null,
    ),
  );
  if (updated == null || !context.mounted) return false;
  showAdminMessage(context, 'Details updated.');
  return true;
}

/// Owns its text controllers so they outlive the dialog's closing animation.
class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.user});
  final AdminUser user;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final _name = TextEditingController(text: widget.user.displayName);
  late final _area = TextEditingController(text: widget.user.homeArea ?? '');

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(
      'Edit details',
      style: TextStyle(fontWeight: FontWeight.w900),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        TextField(
          controller: _area,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Home area'),
        ),
      ],
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
        onPressed: () =>
            Navigator.pop(context, (_name.text.trim(), _area.text.trim())),
        child: const Text('Save'),
      ),
    ],
  );
}

/// Pick users for a Manage Users action when nothing is selected in the table
/// (Onboard's member selection sheet). Returns the chosen users, or null.
Future<List<AdminUser>?> pickUsers(
  BuildContext context, {
  required String title,
  required List<AdminUser> users,
  required String confirmLabel,
  bool single = false,
}) => showAdminSheet<List<AdminUser>>(
  context,
  builder: (_) => _UserSelectionSheet(
    title: title,
    users: users,
    confirmLabel: confirmLabel,
    single: single,
  ),
);

class _UserSelectionSheet extends StatefulWidget {
  const _UserSelectionSheet({
    required this.title,
    required this.users,
    required this.confirmLabel,
    required this.single,
  });

  final String title;
  final List<AdminUser> users;
  final String confirmLabel;
  final bool single;

  @override
  State<_UserSelectionSheet> createState() => _UserSelectionSheetState();
}

class _UserSelectionSheetState extends State<_UserSelectionSheet> {
  final _chosen = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final visible = widget.users
        .where(
          (user) =>
              query.isEmpty ||
              user.displayName.toLowerCase().contains(query) ||
              (user.username ?? '').toLowerCase().contains(query) ||
              (user.phone ?? '').contains(query),
        )
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (!widget.single)
                    TextButton(
                      onPressed: () => setState(() {
                        if (_chosen.length == visible.length) {
                          _chosen.clear();
                        } else {
                          _chosen.addAll(visible.map((user) => user.id));
                        }
                      }),
                      child: Text(
                        _chosen.isNotEmpty && _chosen.length == visible.length
                            ? 'Clear'
                            : 'Select all',
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search name, username, phone…',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('No matching people.'))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final user = visible[index];
                        final checked = _chosen.contains(user.id);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          activeColor: const Color(0xFFF9B900),
                          checkColor: YenkoColors.charcoal,
                          title: Text(
                            user.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${user.handle} · ${adminTitleCase(user.status)}',
                          ),
                          onChanged: (value) => setState(() {
                            if (widget.single) _chosen.clear();
                            value == true
                                ? _chosen.add(user.id)
                                : _chosen.remove(user.id);
                          }),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF9B900),
                    foregroundColor: YenkoColors.charcoal,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: _chosen.isEmpty
                      ? null
                      : () => Navigator.pop(context, [
                          for (final user in widget.users)
                            if (_chosen.contains(user.id)) user,
                        ]),
                  child: Text(
                    widget.confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900),
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
