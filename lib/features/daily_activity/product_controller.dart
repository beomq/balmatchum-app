import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart' as api;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../quiz/quiz_screen.dart';
import '../records/records_models.dart';
import '../wardrobe/wardrobe_art.dart';
import '../wardrobe/wardrobe_models.dart';
import '../watch_sync/watch_sync_service.dart';
import '../watch_sync/watch_bridge.dart';
import 'daily_steps_controller.dart';
import 'home_bootstrap.dart';
import 'product_repository.dart';
import 'record_mapping.dart';
import 'step_streak.dart';
import 'step_upload.dart';

/// The bundled picture for a theme, or null where its colour is drawn.
String? themeBackgroundAsset(String themeId) => backgroundArt[themeId];

class ProductController extends ChangeNotifier {
  ProductController(
    this.repository,
    this.steps,
    this.watch, {
    this.account,
    this.isCurrentAccount,
    this.bootstrap,
    this.stepDirectory = getApplicationSupportDirectory,
  }) : connected = account != null;
  final ProductRepository repository;

  /// The snapshot started when the account was known; the first refresh
  /// takes it instead of reading the server again.
  final HomeBootstrap? bootstrap;

  /// Where the step upload keeps its pending payload.
  final Future<Directory> Function() stepDirectory;
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
  api.OutfitStore? outfits;
  api.DailyQuiz? quiz;

  /// Null until read, after a failed read and after a change that can break
  /// it, so the home never shows an old number.
  StepStreak? streak;

