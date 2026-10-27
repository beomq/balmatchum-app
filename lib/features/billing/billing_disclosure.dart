import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/dependencies.dart';

// Store-required purchase disclosures (App Store Schedule 2 §3.8(b) and
// Guideline 3.1.2, Google Play Subscriptions policy). The copy follows the
// running platform's store; tests override defaultTargetPlatform.
bool get _apple => defaultTargetPlatform == TargetPlatform.iOS;

const billingBenefit =
    '구매하면 보상과 추가 퀴즈에서 광고를 보지 않고 바로 받을 수 있어요. '
    '하루 받을 수 있는 횟수는 광고를 볼 때와 같아요. 월별 선물은 아직 제공하지 않아요.';

String get billingRefund =>
    '결제 취소와 환불은 ${_apple ? 'App Store' : 'Google Play'} 환불 정책을 따라요.';

String billingTerms({required bool subscription, required String price}) {
  if (!subscription) {
    return '한 번 결제 · $price\n한 번만 결제하는 평생 이용 상품이에요. 다시 청구되지 않아요.';
  }
  final renewal = _apple
      ? '현재 기간이 끝나기 최소 24시간 전에 자동 갱신을 끄지 않으면 구독이 갱신돼요. '
            '갱신 요금은 현재 기간이 끝나기 전 24시간 이내에 Apple 계정으로 청구돼요. '
            '설정 > 사용자 이름 > 구독에서 관리하거나 해지할 수 있어요.'
      : '해지하기 전까지 매월 자동으로 갱신되고 Google Play 계정으로 청구돼요. '
            'Google Play 스토어 > 결제 및 구독 > 구독에서 언제든 해지할 수 있어요.';
  return '1개월 자동 갱신 구독 · 매월 $price\n$renewal';
}

class BillingLinks extends StatelessWidget {
  const BillingLinks({required this.openUrl, super.key});
  final Future<bool> Function(Uri url) openUrl;

  Future<void> _open(BuildContext context, String url) async {
    bool opened;
    try {
      opened = await openUrl(Uri.parse(url));
    } on PlatformException {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same per-flavor application ID the Naver redirect uses.
    final package = 'com.beomq.balmatchum${appFlavor == 'dev' ? '.dev' : ''}';
    final links = [
      if (_apple)
        (
          'billing_terms_of_use',
          '이용약관(EULA)',
          'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
        ),
      ('billing_privacy_policy', '개인정보처리방침', privacyPolicyUrl),
      (
        'billing_manage_subscription',
        '구독 관리',
        _apple
            ? 'https://apps.apple.com/account/subscriptions'
            : 'https://play.google.com/store/account/subscriptions?package=$package',
      ),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final (key, label, url) in links)
          TextButton(
            key: ValueKey(key),
            onPressed: () => _open(context, url),
            child: Text(label),
          ),
      ],
    );
  }
}
