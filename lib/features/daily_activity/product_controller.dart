import 'package:balmatchum_client/balmatchum_client.dart' as api;
import 'package:flutter/foundation.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../quiz/quiz_screen.dart';
import '../records/records_models.dart';
import '../wardrobe/wardrobe_models.dart';
import '../watch_sync/watch_sync_service.dart';
import '../watch_sync/watch_bridge.dart';
import 'daily_steps_controller.dart';
import 'product_repository.dart';
import 'record_mapping.dart';
import 'step_upload.dart';

class ProductController extends ChangeNotifier {
  ProductController(
    this.repository,
    this.steps,
    this.watch, {
    this.account,
    this.isCurrentAccount,
  }) : connected = account != null;
  final ProductRepository repository;
  final DailyStepsController steps;
  final WatchSyncService? watch;
  final String? account;
  final bool Function()? isCurrentAccount;
  bool _disposed = false;
  bool get _active => !_disposed && (isCurrentAccount?.call() ?? true);
  bool connected;
  bool busy = false;
  bool adBusy = false;
  bool? premiumActive;
  bool get hasPendingClaim => _pendingClaim != null;
  DateTime? pendingClaimDate;
  Future<api.RewardGrant> Function()? _pendingClaim;
  String? _pendingClaimKey;
  bool _claimAmbiguous = false;
  bool get canClaim => _active && !busy && !adBusy && !hasPendingClaim;

  bool beginAd() {
    if (!canClaim) return false;
    adBusy = true;
    notifyListeners();
    return true;
  }

  void endAd() {
    adBusy = false;
    notifyListeners();
  }

  Future<void> checkPremium() => _mutate(() async {
    premiumActive = null;
    final entitlement = await repository.entitlement();
    _checkAccount();
    premiumActive = entitlement.active;
  });
  String? error;
  api.DailyRecord? today;
  api.WalletView? wallet;
  bool get isActive => _active;
  api.ThemeStore? store;
  api.DailyQuiz? quiz;
  final _requests = <String, String>{};

  void _checkAccount() {
    if (!_active) throw const FormatException('Account changed');
  }

  @override
  void notifyListeners() {
    if (_active) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    _requests.clear();
    super.dispose();
  }

  void disconnect() {
    connected = false;
    today = null;
    wallet = null;
    store = null;
    quiz = null;
  }

  String request(String key) =>
      _requests.putIfAbsent(key, () => api.Uuid().v4());

