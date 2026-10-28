import 'dart:async';

import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart';

/// UI view model mapped 1:1 from generated `DailyQuiz`. The UI never
/// computes correctness; [correctIndex] and [explanation] come from the
/// server only after an answer.
class QuizView {
  const QuizView({
    required this.date,
    required this.questionId,
    required this.question,
    required this.choices,
    this.answerIndex,
    this.correctIndex,
    this.explanation,
    this.awardedPoints = 0,
    this.fixtureLabel,
  });
  final String date;
  final String questionId;
  final String question;
  final List<String> choices;
  final int? answerIndex;
  final int? correctIndex;
  final String? explanation;
  final int awardedPoints;

  /// Non-null when the question is development fixture content.
  final String? fixtureLabel;

  bool get isAnswered => answerIndex != null && correctIndex != null;
  bool get isCorrect => isAnswered && answerIndex == correctIndex;
}

typedef LoadDailyQuiz = Future<QuizView> Function();

/// Returns the server-confirmed quiz after the answer (`answerQuiz`).
typedef SubmitQuizAnswer = Future<QuizView> Function(
  QuizView quiz,
  int answerIndex,
);

/// Daily basic quiz. The home unanswered dot is owned by the parent; it can
/// refresh it from [onAnswered].
class DailyQuizScreen extends StatefulWidget {
  const DailyQuizScreen({
    required this.loadQuiz,
    required this.submitAnswer,
    required this.onBack,
    required this.onHome,
    this.onAnswered,
    this.loadHistory,
    super.key,
  });

  final LoadDailyQuiz loadQuiz;
  final SubmitQuizAnswer submitAnswer;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final ValueChanged<QuizView>? onAnswered;
  final Future<List<QuizView>> Function()? loadHistory;

  @override
  State<DailyQuizScreen> createState() => _DailyQuizScreenState();
}

class _DailyQuizScreenState extends State<DailyQuizScreen> {
  QuizView? quiz;
  String? loadError;
  int? selected;
  bool submitting = false;
  String? submitError;

  Future<void> history() async {
    try {
      final items = await widget.loadHistory!();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '지난 퀴즈 복습',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (items.isEmpty) const Text('아직 답한 문제가 없어요.'),
              for (final item in items)
                ListTile(
                  title: Text('${item.date} · ${item.question}'),
                  subtitle: Text(item.explanation ?? ''),
                ),
            ],
          ),
        ),
      );
    } on Exception {
      if (mounted) setState(() => submitError = '복습 목록을 불러오지 못했어요.');
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      quiz = null;
      loadError = null;
    });
    try {
      final value = await widget.loadQuiz();
      if (!mounted) return;
      setState(() {
        quiz = value;
        selected = value.answerIndex;
      });
    } on Exception {
      if (mounted) setState(() => loadError = '오늘의 퀴즈를 불러오지 못했어요.');
    }
  }

  Future<void> submit() async {
    final q = quiz!;
    final choice = selected!;
    setState(() {
      submitting = true;
      submitError = null;
    });
    try {
      final value = await widget.submitAnswer(q, choice);
      if (!mounted) return;
      setState(() {
        quiz = value;
        selected = value.answerIndex;
        submitting = false;
      });
      widget.onAnswered?.call(value);
    } on Exception {
      if (mounted) {
        setState(() {
          submitting = false;
          submitError = '답을 저장하지 못했어요. 선택은 그대로 두었으니 다시 제출해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final q = quiz;
    final r = q != null && q.isAnswered ? q : null;
    return ProductPage(
      onBack: widget.onBack,
      onHome: widget.onHome,
      children: [
        Text('오늘의 퀴즈', style: text.headlineSmall),
        if (widget.loadHistory != null)
          TextButton(onPressed: history, child: const Text('지난 퀴즈 복습')),
        const SizedBox(height: Space.s1),
        Text(r == null ? '하루 한 문제 · 답을 고르고 제출해요' : '오늘 답한 문제를 다시 볼 수 있어요'),
        const SizedBox(height: Space.s4),
        if (q == null)
          ProductLoadState(error: loadError, onRetry: load)
        else ...[
          if (q.fixtureLabel != null) ...[
            FixtureBadge(q.fixtureLabel!),
            const SizedBox(height: Space.s2),
          ],
          ProductPanel(
            color: MeetingColors.soft,
            child: Text(q.question, style: text.titleLarge),
          ),
          const SizedBox(height: Space.s3),
          for (final (i, c) in q.choices.indexed)
            _ChoiceTile(
              index: i,
              label: c,
              selected: selected == i,
              state: r == null
                  ? null
                  : i == r.correctIndex
                  ? _Mark.correct
                  : i == r.answerIndex
                  ? _Mark.wrong
                  : null,
              onTap: r != null || submitting
                  ? null
                  : () => setState(() => selected = i),
            ),
          const SizedBox(height: Space.s2),
          if (r == null) ...[
            if (submitError != null) ...[
              Text(
                submitError!,
                key: const ValueKey('quiz_submit_error'),
                style: const TextStyle(color: ProductColors.error),
              ),
              const SizedBox(height: Space.s2),
            ],
            FilledButton(
              key: const ValueKey('quiz_submit'),
              onPressed: selected == null || submitting ? null : submit,
              child: Text(submitting ? '확인하는 중…' : '답 제출하기'),
            ),
          ] else
            ProductPanel(
              key: const ValueKey('quiz_result'),
              color: r.isCorrect
                  ? ProductColors.recordSoft
                  : ProductColors.warningSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    r.isCorrect ? '정답이에요' : '아쉽지만 오답이에요',
                    style: text.titleMedium,
                  ),
                  if (r.explanation != null) ...[
                    const SizedBox(height: Space.s2),
                    Text(r.explanation!, style: text.bodyLarge),
                  ],
                  if (r.awardedPoints > 0) ...[
                    const SizedBox(height: Space.s2),
                    Text('${formatCount(r.awardedPoints)}포인트를 받았어요.'),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

enum _Mark { correct, wrong }

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.index,
    required this.label,
    required this.selected,
    required this.state,
    required this.onTap,
  });
  final int index;
  final String label;
  final bool selected;
  final _Mark? state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _Mark.correct => ProductColors.recordSoft,
      _Mark.wrong => ProductColors.warningSoft,
      null => selected ? MeetingColors.soft : ProductColors.raised,
    };
    final trailing = switch (state) {
      _Mark.correct => '정답',
      _Mark.wrong => '내 답',
      null => selected ? '선택됨' : null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Semantics(
        selected: selected,
        child: Material(
          color: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected || state != null
                  ? MeetingColors.primary
                  : MeetingColors.line,
            ),
          ),
          child: InkWell(
            key: ValueKey('quiz_choice_$index'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4,
                  vertical: Space.s3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: Space.s2),
                      Text(
                        trailing,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: MeetingColors.ink),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
