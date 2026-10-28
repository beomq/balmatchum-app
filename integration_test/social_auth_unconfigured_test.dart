import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native sign-in screen rejects missing OAuth config without SDK UI',
    (tester) async {
      expect(serverUrl, isEmpty);
      // The dev flavor intentionally boots the first-meeting preview. Mount the
      // authenticated surface with its real provider rather than testing preview
      // routing as if it were the production entry point.
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, child) => MaterialApp(
              home: SignInScreen(starter: ref.watch(signInStarterProvider)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      final context = tester.element(find.byType(SignInScreen));
      final container = ProviderScope.containerOf(context);
      expect(container.read(authenticatedAccountProvider), isNull);
      await tester.tap(find.byKey(const ValueKey('sign_in_age_confirmation')));
      await tester.pumpAndSettle();
      // A provider's button by its brand, never by its place in the list.
      Finder button(SignInProvider provider) => find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is SocialButton && widget.social.name == provider.name,
        ),
        matching: find.byType(TextButton),
      );
      for (final provider in [
        SignInProvider.google,
        SignInProvider.apple,
        SignInProvider.naver,
      ]) {
        await tester.ensureVisible(button(provider));
        await tester.tap(button(provider));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sign_in_error')), findsOneWidget);
        expect(find.byType(SignInScreen), findsOneWidget);
        expect(container.read(authenticatedAccountProvider), isNull);
        expect(
          tester
              .widgetList<SocialButton>(find.byType(SocialButton))
              .every((button) => button.onPressed != null),
          isTrue,
        );
        await binding.takeScreenshot('auth-${provider.name}-unconfigured');
      }
      await tester.ensureVisible(button(SignInProvider.kakao));
      await tester.tap(button(SignInProvider.kakao));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sign_in_status')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
