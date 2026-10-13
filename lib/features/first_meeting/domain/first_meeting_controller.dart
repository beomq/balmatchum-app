import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'dog_catalog.dart';
import 'first_meeting_state.dart';

class FirstMeetingController extends ChangeNotifier {
  FirstMeetingController({
    required this.storage,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random();

  final FirstMeetingStorage storage;
  final DateTime Function() _clock;
  final Random _random;
  FirstMeetingState _state = FirstMeetingState();
  FirstMeetingState get state => _state;
  FirstMeetingError? _error;
  FirstMeetingError? get error => _error;
  bool _isBusy = false;
  bool get isBusy => _isBusy;
  bool get isRestored => _restored;
  bool _restored = false;
  bool _corrupt = false;
  Future<void> _tail = Future.value();
  String? _pendingRepresentative;
  String? _pendingGroupId;
  DateTime? _pendingFirstMet;

  static String normalizeName(String input) => input.trim();
  static bool isValidName(String input) {
    final name = normalizeName(input);
    return name.isNotEmpty &&
        name.characters.length <= 12 &&
        name.runes.every(
          (rune) =>
              rune == 32 ||
              (rune >= 48 && rune <= 57) ||
              (rune >= 65 && rune <= 90) ||
              (rune >= 97 && rune <= 122) ||
              (rune >= 0xac00 && rune <= 0xd7a3) ||
              (rune >= 0x3131 && rune <= 0x3163) ||
              (rune >= 0x1100 && rune <= 0x11ff) ||
              (rune >= 0xa960 && rune <= 0xa97f) ||
              (rune >= 0xd7b0 && rune <= 0xd7ff),
        );
  }

  static int? parseGoal(String input) {
    final value = int.tryParse(input.trim());
    return value != null && value > 0 ? value : null;
  }

  Future<void> initialize() => restore();
  Future<void> chooseMethod(FirstMeetingMethod method) =>
      method == FirstMeetingMethod.catalog
      ? chooseCatalog()
      : chooseRecommendation();
  Future<void> selectBreed(String breedId, {CandidateOrigin? origin}) =>
      selectCandidate(
        breedId,
        origin:
            origin ??
            (_state.step == FirstMeetingStep.catalog
                ? CandidateOrigin.catalog
                : CandidateOrigin.results),
      );
  Future<void> complete() => commit();
  Future<void> reset() => resetLocalAfterConfirmation();

  Future<void> _run(Future<void> Function() action) {
    final result = _tail.then((_) async {
      _isBusy = true;
      _error = null;
      notifyListeners();
      try {
        await action();
      } catch (_) {
        _error = FirstMeetingError.storage;
      } finally {
        _isBusy = false;
        notifyListeners();
      }
    });
    _tail = result;
    return result;
  }

  bool _canEdit() {
    if (_corrupt) {
      _error = FirstMeetingError.corruption;
      return false;
    }
    if (!_restored || _state.isComplete) return false;
    return true;
  }

  bool _at(FirstMeetingStep step) => _canEdit() && _state.step == step;

  Future<void> _save(FirstMeetingState next) async {
    await storage.write(jsonEncode(next.toJson()));
    _state = next;
  }

  Future<void> restore() => _run(() async {
    final payload = await storage.read();
    if (payload == null) {
      _state = FirstMeetingState();
      _corrupt = false;
    } else {
      try {
        final restored = FirstMeetingState.fromJson(
          jsonDecode(payload) as Map<String, dynamic>,
        );
        if ([
              FirstMeetingStep.goal,
              FirstMeetingStep.home,
            ].contains(restored.step) &&
            (!isValidName(restored.name) ||
                restored.name != normalizeName(restored.name))) {
          throw const FormatException('Invalid profile name');
        }
        _state = restored;
        _corrupt = false;
      } catch (_) {
        _corrupt = true;
        _error = FirstMeetingError.corruption;
      }
    }
    _restored = true;
  });

  Future<void> enter() => _run(() async {
    if (_at(FirstMeetingStep.login)) {
      await _save(_state.copyWith(step: FirstMeetingStep.method));
    }
  });

  Future<void> chooseCatalog() => _run(() async {
    if (_canEdit() &&
        [
          FirstMeetingStep.method,
          FirstMeetingStep.results,
        ].contains(_state.step)) {
      await _save(_state.copyWith(step: FirstMeetingStep.catalog));
    }
  });

  Future<void> toggleCatalogPage() => _run(() async {
    if (_at(FirstMeetingStep.catalog)) {
      await _save(_state.copyWith(catalogPage: 1 - _state.catalogPage));
    }
  });

  Future<void> chooseRecommendation() => _run(() async {
    if (_at(FirstMeetingStep.method)) {
      await _save(
        _state.copyWith(
          step: _state.representativeBreedId == null
              ? FirstMeetingStep.question
              : FirstMeetingStep.results,
        ),
      );
    }
  });

  Future<void> answer(bool choiceB) => _run(() async {
    if (!_at(FirstMeetingStep.question)) return;
    final answers = [..._state.answers];
    if (_state.questionIndex < answers.length) {
      answers[_state.questionIndex] = choiceB;
      answers.removeRange(_state.questionIndex + 1, answers.length);
    } else {
      answers.add(choiceB);
    }
    if (answers.length < 3) {
      await _save(
        _state.copyWith(answers: answers, questionIndex: answers.length),
      );
    } else {
      final group = FirstMeetingCatalog.groupForAnswers(answers);
      if (_pendingGroupId != group.id) {
        _pendingRepresentative = null;
        _pendingGroupId = group.id;
      }
      _pendingRepresentative ??=
          group.breeds[_random.nextInt(group.breeds.length)].id;
      await _save(
        _state.copyWith(
          answers: answers,
          questionIndex: 2,
          representativeBreedId: _pendingRepresentative,
          step: FirstMeetingStep.results,
        ),
      );
      _pendingRepresentative = null;
    }
  });

  Future<void> restartQuestions() => _run(() async {
    if (!_canEdit() ||
        ![
          FirstMeetingStep.results,
          FirstMeetingStep.question,
        ].contains(_state.step)) {
      return;
    }
    await _save(
      _state.copyWith(
        step: FirstMeetingStep.question,
        answers: [],
        questionIndex: 0,
        representativeBreedId: null,
        candidateBreedId: null,
        candidateOrigin: null,
      ),
    );
    _pendingRepresentative = null;
  });

  Future<void> selectCandidate(String id, {required CandidateOrigin origin}) =>
      _run(() async {
        if (!_at(
          origin == CandidateOrigin.catalog
              ? FirstMeetingStep.catalog
              : FirstMeetingStep.results,
        )) {
          return;
        }
        final candidates = origin == CandidateOrigin.catalog
            ? FirstMeetingCatalog.breeds
            : _state.group!.breeds;
        if (!candidates.any((b) => b.id == id)) {
          _error = FirstMeetingError.validation;
          return;
        }
        await _save(
          _state.copyWith(
            step: FirstMeetingStep.confirm,
            candidateBreedId: id,
            candidateOrigin: origin,
          ),
        );
      });

  Future<void> confirmCandidate() => _run(() async {
    if (_at(FirstMeetingStep.confirm)) {
      await _save(_state.copyWith(step: FirstMeetingStep.name));
    }
  });

  Future<void> updateName(String input) => _run(() async {
    if (!_at(FirstMeetingStep.name)) return;
    _state = _state.copyWith(name: input);
    await _save(_state);
  });

  Future<void> updateSex(DogSex sex) => _run(() async {
    if (!_at(FirstMeetingStep.name)) return;
    _state = _state.copyWith(sex: sex);
    await _save(_state);
  });

  Future<void> submitName() => _run(() async {
    if (!_at(FirstMeetingStep.name)) return;
    if (!isValidName(_state.name) || _state.sex == null) {
      _error = FirstMeetingError.validation;
      return;
    }
    await _save(
      _state.copyWith(
        name: normalizeName(_state.name),
        step: FirstMeetingStep.goal,
      ),
    );
  });

  Future<void> updateGoal(String input) => _run(() async {
    if (!_at(FirstMeetingStep.goal)) return;
    _state = _state.copyWith(goalInput: input);
    await _save(_state);
  });

  Future<void> commit() => _run(() async {
    if (!_at(FirstMeetingStep.goal)) return;
    final goal = parseGoal(_state.goalInput);
    if (goal == null || !isValidName(_state.name) || _state.sex == null) {
      _error = FirstMeetingError.validation;
      return;
    }
    _pendingFirstMet ??= _clock().toUtc();
    await _save(
      _state.copyWith(
        goal: goal,
        firstMetAtUTC: _pendingFirstMet,
        isComplete: true,
        step: FirstMeetingStep.home,
      ),
    );
  });

  Future<void> back() => _run(() async {
    if (!_canEdit()) return;
    final step = switch (_state.step) {
      FirstMeetingStep.login || FirstMeetingStep.home => _state.step,
      FirstMeetingStep.method => FirstMeetingStep.login,
      FirstMeetingStep.catalog ||
      FirstMeetingStep.results => FirstMeetingStep.method,
      FirstMeetingStep.confirm =>
        _state.candidateOrigin == CandidateOrigin.catalog
            ? FirstMeetingStep.catalog
            : FirstMeetingStep.results,
      FirstMeetingStep.name => FirstMeetingStep.confirm,
      FirstMeetingStep.goal => FirstMeetingStep.name,
      FirstMeetingStep.question =>
        _state.questionIndex == 0
            ? FirstMeetingStep.method
            : FirstMeetingStep.question,
    };
    await _save(
      _state.copyWith(
        step: step,
        questionIndex:
            _state.step == FirstMeetingStep.question && _state.questionIndex > 0
            ? _state.questionIndex - 1
            : _state.questionIndex,
      ),
    );
    _pendingRepresentative = null;
  });

  /// The caller must obtain explicit UI confirmation before invoking this.
  Future<void> resetLocalAfterConfirmation() => _run(() async {
    await storage.delete();
    _state = FirstMeetingState();
    _corrupt = false;
    _restored = true;
    _pendingFirstMet = null;
    _pendingRepresentative = null;
  });
}
