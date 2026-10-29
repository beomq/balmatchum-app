import 'package:balmatchum_app/features/billing/billing_controller.dart';
import 'package:balmatchum_app/features/billing/billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_fakes.dart';

const _policy = 'https://beomq.github.io/balmatchum-legal/privacy-policy.html';
const _eula =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
const _appleManage = 'https://apps.apple.com/account/subscriptions';
const _googleManage =
    'https://play.google.com/store/account/subscriptions?package=com.beomq.balmatchum';

const _appleRenewal =
    '현재 기간이 끝나기 최소 24시간 전에 자동 갱신을 끄지 않으면 구독이 갱신돼요. '
    '갱신 요금은 현재 기간이 끝나기 전 24시간 이내에 Apple 계정으로 청구돼요. '
    '설정 > 사용자 이름 > 구독에서 관리하거나 해지할 수 있어요.';
const _googleRenewal =
    '해지하기 전까지 매월 자동으로 갱신되고 Google Play 계정으로 청구돼요. '
    'Google Play 스토어 > 결제 및 구독 > 구독에서 언제든 해지할 수 있어요.';
const _lifetime = '한 번만 결제하는 평생 이용 상품이에요. 다시 청구되지 않아요.';
const _benefit =
    '구매하면 보상과 추가 퀴즈에서 광고를 보지 않고 바로 받을 수 있어요. '
    '하루 받을 수 있는 횟수는 광고를 볼 때와 같아요. 월별 선물은 아직 제공하지 않아요.';

final _monthly = ProductDetails(
  id: 'test.monthly',
  title: '테스트 월간 구독',
  description: '로컬 QA 상품, 실제 판매 아님',
  price: '₩1,100',
  rawPrice: 1100,
  currencyCode: 'KRW',
);

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);
final _android = TargetPlatformVariant.only(TargetPlatform.android);

Future<BillingController> _pump(
  WidgetTester tester,
  Future<bool> Function(Uri) openUrl,
) async {
  // Tall enough that every disclosure and link is on screen.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final sdk = FakeBillingStore()..catalog = [product(), _monthly];
  final c = BillingController(
    repository: FakeBillingRepository(),
    store: sdk,
    isCurrent: () => true,
  );
  await c.ready;
  await tester.pumpWidget(
    MaterialApp(
      home: BillingScreen(
        controller: c,
        openUrl: openUrl,
        onBack: () {},
        onHome: () {},
      ),
    ),
  );
  return c;
}

/// Terms show for the picked product only; nothing is picked among several.
Future<void> _pick(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('billing_plan_$id')));
  await tester.pump();
}

/// The benefit lines as read aloud, in order, as one paragraph.
String _benefits(WidgetTester tester) => [
  for (var i = 0; i < 3; i++)
    tester
        .widget<Text>(find.byKey(ValueKey('billing_benefit_$i')))
        .semanticsLabel,
].join(' ');

Future<void> _done(WidgetTester tester, BillingController c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
}

Future<List<Uri>> _tapLinks(WidgetTester tester, List<String> keys) async {
  final opened = <Uri>[];
  final c = await _pump(tester, (url) async {
    opened.add(url);
    return true;
  });
  final result = <Uri>[];
  for (final key in keys) {
    final link = find.byKey(ValueKey(key));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();
    result.add(opened.single);
    opened.clear();
  }
  await _done(tester, c);
  return result;
}

void main() {
  testWidgets('iOS monthly states Apple renewal and cancellation terms', (
    tester,
  ) async {
    final c = await _pump(tester, (_) async => true);
    await _pick(tester, 'test.monthly');
    expect(
      find.text('1개월 자동 갱신 구독 · 매월 ₩1,100\n$_appleRenewal'),
      findsOneWidget,
    );
    expect(find.textContaining('Google Play'), findsNothing);
    await _done(tester, c);
  }, variant: _ios);

  testWidgets('Android monthly states Google Play renewal and cancellation', (
    tester,
  ) async {
    final c = await _pump(tester, (_) async => true);
    await _pick(tester, 'test.monthly');
    expect(
      find.text('1개월 자동 갱신 구독 · 매월 ₩1,100\n$_googleRenewal'),
      findsOneWidget,
    );
    expect(find.textContaining('Apple'), findsNothing);
    await _done(tester, c);
  }, variant: _android);

  testWidgets(
    'lifetime is a one-time purchase without renewal wording',
    (tester) async {
      final c = await _pump(tester, (_) async => true);
      await _pick(tester, 'test.lifetime');
      final terms = tester.widget<Text>(
        find.byKey(const ValueKey('billing_terms_test.lifetime')),
      );
      expect(terms.data, '한 번 결제 · €12,34\n$_lifetime');
      expect(terms.data, isNot(contains('갱신')));
      await _done(tester, c);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('iOS shows the benefit and App Store refund lines', (
    tester,
  ) async {
    final c = await _pump(tester, (_) async => true);
    expect(_benefits(tester), _benefit);
    expect(find.text('결제 취소와 환불은 App Store 환불 정책을 따라요.'), findsOneWidget);
    expect(find.textContaining('광고 제거'), findsNothing);
    await _done(tester, c);
  }, variant: _ios);

  testWidgets('Android shows the benefit and Google Play refund lines', (
    tester,
  ) async {
    final c = await _pump(tester, (_) async => true);
    expect(_benefits(tester), _benefit);
    expect(find.text('결제 취소와 환불은 Google Play 환불 정책을 따라요.'), findsOneWidget);
    await _done(tester, c);
  }, variant: _android);

  testWidgets('iOS links open the EULA, policy and Apple subscriptions', (
    tester,
  ) async {
    final opened = await _tapLinks(tester, [
      'billing_terms_of_use',
      'billing_privacy_policy',
      'billing_manage_subscription',
    ]);
    expect(opened, [
      Uri.parse(_eula),
      Uri.parse(_policy),
      Uri.parse(_appleManage),
    ]);
  }, variant: _ios);

  testWidgets('Android links open the policy and Play subscriptions only', (
    tester,
  ) async {
    final opened = await _tapLinks(tester, [
      'billing_privacy_policy',
      'billing_manage_subscription',
    ]);
    expect(opened, [Uri.parse(_policy), Uri.parse(_googleManage)]);
    expect(find.byKey(const ValueKey('billing_terms_of_use')), findsNothing);
  }, variant: _android);

  testWidgets('a link the launcher cannot open shows a notice', (tester) async {
    final c = await _pump(
      tester,
      (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );
    final link = find.byKey(const ValueKey('billing_manage_subscription'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();
    expect(find.text('링크를 열지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _done(tester, c);
  }, variant: _ios);
}
