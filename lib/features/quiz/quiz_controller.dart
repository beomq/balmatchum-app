import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart';

import 'quiz_repository.dart';

class QuizController extends ChangeNotifier {
  QuizController(this.repository, {required this.isCurrentAccount});
  final QuizRepository repository;
  final bool Function() isCurrentAccount;
  QuizToday? today;
  bool busy = false;
  bool adBusy = false;
  String? premiumError;
  bool get premiumReady =>
      premiumError == null && today?.premiumStatus == 'active';
  bool needsRefresh = false;
  String? notice;
  String? verifiedIntent;
  bool _disposed = false;
  Future<QuizQuestion> Function()? _pending;
  bool _ambiguous = false;
  int? pendingAnswer;
  bool get isActive => !_disposed && isCurrentAccount();
  bool get hasPending => _pending != null;
  bool get canAct =>
      isActive && !busy && !adBusy && !hasPending && !needsRefresh;

  bool beginAd() {
    if (!canAct) return false;
    adBusy = true;
    _notify();
    return true;
  }

  void endAd() {
    adBusy = false;
    _notify();
  }

  Future<void> checkPremium() async {
    if (!canAct) return;
    busy = true;
    premiumError = 'checking';
    _notify();
    try {
      final value = await repository.getTodayWithPremium();
      _check();
      if (today?.date != value.date ||
          today?.extraRevision != value.extraRevision ||
          value.extraStatus != 'adRequired') {
        verifiedIntent = null;
      }
      today = value;
      premiumError = null;
    } on BillingException catch (e) {
      if (isActive) premiumError = e.code;
    } catch (_) {
      if (isActive) premiumError = 'temporarilyUnavailable';
    } finally {
      busy = false;
      _notify();
    }
  }

  void _check() {
    if (!isActive) throw StateError('Quiz account changed');
  }

  void _notify() {
    if (isActive) notifyListeners();
  }

  Future<void> load() async {
    if (!isActive || busy || adBusy || hasPending) return;
    busy = true;
    notice = null;
    _notify();
    try {
      await _refresh();
    } catch (_) {
      if (isActive) notice = '오늘의 퀴즈를 불러오지 못했어요. 다시 조회해 주세요.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _refresh() async {
    final value = await repository.getToday();
    _check();
    if (today?.date != value.date ||
        today?.extraRevision != value.extraRevision ||
        value.extraStatus != 'adRequired') {
      verifiedIntent = null;
    }
    today = value;
    premiumError = null;
    needsRefresh = false;
  }

  void captureVerified(AdIntent intent, String date, int revision) {
    if (isActive &&
        !busy &&
        !hasPending &&
        !needsRefresh &&
        intent.status == 'verified' &&
        intent.purpose == 'extraQuiz' &&
        intent.targetDate == date &&
        intent.targetRevision == revision &&
        today?.date == date &&
        today?.extraRevision == revision &&
        today?.extraStatus == 'adRequired') {
      verifiedIntent = intent.id;
      _notify();
    }
  }

  Future<void> answer(QuizQuestion question, int index) async {
    if (!canAct || question.answerIndex != null) return;
    final requestId = Uuid().v4();
    pendingAnswer = index;
    _pending = () => repository.answer(question, index, requestId);
    await retry();
  }

  Future<void> unlockExtra() async {
    if (!canAct ||
        verifiedIntent == null ||
        today?.extraStatus != 'adRequired') {
      return;
    }
    final date = today!.date;
    final revision = today!.extraRevision!;
    final intent = verifiedIntent!;
    final requestId = Uuid().v4();
    _pending = () => repository.unlockExtra(date, revision, intent, requestId);
    await retry();
  }

  Future<void> unlockExtraWithPremium() async {
    if (!canAct || !premiumReady || today?.extraStatus != 'premiumAvailable') {
      return;
    }
    final date = today!.date;
    final revision = today!.extraRevision!;
    final requestId = Uuid().v4();
    _pending = () =>
        repository.unlockExtraWithPremium(date, revision, requestId);
    await retry();
  }

  Future<void> retry() async {
    if (!isActive || busy || adBusy || _pending == null) return;
    busy = true;
    notice = null;
    _notify();
    try {
      final result = await _pending!();
      _check();
      final wasAnswer = pendingAnswer != null;
      _pending = null;
      _ambiguous = false;
      pendingAnswer = null;
      verifiedIntent = null;
      notice = wasAnswer
          ? '답안 저장을 확인했어요. 이 문제의 지급 기록은 ${result.awardedPoints}P예요. 재전송은 추가 지급되지 않아요.'
          : '추가 문제를 열었어요. 답을 제출하면 지급 기록을 확인할 수 있어요.';
      // Unlock replay can contain the original unanswered DTO. Always reconcile.
      needsRefresh = true;
      try {
        await _refresh();
      } catch (_) {
        if (isActive) notice = '요청은 완료됐어요. 최신 문제를 다시 조회해 주세요.';
      }
    } on ProductException catch (e) {
      if (isActive) {
        _pending = null;
        _ambiguous = false;
        pendingAnswer = null;
        verifiedIntent = null;
        needsRefresh = true;
        notice = quizError(e.code);
      }
    } on AdException catch (e) {
      if (isActive) {
        _pending = null;
        _ambiguous = false;
        pendingAnswer = null;
        verifiedIntent = null;
        needsRefresh = true;
        notice = quizError(e.code);
      }
    } on BillingException catch (e) {
      if (isActive) {
        premiumError = e.code;
        if (!_ambiguous) {
          _pending = null;
          needsRefresh = true;
        }
        notice = _ambiguous
            ? '구매 확인을 완료하지 못했어요. 같은 요청으로 다시 확인해 주세요.'
            : '구매 확인을 완료하지 못했어요. 오늘 상태를 다시 조회해 주세요.';
      }
    } catch (_) {
      _ambiguous = true;
      if (isActive) notice = '결과를 확인하지 못했어요. 선택을 바꾸지 말고 같은 요청으로 다시 확인해 주세요.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<List<QuizQuestion>> history(int? before) async {
    _check();
    final value = await repository.history(before);
    _check();
    return value;
  }

  Future<QuizQuestion> review(int id) async {
    _check();
    final value = await repository.review(id);
    _check();
    return value;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String quizError(String code) => switch (code) {
  'contentUnavailable' => '준비된 문제가 없어요. 나중에 다시 확인해 주세요.',
  'exhausted' => '준비된 문제를 모두 풀었어요. 지난 문제를 복습해 보세요.',
  'freeRequired' => '오늘 무료 문제를 먼저 제출해 주세요.',
  'quizClosed' => '날짜가 지나 제출이 닫힌 문제예요. 오늘 문제를 조회해 주세요.',
  'staleProjection' || 'staleQuestion' => '문제 상태가 바뀌었어요. 최신 문제를 조회해 주세요.',
  'alreadyAnswered' || 'dailyLimitReached' => '이미 처리된 문제예요. 최신 문제를 조회해 주세요.',
  'intentNotVerified' => '서버에서 광고 시청이 아직 확인되지 않았어요.',
  'targetMismatch' ||
  'intentNotFound' => '이 문제에 사용할 수 없는 광고예요. 최신 상태를 확인해 주세요.',
  'idempotencyConflict' => '기존 요청과 내용이 달라요. 최신 상태를 확인해 주세요.',
  _ => '요청을 처리할 수 없어요. 최신 상태를 확인해 주세요.',
};
