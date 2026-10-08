import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yenko_app/core/data/local_auth_client.dart';
import 'package:yenko_app/features/auth/local_landing_screen.dart';
import 'package:yenko_app/shared/widgets/yenko_widgets.dart';

void main() {
  testWidgets('the tagline runs the full width of the logo, left to right', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: YenkoLogo(height: 80))),
      ),
    );
    final image = find.byType(Image);
    final tagline = find.text(YenkoLogo.tagline);
    expect(tagline, findsOneWidget);

    final logoLeft = tester.getTopLeft(image).dx;
    final logoRight = tester.getTopRight(image).dx;
    final textLeft = tester.getTopLeft(tagline).dx;
    final textRight = tester.getTopRight(tagline).dx;
    expect(textLeft, closeTo(logoLeft, 1));
    // The last glyph is followed by a sliver of letter-spacing.
    expect(textRight, closeTo(logoRight, 6));
    expect(
      tester.getTopLeft(tagline).dy,
      greaterThan(tester.getBottomLeft(image).dy - 1),
      reason: 'sits underneath the logo',
    );
  });

  testWidgets('the tagline scales with the logo at every size', (tester) async {
    for (final height in [28.0, 56.0, 80.0, 150.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: YenkoLogo(height: height)),
          ),
        ),
      );
      final width = tester.getSize(find.byType(Image)).width;
      expect(width, closeTo(height * YenkoLogo.aspectRatio, .01));
      final textWidth =
          tester.getTopRight(find.text(YenkoLogo.tagline)).dx -
          tester.getTopLeft(find.text(YenkoLogo.tagline)).dx;
      expect(textWidth, closeTo(width, 8), reason: 'height $height');
    }
  });

  testWidgets('the landing page shows the exact supplied banner image', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalLandingScreen(
          onSignedIn: (_) {},
          authClient: LocalAuthClient(baseUrl: 'http://127.0.0.1:1'),
        ),
      ),
    );
    final banner = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName ==
              'assets/app/yenko_landing_banner.png',
    );
    expect(banner, findsOneWidget);
  });

  testWidgets(
    'the promise bar speaks to drivers and riders (Offer, Book, Share)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: YenkoPromiseBar())),
        ),
      );
      // Two-sided marketplace: a step for drivers, a step for riders, and the
      // shared benefit — not a rider-only pitch.
      expect(find.text('Offer'), findsOneWidget);
      expect(find.text('Book'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('for drivers'), findsOneWidget);
      expect(find.text('for riders'), findsOneWidget);
      expect(find.byIcon(Icons.directions_car_filled_rounded), findsOneWidget);
      expect(find.byIcon(Icons.event_seat_rounded), findsOneWidget);
      expect(find.byIcon(Icons.handshake_rounded), findsOneWidget);
    },
  );
}
