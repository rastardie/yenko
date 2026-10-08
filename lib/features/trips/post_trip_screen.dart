import 'package:flutter/material.dart';

import '../../core/data/trip_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';

class PostTripScreen extends StatefulWidget {
  const PostTripScreen({
    super.key,
    required this.repository,
    required this.onTripPosted,
  });
  final TripRepository repository;
  final VoidCallback onTripPosted;

  @override
  State<PostTripScreen> createState() => _PostTripScreenState();
}

class _PostTripScreenState extends State<PostTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fromController = TextEditingController(text: 'East Legon Hills');
  final _toController = TextEditingController(text: 'Circle');
  final _junctionController = TextEditingController(
    text: 'Madina Market junction',
  );
  final _priceController = TextEditingController(text: '15');
  int _seats = 3;
  bool _womenOnly = false;

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _junctionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await widget.repository.postTrip(
        from: _fromController.text.trim(),
        to: _toController.text.trim(),
        pickupJunction: _junctionController.text.trim(),
        seats: _seats,
        pricePerSeat: int.parse(_priceController.text),
        womenOnly: _womenOnly,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your ride is live. Passengers can now book a seat.'),
        ),
      );
      widget.onTripPosted();
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => YenkoShowcaseBackdrop(
    useWatermark: true,
    child: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            const YenkoScreenTitle(
              title: 'Offer a ride',
              subtitle:
                  'Share empty seats on a journey you are already making.',
            ),
            const SizedBox(height: 18),
            YenkoShowcaseCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your route',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 14),
                  _RouteField(
                    controller: _fromController,
                    label: 'From',
                    icon: Icons.radio_button_checked_rounded,
                    color: YenkoColors.green,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 15),
                    child: SizedBox(
                      height: 16,
                      child: VerticalDivider(color: Color(0xFFE1E4E8)),
                    ),
                  ),
                  _RouteField(
                    controller: _toController,
                    label: 'To',
                    icon: Icons.location_on_rounded,
                    color: YenkoColors.red,
                  ),
                  const SizedBox(height: 13),
                  _RouteField(
                    controller: _junctionController,
                    label: 'Public pickup junction',
                    icon: Icons.directions_bus_rounded,
                    color: YenkoColors.charcoal,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            YenkoShowcaseCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFE8A3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.schedule_rounded),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Departure time',
                          style: TextStyle(
                            fontSize: 12,
                            color: YenkoColors.gray,
                          ),
                        ),
                        Text(
                          'Today, 7:30 AM',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: 12),
            YenkoShowcaseCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available seats',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Keep one seat for yourself and only offer seats you can guarantee.',
                    style: TextStyle(color: YenkoColors.gray, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _SeatButton(
                        icon: Icons.remove_rounded,
                        onPressed: _seats > 1
                            ? () => setState(() => _seats--)
                            : null,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '$_seats',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 28,
                            ),
                          ),
                        ),
                      ),
                      _SeatButton(
                        icon: Icons.add_rounded,
                        onPressed: _seats < 4
                            ? () => setState(() => _seats++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            YenkoShowcaseCard(
              child: TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price per seat (GH₵)',
                  prefixIcon: Icon(Icons.payments_outlined),
                  helperText:
                      'Set a clear, fair price—YɛnKɔ does not support bidding.',
                ),
                validator: (value) => int.tryParse(value ?? '') == null
                    ? 'Enter a whole Ghana cedi amount.'
                    : null,
              ),
            ),
            const SizedBox(height: 12),
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
                  'Women-only ride',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text(
                  'Available after the relevant verification workflow is live.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const YenkoShowcaseCard(
              color: Color(0xFFFFF5D8),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: YenkoColors.charcoal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Use public pickup points only. Never request or share a passenger’s home address.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            YenkoShowcaseButton(
              label: 'Publish ride',
              icon: Icons.rocket_launch_outlined,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    ),
  );
}

class _RouteField extends StatelessWidget {
  const _RouteField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.color,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: color),
    ),
    validator: (value) =>
        (value ?? '').trim().isEmpty ? '$label is required.' : null,
  );
}

class _SeatButton extends StatelessWidget {
  const _SeatButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: IconButton.filled(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFFFFE8A3),
        foregroundColor: YenkoColors.charcoal,
      ),
      icon: Icon(icon),
    ),
  );
}
