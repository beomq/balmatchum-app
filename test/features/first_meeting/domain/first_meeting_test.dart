import 'dart:convert';
import 'dart:math';

import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStorage implements FirstMeetingStorage {
  String? payload;
  bool fail = false;
  int writes = 0;
  @override
  Future<String?> read() async => payload;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('write failure');
    payload = value;
    writes++;
  }

  @override
  Future<void> delete() async {
    if (fail) throw StateError('delete failure');
    payload = null;
  }
}

class CountingRandom implements Random {
  int calls = 0;
  @override
  int nextInt(int max) {
    calls++;
    return max - 1;
  }

  @override
  bool nextBool() => throw UnimplementedError();
  @override
  double nextDouble() => throw UnimplementedError();
}

Future<FirstMeetingController> create(
  MemoryStorage storage, {
  Random? random,
  DateTime Function()? clock,
}) async {
  final controller = FirstMeetingController(
    storage: storage,
    random: random,
    clock: clock,
  );
  await controller.initialize();
  return controller;
}

Future<void> reachName(FirstMeetingController c) async {
  await c.enter();
  await c.chooseMethod(FirstMeetingMethod.catalog);
  await c.selectBreed('shih-tzu');
  await c.confirmCandidate();
}

void main() {
  test('catalog has 30 unique IDs and correct sprite namespace', () {
    expect(FirstMeetingCatalog.breeds.length, 30);
    expect(FirstMeetingCatalog.breeds.map((b) => b.id).toSet().length, 30);
    for (final group in FirstMeetingCatalog.groups) {
      expect(group.breeds.length, greaterThanOrEqualTo(2));
      for (final breed in group.breeds) {
        expect(breed.spritePath, 'assets/first_meeting/dogs/${breed.id}.png');
      }
    }
  });

  for (var combination = 0; combination < 8; combination++) {
    test(
      'recommendation combination $combination survives every restart',
      () async {
        final storage = MemoryStorage();
        final random = CountingRandom();
        var c = await create(storage, random: random);
        await c.enter();
        await c.chooseMethod(FirstMeetingMethod.recommendation);
        for (var q = 0; q < 3; q++) {
          await c.answer((combination & (1 << (2 - q))) != 0);
          c = await create(storage, random: random);
        }
        expect(c.state.step, FirstMeetingStep.results);
        expect(c.state.group!.id, 'G${combination + 1}');
        expect(random.calls, 1);
        final representative = c.state.representativeBreedId;
        expect(
          c.state.otherCandidates.map((b) => b.id),
          c.state.group!.breeds
              .where((b) => b.id != representative)
              .map((b) => b.id),
        );
        await c.selectBreed(c.state.otherCandidates.first.id);
        c = await create(storage, random: random);
        await c.confirmCandidate();
        await c.back();
        expect(c.state.step, FirstMeetingStep.confirm);
        await c.back();
        expect(c.state.step, FirstMeetingStep.results);
        expect(c.state.representativeBreedId, representative);
        expect(random.calls, 1);
        await c.restartQuestions();
        expect(c.state.answers, isEmpty);
        expect(c.state.representativeBreedId, isNull);
      },
    );
  }

  test(
    'all persisted steps restore and catalog back keeps candidate',
    () async {
      final s = MemoryStorage();
      var c = await create(s);
      Future<void> check(FirstMeetingStep step) async {
        c = await create(s);
        expect(c.state.step, step);
      }

      await check(FirstMeetingStep.login);
      await c.enter();
      await check(FirstMeetingStep.method);
      await c.chooseCatalog();
      await check(FirstMeetingStep.catalog);
      await c.selectBreed('pug');
      await check(FirstMeetingStep.confirm);
      await c.confirmCandidate();
      await check(FirstMeetingStep.name);
      await c.back();
      await c.back();
      await check(FirstMeetingStep.catalog);
      expect(c.state.breedId, 'pug');
      await c.selectBreed('pug');
      await c.confirmCandidate();
      await c.updateName('  댕댕 12  ');
      await c.updateSex(DogSex.female);
      await c.submitName();
      await check(FirstMeetingStep.goal);
      expect(c.state.name, '댕댕 12');
      await c.updateGoal('6000');
      await check(FirstMeetingStep.goal);
      expect(c.state.goalInput, '6000');
      await c.complete();
      await check(FirstMeetingStep.home);
      expect(c.state.goal, 6000);
      expect(c.state.firstMetAtUTC!.isUtc, isTrue);
    },
  );

  test(
    'validation uses graphemes, required sex, tryParse and the goal range',
    () async {
      expect(FirstMeetingController.isValidName('가' * 12), isTrue);
      expect(FirstMeetingController.isValidName('가' * 13), isFalse);
      for (final name in ['', '   ', 'dog!', '🐕', 'é']) {
        expect(FirstMeetingController.isValidName(name), isFalse);
      }
      for (final goal in [
        '0',
        '-1',
        '1.5',
        'abc',
        '999999999999999999999999999',
        // Owner decision 9.1 ②: 1,000 to 30,000 steps.
        '999',
        '30001',
        '1000000000',
      ]) {
        expect(FirstMeetingController.parseGoal(goal), isNull);
      }
      expect(FirstMeetingController.parseGoal('1000'), 1000);
      expect(FirstMeetingController.parseGoal(' 30000 '), 30000);
      // Off the 500 marks is still a goal, as settings may save one.
      expect(FirstMeetingController.parseGoal('7777'), 7777);
      final c = await create(MemoryStorage());
      await reachName(c);
      await c.updateName('dog');
      await c.submitName();
      expect(c.error, FirstMeetingError.validation);
      expect(c.state.step, FirstMeetingStep.name);
      await c.updateSex(DogSex.male);
      await c.submitName();
      expect(c.state.goal, 5000);
      await c.updateGoal('-2');
      await c.complete();
      expect(c.state.step, FirstMeetingStep.goal);
      expect(c.state.goalInput, '-2');
    },
  );

  test('goal steps move to the next 500 mark inside the range', () {
    int next(int value, bool up) =>
        FirstMeetingController.nextGoal(value, up: up);
    expect(next(5000, true), 5500);
    expect(next(5000, false), 4500);
    // A restored off-mark goal lands on the nearest mark in that direction.
    expect(next(7777, true), 8000);
    expect(next(7777, false), 7500);
    // The ends hold, and a draft outside the range comes back into it.
    expect(next(1000, false), 1000);
    expect(next(30000, true), 30000);
    expect(next(29800, true), 30000);
    expect(next(40000, false), 30000);
    expect(next(200, true), 1000);
  });

  test('goal estimate rounds half up to minutes and tenths of a km', () {
    ({int minutes, int tenthsKm}) estimate(int goal) =>
        FirstMeetingController.estimateGoal(goal);
    expect(estimate(5000), (minutes: 50, tenthsKm: 35));
    expect(estimate(3000), (minutes: 30, tenthsKm: 21));
    expect(estimate(10000), (minutes: 100, tenthsKm: 70));
    expect(estimate(1500), (minutes: 15, tenthsKm: 11));
    expect(estimate(7777), (minutes: 78, tenthsKm: 54));
    expect(estimate(30000), (minutes: 300, tenthsKm: 210));
  });

  test('queued goal steps each start from the latest draft', () async {
    final storage = MemoryStorage();
    final c = await create(storage);
    await reachName(c);
    await c.updateName('몽글');
    await c.updateSex(DogSex.female);
    await c.submitName();
    expect(c.state.goalInput, '5000');
    // Three taps before any save finishes.
    final taps = [
      c.stepGoal(up: true),
      c.stepGoal(up: true),
      c.stepGoal(up: false),
    ];
    await Future.wait(taps);
    expect(c.state.goalInput, '5500');
    final restored = await create(MemoryStorage()..payload = storage.payload);
    expect(restored.state.goalInput, '5500');
    // Outside the goal step the stepper changes nothing.
    await c.back();
    await c.stepGoal(up: true);
    expect(c.state.goalInput, '5500');
  });

  test('the catalog can switch to the questions, later steps cannot', () async {
    final s = MemoryStorage();
    final c = await create(s);
    await c.enter();
    await c.chooseCatalog();
    // From the catalog, the questions start at the first one.
    await c.chooseRecommendation();
    expect(c.state.step, FirstMeetingStep.question);
    expect(c.state.questionIndex, 0);
    // Answers given before reopen their results instead.
    for (var i = 0; i < 3; i++) {
      await c.answer(false);
    }
    expect(c.state.step, FirstMeetingStep.results);
    await c.chooseCatalog();
    await c.chooseRecommendation();
    expect(c.state.step, FirstMeetingStep.results);
    // Past the choice, the name step neither moves nor saves.
    await c.chooseCatalog();
    await c.selectBreed('pug');
    await c.confirmCandidate();
    final writes = s.writes;
    await c.chooseRecommendation();
    expect(c.state.step, FirstMeetingStep.name);
    expect(s.writes, writes);
  });

  test(
    'serialized repeated commits and restart preserve the atomic meeting',
    () async {
      final s = MemoryStorage();
      var clockCalls = 0;
      final date = DateTime.utc(2026, 10, 13);
      final c = await create(
        s,
        clock: () {
          clockCalls++;
          return date;
        },
      );
      await reachName(c);
      await c.updateName('친구');
      await c.updateSex(DogSex.male);
      await c.submitName();
      await Future.wait([c.complete(), c.complete(), c.complete()]);
      expect(clockCalls, 1);
      final saved = s.payload;
      final restored = await create(s, clock: () => DateTime.utc(2030));
      await restored.complete();
      expect(s.payload, saved);
      expect(restored.state.firstMetAtUTC, date);
      final json = jsonDecode(saved!) as Map;
      expect(json['isComplete'], true);
      expect(json['candidateBreedId'], 'shih-tzu');
      expect(json.containsKey('account'), false);
      expect(json.containsKey('token'), false);
    },
  );

  test(
    'write failure keeps input and retry keeps random and meeting time',
    () async {
      final s = MemoryStorage();
      final random = CountingRandom();
      final c = await create(
        s,
        random: random,
        clock: () => DateTime.utc(2026),
      );
      await c.enter();
      await c.chooseRecommendation();
      await c.answer(false);
      await c.answer(false);
      s.fail = true;
      await c.answer(false);
      expect(c.error, FirstMeetingError.storage);
      expect(c.state.step, FirstMeetingStep.question);
      s.fail = false;
      await c.answer(false);
      expect(random.calls, 1);
      await c.selectBreed(c.state.representativeBreedId!);
      await c.confirmCandidate();
      s.fail = true;
      await c.updateName('다시');
      expect(c.state.name, '다시');
      expect(c.error, FirstMeetingError.storage);
      s.fail = false;
      await c.updateSex(DogSex.female);
      await c.submitName();
      final before = s.payload;
      s.fail = true;
      await c.complete();
      expect(s.payload, before);
      expect(c.state.isComplete, false);
      s.fail = false;
      await c.complete();
      expect(c.state.firstMetAtUTC, DateTime.utc(2026));
    },
  );

  test(
    'corruption is explicit and cannot be overwritten until confirmed reset',
    () async {
      final s = MemoryStorage()..payload = '{broken';
      final c = await create(s);
      expect(c.error, FirstMeetingError.corruption);
      await c.enter();
      await c.chooseCatalog();
      await c.complete();
      expect(c.error, FirstMeetingError.corruption);
      expect(s.payload, '{broken');
      expect(s.writes, 0);
      s.fail = true;
      await c.reset();
      expect(c.error, FirstMeetingError.storage);
      expect(s.payload, '{broken');
      s.fail = false;
      await c.reset();
      expect(s.payload, isNull);
      expect(c.state.step, FirstMeetingStep.login);
      await c.enter();
      expect(c.state.step, FirstMeetingStep.method);
    },
  );

  test(
    'invalid schema and breed IDs are corruption, not new profiles',
    () async {
      final valid = FirstMeetingState().toJson();
      for (final mutation in <Map<String, Object?>>[
        {...valid, 'version': 2},
        {...valid, 'candidateBreedId': 'unknown'},
        {...valid, 'step': 'home', 'isComplete': true},
        {
          ...valid,
          'answers': [true, false, true, false],
        },
      ]) {
        final s = MemoryStorage()..payload = jsonEncode(mutation);
        final c = await create(s);
        expect(c.error, FirstMeetingError.corruption);
        await c.enter();
        expect(s.writes, 0);
      }
    },
  );

  test('days together count the first meeting KST date as day one', () {
    // 2026-10-18 00:00 KST.
    final state = FirstMeetingState(
      firstMetAtUTC: DateTime.utc(2026, 10, 17, 15),
    );
    expect(state.daysTogether(DateTime.utc(2026, 10, 18, 14, 59)), 1);
    expect(state.daysTogether(DateTime.utc(2026, 10, 18, 15)), 2);
    expect(state.daysTogether(DateTime.utc(2026, 11, 1, 15)), 16);
    expect(FirstMeetingState().daysTogether(DateTime.utc(2026)), isNull);
  });
}
