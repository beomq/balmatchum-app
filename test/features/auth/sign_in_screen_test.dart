import 'dart:async';

import 'package:balmatchum_app/app/router.dart';
import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/bootstrap/presentation/bootstrap_screen.dart';
import 'package:balmatchum_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

class _Starter implements SignInStarter {
  _Starter(this.callback);

  final Future<SignInOutcome> Function(SignInProvider) callback;

  @override
  Future<SignInOutcome> start(SignInProvider provider) => callback(provider);
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    SignInStarter starter, {
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: SignInScreen(starter: starter),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Android hides the unsupported Apple button', (tester) async {
    await mount(
      tester,
      const NotConnectedSignInStarter(),
      platform: TargetPlatform.android,
    );
    final list = tester.widget<SocialButtonList>(find.byType(SocialButtonList));
    expect(list.items.map((item) => item.social), [
      Social.google,
      Social.kakao,
      Social.naver,
    ]);
    expect(find.byType(TextButton), findsNWidgets(3));
  });

  testWidgets('iOS keeps the Apple button', (tester) async {
    await mount(tester, const NotConnectedSignInStarter());
    final list = tester.widget<SocialButtonList>(find.byType(SocialButtonList));
    expect(list.items.map((item) => item.social), contains(Social.apple));
    expect(find.byType(TextButton), findsNWidgets(4));
  });

  testWidgets('completed Kakao outcomes expose status without leaving login', (
    tester,
  ) async {
    for (final outcome in [
      SignInOutcome.signedIn,
      SignInOutcome.cancelled,
      SignInOutcome.failed('invalidToken'),
    ]) {
      await mount(tester, _Starter((_) async => outcome));
      await tester.tap(find.text('카카오 로그인'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            outcome.status == SignInStatus.failed
                ? 'sign_in_error'
                : 'sign_in_status',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('로그인 연결 전'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('requested provider assets and inherited styles render equally', (
    tester,
  ) async {
    await mount(tester, const NotConnectedSignInStarter());
    final list = tester.widget<SocialButtonList>(find.byType(SocialButtonList));
    expect(list.items.map((item) => item.social), [
      Social.google,
      Social.apple,
      Social.kakao,
      Social.naver,
    ]);
    expect(list.items.map((item) => item.logo), [
      'assets/social/google.png',
      'assets/social/apple.png',
      'assets/social/kakao.png',
      'assets/social/naver.png',
    ]);
    expect(list.shape, SocialButtonShape.rounded);
    expect(list.appearance, SocialButtonAppearance.light);
    expect(list.locale, const Locale('ko'));
    expect(list.spacing, 12);
    expect(list.size, 56);
    expect(list.items.map((item) => item.appearance), [
      SocialButtonAppearance.light,
      SocialButtonAppearance.providerDefault,
      SocialButtonAppearance.providerDefault,
      SocialButtonAppearance.light,
    ]);
    final sizes = find
        .byType(TextButton)
        .evaluate()
        .map((element) => tester.getSize(find.byWidget(element.widget)));
    expect(sizes.toSet(), hasLength(1));
    expect(sizes.first.height, 56);
    final kakao = tester.widget<TextButton>(
      find.descendant(
        of: find.byWidget(list.items[2]),
        matching: find.byType(TextButton),
      ),
    );
    expect(kakao.style!.backgroundColor!.resolve({}), const Color(0xFFFEE500));
    expect(kakao.style!.foregroundColor!.resolve({}), const Color(0xD9000000));
    expect(tester.takeException(), isNull);
  });

  for (final provider in SignInProvider.values) {
    testWidgets(
      '${provider.name} dispatch disables all buttons until outcome',
      (tester) async {
        final response = Completer<SignInOutcome>();
        final calls = <SignInProvider>[];
        await mount(
          tester,
          _Starter((value) {
            calls.add(value);
            return response.future;
          }),
        );
        expect(calls, isEmpty);
        await tester.tap(find.byType(TextButton).at(provider.index));
        await tester.pump();
        expect(calls, [provider]);
        expect(
          tester
              .widgetList<SocialButton>(find.byType(SocialButton))
              .every((button) => button.onPressed == null),
          isTrue,
        );
        await tester.tap(find.byType(TextButton).first);
        expect(calls, [provider]);
        response.complete(SignInOutcome.notConnected);
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<SocialButton>(find.byType(SocialButton))
              .every((button) => button.onPressed != null),
          isTrue,
        );
        expect(find.byKey(const ValueKey('sign_in_error')), findsNothing);
        expect(find.byType(SignInScreen), findsOneWidget);
      },
    );
  }

  test(
    'default boundary explicitly reports not connected for every provider',
    () async {
      for (final provider in SignInProvider.values) {
        expect(
          await const NotConnectedSignInStarter().start(provider),
          SignInOutcome.notConnected,
        );
      }
    },
  );

  testWidgets('error permits retry and late completion is safely ignored', (
    tester,
  ) async {
    final response = Completer<SignInOutcome>();
    var calls = 0;
    await mount(
      tester,
      _Starter((_) {
        calls++;
        if (calls == 1) return Future.error(Exception('offline'));
        return response.future;
      }),
    );
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign_in_error')), findsOneWidget);
    await tester.tap(find.byType(TextButton).first);
    await tester.pump();
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    response.completeError(Exception('disconnected'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('router injects starter at root and preserves greeting route', (
    tester,
  ) async {
    final calls = <SignInProvider>[];
    final container = ProviderContainer(
      overrides: [
        signInStarterProvider.overrideWithValue(
          _Starter((provider) async {
            calls.add(provider);
            return SignInOutcome.notConnected;
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    expect(calls, [SignInProvider.naver]);
    container.read(routerProvider).go('/greeting');
    await tester.pumpAndSettle();
    expect(find.byType(BootstrapScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('small viewport with large text remains scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const SignInScreen(starter: NotConnectedSignInStarter()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextButton).last);
    expect(tester.takeException(), isNull);
  });
}
