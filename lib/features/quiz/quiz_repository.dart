import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../billing/billing_repository.dart';
import '../daily_activity/scoped_client.dart';

/// Each operation captures its credentials, never the next account's session.
class QuizRepository {
  QuizRepository(
    this.client,
    this.accountId, {
    this.billing,
    ScopedClientPool? pool,
  }) : pool =
           pool ??
           ScopedClientPool(
             host: client.host,
             connectionTimeout: client.connectionTimeout,
           );
  final Client client;
  final ScopedClientPool pool;
  final String accountId;
  final ServerpodBillingRepository? billing;

  Future<QuizToday> getTodayWithPremium() =>
      billing!.request((c) => c.quiz.getTodayWithPremium());
  Future<QuizQuestion> unlockExtraWithPremium(
    String date,
    int revision,
    String requestId,
  ) => billing!.request(
    (c) => c.quiz.unlockExtraWithPremium(date, revision, requestId),
  );

  Future<T> _request<T>(Future<T> Function(Client) request) async {
    final authentication = client.auth.authInfo;
    if (authentication?.authUserId.toString() != accountId) {
      throw StateError('Quiz account changed');
    }
    final header = await client.auth.authHeaderValue;
    if (header == null || !identical(authentication, client.auth.authInfo)) {
      throw StateError('Quiz authentication changed');
    }
    return pool.run(header, _QuizHeader.new, (scoped) async {
      final value = await request(scoped);
      if (!identical(authentication, client.auth.authInfo)) {
        throw StateError('Quiz authentication changed');
      }
      return value;
    });
  }

  void close() => pool.close();

  Future<QuizToday> getToday() => _request((c) => c.quiz.getToday());
  Future<QuizQuestion> answer(QuizQuestion q, int index, String requestId) =>
      _request(
        (c) => c.quiz.answer(
          q.assignmentId,
          q.questionId,
          q.version,
          index,
          requestId,
        ),
      );
  Future<QuizQuestion> unlockExtra(
    String date,
    int revision,
    String intent,
    String requestId,
  ) => _request((c) => c.quiz.unlockExtra(date, revision, intent, requestId));
  Future<List<QuizQuestion>> history(int? before) =>
      _request((c) => c.quiz.listHistory(before));
  Future<QuizQuestion> review(int assignmentId) =>
      _request((c) => c.quiz.review(assignmentId));
}

class _QuizHeader implements ClientAuthKeyProvider {
  _QuizHeader(this.header);
  final String header;
  @override
  Future<String?> get authHeaderValue async => header;
}