  Future<void> connect() async {
    if (busy || !_active) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (account == null) await repository.connectDevelopmentUser();
      _checkAccount();
      connected = true;
      await refresh();
    } catch (_) {
      disconnect();
      if (_active) {
        error = account == null
            ? '개발 서버 연결을 확인해 주세요. 테스트 세션이 필요해요.'
            : '기록을 불러오지 못했어요. 연결 상태를 확인해 주세요.';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _checkAccount();
    final day = await repository.day(ProductRepository.today);
    _checkAccount();
    final balance = await repository.wallet();
    _checkAccount();
    var themes = store;
    try {
      themes = await repository.themes();
    } catch (_) {
      // A real account's theme is decoration; keep the last known store
      // so steps, points and records still refresh.
      if (account == null) rethrow;
    }
    _checkAccount();
    if (account == null) {
      final question = await repository.quiz(ProductRepository.today);
      _checkAccount();
      quiz = question;
    }
    store = themes;
    today = day;
    wallet = balance;
    notifyListeners();
  }

  Future<void> refreshAfterSuccess() async {
    try {
      await refresh();
    } catch (_) {
      if (!_active) return;
      error = '작업은 완료됐지만 최신 화면을 불러오지 못했어요. 다시 동기화해 주세요.';
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (busy || adBusy || hasPendingClaim || !connected || !_active) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (account == null) await repository.connectDevelopmentUser();
      _checkAccount();
      await steps.refresh();
      _checkAccount();
      final observation = steps.result;
      if (observation != null &&
          (account == null ||
              observation.status == DailyStepsStatus.available)) {
        await StepUpload(
          repository.client,
          repository.client.auth.authInfo!.authUserId.toString(),
        ).submit(observation);
      }
      _checkAccount();
      await watch?.resumeAndSync();
      _checkAccount();
      await refresh();
    } catch (_) {
      disconnect();
      if (_active) error = '동기화를 완료하지 못했어요. 기기의 기록은 유지돼요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<RecordMonth> loadMonth(DateTime date) async {
    _checkAccount();
    final days = await repository.month(date);
    _checkAccount();
    return RecordMonth(month: date, days: days.map(recordDay).toList());
  }

  Future<RecordDay> loadDay(DateTime date) async {
    _checkAccount();
    final day = await repository.day(date);
    _checkAccount();
    return recordDay(day);
  }

  Future<T> _mutate<T>(
    Future<T> Function() action, {
    bool replay = false,
  }) async {
    _checkAccount();
    if (busy || adBusy || (hasPendingClaim && !replay)) {
      throw const FormatException('Product operation in progress');
    }
    busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<RecordDay> deleteDay(DateTime date) => _mutate(() async {
    final key = 'delete:${ProductRepository.dateKey(date)}';
    final result = await repository.deleteDay(date, request(key));
    _checkAccount();
    _requests.remove(key);
    await refreshAfterSuccess();
    _checkAccount();
    return recordDay(result);
  });

  Future<int> claim(RecordDay day) => _claim(day);

  Future<int> claimWithAd(RecordDay day, String intentId) =>
      _claim(day, intentId: intentId);

  Future<int> claimWithPremium(RecordDay day) => _claim(day, premium: true);

  Future<int> _claim(RecordDay day, {String? intentId, bool premium = false}) {
    _checkAccount();
    if (busy || adBusy) {
      throw const FormatException('Product operation in progress');
    }
    final date = ProductRepository.dateKey(day.date);
    final key = 'claim:$date:${day.revision}:$intentId:$premium';
    if (hasPendingClaim) {
      if (_pendingClaimKey != key) {
        throw const FormatException('Replay the original claim first');
      }
      return retryClaim();
    }
    if (premium && premiumActive != true) {
      throw const FormatException('Fresh entitlement required');
    }
    final requestId = request(key);
    _pendingClaimKey = key;
    pendingClaimDate = day.date;
    _pendingClaim = premium
        ? () => repository.claimWithPremium(date, requestId, day.revision)
        : intentId == null
        ? () => repository.claim(date, requestId, day.revision)
        : () => repository.claimWithAd(date, requestId, day.revision, intentId);
    return retryClaim();
  }

  void _clearClaim() {
    _requests.remove(_pendingClaimKey);
    _pendingClaimKey = null;
    _pendingClaim = null;
    pendingClaimDate = null;
    _claimAmbiguous = false;
  }

  Future<int> retryClaim() => _mutate(() async {
    final api.RewardGrant grant;
    try {
      grant = await _pendingClaim!();
    } on api.ProductException {
      _checkAccount();
      _clearClaim();
      premiumActive = null;
      rethrow;
    } on api.BillingException {
      // Retain the original payload even when a later store observation fails.
      // A previous ambiguous attempt may already have committed successfully.
      premiumActive = null;
      if (!_claimAmbiguous) _clearClaim();
      rethrow;
    } catch (_) {
      _claimAmbiguous = true;
      rethrow;
    }
    _checkAccount();
    _clearClaim();
    premiumActive = null;
    today = null;
    wallet = null;
    notifyListeners();
    await refreshAfterSuccess();
    _checkAccount();
    return grant.amount;
  }, replay: true);

  QuizView quizView(api.DailyQuiz value) => QuizView(
    date: value.date,
    questionId: value.questionId,
    question: value.question,
    choices: value.choices,
    answerIndex: value.answerIndex,
    correctIndex: value.correctIndex,
    explanation: value.explanation,
    awardedPoints: value.awardedPoints,
    fixtureLabel: value.fixtureLabel,
  );

  void _requireFixture() {
    _checkAccount();
    if (account != null) throw const FormatException('Fixture unavailable');
  }

  Future<QuizView> loadQuiz() async {
    _requireFixture();
    return quizView(await repository.quiz(ProductRepository.today));
  }

  Future<QuizView> answer(QuizView question, int index) => _mutate(() async {
    _requireFixture();
    final key = 'quiz:${question.date}:$index';
    quiz = await repository.answer(question.date, index, request(key));
    _requests.remove(key);
    notifyListeners();
    return quizView(quiz!);
  });

  WardrobeSnapshot wardrobe(api.ThemeStore value) => WardrobeSnapshot(
    equippedThemeId: value.equippedTheme,
    balance: value.balance,
    fixtureLabel: value.fixtureLabel,
    themes: [
      for (final item in value.items)
        WardrobeTheme(
          id: item.themeId,
          name: item.name,
          owned: item.owned,
          colorValue: item.colorValue,
          price: item.price,
          backgroundAsset: item.themeId == 'sunny'
              ? 'assets/first_meeting/sunny.png'
              : null,
        ),
    ],
  );

  Future<WardrobeSnapshot> loadWardrobe() async {
    _checkAccount();
    final value = await repository.themes();
    _checkAccount();
    store = value;
    notifyListeners();
    return wardrobe(value);
  }

  Future<WardrobeSnapshot> themeAction(
    WardrobeTheme theme, {
    required bool equip,
  }) => _mutate(() async {
    final key = '${equip ? 'equip' : 'buy'}:${theme.id}';
    try {
      final confirmed = equip
          ? await repository.equip(theme.id, request(key))
          : await repository.purchase(theme.id, request(key));
      _requests.remove(key);
      try {
        store = await repository.themes();
      } on Exception {
        store = null;
        error = '작업은 완료됐지만 현재 적용 상태를 확인하지 못했어요. 다시 조회해 주세요.';
        notifyListeners();
        return WardrobeSnapshot(
          themes: wardrobe(confirmed).themes,
          equippedThemeId: null,
          fixtureLabel: confirmed.fixtureLabel,
        );
      }
      notifyListeners();
      return wardrobe(store!);
    } on api.ProductException catch (e) {
      throw WardrobeActionException(
        e.code == 'insufficientPoints'
            ? WardrobeFailureReason.insufficientPoints
            : WardrobeFailureReason.unavailable,
      );
    }
  });
}
