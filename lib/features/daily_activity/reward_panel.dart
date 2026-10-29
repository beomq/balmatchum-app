import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';

import '../ads/ads_controller.dart';
import '../ads/ads_session.dart';
import '../ads/ads_sheet.dart';
import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart'
    show PixelIcon, Space, fixtureLabelsVisible, formatCount;
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
    this.onGranted,
    this.showRules = true,
  });
  final ProductController controller;
  final RecordDay day;
  final ValueChanged<RecordDay>? onChanged;
  final Future<AdsController?> Function()? createAds;

  /// The home sheet's result view (REW-02) takes over after a grant with the
  /// amount the server returned. Without it the panel keeps its own notice.
  final ValueChanged<int>? onGranted;

  /// Past days list the claim rules under the actions; the home sheet moves
  /// them behind its info button (guide 5.2).
  final bool showRules;

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
        // The ad button was the ask: play at once, close once verified.
        autoContinue: true,
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
    // Owner decision ⑤ (2026-10-28): a server-verified view is claimed at
    // once, with the same request the explicit button sent before. A lost
    // answer leaves that request pending for its same-request check; it is
    // never sent again from here. An early close never gets here verified.
    if (captured != null &&
        verifiedIntent == captured &&
        active &&
        widget.controller.canClaim) {
      await claim(withAd: true);
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
      final granted = widget.onGranted;
      setState(() {
        notice = granted == null ? '$amount포인트를 받았어요.' : null;
        verifiedIntent = null;
        needsReload = true;
      });
      // Only a confirmed grant reaches this line; the sheet shows its result.
      granted?.call(amount);
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
      final controller = widget.controller;
      final text = Theme.of(context).textTheme;
      final enabled = !busy && controller.canClaim && active && !needsReload;
      final pending = controller.hasPendingClaim;
      final free =
          day.rewardStatus == DayRewardStatus.claimable &&
          (day.claimablePoints ?? 0) > 0;
      final ad = _offersAd(day);
      final premium = ad && controller.premiumActive == true;
      final freePoints = formatCount(day.claimablePoints ?? 0);
      final adPoints = formatCount(day.adClaimablePoints ?? 0);
      // The amount leads (REW-01): the free amount, else the ad amount.
      final points = free
          ? day.claimablePoints
          : ad
          ? day.adClaimablePoints
          : null;
      // One primary button (guide 3.3): free, then paid, then the ad itself.
      final primary = pending
          ? null
          : free
          ? 'free'
          : premium
          ? 'premium'
          : 'ad';
      Widget action(
        String role, {
        required Key key,
        required VoidCallback? onPressed,
        required String label,
      }) {
        final child = Text(label, textAlign: TextAlign.center);
        return role == primary
            ? FilledButton(
                key: key,
                style: _action,
                onPressed: onPressed,
                child: child,
              )
            : OutlinedButton(
                key: key,
                style: _action,
                onPressed: onPressed,
                child: child,
              );
      }

      final wallet = controller.wallet;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          if (points != null) ...[
            // Pen `Reward Amount`: the points icon, 10 pt, then the amount.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 10,
              children: [
                const PixelIcon('points', size: 44),
                Flexible(
                  child: Text(
                    '+${formatCount(points)}P',
                    key: const ValueKey('reward_amount'),
                    textAlign: TextAlign.center,
                    style: meetingType(46, 54, FontWeight.w800),
                  ),
                ),
              ],
            ),
            Text(
              free ? _basis(day) : '광고를 보면 받을 수 있어요',
              key: const ValueKey('reward_status'),
              textAlign: TextAlign.center,
            ),
          ] else
            Text(
              _statusLine(day),
              key: const ValueKey('reward_status'),
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
          if (day.grantedPoints > 0)
            Text(
              '이미 받은 포인트 ${formatCount(day.grantedPoints)}P',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          if (fixtureLabelsVisible && day.fixtureLabel != null)
            Text('개발 검증용 · ${day.fixtureLabel}'),
          if (notice != null)
            Text(notice!, key: const ValueKey('reward_notice')),
          if (pending) ...[
            Text(
              '미확정 수령 날짜 · ${ProductRepository.dateKey(controller.pendingClaimDate!)}',
            ),
            FilledButton(
              key: const ValueKey('reward_retry_claim'),
              style: _action,
              onPressed: busy || controller.busy
                  ? null
                  : () => claim(replay: true),
              child: const Text('같은 요청으로 결과 확인'),
            ),
          ],
          if (busy) const Text('처리 중…', textAlign: TextAlign.center),
          // Reloads run on their own; this shows only after one failed.
          if (needsReload && !busy)
            TextButton(
              key: const ValueKey('reward_reload'),
              onPressed: busy || pending
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
            action(
              'free',
              key: const ValueKey('reward_free_claim'),
              onPressed: enabled ? () => claim(withAd: false) : null,
              label: '${freePoints}P 받기',
            ),
          if (ad) ...[
            // The observation runs on its own; a failed one offers a retry.
            if (premiumFailed)
              OutlinedButton(
                key: const ValueKey('reward_check_premium'),
                onPressed: enabled ? checkPremium : null,
                child: const Text('다시 시도'),
              ),
            if (premium)
              action(
                'premium',
                key: const ValueKey('reward_premium_claim'),
                onPressed: enabled ? () => claim(premium: true) : null,
                label: '유료 혜택으로 ${adPoints}P 받기',
              ),
            action(
              'ad',
              key: const ValueKey('reward_watch_ad'),
              onPressed: enabled ? watchAd : null,
              label: '광고 보고 2배로 받기 · ${adPoints}P',
            ),
            // Only when the automatic claim could not start; never alongside
            // a pending request.
            if (verifiedIntent != null && !pending)
              OutlinedButton(
                key: const ValueKey('reward_ad_claim'),
                style: _action,
                onPressed: enabled ? () => claim(withAd: true) : null,
                child: Text('확인된 광고로 ${adPoints}P 받기'),
              ),
          ],
          if (widget.showRules)
            for (final line in rewardRules(day))
              Text(line, style: text.bodySmall),
          // An unread balance is left out, never shown as 0P.
          if (wallet != null)
            Text(
              '보유 ${formatCount(wallet.balance)}P · 포인트로 꾸미기 아이템을 살 수 있어요',
              key: const ValueKey('reward_balance'),
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
        ],
      );
    },
  );
}

