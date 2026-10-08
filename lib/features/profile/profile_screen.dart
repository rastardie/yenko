import 'package:flutter/material.dart';

import '../../core/data/trip_repository.dart';
import '../../core/security/biometric_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/sign_out.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.repository,
    this.displayName,
    this.roleLabel,
  });
  final TripRepository repository;

  /// The signed-in person's name and role; null in mock mode.
  final String? displayName;
  final String? roleLabel;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _womenOnly = false;
  bool _biometricLoading = true;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _driverMode = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    await BiometricService.instance.initialize();
    if (!mounted) return;
    setState(() {
      _biometricLoading = false;
      _biometricAvailable = BiometricService.instance.isAvailable;
      _biometricEnabled = BiometricService.instance.isEnabled;
    });
  }

  Future<void> _changeBiometricEnrollment(bool enable) async {
    setState(() => _biometricLoading = true);
    if (!enable) {
      await BiometricService.instance.disable();
      await _loadBiometricState();
      return;
    }
    final result = await BiometricService.instance.enable();
    await _loadBiometricState();
    if (!mounted) return;
    final message = switch (result) {
      BiometricEnableResult.enabled =>
        'Biometric unlock is enabled on this device.',
      BiometricEnableResult.unavailable =>
        'Set up Face ID or a fingerprint in device settings first.',
      BiometricEnableResult.verificationFailed =>
        'Biometric confirmation was not completed.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) => YenkoShowcaseBackdrop(
      useWatermark: true,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            YenkoScreenTitle(
              title: 'My profile',
              action: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
            const SizedBox(height: 16),
            YenkoShowcaseCard(
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFE8A3),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (widget.displayName ?? 'Ama Addo').characters.first
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.displayName ?? 'Ama Addo',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.roleLabel ?? 'ama.addo@yenko.local',
                          style: const TextStyle(
                            fontSize: 12,
                            color: YenkoColors.gray,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          widget.displayName == null
                              ? 'Local development profile'
                              : 'Signed in',
                          style: const TextStyle(
                            fontSize: 11,
                            color: YenkoColors.gray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Account type',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: const Color(0xFFF9B900),
                selectedForegroundColor: YenkoColors.charcoal,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.person_outline_rounded),
                  label: Text('Passenger'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.directions_car_outlined),
                  label: Text('Driver'),
                ),
              ],
              selected: {_driverMode},
              onSelectionChanged: (selected) =>
                  setState(() => _driverMode = selected.first),
            ),
            const SizedBox(height: 18),
            if (_driverMode) ...[
              _MomoPayoutCard(repository: widget.repository),
              const SizedBox(height: 12),
              const Text(
                'Driver overview',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (widget.repository.driverTripSummaries.isEmpty)
                const YenkoWatermarkEmptyState(
                  icon: Icons.directions_car_outlined,
                  title: 'No driver rides yet',
                  message:
                      'Publish a ride to see booking requests and expected earnings here.',
                ),
              for (final summary in widget.repository.driverTripSummaries) ...[
                YenkoShowcaseCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${summary.trip.from} → ${summary.trip.to}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary.trip.departureLabel,
                        style: const TextStyle(
                          color: YenkoColors.gray,
                          fontSize: 12,
                        ),
                      ),
                      const Divider(height: 22),
                      Row(
                        children: [
                          _Metric(
                            value: '${summary.bookingCount}',
                            label: 'Requests',
                          ),
                          _Metric(
                            value: '${summary.seatsBooked}',
                            label: 'Seats',
                          ),
                          _Metric(
                            value: 'GH₵ ${summary.expectedFare}',
                            label: 'Expected fare',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
            ],
            const Text(
              'Account & safety',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const _ProfileAction(
              icon: Icons.person_outline_rounded,
              label: 'Personal information',
            ),
            const _ProfileAction(
              icon: Icons.directions_car_outlined,
              label: 'My vehicles',
              detail: 'Set up before live driver trips',
            ),
            const _ProfileAction(
              icon: Icons.badge_outlined,
              label: 'Documents & verification',
              detail: 'Pending',
            ),
            const _ProfileAction(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Payment methods',
            ),
            const _ProfileAction(
              icon: Icons.notifications_none_rounded,
              label: 'Notifications',
            ),
            const SizedBox(height: 10),
            YenkoShowcaseCard(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _womenOnly,
                onChanged: (value) => setState(() => _womenOnly = value),
                secondary: const Icon(
                  Icons.female_rounded,
                  color: YenkoColors.gold,
                ),
                title: const Text(
                  'Women-only rides',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text('Show only women drivers when searching.'),
              ),
            ),
            const SizedBox(height: 10),
            YenkoShowcaseCard(
              child: _biometricLoading
                  ? const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.fingerprint_rounded),
                      title: Text('Checking biometric availability…'),
                    )
                  : _biometricAvailable
                  ? SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _biometricEnabled,
                      onChanged: _changeBiometricEnrollment,
                      secondary: const Icon(
                        Icons.fingerprint_rounded,
                        color: YenkoColors.gold,
                      ),
                      title: const Text(
                        'Biometric unlock',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: const Text(
                        'Optional Face ID or fingerprint unlock for this device.',
                      ),
                    )
                  : ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.fingerprint_outlined),
                      title: const Text(
                        'Biometric unlock unavailable',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: const Text(
                        'Enroll Face ID or a fingerprint in device settings to enable it.',
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            if (SignOutScope.maybeOf(context) != null) ...[
              OutlinedButton.icon(
                onPressed: () => confirmSignOut(context),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 10),
            ],
            const YenkoShowcaseCard(
              color: Color(0xFFFFF5D8),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Fair fixed prices, public pickup points, and clear safety boundaries—always.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: YenkoColors.gray),
        ),
      ],
    ),
  );
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({required this.icon, required this.label, this.detail});
  final IconData icon;
  final String label;
  final String? detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: YenkoShowcaseCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: YenkoColors.charcoal),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: const TextStyle(
                fontSize: 10,
                color: YenkoColors.green,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: YenkoColors.gray),
        ],
      ),
    ),
  );
}

