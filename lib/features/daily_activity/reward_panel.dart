import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';

import '../ads/ads_controller.dart';
import '../ads/ads_session.dart';
import '../ads/ads_sheet.dart';
import '../records/product_page.dart' show fixtureLabelsVisible, formatCount;
import '../records/records_models.dart';
import 'product_controller.dart';
import 'product_repository.dart';

/// Both home and past-day detail use the same server projection and actions.
class RewardPanel extends StatefulWidget {
  const RewardPanel({
    super.key,
    required this.controller,
    required this.day,
    this.onChanged,
    this.createAds,
  });
  final ProductController controller;
  final RecordDay day;
  final ValueChanged<RecordDay>? onChanged;
  final Future<AdsController?> Function()? createAds;

  @override
  State<RewardPanel> createState() => _RewardPanelState();
}

class _RewardPanelState extends State<RewardPanel> {
  late RecordDay day = widget.day;
  String? verifiedIntent;
  String? notice;
  bool busy = false;
  bool needsReload = false;

  /// The automatic paid-benefit observation failed; only then is its retry
  /// shown (guide 3.1).
  bool premiumFailed = false;
  bool get active => mounted && widget.controller.isActive;

  @override
  void initState() {
    super.initState();
    // Not during this build: observing notifies the shared controller, whose
    // listeners include the home under this sheet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) autoCheckPremium();
    });
  }

  /// Observes the paid benefit while the day offers the ad path and no fresh
  /// observation exists, so a paid user sees the paid claim without asking.
  /// Only a billing connection can observe, and observing never claims.
  void autoCheckPremium() {
    if (_offersAd(day) &&
        widget.controller.repository.billing != null &&
        widget.controller.premiumActive == null &&
        !premiumFailed) {
      unawaited(checkPremium());
    }
  }

  @override
  void didUpdateWidget(RewardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day.revision != widget.day.revision ||
        oldWidget.day.date != widget.day.date) {
      if (widget.controller.hasPendingClaim) return;
      day = widget.day;
      verifiedIntent = null;
    }
  }

  Future<void> reload() async {
    final fresh = await widget.controller.loadDay(day.date);
    if (!active) return;
    setState(() {
      day = fresh;
      verifiedIntent = null;
      needsReload = false;
    });
    widget.onChanged?.call(fresh);
  }

  Future<void> watchAd() async {
    if (busy || !active || !widget.controller.beginAd()) return;
    setState(() => busy = true);
    AdsController? ads;
    String? captured;
    void capture() {
      final intent = ads?.intent;
      if (active &&
          ads?.status == AdsStatus.verified &&
          intent?.targetDate == ProductRepository.dateKey(day.date) &&
          intent?.targetRevision == day.revision) {
        captured = intent!.id;
      }
    }

    try {
      ads =
          await (widget.createAds?.call() ??
              createAdsController(widget.controller.repository.client));
      if (!mounted || !widget.controller.isActive || ads == null) return;
      ads.addListener(capture);
      await showAdsSheet(
        context,
        controller: ads,
        purpose: 'dailyReward',
        targetDate: ProductRepository.dateKey(day.date),
        targetRevision: day.revision,
      );
      // showAdsSheet cancels on close. Only the earlier verified event counts.
      if (active) setState(() => verifiedIntent = captured);
    } catch (_) {
      if (active) setState(() => notice = '광고 확인을 완료하지 못했어요. 다시 시도해 주세요.');
    } finally {
      ads?.removeListener(capture);
      ads?.dispose();
      widget.controller.endAd();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> checkPremium() async {
    if (busy || !widget.controller.canClaim) return;
    setState(() {
      busy = true;
      notice = null;
      premiumFailed = false;
    });
    var observed = false;
    try {
      await widget.controller.checkPremium();
      observed = true;
      if (active) {
        setState(() => needsReload = true);
        await reload();
      }
    } catch (_) {
      if (active) {
        setState(() {
          // A reload failing after a good observation keeps its own retry.
          premiumFailed = !observed;
          notice = '유료 혜택을 확인하지 못했어요. 다시 확인해 주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> claim({
    bool withAd = false,
    bool premium = false,
    bool replay = false,
  }) async {
    if (busy || !active) return;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final amount = replay
          ? await widget.controller.retryClaim()
          : premium
          ? await widget.controller.claimWithPremium(day)
          : withAd
          ? await widget.controller.claimWithAd(day, verifiedIntent!)
          : await widget.controller.claim(day);
      if (!active) return;
      setState(() {
        notice = '$amount포인트를 받았어요.';
        verifiedIntent = null;
        needsReload = true;
      });
      try {
        await reload();
      } catch (_) {
        if (active) {
          setState(() => notice = '$amount포인트를 받았어요. 남은 보상은 다시 조회해 주세요.');
        }
      }
    } on ProductException catch (e) {
      if (!active) return;
      setState(() {
        verifiedIntent = null;
        needsReload = true;
        notice = switch (e.code) {
          'adRequired' => '무료 유예가 끝났어요. 남은 포인트는 광고 확인 후 받을 수 있어요.',
          'legacyPolicyExcluded' => '이 기록은 이전 테스트 정책으로 운영 보상 대상이 아니에요.',
          'staleProjection' => '기록이 변경됐어요. 최신 금액을 확인하고 다시 선택해 주세요.',
          'nothingToClaim' => '현재 추가로 받을 포인트가 없어요.',
          'dayDeleted' => '삭제된 기록의 미수령 포인트는 받을 수 없어요.',
          'futureDate' => '미래 날짜의 포인트는 받을 수 없어요.',
          _ => '수령할 수 없는 상태예요. 최신 기록을 확인해 주세요.',
        };
      });
      try {
        await reload();
      } catch (_) {
        if (active) setState(() => needsReload = true);
      }
    } on BillingException catch (e) {
      if (active) {
        setState(
          () => notice = widget.controller.hasPendingClaim
              ? '구매 확인을 완료하지 못했어요. 같은 요청으로 다시 확인해 주세요.'
              : e.code == 'entitlementInactive'
              ? '현재 유효한 구매가 없어요. 무료 또는 광고 수령을 선택할 수 있어요.'
              : '구매 확인을 완료하지 못했어요. 유료 혜택을 다시 확인해 주세요.',
        );
      }
    } catch (_) {
      // Keep the original date/revision/intent and request id after response loss.
      if (active) {
        setState(() => notice = '수령 결과를 확인하지 못했어요. 같은 요청으로 다시 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    // Every settled claim clears the observation; the next paid claim needs
    // a fresh one.
    if (active) autoCheckPremium();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final enabled =
          !busy && widget.controller.canClaim && active && !needsReload;
      final free =
          day.rewardStatus == DayRewardStatus.claimable &&
          (day.claimablePoints ?? 0) > 0;
      final ad = _offersAd(day);
      final premium = ad && widget.controller.premiumActive == true;
      final freePoints = formatCount(day.claimablePoints ?? 0);
      final adPoints = formatCount(day.adClaimablePoints ?? 0);
      // One primary button (guide 3.3): the first available claim leads and
      // the other claims step down to outlined buttons.
      final primary = widget.controller.hasPendingClaim
          ? null
          : free
          ? 'free'
          : premium
          ? 'premium'
          : 'ad';
      Widget claimButton(
        String role, {
        required Key key,
        required VoidCallback? onPressed,
        required String label,
      }) => role == primary
          ? FilledButton(key: key, onPressed: onPressed, child: Text(label))
          : OutlinedButton(key: key, onPressed: onPressed, child: Text(label));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(switch (day.rewardStatus) {
            DayRewardStatus.pending => '걸음이 확정되면 받을 수 있어요.',
            DayRewardStatus.claimable =>
              '무료 수령은 유예 중인 구간만 받을 수 있어요. 만료된 구간은 광고 대상으로 남아요.',
            DayRewardStatus.adRequired =>
              '무료 유예가 끝났어요. 미수령 포인트는 광고 확인 후 받을 수 있어요.',
            DayRewardStatus.paid => '현재 추가로 받을 포인트가 없어요.',
            DayRewardStatus.legacyPolicyExcluded =>
              '이전 테스트 정책 기록으로 운영 보상 대상이 아니에요.',
            DayRewardStatus.futureDate => '미래 날짜의 기록이에요.',
            DayRewardStatus.canceled => '삭제로 미수령 포인트가 취소됐어요.',
            DayRewardStatus.expired => '무료 수령 기간이 지났어요.',
            DayRewardStatus.unconfigured => '포인트 정책이 아직 준비되지 않았어요.',
          }, key: const ValueKey('reward_status')),
          if (fixtureLabelsVisible && day.fixtureLabel != null)
            Text('개발 검증용 · ${day.fixtureLabel}'),
          Text('받은 포인트 ${formatCount(day.grantedPoints)}P'),
          if (notice != null)
            Text(notice!, key: const ValueKey('reward_notice')),
          if (widget.controller.hasPendingClaim)
            Text(
              '미확정 수령 날짜 · ${ProductRepository.dateKey(widget.controller.pendingClaimDate!)}',
            ),
          if (widget.controller.hasPendingClaim)
            FilledButton(
              key: const ValueKey('reward_retry_claim'),
              onPressed: busy || widget.controller.busy
                  ? null
                  : () => claim(replay: true),
              child: const Text('같은 요청으로 결과 확인'),
            ),
          if (busy) const Text('처리 중…'),
          // Reloads run on their own; this shows only after one failed.
          if (needsReload && !busy)
            TextButton(
              key: const ValueKey('reward_reload'),
              onPressed: busy || widget.controller.hasPendingClaim
                  ? null
                  : () async {
                      try {
                        await reload();
                      } catch (_) {
                        if (active) {
                          setState(() => notice = '최신 기록을 불러오지 못했어요.');
                        }
                      }
                    },
              child: const Text('다시 시도'),
            ),
          if (free)
            claimButton(
              'free',
              key: const ValueKey('reward_free_claim'),
              onPressed: enabled ? () => claim(withAd: false) : null,
              label: '무료 ${freePoints}P 받기',
            ),
          if (ad) ...[
            // The observation runs on its own; a failed one offers a retry.
            if (premiumFailed)
              OutlinedButton(
                key: const ValueKey('reward_check_premium'),
                onPressed: enabled ? checkPremium : null,
                child: const Text('다시 시도'),
              ),
            if (widget.controller.premiumActive == false)
              const Text('현재 유효한 구매가 없어요. 무료 또는 광고 수령을 선택할 수 있어요.'),
            if (premium)
              claimButton(
                'premium',
                key: const ValueKey('reward_premium_claim'),
                onPressed: enabled ? () => claim(premium: true) : null,
                label: '유료 혜택으로 ${adPoints}P 받기',
              ),
            Text('광고 확인 시 미수령 전체 기본분의 총 2배 · ${adPoints}P'),
            OutlinedButton(
              key: const ValueKey('reward_watch_ad'),
              onPressed: enabled ? watchAd : null,
              child: const Text('광고 시청 확인'),
            ),
            if (verifiedIntent != null)
              claimButton(
                'ad',
                key: const ValueKey('reward_ad_claim'),
                onPressed: enabled ? () => claim(withAd: true) : null,
                label: '확인된 광고로 ${adPoints}P 받기',
              ),
          ],
        ],
      );
    },
  );
}

/// The ad and paid paths apply only while unclaimed ad-eligible points remain.
bool _offersAd(RecordDay day) =>
    (day.rewardStatus == DayRewardStatus.claimable ||
        day.rewardStatus == DayRewardStatus.adRequired) &&
    (day.adClaimablePoints ?? 0) > 0;
