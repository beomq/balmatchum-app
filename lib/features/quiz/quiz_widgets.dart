import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart';
import '../records/status_widgets.dart';
import '../wardrobe/dog_sprite.dart';

/// How a [QuizOption] reads: open, sent and waiting for the server, sent
/// but unconfirmed, the right answer, the user's wrong answer, or one of
/// the others once answered.
enum QuizOptionState { idle, sending, chosen, correct, wrong, rest }

/// The state of choice [index] of [question]. [pending] is the choice whose
/// request the server has not confirmed; [sending] while it is in flight.
QuizOptionState quizOptionState(
  QuizQuestion question,
  int index, {
  int? pending,
  bool sending = false,
}) {
  final mine = question.answerIndex;
  final correct = question.correctIndex;
  if (mine == null) {
    if (index != pending) return QuizOptionState.idle;
    return sending ? QuizOptionState.sending : QuizOptionState.chosen;
  }
  // Right and wrong are judged only when the server sent both indexes.
  if (correct == null) {
    return index == mine ? QuizOptionState.chosen : QuizOptionState.rest;
  }
  if (index == correct) return QuizOptionState.correct;
  if (index == mine) return QuizOptionState.wrong;
  return QuizOptionState.rest;
}

/// The word after a choice once answered wrong: the real answer and the
/// user's own. A right answer needs none; the panel says it.
String? quizOptionTag(QuizQuestion question, int index) {
  final mine = question.answerIndex;
  final correct = question.correctIndex;
  if (mine == null || correct == null || mine == correct) return null;
  if (index == correct) return '정답';
  if (index == mine) return '내 답';
  return null;
}

/// `Quiz/Option` (`LEfqt`): one choice as a rounded card with a round marker
/// and a label that wraps. Right and wrong also read as a mark and a word,
/// never as color alone, and the other choices stay readable.
class QuizOption extends StatelessWidget {
  const QuizOption({
    required this.label,
    required this.state,
    this.selected = false,
    this.tag,
    this.onTap,
    super.key,
  });
  final String label;
  final QuizOptionState state;

  /// The user's own choice, sent or answered.
  final bool selected;
  final String? tag;

  /// Null while the choice cannot be sent.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (fill, line, ink) = switch (state) {
      QuizOptionState.idle => (
        ProductColors.raised,
        MeetingColors.line,
        MeetingColors.ink,
      ),
      QuizOptionState.sending || QuizOptionState.chosen => (
        ProductColors.raised,
        MeetingColors.primaryStrong,
        MeetingColors.ink,
      ),
      QuizOptionState.correct => (
        ProductColors.recordSoft,
        ProductColors.record,
        ProductColors.recordInk,
      ),
      QuizOptionState.wrong => (
        ProductColors.errorSoft,
        ProductColors.error,
        MeetingColors.ink,
      ),
      QuizOptionState.rest => (
        MeetingColors.well,
        MeetingColors.line,
        MeetingColors.muted,
      ),
    };
    final width = line == MeetingColors.line ? 1.0 : 2.0;
    final shape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      side: BorderSide(color: line, width: width),
    );
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        selected: selected,
        child: Material(
          color: fill,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              // The thicker line keeps the content in place.
              padding: EdgeInsets.all(15 - width),
              child: Row(
                children: [
                  _Marker(state),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Text(
                      label,
                      style: meetingType(15, 21, FontWeight.w700, ink),
                    ),
                  ),
                  if (tag case final tag?) ...[
                    const SizedBox(width: Space.s2),
                    Text(
                      tag,
                      style: meetingType(
                        12,
                        16,
                        FontWeight.w700,
                        state == QuizOptionState.correct
                            ? ProductColors.recordInk
                            : line,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker(this.state);
  final QuizOptionState state;

  static const size = 24.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: switch (state) {
      QuizOptionState.correct || QuizOptionState.wrong => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: state == QuizOptionState.correct
              ? ProductColors.record
              : ProductColors.error,
        ),
        child: Center(
          child: Text(
            state == QuizOptionState.correct ? '✓' : '✕',
            semanticsLabel: state == QuizOptionState.correct ? '정답' : '오답',
            style: meetingType(13, 16, FontWeight.w800, ProductColors.raised),
          ),
        ),
      ),
      QuizOptionState.sending => const Padding(
        padding: EdgeInsets.all(3),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: MeetingColors.primaryStrong,
        ),
      ),
      QuizOptionState.chosen => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: MeetingColors.primaryStrong, width: 2),
        ),
        child: const Center(
          child: SizedBox.square(
            dimension: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MeetingColors.primaryStrong,
              ),
            ),
          ),
        ),
      ),
      QuizOptionState.idle || QuizOptionState.rest => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: MeetingColors.line, width: 1.5),
        ),
      ),
    },
  );
}