/// Lets a driver register (or clear) the mobile money number their
/// confirmed passengers should pay directly, outside the app. YɛnKɔ never
/// verifies this number or moves any money itself — see
/// [TripRepository.setMomoDetails] and HANDOVER.md.
class _MomoPayoutCard extends StatefulWidget {
  const _MomoPayoutCard({required this.repository});
  final TripRepository repository;

  @override
  State<_MomoPayoutCard> createState() => _MomoPayoutCardState();
}

class _MomoPayoutCardState extends State<_MomoPayoutCard> {
  final _numberController = TextEditingController();
  String? _network;
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  void _startEditing() {
    final current = widget.repository.myMomoDetails;
    _numberController.text = current?.momoNumber ?? '';
    setState(() {
      _network = current?.momoNetwork;
      _editing = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.setMomoDetails(
        momoNumber: _numberController.text.trim(),
        momoNetwork: _network,
      );
      if (!mounted) return;
      setState(() => _editing = false);
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    try {
      await widget.repository.setMomoDetails();
      if (!mounted) return;
      setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.repository.myMomoDetails;
    return YenkoShowcaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: YenkoColors.gold,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Mobile money payout number',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Passengers pay this number directly after you confirm their seat. YɛnKɔ does not collect, hold, or verify this payment.',
            style: TextStyle(fontSize: 11, color: YenkoColors.gray),
          ),
          const SizedBox(height: 12),
          if (!_editing) ...[
            if (current == null)
              const Text(
                'Not set yet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              )
            else
              Text(
                '${current.networkLabel} · ${current.momoNumber}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _startEditing,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(current == null ? 'Add payout number' : 'Edit'),
            ),
          ] else ...[
            TextField(
              controller: _numberController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile money number',
                hintText: '+233244000111',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final option in const [
                  ('mtn', 'MTN MoMo'),
                  ('telecel', 'Telecel Cash'),
                  ('airteltigo', 'AirtelTigo Money'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _network == option.$1,
                    onSelected: (_) => setState(() => _network = option.$1),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (current != null)
                  TextButton(
                    onPressed: _saving ? null : _clear,
                    child: const Text('Remove'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _editing = false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
