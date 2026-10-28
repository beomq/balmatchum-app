import 'dart:async';

import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/app/router.dart';
import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/bootstrap/presentation/bootstrap_screen.dart';
import 'package:balmatchum_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

import '../../support/duo_viewports.dart';

class _Starter implements SignInStarter {
  _Starter(this.callback);

  final Future<SignInOutcome> Function(SignInProvider) callback;

  @override
  Future<SignInOutcome> start(SignInProvider provider) => callback(provider);
}

// Provider buttons only; the privacy link is also a TextButton.
final _social = find.descendant(
  of: find.byType(SocialButtonList),
  matching: find.byType(TextButton),
);
final _age = find.byKey(const ValueKey('sign_in_age_confirmation'));
const _ageRequired = '만 14세 이상인지 확인해 주세요.';
const _policy = 'https://beomq.github.io/balmatchum-legal/privacy-policy.html';
const _policyFailure = '개인정보처리방침을 열지 못했어요. 잠시 후 다시 시도해 주세요.';

void main() {
  Future<void> mount(
    WidgetTester tester,
    SignInStarter starter, {
    TargetPlatform platform = TargetPlatform.iOS,
    bool confirmAge = true,
    Future<bool> Function(Uri url)? openUrl,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: openUrl == null
            ? SignInScreen(starter: starter)
            : SignInScreen(starter: starter, openUrl: openUrl),
      ),
    );
    await tester.pumpAndSettle();
    // Remounting in a loop keeps the state, so only tap an unchecked box.
    if (confirmAge && !tester.widget<CheckboxListTile>(_age).value!) {
      await tester.tap(_age);
      await tester.pumpAndSettle();
    }
  }

  for (final provider in SignInProvider.values) {
    testWidgets('${provider.name} tap before age confirmation starts nothing', (
      tester,
    ) async {
      final calls = <SignInProvider>[];
      await mount(
        tester,
        _Starter((value) async {
          calls.add(value);
          return SignInOutcome.notConnected;
        }),
        confirmAge: false,
      );
      await tester.tap(_social.at(provider.index));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text(_ageRequired), findsOneWidget);
      // Brand guidelines: the official buttons stay enabled, never greyed.
      expect(
        tester
            .widgetList<SocialButton>(find.byType(SocialButton))
            .every((button) => button.onPressed != null),
        isTrue,
      );
    });

    testWidgets('${provider.name} tap after age confirmation starts sign-in', (
      tester,
    ) async {
      final calls = <SignInProvider>[];
      await mount(
        tester,
        _Starter((value) async {
          calls.add(value);
          return SignInOutcome.notConnected;
        }),
        confirmAge: false,
      );
      await tester.tap(_social.at(provider.index));
      await tester.pumpAndSettle();
      await tester.tap(_age);
      await tester.pumpAndSettle();
      expect(find.text(_ageRequired), findsNothing);
      await tester.tap(_social.at(provider.index));
      await tester.pumpAndSettle();
      expect(calls, [provider]);
    });
  }

  testWidgets('age confirmation is required again after unchecking', (
    tester,
  ) async {
    final calls = <SignInProvider>[];
    await mount(
      tester,
      _Starter((value) async {
        calls.add(value);
        return SignInOutcome.notConnected;
      }),
    );
    await tester.tap(_age);
    await tester.pumpAndSettle();
    await tester.tap(_social.first);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text(_ageRequired), findsOneWidget);
  });

  testWidgets('privacy policy link opens the published policy URL', (
    tester,
  ) async {
    final opened = <Uri>[];
    await mount(
      tester,
      const NotConnectedSignInStarter(),
      confirmAge: false,
      openUrl: (url) async {
        opened.add(url);
        return true;
      },
    );
    await tester.tap(find.byKey(const ValueKey('sign_in_privacy_policy')));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(_policy)]);
    expect(find.text(_policyFailure), findsNothing);
  });

  testWidgets('privacy policy link reports a launcher failure', (tester) async {
    await mount(
      tester,
      const NotConnectedSignInStarter(),
      confirmAge: false,
      openUrl: (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );
    await tester.tap(find.byKey(const ValueKey('sign_in_privacy_policy')));
    await tester.pumpAndSettle();
    expect(find.text(_policyFailure), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(_social, findsNWidgets(3));
  });

  testWidgets('iOS keeps the Apple button', (tester) async {
    await mount(tester, const NotConnectedSignInStarter());
    final list = tester.widget<SocialButtonList>(find.byType(SocialButtonList));
    expect(list.items.map((item) => item.social), contains(Social.apple));
    expect(_social, findsNWidgets(4));
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
    final sizes = _social.evaluate().map(
      (element) => tester.getSize(find.byWidget(element.widget)),
    );
    expect(sizes.toSet(), hasLength(1));
    expect(sizes.first.height, 56);
    final kakao = tester.widget<TextButton>(
      find.descendant(of: find.byWidget(list.items[2]), matching: _social),
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
        await tester.tap(_social.at(provider.index));
        await tester.pump();
        expect(calls, [provider]);
        expect(
          tester
              .widgetList<SocialButton>(find.byType(SocialButton))
              .every((button) => button.onPressed == null),
          isTrue,
        );
        await tester.tap(_social.first);
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
    await tester.tap(_social.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign_in_error')), findsOneWidget);
    await tester.tap(_social.first);
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
    await tester.tap(_age);
    await tester.pumpAndSettle();
    await tester.tap(_social.last);
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
    await tester.ensureVisible(_social.last);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duo outer panel paints an empty side rail', (tester) async {
    // Given the measured iPhone Duo outer panel.
    useDuoViewport(tester, 'outer portrait');
    // When the sign-in screen is shown.
    await tester.pumpWidget(
      duoHost(const SignInScreen(starter: NotConnectedSignInStarter())),
    );
    await tester.pumpAndSettle();
    // Then the side column is painted with no rail button, beside the form.
    expectEmptyDuoRail(tester);
    expect(tester.getRect(_age).right, lessThanOrEqualTo(382));
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal iPhone sign-in has no side rail', (tester) async {
    // Given an ordinary iPhone safe area.
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
    addTearDown(tester.view.reset);
    // When the sign-in screen is shown.
    await tester.pumpWidget(
      duoHost(const SignInScreen(starter: NotConnectedSignInStarter())),
    );
    await tester.pumpAndSettle();
    // Then no rail or side column is drawn.
    expect(find.byType(DuoRail), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
