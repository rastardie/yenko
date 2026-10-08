import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/data/admin_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String adminWhen(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.day} ${_months[value.month - 1]}, $hour:$minute';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String adminDay(DateTime value) =>
    '${_weekdays[value.weekday - 1]} ${value.day} ${_months[value.month - 1]}';

String adminTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String adminTitleCase(String value) => value
    .split(RegExp(r'[_\s]+'))
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

/// Accent colour per role/status so staff can scan lists quickly.
Color adminAccent(String key) => switch (key) {
  'super_admin' => const Color(0xFF7A3EFF),
  'admin' => const Color(0xFFE5484D),
  'operator' => const Color(0xFF0B7AC4),
  'support' => const Color(0xFF008A7B),
  'finance' => const Color(0xFF9A6B00),
  'fleet_manager' => const Color(0xFF5B6B7B),
  'driver' => const Color(0xFFE5A900),
  'active' || 'open' || 'confirmed' => YenkoColors.green,
  'suspended' || 'cancelled' || 'denied' => YenkoColors.red,
  'pending' || 'requested' => const Color(0xFFE07B00),
  _ => YenkoColors.gray,
};

void showAdminMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}

/// Runs [action], reporting a server/connection failure in a snack bar.
/// Returns the result, or null when it failed.
Future<T?> runAdminAction<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on AdminApiException catch (error) {
    // Dismissing the password prompt is not an error worth a message.
    if (!error.cancelled && context.mounted) {
      showAdminMessage(context, error.message);
    }
  } catch (_) {
    if (context.mounted) {
      showAdminMessage(context, 'Something went wrong. Please try again.');
    }
  }
  return null;
}

Future<bool> confirmAdminAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive
                ? YenkoColors.red
                : const Color(0xFFF9B900),
            foregroundColor: destructive ? Colors.white : YenkoColors.charcoal,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Shows a credential exactly once (for example a generated temporary password).
Future<void> showSecretDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String secret,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (dialogContext) => AlertDialog(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF5D8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            secret,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'It is shown only once and is not stored anywhere readable. Share it securely.',
          style: TextStyle(fontSize: 12, color: YenkoColors.gray),
        ),
      ],
    ),
    actions: [
      TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: secret));
          if (dialogContext.mounted) {
            showAdminMessage(dialogContext, 'Copied to clipboard.');
          }
        },
        icon: const Icon(Icons.copy_rounded, size: 18),
        label: const Text('Copy'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF9B900),
          foregroundColor: YenkoColors.charcoal,
        ),
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Done'),
      ),
    ],
  ),
);

/// The "Confirm administrator action" prompt: re-enter the password or PIN
/// before a sensitive change. Returns null when dismissed.
Future<String?> showAdminActionPrompt(BuildContext context, {String? error}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var obscure = true;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          icon: const Icon(Icons.verified_user_outlined, size: 30),
          title: const Text(
            'Confirm administrator action',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter your current password or PIN to continue.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: obscure,
                keyboardType: TextInputType.visiblePassword,
                onSubmitted: (value) => Navigator.pop(dialogContext, value),
                decoration: InputDecoration(
                  labelText: 'Password or PIN',
                  errorText: error,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF9B900),
                foregroundColor: YenkoColors.charcoal,
              ),
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    },
  ).whenComplete(
    // Dispose after the dialog's closing animation has finished with it.
    () => Future<void>.delayed(
      const Duration(milliseconds: 500),
      controller.dispose,
    ),
  );
}