/// REW-01's 52 pt action height.
final _action = FilledButton.styleFrom(minimumSize: const Size.fromHeight(52));

/// The server-confirmed steps behind the amount; device steps never stand in.
String _basis(RecordDay day) {
  final steps = day.steps;
  if (steps == null) return '받을 수 있어요';
  final today =
      ProductRepository.dateKey(day.date) ==
      ProductRepository.dateKey(ProductRepository.today);
  return '${today ? '오늘 ' : ''}${formatCount(steps)}걸음으로 받을 수 있어요';
}

String _statusLine(RecordDay day) => switch (day.rewardStatus) {
  DayRewardStatus.pending => '걸음이 확정되면 받을 수 있어요.',
  DayRewardStatus.claimable ||
  DayRewardStatus.adRequired ||
  DayRewardStatus.paid => '현재 추가로 받을 포인트가 없어요.',
  DayRewardStatus.legacyPolicyExcluded => '이전 테스트 정책 기록으로 운영 보상 대상이 아니에요.',
  DayRewardStatus.futureDate => '미래 날짜의 기록이에요.',
  DayRewardStatus.canceled => '삭제로 미수령 포인트가 취소됐어요.',
  DayRewardStatus.expired => '무료 수령 기간이 지났어요.',
  DayRewardStatus.unconfigured => '포인트 정책이 아직 준비되지 않았어요.',
};

/// The claim rules the sheet's info button shows (guide 5.2). They restate
/// the server policy and change nothing about it.
List<String> rewardRules(RecordDay day) => [
  switch (day.rewardStatus) {
    DayRewardStatus.claimable =>
      '무료 수령은 유예 중인 구간만 받을 수 있어요. 만료된 구간은 광고 대상으로 남아요.',
    DayRewardStatus.adRequired => '무료 유예가 끝났어요. 미수령 포인트는 광고 확인 후 받을 수 있어요.',
    _ => _statusLine(day),
  },
  if (_offersAd(day)) ...[
    '광고 확인 시 미수령 전체 기본분의 총 2배 · ${formatCount(day.adClaimablePoints ?? 0)}P',
    '광고를 끝까지 보면 서버에서 확인한 뒤 바로 받아요.',
  ],
];

/// The ad and paid paths apply only while unclaimed ad-eligible points remain.
bool _offersAd(RecordDay day) =>
    (day.rewardStatus == DayRewardStatus.claimable ||
        day.rewardStatus == DayRewardStatus.adRequired) &&
    (day.adClaimablePoints ?? 0) > 0;

/// Whether [day] still has something to receive.
bool hasRewardLeft(RecordDay day) =>
    (day.rewardStatus == DayRewardStatus.claimable &&
        (day.claimablePoints ?? 0) > 0) ||
    _offersAd(day);
