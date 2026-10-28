import 'package:flutter/material.dart';

import '../ads/ads_controller.dart';
import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart' show Space, formatCount;
import '../records/records_models.dart';
import '../records/status_widgets.dart';
import '../wardrobe/dog_sprite.dart';
import 'product_controller.dart';
import 'product_repository.dart';
import 'record_mapping.dart';
import 'reward_panel.dart';

/// Today's points over the home: REW-01 (`lJDCD`), then REW-02 (`BQ3Wd`)
/// once a grant is confirmed. Completes with true when the user chose the
/// wardrobe; the home navigates after this sheet is gone.
Future<bool> showTodayRewardSheet(
  BuildContext context, {
  required ProductController product,
  required RecordDay day,
  required String dogAsset,
  String? dogLayer,
  bool canOpenWardrobe = true,
  Future<AdsController?> Function()? createAds,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // The 28 pt corner belongs to this sheet only (guide 5.2).
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => TodayRewardSheet(
        product: product,
        day: day,
        dogAsset: dogAsset,
        dogLayer: dogLayer,
        canOpenWardrobe: canOpenWardrobe,
        createAds: createAds,
      ),
    ) ??
    false;

class TodayRewardSheet extends StatefulWidget {
  const TodayRewardSheet({
    required this.product,
    required this.day,
    required this.dogAsset,
    this.dogLayer,
    this.canOpenWardrobe = true,
    this.createAds,
    super.key,
  });
  final ProductController product;
  final RecordDay day;

  /// The home's companion: the chosen breed and its confirmed worn layer.
  final String dogAsset;
  final String? dogLayer;
  final bool canOpenWardrobe;
  final Future<AdsController?> Function()? createAds;

  @override
  State<TodayRewardSheet> createState() => _TodayRewardSheetState();
}

class _TodayRewardSheetState extends State<TodayRewardSheet> {
  late RecordDay day = widget.day;

  /// The amount of the grant this sheet received; only a confirmed claim
  /// sets it, so reopening never celebrates an earlier grant again.
  int? granted;
  bool rulesOpen = false;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, Space.s3, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MeetingColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: Space.s3),
          Row(
            children: [
              // Large text wraps the title; the close button stays put.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '오늘 포인트',
                        style: meetingType(18, 24, FontWeight.w800),
                      ),
                    ),
                    if (granted == null)
                      IconButton(
                        key: const ValueKey('reward_info'),
                        tooltip: '받는 방법',
                        onPressed: () => setState(() => rulesOpen = !rulesOpen),
                        icon: const Icon(
                          Icons.info_outline,
                          color: MeetingColors.ink,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('reward_close'),
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(false),
                style: IconButton.styleFrom(
                  fixedSize: const Size(44, 44),
                  side: const BorderSide(color: MeetingColors.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.close, color: MeetingColors.ink),
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          if (granted case final amount?)
            _Granted(
              amount: amount,
              date: ProductRepository.dateKey(widget.day.date),
              product: widget.product,
              dogAsset: widget.dogAsset,
              dogLayer: widget.dogLayer,
              canOpenWardrobe: widget.canOpenWardrobe,
            )
          else ...[
            if (rulesOpen) ...[
              Container(
                key: const ValueKey('reward_rules'),
                padding: const EdgeInsets.all(Space.s3),
                decoration: BoxDecoration(
                  color: MeetingColors.pressed,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.s1,
                  children: [for (final line in rewardRules(day)) Text(line)],
                ),
              ),
              const SizedBox(height: Space.s3),
            ],
            RewardPanel(
              controller: widget.product,
              day: widget.day,
              createAds: widget.createAds,
              showRules: false,
              onChanged: (value) => setState(() => day = value),
              onGranted: (amount) => setState(() => granted = amount),
            ),
          ],
        ],
      ),
    ),
  );
}

/// REW-02: the grant just received, the server's new balance and the way
/// back. The amount is the claim's answer, never the day's running total.
class _Granted extends StatelessWidget {
  const _Granted({
    required this.amount,
    required this.date,
    required this.product,
    required this.dogAsset,
    required this.dogLayer,
    required this.canOpenWardrobe,
  });
  final int amount;

  /// The claimed day; a record of another day says nothing about its rest.
  final String date;
  final ProductController product;
  final String dogAsset;
  final String? dogLayer;
  final bool canOpenWardrobe;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: product,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final wallet = product.wallet;
      // The refreshed record tells whether a part is still left to receive.
      bool? left;
      if (product.today case final today? when today.date == date) {
        try {
          left = hasRewardLeft(recordDay(today));
        } on FormatException {
          left = null;
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox.square(
              dimension: 96,
              child: DogSprite(
                asset: dogAsset,
                layer: dogLayer,
                spriteKey: const ValueKey('reward_granted_dog'),
              ),
            ),
          ),
          const SizedBox(height: Space.s3),
          Semantics(
            liveRegion: true,
            child: Text(
              '${formatCount(amount)}P 받았어요!',
              key: const ValueKey('reward_granted_title'),
              textAlign: TextAlign.center,
              style: meetingType(26, 32, FontWeight.w800),
            ),
          ),
          const SizedBox(height: Space.s3),
          // The new balance is the server's, never the old one plus amount.
          if (wallet != null)
            Center(
              child: StatusChip(
                '보유 ${formatCount(wallet.balance)}P',
                textKey: const ValueKey('reward_granted_balance'),
              ),
            )
          else ...[
            Text(
              '받은 포인트는 그대로예요. 보유 포인트를 아직 확인하지 못했어요.',
              key: const ValueKey('reward_balance_unknown'),
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            // Reads only: the grant itself is never sent again.
            TextButton(
              key: const ValueKey('reward_balance_retry'),
              onPressed: product.busy ? null : product.connect,
              child: const Text('다시 불러오기'),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('reward_done'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('확인'),
          ),
          if (canOpenWardrobe) ...[
            const SizedBox(height: Space.s3),
            OutlinedButton(
              key: const ValueKey('reward_open_wardrobe'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('꾸미기 보러 가기'),
            ),
          ],
          if (left != null) ...[
            const SizedBox(height: Space.s3),
            Text(
              left ? '남은 포인트가 있어요. 다시 열면 이어서 받을 수 있어요' : '내일도 걸으면 다시 받을 수 있어요',
              // A partial grant and a settled day are different states.
              key: ValueKey(
                left ? 'reward_granted_left' : 'reward_granted_done',
              ),
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        ],
      );
    },
  );
}
