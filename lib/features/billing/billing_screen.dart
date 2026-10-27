import 'package:flutter/material.dart';

import 'billing_controller.dart';

class BillingScreen extends StatelessWidget {
  const BillingScreen({required this.controller, super.key});
  final BillingController? controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: const Text('구매 및 복원')),
      body: c == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('로그인한 iPhone 또는 Android 기기에서 구매를 확인해 주세요.'),
              ),
            )
          : ListenableBuilder(
              listenable: c,
              builder: (context, _) => SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          '스토어 구매 관리',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '유효한 구매 확인 후 보상과 추가 퀴즈에서 광고 대신 유료 혜택을 직접 선택할 수 있어요. 월별 선물은 아직 제공하지 않아요.',
                        ),
                        const SizedBox(height: 24),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _status(c),
                            key: const ValueKey('billing_status'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (c.busy) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                        ],
                        if (c.errorCode != null) ...[
                          const SizedBox(height: 12),
                          Text(_error(c.errorCode!)),
                        ],
                        const SizedBox(height: 24),
                        for (final product in c.products) ...[
                          Text(
                            product.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(product.description),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            key: ValueKey('billing_buy_${product.id}'),
                            onPressed: c.canBuy ? () => c.buy(product) : null,
                            child: Text('${product.price} · 스토어에서 구매'),
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (c.products.isEmpty && !c.busy)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 24),
                            child: Text(
                              '구매 가능한 상품을 불러오지 못했어요. 가격은 스토어 연결 후 표시됩니다.',
                            ),
                          ),
                        FilledButton(
                          key: const ValueKey('billing_retry'),
                          onPressed: c.busy ? null : c.retry,
                          child: Text(
                            c.errorCode == null ? '구매 상태 새로 확인' : '구매 확인 재시도',
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          key: const ValueKey('billing_restore'),
                          onPressed: c.busy || c.configuration == null
                              ? null
                              : c.restore,
                          child: const Text('스토어 구매 복원'),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '처음 구매한 발맞춤 계정으로 로그인해 주세요.\n구독 변경과 취소는 스토어에서 관리해요.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  String _status(BillingController c) => switch (c.phase) {
    BillingPhase.loading => '상품과 구매 상태를 확인하고 있어요',
    BillingPhase.purchasing => '스토어에서 구매를 진행해 주세요',
    BillingPhase.pending => '스토어 결제 승인을 기다리고 있어요',
    BillingPhase.verifying => '서버에서 구매를 확인하고 있어요',
    BillingPhase.canceled => '구매를 취소했어요',
    BillingPhase.retry => '구매 확인을 다시 진행해 주세요',
    BillingPhase.unavailable => '지금은 스토어 구매를 이용할 수 없어요',
    BillingPhase.ready =>
      c.entitlement?.active == true ? '서버에서 유효한 구매를 확인했어요' : '현재 유효한 구매가 없어요',
  };

  String _error(String code) => switch (code) {
    'acknowledgementPending' =>
      '구매 확인 후 스토어 승인이 남아 있어요.\n아래 재시도 버튼으로 승인을 요청해 주세요.',
    'configurationMissing' => '스토어 상품 설정이 준비되지 않았어요.\n나중에 다시 확인해 주세요.',
    'accountMismatch' ||
    'purchaseUnavailable' => '이 구매를 현재 계정에서 확인할 수 없어요. 처음 구매한 계정으로 로그인해 주세요.',
    'invalidPurchase' => '지원하는 구매인지 확인하지 못했어요. 스토어 계정과 상품을 확인해 주세요.',
    'accountDeleted' => '삭제된 계정에서는 구매를 확인할 수 없어요.',
    'staleObservation' => '다른 구매 확인 요청과 겹쳤어요. 현재 요청이 끝난 뒤 다시 확인해 주세요.',
    'productsUnavailable' => '설정된 상품을 스토어에서 찾지 못했어요. 나중에 다시 시도해 주세요.',
    'purchaseNotActive' =>
      '아직 유효한 결제가 아니어서 승인을 완료하지 않았어요. 스토어 결제 상태를 확인한 뒤 재시도해 주세요.',
    _ => '구매 상태를 확인하지 못했어요.\n연결을 확인하고 다시 시도해 주세요.',
  };
}
