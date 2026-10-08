import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yenko_app/core/data/local_auth_client.dart';
import 'package:yenko_app/features/auth/email_signup_screen.dart';
import 'package:yenko_app/features/auth/local_signup_screen.dart';
import 'package:yenko_app/features/auth/social_auth_buttons.dart';

LocalAuthClient _client() => LocalAuthClient(baseUrl: 'http://127.0.0.1:1');

void main() {
  testWidgets('social sign-in options are shown (Google, Apple, Facebook, X)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SocialAuthButtons(authClient: _client(), onSignedIn: (_) {}),
        ),
      ),
    );
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Facebook'), findsOneWidget);
    expect(find.text('Continue with X'), findsOneWidget);
  });

  testWidgets(
    'email signup collects the full legal name as on the national ID',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EmailSignupScreen(authClient: _client(), onSignedIn: (_) {}),
        ),
      );
      expect(find.text('Sign up with email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Given names (as on ID)'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Surname (as on ID)'),
        findsOneWidget,
      );
      expect(find.text('Create account'), findsOneWidget);

      // Submitting empty shows the mandatory-field validators.
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter your given names.'), findsOneWidget);
      expect(find.text('Enter your surname.'), findsOneWidget);
    },
  );

  testWidgets(
    'the signup screen leads with social and email, above the username form',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: LocalSignupScreen(authClient: _client(), onSignedIn: (_) {}),
        ),
      );
      await tester.pump();

      final social = find.text('Continue with Google');
      final email = find.text('Continue with email');
      final usernameForm = find.widgetWithText(TextFormField, 'Full name');
      expect(social, findsOneWidget);
      expect(email, findsOneWidget);
      expect(usernameForm, findsOneWidget);

      // Social and email options sit above the username/password form.
      expect(
        tester.getTopLeft(social).dy,
        lessThan(tester.getTopLeft(usernameForm).dy),
      );
      expect(
        tester.getTopLeft(email).dy,
        lessThan(tester.getTopLeft(usernameForm).dy),
      );
    },
  );
}