  /// The last [StepStreak.window] KST days of the last snapshot, kept so an
  /// upload answer can patch today without another read.
  List<api.DailyRecord> _recentDays = const [];
  DateTime? _snapshotDate;
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
    repository.close();
    _requests.clear();
    super.dispose();
  }

  void disconnect() {
    connected = false;
    today = null;
    wallet = null;
    store = null;
    outfits = null;
    wardrobeStore = null;
    quiz = null;
    streak = null;
    _recentDays = const [];
    _snapshotDate = null;
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

  /// One home snapshot replaces today, the wallet, themes, outfits and the
  /// streak together. A failed read throws and leaves the last state shown.
  Future<void> refresh() async {
    _checkAccount();
    final snapshot = await _readSnapshot();
    _checkAccount();
    if (account == null) {
      final question = await repository.quiz(ProductRepository.today);
      _checkAccount();
      quiz = question;
    }
    store = snapshot.themes;
    outfits = snapshot.outfits;
    wardrobeStore = snapshot.wardrobe;
    today = snapshot.day;
    wallet = snapshot.wallet;
    _recentDays = snapshot.recentDays;
    _snapshotDate = DateTime.parse(snapshot.date);
    // The same [StepStreak.window] days the records page reads.
    streak = StepStreak.of(_recentDays, _snapshotDate!);
    notifyListeners();
  }

  /// The bootstrap's snapshot the first time, a fresh read after that. A
  /// snapshot of another KST day than the device's is read once more; if the
  /// server still disagrees, its date is today (the device clock can be off).
  Future<api.HomeSnapshot> _readSnapshot() async {
    final started = account == null ? null : bootstrap?.take(account!);
    final snapshot = await (started ?? repository.home());
    if (snapshot.date == ProductRepository.dateKey(ProductRepository.today)) {
      return snapshot;
    }
    _checkAccount();
    return repository.home();
  }

  /// Puts an upload's answer in place of the same day without another read;
  /// the wallet, themes and outfits do not change with steps.
  void _patchDay(api.DailyRecord record) {
    if (today?.date == record.date) today = record;
    _recentDays = [
      for (final day in _recentDays)
        if (day.date != record.date) day,
      record,
    ];
    final date = _snapshotDate;
    if (date != null) streak = StepStreak.of(_recentDays, date);
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
      // The first refresh takes the bootstrap snapshot, so the home shows
      // without a round trip of its own; later ones read one snapshot.
      try {
        await refresh();
      } catch (_) {
        // A failed read keeps the last home on screen and skips the upload,
        // which needs today's record. An account change, or no home shown
        // yet, still clears everything below.
        if (!_active || _snapshotDate == null) rethrow;
        error = '동기화를 완료하지 못했어요. 기기의 기록은 유지돼요.';
        return;
      }
      _checkAccount();
      final observation = steps.result;
      if (observation != null &&
          (account == null ||
              observation.status == DailyStepsStatus.available)) {
        final uploaded =
            await StepUpload(
              repository.client,
              repository.client.auth.authInfo!.authUserId.toString(),
              pool: repository.pool,
              directory: stepDirectory,
            ).submit(
              observation,
              knownDay: today,
              knownStreamGeneration: wallet?.streamGeneration,
            );
        _checkAccount();
        if (uploaded != null) _patchDay(uploaded);
      }
      _checkAccount();
      // Only a connected watch adds round trips of its own here.
      await watch?.resumeAndSync();
    } catch (_) {
      disconnect();
      if (_active) error = '동기화를 완료하지 못했어요. 기기의 기록은 유지돼요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Reads the last [StepStreak.window] KST days for the home's streak and
  /// week count. Only reads; a failure leaves no number.
  Future<void> loadStreak() async {
    if (!connected || !_active) return;
    final today = ProductRepository.today;
    try {
      final records = await repository.days(
        today.subtract(const Duration(days: StepStreak.window - 1)),
        today,
      );
      _checkAccount();
      streak = StepStreak.of(records, today);
    } catch (_) {
      if (!_active) return;
      streak = null;
    }
    notifyListeners();
  }

  /// The records page's tiles (guide 7.1): the same one read of the last
  /// [StepStreak.window] KST days as the home's streak, so both agree. Only
  /// reads; a failed read throws and the tiles show no number.
  Future<RecordsSummary> loadRecordsSummary() async {
    _checkAccount();
    final today = ProductRepository.today;
    final records = await repository.days(
      today.subtract(const Duration(days: StepStreak.window - 1)),
      today,
    );
    _checkAccount();
    final streak = StepStreak.of(records, today);
    return RecordsSummary(
      thisWeek: streak.thisWeek,
      streak: streak.days,
      streakAtLeast: streak.atLeast,
      monthAverage: monthAverage(records, today),
    );
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
    // A deleted day can break the streak; the next home refresh reads it.
    streak = null;
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

  /// The last confirmed wardrobe (home snapshot, wardrobe read or action).
  api.WardrobeStore? wardrobeStore;

  /// What [breedId] wears by the last confirmed wardrobe, or null.
  DogLook? wornLook(String breedId) => wardrobeStore?.look(breedId);

  /// The equipped background by the last confirmed state.
  String? get equippedBackground =>
      wardrobeStore?.equippedBackground ?? store?.equippedTheme;

  /// Wardrobe writes whose answer was lost, by request key. A later read
  /// that shows the write applied settles it, so the next intent with the
  /// same key gets a fresh request id instead of replaying the old answer.
  final _unsettledWardrobe = <String, WardrobeAction>{};

  /// Applies a confirmed wardrobe state, and its balance to the home wallet
  /// (development fixture balances are kept apart from the step wallet).
  void _confirmWardrobe(api.WardrobeStore value) {
    wardrobeStore = value;
    final current = wallet;
    if (current != null && value.fixtureLabel == null) {
      wallet = current.copyWith(balance: value.balance);
    }
    for (final MapEntry(:key, value: action)
        in _unsettledWardrobe.entries.toList()) {
      if (value.confirms(action)) {
        _unsettledWardrobe.remove(key);
        _requests.remove(key);
      }
    }
  }

  Future<api.WardrobeStore> loadWardrobe() async {
    _checkAccount();
    final value = await repository.wardrobe();
    _checkAccount();
    _confirmWardrobe(value);
    notifyListeners();
    return value;
  }

  Future<api.WardrobeStore> wardrobeAction(WardrobeAction action) => _mutate(
    () async {
      final key = action.key;
      // A replayed answer can be stale; only a retry re-reads the server.
      final retry = _requests.containsKey(key);
      api.WardrobeStore answer;
      try {
        answer = await repository.wardrobeAction(action, request(key));
      } on api.ProductException catch (e) {
        _requests.remove(key);
        _unsettledWardrobe.remove(key);
        throw WardrobeActionException(switch (e.code) {
          'insufficientPoints' => WardrobeFailureReason.insufficientPoints,
          'outfitIncompatible' => WardrobeFailureReason.incompatible,
          'subscriptionRequired' => WardrobeFailureReason.subscriptionRequired,
          _ => WardrobeFailureReason.unavailable,
        });
      } catch (_) {
        // The server may have applied it: keep the key for a retry until a
        // read settles it.
        _unsettledWardrobe[key] = action;
        rethrow;
      }
      _requests.remove(key);
      _unsettledWardrobe.remove(key);
      _checkAccount();
      if (retry) answer = await repository.wardrobe();
      _checkAccount();
      _confirmWardrobe(answer);
      notifyListeners();
      return answer;
    },
  );
}
