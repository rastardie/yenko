import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The YɛnKɔ Road Trip logo with "Your Journey, Simplified" written underneath,
/// scaled so the tagline runs the full width of the logo, left to right.
/// Sized by [height] (the logo artwork); the width follows its proportions.
class YenkoLogo extends StatelessWidget {
  const YenkoLogo({super.key, this.height = 30, this.showTagline = true});

  final double height;
  final bool showTagline;

  /// Width-to-height ratio of assets/app/yenko_logo.png.
  static const aspectRatio = 1600 / 386;
  static const tagline = 'Your Journey, Simplified';

  @override
  Widget build(BuildContext context) => SizedBox(
    width: height * aspectRatio,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/app/yenko_logo.png',
          height: height,
          width: height * aspectRatio,
          fit: BoxFit.contain,
          semanticLabel: 'YɛnKɔ',
        ),
        if (showTagline)
          Padding(
            // Mirrors Onboard's compact app-bar promise: the promise belongs
            // directly to the mark, not in a separate visual band.
            padding: EdgeInsets.only(top: height * .04),
            child: SizedBox(
              width: height * aspectRatio,
              // Keep the promise at the same visual width as the lockup—the
              // useful Onboard pattern—but let the colourful logo carry the
              // accent. Extra slogan colours looked busy next to this mark.
              child: FittedBox(
                fit: BoxFit.fitWidth,
                child: Text(
                  tagline,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: YenkoColors.charcoal.withValues(alpha: .72),
                    fontWeight: FontWeight.w700,
                    letterSpacing: .15,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// YɛnKɔ's brand promise, styled after Onboard's "Reserve · Ride · Relax"
/// pill but deliberately two-sided: YɛnKɔ needs both drivers and riders, so the
/// strip names each role and lands on the shared benefit — drivers **Offer**
/// spare seats, riders **Book** them, and both **Share** the fixed fare. The
/// three steps use the Ghana flag colours already drawn in the logo's road arc.
class YenkoPromiseBar extends StatelessWidget {
  const YenkoPromiseBar({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  static const _red = Color(0xFFC9362B);
  static const _gold = Color(0xFFE5A900);
  static const _green = Color(0xFF187444);

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFEDE9E0)),
      boxShadow: [
        BoxShadow(
          color: YenkoColors.charcoal.withValues(alpha: .06),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: const Row(
      children: [
        Expanded(
          child: _PromiseStep(
            icon: Icons.directions_car_filled_rounded,
            label: 'Offer',
            caption: 'for drivers',
            color: _gold,
          ),
        ),
        _PromiseDivider(),
        Expanded(
          child: _PromiseStep(
            icon: Icons.event_seat_rounded,
            label: 'Book',
            caption: 'for riders',
            color: _red,
          ),
        ),
        _PromiseDivider(),
        Expanded(
          child: _PromiseStep(
            icon: Icons.handshake_rounded,
            label: 'Share',
            caption: 'fixed fare',
            color: _green,
          ),
        ),
      ],
    ),
  );
}

class _PromiseStep extends StatelessWidget {
  const _PromiseStep({
    required this.icon,
    required this.label,
    required this.caption,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 25, color: color),
      ),
      const SizedBox(height: 10),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 17,
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        caption,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: YenkoColors.gray,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    ],
  );
}

/// A thin full-height rule between promise steps, matching the redesign (and
/// Onboard's promise pill) rather than the earlier floating dots.
class _PromiseDivider extends StatelessWidget {
  const _PromiseDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 70, color: const Color(0xFFEBE7DE));
}

class YenkoPrimaryButton extends StatelessWidget {
  const YenkoPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: YenkoColors.gold,
      foregroundColor: YenkoColors.charcoal,
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      shape: const StadiumBorder(),
    ),
    onPressed: onPressed,
    icon: icon == null ? const SizedBox.shrink() : Icon(icon),
    label: Text(label),
  );
}

class YenkoCard extends StatelessWidget {
  const YenkoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE1E4E8)),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class VerifiedChip extends StatelessWidget {
  const VerifiedChip({super.key, this.label = 'Verified'});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: YenkoColors.green,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.verified_rounded, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class YenkoFuelSavingsCard extends StatelessWidget {
  const YenkoFuelSavingsCard({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(compact ? 12 : 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFE9A5), Color(0xFFFFF8E9)],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Container(
          width: compact ? 38 : 48,
          height: compact ? 38 : 48,
          decoration: BoxDecoration(
            color: const Color(0xFFFFD968),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.eco_outlined, color: YenkoColors.charcoal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compact ? 'Fuel-saving calculator' : 'You could save',
                style: const TextStyle(fontSize: 12, color: YenkoColors.gray),
              ),
              Text(
                compact ? 'Track every shared journey' : 'GH₵ 240 this week',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              if (!compact)
                const Text(
                  'by sharing your ride!',
                  style: TextStyle(fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class YenkoVehicleThumbnail extends StatelessWidget {
  const YenkoVehicleThumbnail({super.key, this.width = 112});
  final double width;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/app/private_saloon.png',
    width: width,
    fit: BoxFit.contain,
  );
}

class YenkoMapPanel extends StatelessWidget {
  const YenkoMapPanel({
    super.key,
    required this.pickup,
    required this.destination,
    this.compact = false,
    this.tracking = false,
  });

  final String pickup;
  final String destination;
  final bool compact;
  final bool tracking;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: SizedBox(
      height: compact ? 170 : 310,
      child: CustomPaint(
        painter: _AccraMapPainter(tracking: tracking),
        child: Stack(
          children: [
            if (!tracking) ...[
              const Positioned(
                top: 18,
                right: 22,
                child: _MapLabel(label: 'East Legon'),
              ),
              const Positioned(
                top: 66,
                left: 54,
                child: _MapLabel(label: 'Madina'),
              ),
              const Positioned(
                bottom: 82,
                left: 22,
                child: _MapLabel(label: 'Lapaz'),
              ),
              const Positioned(
                bottom: 54,
                right: 22,
                child: _MapLabel(label: 'Circle'),
              ),
              const Positioned(top: 110, left: 145, child: _CarPin()),
              const Positioned(top: 158, right: 106, child: _CarPin()),
              const Positioned(bottom: 68, left: 108, child: _CarPin()),
            ],
            if (tracking)
              const Positioned(
                left: 88,
                bottom: 52,
                child: _CarPin(active: true),
              ),
            Positioned(
              top: tracking ? 14 : 18,
              right: 16,
              child: _MapBubble(icon: Icons.location_on_rounded, label: pickup),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: _MapBubble(
                icon: Icons.directions_car_filled_rounded,
                label: tracking ? '4 min away' : '3 cars going your way',
              ),
            ),
            if (!tracking)
              const Positioned(
                right: 16,
                bottom: 16,
                child: _RoundMapControl(),
              ),
          ],
        ),
      ),
    ),
  );
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: YenkoColors.charcoal,
    ),
  );
}

class _CarPin extends StatelessWidget {
  const _CarPin({this.active = false});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    width: 31,
    height: 31,
    decoration: BoxDecoration(
      color: active ? const Color(0xFF2F80ED) : YenkoColors.gold,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 5)],
    ),
    child: Icon(
      active ? Icons.navigation_rounded : Icons.directions_car_filled_rounded,
      size: 17,
      color: YenkoColors.charcoal,
    ),
  );
}

