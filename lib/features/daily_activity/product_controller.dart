import 'package:balmatchum_client/balmatchum_client.dart' as api;
import 'package:flutter/foundation.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../quiz/quiz_screen.dart';
import '../records/records_models.dart';
import '../wardrobe/wardrobe_models.dart';
import '../watch_sync/watch_sync_service.dart';
import 'daily_steps_controller.dart';
import 'product_repository.dart';
import 'record_mapping.dart';
import 'step_upload.dart';

class ProductController extends ChangeNotifier {
  ProductController(this.repository, this.steps, this.watch);
  final ProductRepository repository;
  final DailyStepsController steps;
  final WatchSyncService? watch;
  bool connected = false;
  bool busy = false;
  String? error;
  api.DailyRecord? today;
  api.ThemeStore? store;
  api.DailyQuiz? quiz;
  final _requests = <String, String>{};

  void disconnect() {
    connected = false;
    today = null;
    store = null;
    quiz = null;
  }

  String request(String key) =>
      _requests.putIfAbsent(key, () => api.Uuid().v4());

  Future<void> connect() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await repository.connectDevelopmentUser();
      connected = true;
      await refresh();
    } on Exception {
      disconnect();
      error = '개발 서버 연결을 확인해 주세요. 테스트 세션이 필요해요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    today = await repository.day(ProductRepository.today);
    store = await repository.themes();
    quiz = await repository.quiz(ProductRepository.today);
    notifyListeners();
  }

  Future<void> refreshAfterSuccess() async {
    try {
      await refresh();
    } on Exception {
      error = '작업은 완료됐지만 최신 화면을 불러오지 못했어요. 다시 동기화해 주세요.';
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (busy || !connected) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await repository.connectDevelopmentUser();
      await steps.refresh();
      final observation = steps.result;
      if (observation != null) {
        await StepUpload(
          repository.client,
          repository.client.auth.authInfo!.authUserId.toString(),
        ).submit(observation);
      }
      await watch?.resumeAndSync();
      await refresh();
    } on Exception {
      disconnect();
      error = '동기화를 완료하지 못했어요. 기기의 기록은 유지돼요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<RecordMonth> loadMonth(DateTime date) async => RecordMonth(
    month: date,
    days: (await repository.month(date)).map(recordDay).toList(),
  );

  Future<RecordDay> loadDay(DateTime date) async =>
      recordDay(await repository.day(date));

  Future<RecordDay> deleteDay(DateTime date) async {
    final key = 'delete:${ProductRepository.dateKey(date)}';
    final result = await repository.deleteDay(date, request(key));
    _requests.remove(key);
    await refreshAfterSuccess();
    return recordDay(result);
  }

  Future<int> claim(RecordDay day) async {
    final date = ProductRepository.dateKey(day.date);
    final key = 'claim:$date:${day.revision}';
    final grant = await repository.client.product.claimDay(
      date,
      request(key),
      day.revision,
    );
    _requests.remove(key);
    today = null;
    notifyListeners();
    await refreshAfterSuccess();
    return grant.amount;
  }

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

  Future<QuizView> loadQuiz() async =>
      quizView(await repository.quiz(ProductRepository.today));

  Future<QuizView> answer(QuizView question, int index) async {
    final key = 'quiz:${question.date}:$index';
    quiz = await repository.answer(question.date, index, request(key));
    _requests.remove(key);
    notifyListeners();
    return quizView(quiz!);
  }

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

  Future<WardrobeSnapshot> loadWardrobe() async =>
      wardrobe(await repository.themes());

  Future<WardrobeSnapshot> themeAction(
    WardrobeTheme theme, {
    required bool equip,
  }) async {
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
  }
}
