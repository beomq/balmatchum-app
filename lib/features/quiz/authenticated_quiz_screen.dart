import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';

import '../ads/ads_controller.dart';
import '../ads/ads_session.dart';
import '../ads/ads_sheet.dart';
import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart';
import '../records/status_widgets.dart';
import '../wardrobe/dog_sprite.dart';
import 'quiz_controller.dart';
import 'quiz_review_sheet.dart';
import 'quiz_widgets.dart';

/// Today's quiz (`pJMis`, `aZln1`, `w2cyk`). The legacy development quiz
/// screen remains separate from this API.
class AuthenticatedQuizScreen extends StatefulWidget {
  const AuthenticatedQuizScreen({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onHome,
    this.createAds,
    this.dogAsset,
  });
  final QuizController controller;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final Future<AdsController?> Function()? createAds;

  /// The user's own companion sprite for results and the empty state (3.6).
  final String? dogAsset;
  @override
  State<AuthenticatedQuizScreen> createState() =>
      _AuthenticatedQuizScreenState();
}

class _AuthenticatedQuizScreenState extends State<AuthenticatedQuizScreen> {
  bool adOpen = false;
  String? adError;

  /// Questions whose answer this screen sent. Only their result reads as
  /// points received now; any other answered question shows its record.
  final sent = <int>{};
  QuizController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    unawaited(controller.load());
  }

  /// A tap is the answer (guide 6.1). The controller takes the first tap
  /// only and keeps that request until the server settles it.
  Future<void> answer(QuizQuestion question, int index) async {
    if (adOpen || !controller.canAct) return;
    sent.add(question.assignmentId);
    await controller.answer(question, index);
  }

  /// Settles the pending request with its own id and payload.
  Future<void> retry() async {
    final today = controller.today;
    if (controller.pendingAnswer != null && today != null) {
      final question = today.extra ?? today.free;
      if (question != null) sent.add(question.assignmentId);
    }
    await controller.retry();
  }

  Future<void> openReview() => showQuizReviewSheet(context, controller);

  Future<void> watchAd() async {
    if (adOpen || !controller.beginAd()) return;
    final today = controller.today!;
    final revision = today.extraRevision!;
    setState(() {
      adOpen = true;
      adError = null;
    });
    AdsController? ads;
    String? captured;
    void capture() {
      final intent = ads?.intent;
      if (mounted && ads?.status == AdsStatus.verified && intent != null) {
        controller.captureVerified(intent, today.date, revision);
        if (controller.verifiedIntent == intent.id) captured = intent.id;
      }
    }

    try {
      ads =
          await (widget.createAds?.call() ??
              createAdsController(controller.repository.client));
      if (!mounted || !controller.isActive) return;
      if (ads == null) {
        setState(() => adError = '인증을 확인하지 못했어요. 다시 로그인해 주세요.');
        return;
      }
      ads.addListener(capture);
      await showAdsSheet(
        context,
        controller: ads,
        purpose: 'extraQuiz',
        targetDate: today.date,
        targetRevision: revision,
        // The ad button was the ask: play at once, close once verified.
        autoContinue: true,
      );
      // The sheet cancels on close. Only its earlier verified event counts.
    } catch (_) {
      if (mounted && controller.isActive) {
        setState(() => adError = '광고 확인을 완료하지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      ads?.removeListener(capture);
      ads?.dispose();
      controller.endAd();
      if (mounted) setState(() => adOpen = false);
    }
    // Owner decision ⑤ (2026-10-28): a server-verified view opens the extra
    // question at once, with the request the explicit button sent before. A
    // lost answer leaves that request pending for its same-request check; it
    // is never sent again from here. An early close never gets here verified.
    if (captured != null &&
        mounted &&
        controller.verifiedIntent == captured &&
        controller.canAct) {
      await controller.unlockExtra();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final today = controller.today;
      // The extra question takes over once issued; the free one is in review.
      final question = today?.status == 'ready'
          ? today!.extra ?? today.free
          : null;
      final empty = today != null && question == null;
      final answered = question?.answerIndex != null;
      final notice = controller.notice;
      final open = controller.canAct && !adOpen;
      return ProductPage(
        onBack: widget.onBack,
        onHome: widget.onHome,
        centerFooter: empty,
        footer: switch ((today, question)) {
          (null, _) => null,
          (final QuizToday today, null) => (gutter) => _Empty(
            status: today.status,
            gutter: gutter,
            dogAsset: widget.dogAsset,
            onReview: adOpen ? null : openReview,
          ),
          (final QuizToday today, final QuizQuestion q) when answered =>
            (gutter) => _ResultPanel(
              result: QuizResult(
                key: ValueKey('quiz_${q.assignmentId}_result'),
                question: q,
                received: sent.contains(q.assignmentId),
                dogAsset: widget.dogAsset,
              ),
              onHome: widget.onHome,
              next: next(today, open),
            ),
          // Nothing to promise while a request waits for the server.
          _ when notice != null => null,
          _ => (gutter) => _Hint(gutter: gutter, dogAsset: widget.dogAsset),
        },
        children: [
          Text('오늘의 퀴즈', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: Space.s2),
          _StatusRow(
            chip: today == null ? null : chip(today, question),
            onReview: adOpen ? null : openReview,
          ),
          const SizedBox(height: Space.s3),
          // The first load and its failure; never shown as "preparing".
          if (today == null)
            ProductLoadState(
              error: notice,
              onRetry: controller.load,
              retryKey: const ValueKey('quiz_reload'),
            )
          else if (question != null) ...[
            QuizQuestionCard(
              key: ValueKey('quiz_${question.assignmentId}_card'),
              question: question,
              kicker: today.extra == null ? '오늘의 문제' : '한 문제 더',
            ),
            const SizedBox(height: 14),
            for (final (index, label) in question.choices.indexed) ...[
              if (index > 0) const SizedBox(height: 10),
              QuizOption(
                key: ValueKey('quiz_${question.assignmentId}_choice_$index'),
                label: label,
                state: quizOptionState(
                  question,
                  index,
                  pending: controller.pendingAnswer,
                  sending: controller.busy,
                ),
                selected:
                    index == (question.answerIndex ?? controller.pendingAnswer),
                tag: quizOptionTag(question, index),
                onTap: open && !answered ? () => answer(question, index) : null,
              ),
            ],
            if (!answered && notice == null) ...[
              const SizedBox(height: Space.s3),
              Text(
                '첫 제출은 정오답과 관계없이 2P예요.',
                key: const ValueKey('quiz_rules'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
          if (today != null && notice != null) ...[
            const SizedBox(height: Space.s4),
            _Attention(
              notice: notice,
              // A pending request is settled with its own id; anything
              // else needs today's state again (guide 6.1).
              retryKey: ValueKey(
                controller.hasPending ? 'quiz_retry_request' : 'quiz_reload',
              ),
              onRetry: controller.busy
                  ? null
                  : controller.hasPending
                  ? retry
                  : controller.load,
              // The result panel's home button stays the one primary.
              primary: !answered,
            ),
          ],
        ],
      );
    },
  );

  TextChip chip(QuizToday today, QuizQuestion? question) {
    const key = ValueKey('quiz_chip');
    if (question == null) return const TextChip('오늘 문제 준비 중', textKey: key);
    if (question.answerIndex == null) {
      return TextChip(
        today.extra == null ? '오늘 1문제 · 첫 제출 보상' : '한 문제 더 · 첫 제출 보상',
        textKey: key,
      );
    }
    return TextChip(
      today.extra == null ? '오늘 1문제 · 완료' : '오늘 2문제 · 완료',
      tone: TextChipTone.record,
      textKey: key,
    );
  }

  /// The one optional step after the free question, under '홈으로'.
  List<Widget> next(QuizToday today, bool open) {
    final text = Theme.of(context).textTheme;
    final premiumError = controller.premiumError;
    final checking = premiumError == 'checking';
    return [
      // The paid benefit is observed on its own (3.1); only a failure says
      // so and offers its retry.
      if (premiumError != null && !checking) ...[
        Text(
          '유료 혜택을 확인하지 못했어요.',
          key: const ValueKey('quiz_premium_status'),
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
        _quiet(
          const ValueKey('quiz_check_premium'),
          '다시 시도',
          open ? controller.checkPremium : null,
        ),
      ],
      if (adError case final error? when today.extra == null)
        Text(
          error,
          key: const ValueKey('quiz_ad_error'),
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
      if (!checking && today.extra == null)
        ...switch (today.extraStatus) {
          // Only when the automatic unlock could not start.
          'adRequired'
              when controller.verifiedIntent != null &&
                  !controller.hasPending =>
            [
              _quiet(
                const ValueKey('quiz_unlock'),
                '확인된 광고로 한 문제 열기',
                open ? controller.unlockExtra : null,
              ),
            ],
          'adRequired' => [
            _quiet(
              const ValueKey('quiz_watch_ad'),
              '광고 보고 한 문제 더',
              open ? watchAd : null,
            ),
          ],
          'premiumAvailable' => [
            _quiet(
              const ValueKey('quiz_premium_unlock'),
              '유료 혜택으로 한 문제 더',
              open && controller.premiumReady
                  ? controller.unlockExtraWithPremium
                  : null,
            ),
          ],
          'contentUnavailable' || 'exhausted' => [
            Text(
              quizError(today.extraStatus),
              key: ValueKey('quiz_extra_${today.extraStatus}'),
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
          _ => const <Widget>[],
        },
    ];
  }
}

/// The status chip and the small way into past quizzes.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.chip, required this.onReview});
  final Widget? chip;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: chip == null
        ? MainAxisAlignment.end
        : MainAxisAlignment.spaceBetween,
    children: [
      if (chip case final chip?) ...[
        Flexible(child: chip),
        const SizedBox(width: Space.s2),
      ],
      TextButton(
        key: const ValueKey('quiz_history'),
        onPressed: onReview,
        style: TextButton.styleFrom(
          foregroundColor: MeetingColors.muted,
          textStyle: meetingType(13.5, 18, FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: Space.s1),
        ),
        // The pixel caret is not exported yet (guide 9.2).
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [Text('지난 퀴즈'), Icon(Icons.chevron_right, size: 16)],
        ),
      ),
    ],
  );
}

/// Under an open question: the companion saying a tap answers at once.
class _Hint extends StatelessWidget {
  const _Hint({required this.gutter, this.dogAsset});
  final double gutter;
  final String? dogAsset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      gutter,
      Space.s4,
      gutter,
      20 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Row(
      children: [
        if (dogAsset case final dog?) ...[
          SizedBox.square(
            key: const ValueKey('quiz_hint_dog'),
            dimension: DogSpriteSize.hint,
            child: DogSprite(asset: dog),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: MeetingColors.raised,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                '보기를 누르면\n바로 정답을 알려 줄게!',
                key: const ValueKey('quiz_hint'),
                style: meetingType(
                  14,
                  20,
                  FontWeight.w400,
                ).copyWith(fontFamily: 'Galmuri11'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// `w2cyk`: the server has no question for today. Never a load failure.
class _Empty extends StatelessWidget {
  const _Empty({
    required this.status,
    required this.gutter,
    required this.onReview,
    this.dogAsset,
  });
  final String status;
  final double gutter;
  final VoidCallback? onReview;
  final String? dogAsset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      gutter,
      Space.s4,
      gutter,
      40 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        if (dogAsset case final dog?)
          SizedBox.square(
            key: const ValueKey('quiz_empty_dog'),
            dimension: DogSpriteSize.emptyState,
            child: DogSprite(asset: dog),
          ),
        Text(
          switch (status) {
            'exhausted' => '준비된 문제를 모두 풀었어요',
            'contentUnavailable' => '준비된 문제가 없어요',
            _ => '오늘 문제를 열 수 없어요',
          },
          key: ValueKey('quiz_status_$status'),
          textAlign: TextAlign.center,
          style: meetingType(20, 28, FontWeight.w800),
        ),
        // No date is promised: new questions have no fixed day (guide 6.2).
        Text(
          '새 문제가 올라오면 여기서 풀 수 있어요.\n그동안 지난 퀴즈를 복습해 볼까요?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: OutlinedButton(
            key: const ValueKey('quiz_empty_review'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(200, 48)),
            onPressed: onReview,
            child: const Text('지난 퀴즈 복습'),
          ),
        ),
      ],
    ),
  );
}

/// `Quiz Feedback Panel` (`aZln1`): the result docked to the bottom edge,
/// the way home and the one optional next step.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.result,
    required this.onHome,
    required this.next,
  });
  final Widget result;
  final VoidCallback onHome;
  final List<Widget> next;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: ProductColors.raised,
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      boxShadow: [
        BoxShadow(
          color: ProductColors.panelShadow,
          offset: Offset(0, -4),
          blurRadius: 20,
        ),
      ],
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        26 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s3,
        children: [
          result,
          FilledButton(
            key: const ValueKey('quiz_home'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: onHome,
            child: const Text('홈으로'),
          ),
          ...next,
        ],
      ),
    ),
  );
}

/// `Feedback More`: a quiet text action under the primary button.
TextButton _quiet(Key key, String label, VoidCallback? onPressed) => TextButton(
  key: key,
  onPressed: onPressed,
  style: TextButton.styleFrom(
    foregroundColor: MeetingColors.muted,
    minimumSize: const Size.fromHeight(44),
  ),
  child: Text(label, textAlign: TextAlign.center),
);

/// A notice that needs the user, with its one retry.
class _Attention extends StatelessWidget {
  const _Attention({
    required this.notice,
    required this.retryKey,
    required this.onRetry,
    required this.primary,
  });
  final String notice;
  final Key retryKey;
  final VoidCallback? onRetry;
  final bool primary;

  @override
  Widget build(BuildContext context) => ProductPanel(
    color: ProductColors.warningSoft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            notice,
            key: const ValueKey('quiz_notice'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        primary
            ? FilledButton(
                key: retryKey,
                onPressed: onRetry,
                child: const Text('다시 시도'),
              )
            : OutlinedButton(
                key: retryKey,
                onPressed: onRetry,
                child: const Text('다시 시도'),
              ),
      ],
    ),
  );
}
