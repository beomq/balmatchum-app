import 'package:flutter/foundation.dart';

import 'dog_catalog.dart';

enum FirstMeetingStep {
  login,
  method,
  question,
  results,
  catalog,
  confirm,
  name,
  goal,
  home,
}

enum DogSex { female, male }

enum FirstMeetingMethod { recommendation, catalog }

enum CandidateOrigin { results, catalog }

enum FirstMeetingError { corruption, storage, validation }

abstract interface class FirstMeetingStorage {
  Future<String?> read();
  Future<void> write(String payload);
  Future<void> delete();
}

@immutable
class FirstMeetingState {
  FirstMeetingState({
    this.step = FirstMeetingStep.login,
    List<bool> answers = const [],
    this.questionIndex = 0,
    this.representativeBreedId,
    this.candidateBreedId,
    this.candidateOrigin,
    this.name = '',
    this.sex,
    this.goal = 5000,
    this.goalInput = '5000',
    this.firstMetAtUTC,
    this.isComplete = false,
  }) : answers = List.unmodifiable(answers);

  final FirstMeetingStep step;
  final List<bool> answers;
  final int questionIndex;
  final String? representativeBreedId;
  final String? candidateBreedId;
  final CandidateOrigin? candidateOrigin;
  final String name;
  final DogSex? sex;
  final int goal;
  final String goalInput;
  final DateTime? firstMetAtUTC;
  final bool isComplete;

  int get currentQuestion => questionIndex;
  String? get breedId => candidateBreedId;

  DogBreed? get representative => representativeBreedId == null
      ? null
      : FirstMeetingCatalog.byId(representativeBreedId!);
  DogBreed? get candidate => candidateBreedId == null
      ? null
      : FirstMeetingCatalog.byId(candidateBreedId!);
  DogGroup? get group =>
      answers.length == 3 ? FirstMeetingCatalog.groupForAnswers(answers) : null;
  List<DogBreed> get otherCandidates => List.unmodifiable(
    group?.breeds.where((b) => b.id != representativeBreedId) ?? <DogBreed>[],
  );

  static const _unchanged = Object();
  FirstMeetingState copyWith({
    FirstMeetingStep? step,
    List<bool>? answers,
    int? questionIndex,
    Object? representativeBreedId = _unchanged,
    Object? candidateBreedId = _unchanged,
    Object? candidateOrigin = _unchanged,
    String? name,
    Object? sex = _unchanged,
    int? goal,
    String? goalInput,
    Object? firstMetAtUTC = _unchanged,
    bool? isComplete,
  }) => FirstMeetingState(
    step: step ?? this.step,
    answers: answers ?? this.answers,
    questionIndex: questionIndex ?? this.questionIndex,
    representativeBreedId: identical(representativeBreedId, _unchanged)
        ? this.representativeBreedId
        : representativeBreedId as String?,
    candidateBreedId: identical(candidateBreedId, _unchanged)
        ? this.candidateBreedId
        : candidateBreedId as String?,
    candidateOrigin: identical(candidateOrigin, _unchanged)
        ? this.candidateOrigin
        : candidateOrigin as CandidateOrigin?,
    name: name ?? this.name,
    sex: identical(sex, _unchanged) ? this.sex : sex as DogSex?,
    goal: goal ?? this.goal,
    goalInput: goalInput ?? this.goalInput,
    firstMetAtUTC: identical(firstMetAtUTC, _unchanged)
        ? this.firstMetAtUTC
        : firstMetAtUTC as DateTime?,
    isComplete: isComplete ?? this.isComplete,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'step': step.name,
    'answers': answers,
    'questionIndex': questionIndex,
    'representativeBreedId': representativeBreedId,
    'candidateBreedId': candidateBreedId,
    'candidateOrigin': candidateOrigin?.name,
    'name': name,
    'sex': sex?.name,
    'goal': goal,
    'goalInput': goalInput,
    'firstMetAtUTC': firstMetAtUTC?.toIso8601String(),
    'isComplete': isComplete,
  };

  factory FirstMeetingState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('Unknown version');
    final state = FirstMeetingState(
      step: FirstMeetingStep.values.byName(json['step'] as String),
      answers: (json['answers'] as List).cast<bool>(),
      questionIndex: json['questionIndex'] as int,
      // Drafts may still carry the retired two-page `catalogPage`; the breed
      // pager starts from the catalog candidate instead.
      representativeBreedId: json['representativeBreedId'] as String?,
      candidateBreedId: json['candidateBreedId'] as String?,
      candidateOrigin: json['candidateOrigin'] == null
          ? null
          : CandidateOrigin.values.byName(json['candidateOrigin'] as String),
      name: json['name'] as String,
      sex: json['sex'] == null
          ? null
          : DogSex.values.byName(json['sex'] as String),
      goal: json['goal'] as int,
      goalInput: json['goalInput'] as String,
      firstMetAtUTC: json['firstMetAtUTC'] == null
          ? null
          : DateTime.parse(json['firstMetAtUTC'] as String),
      isComplete: json['isComplete'] as bool,
    );
    if (state.answers.length > 3 ||
        state.questionIndex < 0 ||
        state.questionIndex > 2 ||
        state.questionIndex > state.answers.length ||
        state.goal <= 0 ||
        state.isComplete != (state.step == FirstMeetingStep.home) ||
        (!state.isComplete && state.firstMetAtUTC != null) ||
        (state.firstMetAtUTC != null && !state.firstMetAtUTC!.isUtc)) {
      throw const FormatException('Invalid draft');
    }
    if (state.representativeBreedId != null) {
      final breed = state.representative;
      if (state.group == null || breed!.groupId != state.group!.id) {
        throw const FormatException('Invalid recommendation');
      }
    }
    if (state.candidateBreedId != null) {
      final breed = state.candidate!;
      if (state.candidateOrigin == null ||
          (state.candidateOrigin == CandidateOrigin.results &&
              breed.groupId != state.group?.id)) {
        throw const FormatException('Invalid candidate origin');
      }
    }
    if ((state.step == FirstMeetingStep.question &&
            state.answers.length == 3) ||
        (state.step == FirstMeetingStep.results &&
            state.representative == null) ||
        ([
              FirstMeetingStep.confirm,
              FirstMeetingStep.name,
              FirstMeetingStep.goal,
              FirstMeetingStep.home,
            ].contains(state.step) &&
            state.candidate == null) ||
        ([FirstMeetingStep.goal, FirstMeetingStep.home].contains(state.step) &&
            state.sex == null) ||
        (state.isComplete && state.firstMetAtUTC == null)) {
      throw const FormatException('Missing step data');
    }
    return state;
  }
}
