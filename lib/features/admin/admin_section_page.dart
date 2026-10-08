import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/sign_out.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';
import '../../shared/widgets/yenko_widgets.dart';

class AdminSubTab {
  const AdminSubTab({
    required this.label,
    required this.icon,
    required this.builder,
  });
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

/// A plain full-screen admin page (dashboard, reports, audit) with the
/// standard back arrow, title, optional actions and sign-out button.
class AdminFullPage extends StatelessWidget {
  const AdminFullPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: YenkoShowcaseBackdrop(
      useWatermark: true,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: YenkoLogo(height: 28),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.4,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: YenkoColors.gray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...actions,
                  const YenkoSignOutButton(),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}
