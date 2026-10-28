import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';

import '../ads/ads_controller.dart';
import '../ads/ads_session.dart';
import '../ads/ads_sheet.dart';
import '../records/product_page.dart';
import 'quiz_controller.dart';

/// The legacy development quiz screen remains separate from this API.
class AuthenticatedQuizScreen extends StatefulWidget {
  const AuthenticatedQuizScreen({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onHome,
    this.createAds,
  });
  final QuizController controller;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final Future<AdsController?> Function()? createAds;

  @override
  State<AuthenticatedQuizScreen> createState() =>
      _AuthenticatedQuizScreenState();
}

class _AuthenticatedQuizScreenState extends State<AuthenticatedQuizScreen> {
  bool adOpen = false;
  String? adError;
  QuizController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    unawaited(controller.load());
  }

  Future<void> watchAd() async {
    if (adOpen || !controller.beginAd()) return;
    final today = controller.today!;
    final revision = today.extraRevision!;
    setState(() {
      adOpen = true;
      adError = null;
    });
    AdsController? ads;
    void capture() {
      final intent = ads?.intent;
      if (mounted && ads?.status == AdsStatus.verified && intent != null) {
        controller.captureVerified(intent, today.date, revision);
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
      );
      // The sheet cancels on close. Capture only its earlier verified event.
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
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final today = controller.today;
      final enabled = controller.canAct && !adOpen;
      return ProductPage(
        onBack: widget.onBack,
        onHome: widget.onHome,
        children: [
          Text('오늘의 퀴즈', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: Space.s2),
          const Text('무료 1문제 · 광고 또는 유료 혜택으로 추가 1문제\n첫 제출은 정오답과 관계없이 2P예요.'),
          TextButton(
            key: const ValueKey('quiz_history'),
            onPressed: adOpen
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => QuizHistoryScreen(
                        controller: controller,
                        onHome: widget.onHome,
                      ),
                    ),
                  ),
            child: const Text('지난 퀴즈 복습'),
          ),
          if (controller.notice != null)
            Semantics(
              liveRegion: true,
              child: Text(
                controller.notice!,
                key: const ValueKey('quiz_notice'),
              ),
            ),
          if (controller.busy) const Text('서버에서 확인하는 중…'),
          if (controller.hasPending)
            FilledButton(
              key: const ValueKey('quiz_retry_request'),
              onPressed: controller.busy ? null : controller.retry,
              child: const Text('같은 요청으로 결과 확인'),
            )
          // Loads run on their own; a retry shows only after one failed (3.1).
          else if (!controller.busy &&
              (controller.needsRefresh || today == null))
            TextButton(
              key: const ValueKey('quiz_reload'),
              onPressed: adOpen ? null : controller.load,
              child: const Text('다시 시도'),
            ),
          if (today == null && controller.notice == null)
            const Text('오늘의 퀴즈를 불러오고 있어요.'),
          if (today != null) ...[
            // The paid benefit is observed on its own (3.1): nothing to say
            // before an observation, and only a failure offers a retry.
            if (controller.premiumError != null ||
                today.premiumStatus != 'notChecked')
              Text(
                controller.premiumError == 'checking'
                    ? '유료 혜택을 확인하고 있어요.'
                    : controller.premiumError != null
                    ? '유료 혜택을 확인하지 못했어요. 다시 확인해 주세요.'
                    : switch (today.premiumStatus) {
                        'active' => '유효한 구매를 확인했어요.',
                        'inactive' => '현재 유효한 구매가 없어요.',
                        _ => '유료 혜택을 아직 확인하지 않았어요.',
                      },
                key: const ValueKey('quiz_premium_status'),
              ),
            if (controller.premiumError != null &&
                controller.premiumError != 'checking')
              OutlinedButton(
                key: const ValueKey('quiz_check_premium'),
                onPressed: enabled ? controller.checkPremium : null,
                child: const Text('다시 시도'),
              ),
            if (today.status != 'ready')
              Text(
                quizError(today.status),
                key: ValueKey('quiz_status_${today.status}'),
              ),
            if (today.free != null)
              _QuestionCard(
                key: ValueKey(today.free!.assignmentId),
                question: today.free!,
                enabled: enabled,
                onSubmit: controller.answer,
              ),
            const SizedBox(height: Space.s4),
            Text('추가 퀴즈', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.s2),
            if (today.extra != null)
              _QuestionCard(
                key: ValueKey(today.extra!.assignmentId),
                question: today.extra!,
                enabled: enabled,
                onSubmit: controller.answer,
              )
            else ...[
              Text(switch (today.extraStatus) {
                'premiumAvailable' =>
                  '유료 혜택으로 광고 없이 추가 문제를 열 수 있어요. 직접 열기를 눌러 주세요.',
                'adRequired' =>
                  '광고 확인 후 직접 열기를 눌러 주세요. 시청만으로 문제가 열리거나 포인트가 지급되지 않아요.',
                'freeRequired' =>
                  today.free == null
                      ? '새 문제가 준비되면 무료 문제부터 시작할 수 있어요.'
                      : '무료 문제를 먼저 제출해 주세요.',
                _ => quizError(today.extraStatus),
              }, key: ValueKey('quiz_extra_${today.extraStatus}')),
              if (adError != null) Text(adError!),
              if (today.extraStatus == 'premiumAvailable')
                FilledButton(
                  key: const ValueKey('quiz_premium_unlock'),
                  onPressed: enabled && controller.premiumReady
                      ? controller.unlockExtraWithPremium
                      : null,
                  child: const Text('유료 혜택으로 추가 문제 열기'),
                ),
              if (today.extraStatus == 'adRequired') ...[
                if (controller.verifiedIntent == null)
                  OutlinedButton(
                    key: const ValueKey('quiz_watch_ad'),
                    onPressed: enabled ? watchAd : null,
                    child: const Text('광고 시청 확인'),
                  )
                else
                  FilledButton(
                    key: const ValueKey('quiz_unlock'),
                    onPressed: enabled ? controller.unlockExtra : null,
                    child: const Text('확인된 광고로 추가 문제 열기'),
                  ),
              ],
            ],
          ],
        ],
      );
    },
  );
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({
    super.key,
    required this.question,
    this.enabled = false,
    this.onSubmit,
  });
  final QuizQuestion question;
  final bool enabled;
  final Future<void> Function(QuizQuestion, int)? onSubmit;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final answered = q.answerIndex != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fixtureLabelsVisible && q.fixtureLabel != null) ...[
          FixtureBadge(q.fixtureLabel!),
          const Text('테스트 문항이며 운영 포인트에 포함되지 않아요.'),
        ],
        const SizedBox(height: Space.s2),
        Text(q.question, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.s2),
        Text(
          '적용 조건 · ${q.conditions}',
          key: ValueKey('quiz_conditions_${q.assignmentId}'),
        ),
        const SizedBox(height: Space.s3),
        for (final (index, label) in q.choices.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: Semantics(
              selected: (answered ? q.answerIndex : selected) == index,
              child: OutlinedButton(
                key: ValueKey('quiz_${q.assignmentId}_choice_$index'),
                style: answered
                    ? OutlinedButton.styleFrom(
                        disabledForegroundColor: Theme.of(context)
                            .colorScheme
                            .onSurface,
                      )
                    : null,
                onPressed: answered || !widget.enabled
                    ? null
                    : () => setState(() => selected = index),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$label${answered
                        ? (index == q.correctIndex ? ' · 정답' : '') + (index == q.answerIndex ? ' · 내 답' : '')
                        : selected == index
                        ? ' · 선택됨'
                        : ''}',
                  ),
                ),
              ),
            ),
          ),
        if (!answered && widget.onSubmit != null)
          FilledButton(
            key: ValueKey('quiz_${q.assignmentId}_submit'),
            onPressed: widget.enabled && selected != null
                ? () => widget.onSubmit!(q, selected!)
                : null,
            child: const Text('답 제출하기'),
          ),
        if (answered) ...[
          Text(
            q.answerIndex == q.correctIndex ? '정답이에요' : '아쉽지만 오답이에요',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (q.explanation != null) Text(q.explanation!),
          const SizedBox(height: Space.s2),
          if (q.source != null) SelectableText('출처 · ${q.source}'),
          Text('검토일 ${q.reviewedAt} · ${q.reviewedBy}'),
          Text(
            '이 문제의 기존 지급 기록 ${formatCount(q.awardedPoints)}P · 복습은 추가 지급 없음',
            key: ValueKey('quiz_${q.assignmentId}_past_points'),
          ),
        ],
      ],
    );
  }
}

