import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:balmatchum_client/balmatchum_client.dart';

import '../data/profile_repository.dart';
import 'dog_catalog.dart';
import 'first_meeting_state.dart';

class FirstMeetingController extends ChangeNotifier {
  FirstMeetingController({
    required this.storage,
    this.profileRepository,
    this.isCurrentAccount,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random();

  final FirstMeetingStorage storage;
  final ProfileRepository? profileRepository;
  final bool Function()? isCurrentAccount;
  ProfileView? profile;
  String? profileError;
  Map<String, dynamic>? _pendingMutation;
  bool _closed = false;
  bool get _disposed => _closed || !(isCurrentAccount?.call() ?? true);
  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

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
      if (_disposed) return;
      _isBusy = true;
      _error = null;
      profileError = null;
      notifyListeners();
      try {
        await action();
      } on ProfileException catch (error) {
        if (_disposed) return;
        profileError = error.code;
        if (error.code.startsWith('invalid') ||
            error.code == 'idempotencyConflict') {
          _pendingMutation = null;
          await _save(_state);
        }
        if (error.code == 'staleRevision' || error.code == 'alreadyExists') {
          _pendingMutation = null;
          try {
            final latest = await profileRepository!.getProfile();
            if (!_disposed && latest != null) _applyProfile(latest);
            if (!_disposed) await _save(_state);
          } on Exception {
            profileError = 'refreshRequired';
          }
        }
      } catch (_) {
        _error = FirstMeetingError.storage;
      } finally {
        _isBusy = false;
        if (!_disposed) notifyListeners();
      }
    });
    _tail = result.catchError((Object _) {
      _error = FirstMeetingError.storage;
      if (!_disposed) notifyListeners();
    });
    return _tail;
  }

  bool _canEdit() {
    if (_pendingMutation != null) return false;
    if (_corrupt) {
      _error = FirstMeetingError.corruption;
      return false;
    }
    if (!_restored || _state.isComplete) return false;
    return true;
  }

  bool _at(FirstMeetingStep step) => _canEdit() && _state.step == step;

  Future<void> _save(FirstMeetingState next) async {
    if (_disposed) return;
    await storage.write(
      jsonEncode({...next.toJson(), 'pendingMutation': _pendingMutation}),
    );
    if (!_disposed) _state = next;
  }

  void _applyProfile(ProfileView value) {
    profile = value;
    _state = FirstMeetingState(
      step: FirstMeetingStep.home,
      candidateBreedId: value.breedId,
      candidateOrigin: CandidateOrigin.catalog,
      name: value.name,
      sex: DogSex.values.byName(value.sex),
      goal: value.dailyGoal,
      goalInput: '${value.dailyGoal}',
      firstMetAtUTC: value.firstMetAt.toUtc(),
      isComplete: true,
    );
  }

  Future<void> restore() => _run(() async {
    final server = profileRepository;
    final latest = server == null ? null : await server.getProfile();
    if (_disposed) return;
    final payload = await storage.read();
    if (_disposed) return;
    if (payload == null) {
      _state = FirstMeetingState();
      _pendingMutation = null;
      _corrupt = false;
    } else {
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        _pendingMutation = json['pendingMutation'] as Map<String, dynamic>?;
        final restored = FirstMeetingState.fromJson(json);
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
    if (latest != null) {
      _applyProfile(latest);
      _corrupt = false;
      _error = null;
    } else if (server != null && _state.isComplete) {
      _state = FirstMeetingState(step: FirstMeetingStep.method);
    }
    if (server != null && _corrupt) {
      // A broken local draft cannot override or prevent a server profile lookup.
      _state = FirstMeetingState(step: FirstMeetingStep.method);
      _pendingMutation = null;
      _corrupt = false;
      _error = null;
    }
    if (server != null && _state.step == FirstMeetingStep.login) {
      _state = _state.copyWith(step: FirstMeetingStep.method);
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
    if (profileRepository != null) {
      await _mutate('create', {
        'breedId': _state.candidateBreedId!,
        'name': _state.name,
        'sex': _state.sex!.name,
        'goal': goal,
      });
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

  Future<void> renameDog(String input) => _run(() async {
    if (!isValidName(input)) {
      _error = FirstMeetingError.validation;
      return;
    }
    if (profile == null) return;
    await _mutate('rename', {'name': normalizeName(input)});
  });

  Future<void> changeGoal(String input) => _run(() async {
    final goal = parseGoal(input);
    if (goal == null) {
      _error = FirstMeetingError.validation;
      return;
    }
    if (profile == null) return;
    await _mutate('goal', {'goal': goal});
  });

  Future<void> retryMutation() => _run(() async {
    if (_pendingMutation != null) {
      await _save(_state);
      if (!_disposed) await _sendMutation();
    }
  });

  bool get hasPendingMutation => _pendingMutation != null;

  Future<void> _mutate(String method, Map<String, dynamic> payload) async {
    // An uncertain write must resolve with its exact original payload first.
    _pendingMutation ??= {
      'method': method,
      'payload': payload,
      'revision': profile?.revision,
      'requestId':
          'profile-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}',
    };
    await _save(_state);
    if (!_disposed) await _sendMutation();
  }

  Future<void> _sendMutation() async {
    final pending = _pendingMutation!;
    final payload = pending['payload'] as Map<String, dynamic>;
    final id = pending['requestId'] as String;
    final repository = profileRepository!;
    final response = switch (pending['method']) {
      'create' => await repository.createProfile(
        ProfileInput(
          breedId: payload['breedId'] as String,
          name: payload['name'] as String,
          sex: payload['sex'] as String,
          dailyGoal: payload['goal'] as int,
        ),
        id,
      ),
      'rename' => await repository.renameDog(
        payload['name'] as String,
        id,
        pending['revision'] as int,
      ),
      'goal' => await repository.updateGoal(
        payload['goal'] as int,
        id,
        pending['revision'] as int,
      ),
      _ => throw const FormatException('Unknown profile mutation'),
    };
    if (response.revision < 1) throw StateError('Invalid server revision');
    if (_disposed) return;
    // Replayed responses may be older than the current server revision.
    final latest = await repository.getProfile();
    if (_disposed) return;
    if (latest == null) throw StateError('Saved profile missing from server');
    _applyProfile(latest);
    _pendingMutation = null;
    await _save(_state);
  }

  Future<void> back() => _run(() async {
    if (!_canEdit()) return;
    final step = switch (_state.step) {
      FirstMeetingStep.login || FirstMeetingStep.home => _state.step,
      FirstMeetingStep.method =>
        profileRepository == null
            ? FirstMeetingStep.login
            : FirstMeetingStep.method,
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
    if (profileRepository != null) return;
    await storage.delete();
    _state = FirstMeetingState();
    _corrupt = false;
    _restored = true;
    _pendingFirstMet = null;
    _pendingRepresentative = null;
  });
}