class _MapBubble extends StatelessWidget {
  const _MapBubble({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 205),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: YenkoColors.gold),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _RoundMapControl extends StatelessWidget {
  const _RoundMapControl();
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
    ),
    child: const Icon(Icons.my_location_rounded, size: 20),
  );
}

class _AccraMapPainter extends CustomPainter {
  const _AccraMapPainter({required this.tracking});
  final bool tracking;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8EEE5),
    );
    final water = Path()
      ..moveTo(0, size.height * .84)
      ..quadraticBezierTo(
        size.width * .45,
        size.height * .68,
        size.width,
        size.height * .8,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(water, Paint()..color = const Color(0xFFAEDAF5));
    final minorRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final majorRoad = Paint()
      ..color = const Color(0xFFF6F6F2)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    final routes = <Path>[
      Path()
        ..moveTo(0, size.height * .22)
        ..quadraticBezierTo(
          size.width * .3,
          size.height * .1,
          size.width * .88,
          size.height * .34,
        ),
      Path()
        ..moveTo(size.width * .1, 0)
        ..quadraticBezierTo(
          size.width * .45,
          size.height * .42,
          size.width * .93,
          size.height * .65,
        ),
      Path()
        ..moveTo(size.width * .02, size.height * .58)
        ..quadraticBezierTo(
          size.width * .42,
          size.height * .72,
          size.width,
          size.height * .36,
        ),
      Path()
        ..moveTo(size.width * .45, 0)
        ..quadraticBezierTo(
          size.width * .24,
          size.height * .36,
          size.width * .1,
          size.height,
        ),
      Path()
        ..moveTo(size.width * .76, 0)
        ..quadraticBezierTo(
          size.width * .55,
          size.height * .4,
          size.width * .72,
          size.height,
        ),
    ];
    for (final path in routes) {
      canvas.drawPath(path, majorRoad);
      canvas.drawPath(path, minorRoad);
    }
    final route = Path()
      ..moveTo(size.width * .43, size.height * .72)
      ..cubicTo(
        size.width * .52,
        size.height * .52,
        size.width * .67,
        size.height * .74,
        size.width * .82,
        size.height * .35,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFFE5A900)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    if (!tracking) {
      canvas.drawCircle(
        Offset(size.width * .42, size.height * .69),
        10,
        Paint()..color = const Color(0xFF2F80ED),
      );
      canvas.drawCircle(
        Offset(size.width * .82, size.height * .35),
        12,
        Paint()..color = YenkoColors.red,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AccraMapPainter oldDelegate) =>
      oldDelegate.tracking != tracking;
}