/// Runs [task] for each item while showing "Processing n of total…". A failure
/// does not stop the rest (as in Onboard's bulk actions); the result reports
/// how many succeeded. Returns null if the administrator cancelled the
/// re-authentication prompt, in which case nothing further is attempted.
Future<({int done, int total, String? firstError})?> runWithProgress<T>(
  BuildContext context, {
  required String label,
  required List<T> items,
  required Future<void> Function(T item) task,
}) async {
  final progress = ValueNotifier<int>(0);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: items.isEmpty ? null : value / items.length,
                  color: const Color(0xFFF9B900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Processing $value of ${items.length}…',
                  style: const TextStyle(fontSize: 12, color: YenkoColors.gray),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  var done = 0;
  String? firstError;
  var cancelled = false;
  for (final item in items) {
    try {
      await task(item);
      done++;
    } on AdminApiException catch (error) {
      if (error.cancelled) {
        cancelled = true;
        break;
      }
      firstError ??= error.message;
    } catch (_) {
      firstError ??= 'Something went wrong.';
    }
    progress.value++;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  return cancelled
      ? null
      : (done: done, total: items.length, firstError: firstError);
}

class AdminPill extends StatelessWidget {
  const AdminPill(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? YenkoColors.gray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The account's most privileged application role, for the ROLE column.
String adminPrimaryRole(List<String> roles) {
  const order = [
    'super_admin',
    'admin',
    'operator',
    'support',
    'finance',
    'fleet_manager',
    'driver',
    'passenger',
  ];
  for (final role in order) {
    if (roles.contains(role)) return role;
  }
  return roles.isEmpty ? 'passenger' : roles.first;
}

/// One action in the Manage Users sheet (Onboard's AdminManageTile).
class AdminManageTile extends StatelessWidget {
  const AdminManageTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? YenkoColors.charcoal;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: accent.withValues(alpha: .1),
        child: Icon(icon, color: accent, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: color,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }
}

/// "3 selected" tag shown next to a table's record count.
class AdminSelectionChip extends StatelessWidget {
  const AdminSelectionChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1CC),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFE2C15A)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: YenkoColors.charcoal,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Single-select filter chips, e.g. All / Active / Suspended.
class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  final Map<String?, String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: selected == entry.key,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selectedColor: const Color(0xFFF9B900),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: YenkoColors.charcoal.withValues(
                    alpha: selected == entry.key ? 1 : .7,
                  ),
                ),
                onSelected: (_) => onSelected(entry.key),
              ),
            ),
        ],
      ),
    ),
  );
}

class AdminErrorState extends StatelessWidget {
  const AdminErrorState({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final forbidden =
        error is AdminApiException && (error as AdminApiException).isForbidden;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: YenkoWatermarkEmptyState(
          icon: forbidden
              ? Icons.lock_outline_rounded
              : Icons.cloud_off_rounded,
          title: forbidden ? 'Not permitted' : 'Could not load this',
          message: error is AdminApiException
              ? (error as AdminApiException).message
              : 'Something went wrong. Pull down to try again.',
        ),
      ),
    );
  }
}

/// Loads data once, then offers pull-to-refresh and retry on failure. The
/// [builder] receives a `reload` callback to call after a change is saved.
class AdminLoader<T> extends StatefulWidget {
  const AdminLoader({
    super.key,
    required this.load,
    required this.builder,
    this.reloadKey,
    this.frame,
  });

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  builder;

  /// Reloads automatically when this value changes (e.g. the active filter).
  final Object? reloadKey;

  /// Wraps the loading and error states, for full-page loaders that need the
  /// page chrome (back arrow, sign-out) even before data arrives.
  final Widget Function(BuildContext context, Widget child)? frame;

  @override
  State<AdminLoader<T>> createState() => _AdminLoaderState<T>();
}

class _AdminLoaderState<T> extends State<AdminLoader<T>> {
  late Future<T> _future = widget.load();

  @override
  void didUpdateWidget(AdminLoader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) _future = widget.load();
  }

  Future<void> _reload() async {
    final next = widget.load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The error is shown by the FutureBuilder below.
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      Widget framed(Widget child) =>
          widget.frame == null ? child : widget.frame!(context, child);
      if (snapshot.connectionState != ConnectionState.done) {
        return framed(
          const Center(
            child: CircularProgressIndicator(color: Color(0xFFF9B900)),
          ),
        );
      }
      if (snapshot.hasError) {
        return framed(
          RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 420,
                  child: AdminErrorState(error: snapshot.error!),
                ),
              ],
            ),
          ),
        );
      }
      return widget.builder(context, snapshot.requireData, _reload);
    },
  );
}

/// Bottom sheet shell with a grab handle and consistent padding.
Future<T?> showAdminSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
    ),
    child: builder(sheetContext),
  ),
);

class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