class QuizHistoryScreen extends StatefulWidget {
  const QuizHistoryScreen({
    super.key,
    required this.controller,
    required this.onHome,
  });
  final QuizController controller;
  final VoidCallback onHome;
  @override
  State<QuizHistoryScreen> createState() => _QuizHistoryScreenState();
}

class _QuizHistoryScreenState extends State<QuizHistoryScreen> {
  final items = <QuizQuestion>[];
  bool busy = false;
  bool more = true;
  String? error;
  QuizQuestion? review;
  int? reviewId;
  bool get active => mounted && widget.controller.isActive;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    if (!active || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await widget.controller.history(
        items.lastOrNull?.assignmentId,
      );
      if (!active) return;
      setState(() {
        items.addAll(page);
        more = page.length == 30;
      });
    } catch (_) {
      if (active) setState(() => error = '복습 목록을 불러오지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (active) setState(() => busy = false);
    }
  }

  Future<void> open(int id) async {
    if (!active || busy) return;
    setState(() {
      busy = true;
      error = null;
      reviewId = id;
    });
    try {
      final q = await widget.controller.review(id);
      if (active && reviewId == id) setState(() => review = q);
    } catch (_) {
      if (active && reviewId == id) {
        setState(() => error = '문제를 불러오지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (active) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ProductPage(
    onBack: () {
      if (reviewId != null) {
        setState(() {
          reviewId = null;
          review = null;
          error = null;
        });
      } else {
        Navigator.of(context).pop();
      }
    },
    onHome: () {
      Navigator.of(context).pop();
      widget.onHome();
    },
    children: [
      Text('지난 퀴즈 복습', style: Theme.of(context).textTheme.headlineSmall),
      const Text('이미 제출한 문제예요. 복습으로 포인트가 다시 지급되지 않아요.'),
      if (busy) const Text('불러오는 중…'),
      if (error != null) ...[
        Text(error!),
        TextButton(
          key: const ValueKey('quiz_history_retry'),
          onPressed: busy
              ? null
              : () => reviewId == null ? load() : open(reviewId!),
          child: const Text('다시 시도'),
        ),
      ],
      if (review != null)
        _QuestionCard(question: review!)
      else if (reviewId == null) ...[
        if (!busy && items.isEmpty && error == null)
          const Text('아직 답한 문제가 없어요.'),
        for (final q in items)
          ListTile(
            key: ValueKey('quiz_history_${q.assignmentId}'),
            title: Text(q.question),
            subtitle: Text(
              '${q.date} · ${q.slot == 'free' ? '무료' : '추가'} · 기존 ${formatCount(q.awardedPoints)}P',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => open(q.assignmentId),
          ),
        if (more && error == null && !busy)
          TextButton(
            key: const ValueKey('quiz_history_more'),
            onPressed: load,
            child: const Text('이전 문제 더 보기'),
          ),
      ],
    ],
  );
}
