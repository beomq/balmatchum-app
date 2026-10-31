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
import 'step_streak.dart';
import 'step_upload.dart';

/// Server theme ids with a bundled scene at `assets/first_meeting/<id>.png`
/// (design home-v1 backgrounds).
const _weatherBackgrounds = {'sunny', 'cloudy', 'rainy', 'snowy'};

/// The bundled picture for a theme, or null where its colour is drawn.
String? themeBackgroundAsset(String themeId) =>
    _weatherBackgrounds.contains(themeId)
    ? 'assets/first_meeting/$themeId.png'
    : null;

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
  api.OutfitStore? outfits;
  api.DailyQuiz? quiz;

  /// Null until read, after a failed read and after a change that can break
  /// it, so the home never shows an old number.
  StepStreak? streak;
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
    quiz = null;
    streak = null;
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
    // Each read is a round trip to a distant server, so all four start at
    // once instead of one after another.
    final dayRead = repository.day(ProductRepository.today);
    final walletRead = repository.wallet();
    // A real account's theme and outfits are decoration; keep the last known
    // state so steps, points and records still refresh.
    final themesRead = _orLast(repository.themes(), store);
    final wornRead = _orLast(repository.outfits(), outfits);
    // Every failure is still seen by the awaits below; this only stops a
    // later one from being reported as unhandled after an earlier throw.
    for (final read in [dayRead, walletRead, themesRead, wornRead]) {
      read.ignore();
    }
    final day = await dayRead;
    final balance = await walletRead;
    final themes = await themesRead;
    final worn = await wornRead;
    _checkAccount();
    if (account == null) {
      final question = await repository.quiz(ProductRepository.today);
      _checkAccount();
      quiz = question;
    }
    store = themes;
    outfits = worn;
    today = day;
    wallet = balance;
    notifyListeners();
  }

  Future<T?> _orLast<T>(Future<T> read, T? last) => account == null
      ? read
      : read.then<T?>((value) => value, onError: (Object _) => last);

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
          pool: repository.pool,
        ).submit(
          observation,
          knownDay: today,
          knownStreamGeneration: wallet?.streamGeneration,
        );
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

  /// [balance] overrides the theme store's when [outfitStore] was read later.
  WardrobeSnapshot wardrobe(
    api.ThemeStore value, {
    api.OutfitStore? outfitStore,
    int? balance,
  }) => WardrobeSnapshot(
    equippedThemeId: value.equippedTheme,
    balance: balance ?? value.balance,
    fixtureLabel: value.fixtureLabel,
    outfits: outfitStore == null ? null : outfitView(outfitStore),
    themes: [
      for (final item in value.items)
        WardrobeTheme(
          id: item.themeId,
          name: item.name,
          owned: item.owned,
          colorValue: item.colorValue,
          price: item.price,
          backgroundAsset: themeBackgroundAsset(item.themeId),
        ),
    ],
  );

  WardrobeOutfits outfitView(api.OutfitStore value) => WardrobeOutfits(
    equippedId: value.equippedOutfit,
    items: [
      for (final item in value.items)
        WardrobeOutfit(
          id: item.outfitId,
          name: item.name,
          price: item.price,
          owned: item.owned,
          // Without a server profile there is no breed to fit.
          compatible: item.compatible && value.breedId != null,
        ),
    ],
  );

  /// The layer to draw over the [breedId] sprite from the last confirmed
  /// server outfit state, or null.
  String? wornLayer(String breedId) {
    final value = outfits;
    return value == null ? null : outfitView(value).wornLayer(breedId);
  }

  /// The wardrobe as the last refresh saw it, shown at once while
  /// [loadWardrobe] confirms it with the server.
  WardrobeSnapshot? get cachedWardrobe {
    final value = store;
    final worn = outfits;
    return value == null
        ? null
        : wardrobe(value, outfitStore: worn, balance: worn?.balance);
  }

  Future<WardrobeSnapshot> loadWardrobe() async {
    _checkAccount();
    final themesRead = repository.themes();
    // The outfit shelf shows its own reload; themes stay usable.
    final wornRead = repository.outfits().then<api.OutfitStore?>(
      (value) => value,
      onError: (Object _) => null,
    );
    final value = await themesRead;
    final worn = await wornRead;
    _checkAccount();
    store = value;
    if (worn != null) outfits = worn;
    notifyListeners();
    return wardrobe(value, outfitStore: worn, balance: worn?.balance);
  }

  Future<WardrobeSnapshot> themeAction(
    WardrobeTheme theme, {
    required bool equip,
  }) => _mutate(() async {
    final key = '${equip ? 'equip' : 'buy'}:${theme.id}';
    // A replayed answer can be stale; only a retry re-reads the server.
    final retry = _requests.containsKey(key);
    try {
      final confirmed = equip
          ? await repository.equip(theme.id, request(key))
          : await repository.purchase(theme.id, request(key));
      _requests.remove(key);
      if (!retry) {
        store = confirmed;
        notifyListeners();
        return wardrobe(confirmed, outfitStore: outfits);
      }
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
      return wardrobe(store!, outfitStore: outfits);
    } on api.ProductException catch (e) {
      _requests.remove(key);
      throw WardrobeActionException(
        e.code == 'insufficientPoints'
            ? WardrobeFailureReason.insufficientPoints
            : WardrobeFailureReason.unavailable,
      );
    }
  });

  Future<WardrobeSnapshot> outfitAction(
    WardrobeOutfit outfit,
    OutfitChange change,
  ) => _mutate(() async {
    final key = 'outfit:${change.name}:${outfit.id}';
    final retry = _requests.containsKey(key);
    api.OutfitStore? answer;
    try {
      final requestId = request(key);
      answer = await switch (change) {
        OutfitChange.purchase => repository.purchaseOutfit(
          outfit.id,
          requestId,
        ),
        OutfitChange.wear => repository.equipOutfit(outfit.id, requestId),
        OutfitChange.remove => repository.unequipOutfit(requestId),
      };
    } on api.ProductException catch (e) {
      _requests.remove(key);
      throw WardrobeActionException(switch (e.code) {
        'insufficientPoints' => WardrobeFailureReason.insufficientPoints,
        'outfitIncompatible' => WardrobeFailureReason.incompatible,
        _ => WardrobeFailureReason.unavailable,
      });
    }
    _requests.remove(key);
    _checkAccount();
    api.OutfitStore? worn;
    if (retry) {
      try {
        // A replayed answer can be stale; show what the server holds now.
        worn = await repository.outfits();
      } catch (_) {
        error = '작업은 완료됐지만 현재 적용 상태를 확인하지 못했어요. 다시 조회해 주세요.';
      }
    } else {
      worn = answer;
    }
    _checkAccount();
    outfits = worn;
    final themes = store;
    return themes == null
        // The theme state is unknown as well; the screen asks for a reload.
        ? WardrobeSnapshot(
            themes: const [],
            equippedThemeId: null,
            balance: worn?.balance,
          )
        : wardrobe(themes, outfitStore: worn, balance: worn?.balance);
  });
}
