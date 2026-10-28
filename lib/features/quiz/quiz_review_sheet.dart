import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart';
import '../records/status_widgets.dart';
import 'quiz_controller.dart';
import 'quiz_widgets.dart';

/// Past quizzes (`dmEHl`) over the quiz. Submitted questions only (owner
/// decision ⑫ is open). It only reads: listing and reviewing never answer,
/// unlock or grant, and closing leaves the quiz as it was.
Future<void> showQuizReviewSheet(
  BuildContext context,
  QuizController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => QuizReviewSheet(controller: controller),
);

class QuizReviewSheet extends StatefulWidget {
  const QuizReviewSheet({required this.controller, super.key});
  final QuizController controller;

  @override
  State<QuizReviewSheet> createState() => _QuizReviewSheetState();
}

class _QuizReviewSheetState extends State<QuizReviewSheet> {
  final items = <QuizQuestion>[];
  bool busy = false;
  bool loaded = false;
  bool more = true;

  /// A failed page; the questions already listed stay.
  String? listError;
  int? reviewId;
  QuizQuestion? review;
  String? reviewError;
  bool get active => mounted && widget.controller.isActive;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  /// The next page after the last listed assignment.
  Future<void> load() async {
    if (!active || busy) return;
    setState(() {
      busy = true;
      listError = null;
    });
    try {
      final page = await widget.controller.history(
        items.lastOrNull?.assignmentId,
      );
      if (!active) return;
      setState(() {
        items.addAll(page);
        loaded = true;
        more = page.length == 30;
      });
    } catch (_) {
      if (active) setState(() => listError = '지난 퀴즈를 불러오지 못했어요.');
    } finally {
      if (active) setState(() => busy = false);
    }
  }

  Future<void> open(int id) async {
    if (!active || busy) return;
    setState(() {
      busy = true;
      reviewId = id;
      review = null;
      reviewError = null;
    });
    try {
      final q = await widget.controller.review(id);
      if (active && reviewId == id) setState(() => review = q);
    } catch (_) {
      if (active && reviewId == id) {
        setState(() => reviewError = '문제를 불러오지 못했어요.');
      }
    } finally {
      if (active) setState(() => busy = false);
    }
  }

  /// Back to the list, whose questions and cursor are kept.
  void back() => setState(() {
    reviewId = null;
    review = null;
    reviewError = null;
  });

  @override
  Widget build(BuildContext context) {
    final judged = items.where(
      (q) => q.answerIndex != null && q.correctIndex != null,
    );
    final right = judged.where((q) => q.answerIndex == q.correctIndex).length;
    return SafeArea(
      top: false,
      child: SizedBox(
        // Pen sheet: 608 of 844 pt.
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: MeetingColors.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  Row(
                    children: [
                      if (reviewId != null)
                        IconButton(
                          key: const ValueKey('quiz_review_back'),
                          tooltip: '목록으로',
                          onPressed: back,
                          icon: Image.asset(
                            'assets/first_meeting/icons/back.png',
                            width: 24,
                            height: 24,
                            filterQuality: FilterQuality.none,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            Text(
                              '지난 퀴즈',
                              style: meetingType(18, 24, FontWeight.w800),
                            ),
                            // Counts only what was read: the latest questions
                            // listed so far, never a period the list may not
                            // cover (guide 6.3).
                            if (judged.isNotEmpty)
                              Text(
                                '최근 ${judged.length}문제 중 $right문제 정답',
                                key: const ValueKey('quiz_review_summary'),
                                style: meetingType(
                                  12.5,
                                  18,
                                  FontWeight.w600,
                                  MeetingColors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('quiz_review_close'),
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          fixedSize: const Size(44, 44),
                          side: const BorderSide(color: MeetingColors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const PixelIcon('close-x', size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, Space.s3, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: reviewId == null ? list() : detail(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> list() {
    if (items.isEmpty) {
      return [
        if (listError != null)
          ProductLoadState(
            error: listError,
            onRetry: load,
            retryKey: const ValueKey('quiz_history_retry'),
          )
        else if (!loaded)
          ProductLoadState(error: null, onRetry: load)
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s8),
            child: Text(
              '아직 답한 문제가 없어요.',
              key: const ValueKey('quiz_history_empty'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ];
    }
    return [
      Material(
        color: ProductColors.raised,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: MeetingColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: 2,
          ),
          child: Column(
            children: [
              for (final (i, q) in items.indexed)
                _ReviewRow(
                  question: q,
                  divided: i < items.length - 1,
                  onTap: busy ? null : () => open(q.assignmentId),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: Space.s3),
      if (listError != null) ...[
        Text(
          listError!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        TextButton(
          key: const ValueKey('quiz_history_retry'),
          onPressed: busy ? null : load,
          child: const Text('다시 시도'),
        ),
      ] else if (busy)
        const Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: MeetingColors.primary,
            ),
          ),
        )
      else if (more)
        TextButton(
          key: const ValueKey('quiz_history_more'),
          onPressed: load,
          child: const Text('이전 문제 더 보기'),
        ),
    ];
  }

  List<Widget> detail() {
    final q = review;
    if (q == null) {
      return [
        ProductLoadState(
          error: reviewError,
          onRetry: () => open(reviewId!),
          retryKey: const ValueKey('quiz_history_retry'),
        ),
      ];
    }
    return [
      QuizQuestionCard(question: q, kicker: quizDateLabel(q.date)),
      const SizedBox(height: 14),
      for (final (index, label) in q.choices.indexed) ...[
        if (index > 0) const SizedBox(height: 10),
        QuizOption(
          key: ValueKey('quiz_${q.assignmentId}_choice_$index'),
          label: label,
          state: quizOptionState(q, index),
          selected: index == q.answerIndex,
          tag: quizOptionTag(q, index),
        ),
      ],
      const SizedBox(height: Space.s4),
      QuizResult(question: q, received: false),
      const SizedBox(height: Space.s3),
      Text(
        '복습은 포인트가 다시 지급되지 않아요.',
        key: const ValueKey('quiz_review_note'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }
}

/// A submitted question: its date, the question and, once both indexes are
/// known, whether the answer was right. Points never decide right or wrong.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.question,
    required this.divided,
    required this.onTap,
  });
  final QuizQuestion question;
  final bool divided;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final judged = q.answerIndex != null && q.correctIndex != null;
    final right = judged && q.answerIndex == q.correctIndex;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          key: ValueKey('quiz_history_${q.assignmentId}'),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: divided
                ? const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: ProductColors.divider),
                    ),
                  )
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Text(
                        quizDateLabel(q.date),
                        style: meetingType(
                          12,
                          16,
                          FontWeight.w700,
                          MeetingColors.muted,
                        ),
                      ),
                      Text(
                        q.question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: meetingType(14.5, 20, FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (judged) ...[
                  const SizedBox(width: Space.s3),
                  TextChip(
                    right ? '정답' : '오답',
                    key: ValueKey('quiz_history_${q.assignmentId}_result'),
                    tone: right ? TextChipTone.record : TextChipTone.error,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