/// `Quiz Question Card`: a kicker, the question and the conditions it holds
/// under, readable before and after an answer.
class QuizQuestionCard extends StatelessWidget {
  const QuizQuestionCard({
    required this.question,
    required this.kicker,
    super.key,
  });
  final QuizQuestion question;
  final String kicker;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: ProductColors.raised,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: MeetingColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s2,
        children: [
          if (fixtureLabelsVisible && question.fixtureLabel != null) ...[
            FixtureBadge(question.fixtureLabel!),
            Text('테스트 문항이며 운영 포인트에 포함되지 않아요.', style: small),
          ],
          Text(
            kicker,
            style: meetingType(12, 16, FontWeight.w800, MeetingColors.primary),
          ),
          Text(
            question.question,
            style: meetingType(19, 27.5, FontWeight.w800),
          ),
          Text(
            '적용 조건 · ${question.conditions}',
            key: ValueKey('quiz_conditions_${question.assignmentId}'),
            style: small,
          ),
        ],
      ),
    );
  }
}

/// An answered question's result: right or wrong, the server's grant record
/// and the explanation. The source and review details open from the info
/// button.
class QuizResult extends StatefulWidget {
  const QuizResult({
    required this.question,
    required this.received,
    this.dogAsset,
    super.key,
  });
  final QuizQuestion question;

  /// This screen's own answer was just confirmed, so the grant reads as
  /// received now. Otherwise it is the question's earlier record.
  final bool received;

  /// The user's own companion (guide 3.6); a review passes none.
  final String? dogAsset;

  @override
  State<QuizResult> createState() => _QuizResultState();
}

class _QuizResultState extends State<QuizResult> {
  bool details = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final id = q.assignmentId;
    final right = q.answerIndex == q.correctIndex;
    final points = formatCount(q.awardedPoints);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        Row(
          children: [
            if (widget.dogAsset case final dog?) ...[
              SizedBox.square(
                key: ValueKey('quiz_${id}_dog'),
                dimension: DogSpriteSize.companion,
                child: DogSprite(asset: dog),
              ),
              const SizedBox(width: Space.s3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      right ? '정답이에요!' : '아쉽지만 오답이에요',
                      key: ValueKey(
                        right ? 'quiz_result_correct' : 'quiz_result_wrong',
                      ),
                      style: meetingType(
                        21,
                        28,
                        FontWeight.w800,
                        right ? ProductColors.record : ProductColors.error,
                      ),
                    ),
                  ),
                  if (widget.received && q.awardedPoints > 0)
                    TextChip(
                      '+${points}P 받음',
                      key: ValueKey('quiz_${id}_award_new'),
                      tone: TextChipTone.record,
                    )
                  else
                    TextChip(
                      '지급 기록 ${points}P',
                      key: ValueKey('quiz_${id}_past_points'),
                    ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('quiz_${id}_info'),
              tooltip: '문제 정보',
              onPressed: () => setState(() => details = !details),
              icon: const PixelIcon('info', size: 20),
            ),
          ],
        ),
        if (q.explanation case final explanation?)
          Text(explanation, style: text.bodyMedium),
        if (details)
          Container(
            key: ValueKey('quiz_${id}_details'),
            padding: const EdgeInsets.all(Space.s3),
            decoration: BoxDecoration(
              color: MeetingColors.pressed,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s1,
              children: [
                if (q.source case final source?)
                  SelectableText('출처 · $source', style: text.bodySmall),
                Text(
                  '검토일 ${q.reviewedAt} · ${q.reviewedBy}',
                  style: text.bodySmall,
                ),
                Text(
                  '이 문제의 지급 기록 ${points}P · 복습은 추가 지급 없음',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 'YYYY-MM-DD' as '10월 27일 (화)'.
String quizDateLabel(String date) {
  final day = DateTime.tryParse(date);
  if (day == null) return date;
  return '${day.month}월 ${day.day}일 (${_weekdays[day.weekday - 1]})';
}
