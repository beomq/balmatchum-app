import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/quiz/quiz_repository.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'authenticated_quiz_test.dart' show question;

/// Answered history in pages of two, newest assignment first.
class History extends QuizRepository {
  History(this.items) : super(Client('http://localhost/'), 'A');
  final List<QuizQuestion> items;
  final cursors = <int?>[];

  @override
  Future<List<QuizQuestion>> history(int? before) async {
    cursors.add(before);
    return items
        .where((q) => before == null || q.assignmentId < before)
        .take(2)
        .toList();
  }
}

QuizQuestion answered(int id, String date, {bool correct = true}) =>
    question(id, answered: true).copyWith(
      date: date,
      answerIndex: correct ? 0 : 1,
      correctIndex: 0,
      awardedPoints: correct ? 2 : 0,
    );

void main() {
  test('a date is read back page by page and the read stops past it', () async {
    final repository = History([
      answered(9, '2026-10-28'),
      answered(8, '2026-10-27'),
      answered(7, '2026-10-26'),
      answered(6, '2026-10-26', correct: false),
      answered(5, '2026-10-25'),
      answered(4, '2026-10-24'),
      answered(3, '2026-10-23'),
    ]);
    final controller = QuizController(repository, isCurrentAccount: () => true);
    addTearDown(() {
      controller.dispose();
      repository.client.close();
    });
    final day = await controller.dayQuiz('2026-10-26');
    expect((day.answered, day.correct, day.points), (2, 1, 2));
    // Pages 9-8, 7-6 and 5-4; 5 is older, so nothing past it is read.
    expect(repository.cursors, [null, 8, 6]);
    repository.cursors.clear();
    final none = await controller.dayQuiz('2026-10-01');
    expect(none.answered, 0);
    expect(repository.cursors.last, isNotNull);
    final empty = History(const []);
    final quiet = QuizController(empty, isCurrentAccount: () => true);
    addTearDown(() {
      quiet.dispose();
      empty.client.close();
    });
    expect((await quiet.dayQuiz('2026-10-26')).answered, 0);
    expect(empty.cursors, [null]);
  });
}
