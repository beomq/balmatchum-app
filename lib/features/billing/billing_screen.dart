import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../app/dependencies.dart';
import '../first_meeting/meeting_theme.dart';
import '../first_meeting/onboarding_widgets.dart' show wrapByWords;
import '../records/product_page.dart';
import 'billing_controller.dart';
import 'billing_disclosure.dart';

/// 구매 및 복원 (guide 6.6, no Pen design): the benefit lines, a price card
/// per store product, one purchase button for the chosen product with its
/// terms right under it, and restore beside the legal links at the bottom.
class BillingScreen extends StatefulWidget {
  const BillingScreen({
    required this.controller,
    required this.onBack,
    required this.onHome,
    this.openUrl = openExternalUrl,
    super.key,
  });

  /// Null without a signed-in account or a store. The page then only says
  /// where purchases work: signing in builds a new controller, so the page
  /// has nothing of its own to retry.
  final BillingController? controller;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final Future<bool> Function(Uri url) openUrl;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  /// The product picked among several. Nothing is picked for the user while
  /// the products and the default choice are undecided (guide 9.1 ⑧).
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (c == null) {
      return ProductPage(
        onBack: widget.onBack,
        onHome: widget.onHome,
        children: const [
          _Title(),
          SizedBox(height: Space.s3),
          Text(
            '로그인한 iPhone 또는 Android 기기에서 구매를 확인해 주세요.',
            key: ValueKey('billing_unsupported'),
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => _page(context, c),
    );
  }

  Widget _page(BuildContext context, BillingController c) {
    final products = c.products;
    final choice = products.length > 1;
    // A single product is the purchase itself; among several only a pick.
    final chosen = choice
        ? products.where((p) => p.id == _picked).firstOrNull
        : products.firstOrNull;
    final error = c.errorCode;
    return ProductPage(
      onBack: widget.onBack,
      onHome: widget.onHome,
      footer: (gutter) => _Footer(
        gutter: gutter,
        // Restore needs the store setup and a store that answers.
        restore: c.configuration != null && c.phase != BillingPhase.unavailable,
        onRestore: c.busy ? null : c.restore,
        openUrl: widget.openUrl,
      ),
      children: [
        const _Title(),
        const SizedBox(height: Space.s4),
        const _Benefits(),
        const SizedBox(height: Space.s6),
        if (error != null)
          // A failure is the one state with an action of its own: its cause
          // in one line and one retry, never a new purchase (6.6 ⑤⑥).
          Semantics(
            liveRegion: true,
            child: ProductLoadState(
              error: c.busy ? null : _error(error),
              onRetry: c.retry,
              retryKey: const ValueKey('billing_retry'),
            ),
          )
        else ...[
          for (final product in products) ...[
            _PlanCard(
              key: ValueKey('billing_plan_${product.id}'),
              product: product,
              subscription: _subscription(c, product),
              choice: choice,
              selected: product == chosen,
              // Purchasing, pending and verifying lock the pick as well.
              onTap: choice && c.canBuy
                  ? () => setState(() => _picked = product.id)
                  : null,
            ),
            const SizedBox(height: Space.s3),
          ],
          Semantics(
            liveRegion: true,
            child: Text(_status(c), key: const ValueKey('billing_status')),
          ),
          if (c.busy) ...[
            const SizedBox(height: Space.s2),
            const LinearProgressIndicator(color: MeetingColors.primary),
          ],
          if (products.isNotEmpty) ...[
            const SizedBox(height: Space.s3),
            FilledButton(
              key: ValueKey(
                chosen == null ? 'billing_buy' : 'billing_buy_${chosen.id}',
              ),
              onPressed: chosen != null && c.canBuy
                  ? () => c.buy(chosen)
                  : null,
              child: Text(
                chosen == null
                    ? '구매할 상품을 골라 주세요'
                    : '${chosen.price} · 스토어에서 구매',
              ),
            ),
            const SizedBox(height: Space.s3),
            // Store-required terms of exactly what the button buys.
            if (chosen != null) ...[
              Text(
                billingTerms(
                  subscription: _subscription(c, chosen),
                  price: chosen.price,
                ),
                key: ValueKey('billing_terms_${chosen.id}'),
              ),
              const SizedBox(height: Space.s2),
            ],
            Text(billingRefund),
            const SizedBox(height: Space.s2),
            const Text('처음 구매한 발맞춤 계정으로 로그인해 주세요.\n구독 변경과 취소는 스토어에서 관리해요.'),
          ],
        ],
      ],
    );
  }

  bool _subscription(BillingController c, ProductDetails product) =>
      c.configuration!.products
          .firstWhere((p) => p.productId == product.id)
          .kind ==
      'subscription';

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

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text('구매 및 복원', style: Theme.of(context).textTheme.headlineSmall),
  );
}

/// [billingBenefits], one bulleted line each.
class _Benefits extends StatelessWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s2,
      children: [
        for (final (i, line) in billingBenefits.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: Space.s2,
            children: [
              ExcludeSemantics(
                child: Text(
                  '•',
                  style: style?.copyWith(color: MeetingColors.primary),
                ),
              ),
              Expanded(
                child: Text(
                  wrapByWords(line),
                  key: ValueKey('billing_benefit_$i'),
                  semanticsLabel: line,
                  style: style,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// A price card: the store's title and localized price with the plan's
/// kind. Among several products the cards pick what the button buys, in
/// the selected look of the goal presets.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.product,
    required this.subscription,
    required this.choice,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final ProductDetails product;
  final bool subscription;

  /// One of several cards to pick from.
  final bool choice;
  final bool selected;

  /// Null for a single product and while input is locked.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final kind = billingPlanKind(subscription: subscription);
    return Semantics(
      container: true,
      button: choice,
      enabled: choice ? onTap != null : null,
      selected: choice ? selected : null,
      child: Material(
        color: selected ? MeetingColors.well : MeetingColors.raised,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: selected
              ? const BorderSide(color: MeetingColors.primaryStrong, width: 2)
              : const BorderSide(color: MeetingColors.line),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.s4),
            // The price moves under the plan when a narrow card or large
            // text leaves no room beside it.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.s3,
              runSpacing: Space.s1,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.s1,
                  children: [
                    Text(
                      wrapByWords(product.title),
                      semanticsLabel: product.title,
                      style: text.titleMedium,
                    ),
                    Text(wrapByWords(kind), semanticsLabel: kind),
                  ],
                ),
                Text(
                  billingPlanPrice(
                    subscription: subscription,
                    price: product.price,
                  ),
                  key: ValueKey('billing_price_${product.id}'),
                  style: text.titleLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Restore and the legal links as small text actions: a lower rank, not a
/// smaller target (the theme keeps 44 pt).
class _Footer extends StatelessWidget {
  const _Footer({
    required this.gutter,
    required this.restore,
    required this.onRestore,
    required this.openUrl,
  });
  final double gutter;

  /// Whether restore can run here at all.
  final bool restore;

  /// Null while another store or server request runs.
  final VoidCallback? onRestore;
  final Future<bool> Function(Uri url) openUrl;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      gutter,
      Space.s2,
      gutter,
      Space.s4 + MediaQuery.paddingOf(context).bottom,
    ),
    child: TextButtonTheme(
      data: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: meetingType(14, 20, FontWeight.w700),
        ).merge(Theme.of(context).textButtonTheme.style),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (restore)
            TextButton(
              key: const ValueKey('billing_restore'),
              onPressed: onRestore,
              child: const Text('스토어 구매 복원'),
            ),
          BillingLinks(openUrl: openUrl),
        ],
      ),
    ),
  );
}
