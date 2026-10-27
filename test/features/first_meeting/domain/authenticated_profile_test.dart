import 'dart:async';
import 'dart:convert';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:balmatchum_app/features/first_meeting/data/profile_repository.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'first_meeting_test.dart' show MemoryStorage;

ProfileView view({String name = '보리', int goal = 5000, int revision = 1}) =>
    ProfileView(
      breedId: 'pug',
      name: name,
      sex: 'female',
      dailyGoal: goal,
      firstMetAt: DateTime.utc(2026, 10, 17),
      revision: revision,
    );

class Profiles implements ProfileRepository {
  ProfileView? current;
  bool loseResponse = false;
  bool conflict = false;
  Completer<ProfileView?>? reading;
  Completer<void>? mutationStarted;
  Completer<void>? mutationRelease;
  final ids = <String>[];
  final payloads = <String>[];
  final replies = <String, ProfileView>{};
  @override
  Future<ProfileView?> getProfile() async =>
      reading == null ? current : reading!.future;
  Future<ProfileView> save(String id, String payload, ProfileView value) async {
    ids.add(id);
    payloads.add(payload);
    mutationStarted?.complete();
    if (mutationRelease != null) await mutationRelease!.future;
    if (conflict) throw ProfileException(code: 'staleRevision');
    final result = replies.putIfAbsent(id, () => current = value);
    if (loseResponse) throw Exception('lost response');
    return result;
  }

  @override
  Future<ProfileView> createProfile(ProfileInput input, String requestId) =>
      save(
        requestId,
        '${input.name}/${input.dailyGoal}',
        view(name: input.name, goal: input.dailyGoal),
      );
  @override
  Future<ProfileView> renameDog(String name, String requestId, int revision) =>
      save(
        requestId,
        '$name/$revision',
        view(name: name, goal: current!.dailyGoal, revision: revision + 1),
      );
  @override
  Future<ProfileView> updateGoal(int goal, String requestId, int revision) =>
      save(
        requestId,
        '$goal/$revision',
        view(name: current!.name, goal: goal, revision: revision + 1),
      );
}

Future<FirstMeetingController> controller(
  Profiles server,
  MemoryStorage storage, {
  bool Function()? active,
}) async {
  final c = FirstMeetingController(
    storage: storage,
    profileRepository: server,
    isCurrentAccount: active,
  );
  await c.initialize();
  return c;
}

void main() {
  test(
    'late mutation after account switch cannot publish or write completion',
    () async {
      var active = true;
      final server = Profiles()..current = view();
      final storage = MemoryStorage();
      final c = await controller(server, storage, active: () => active);
      server.mutationStarted = Completer<void>();
      server.mutationRelease = Completer<void>();
      final saving = c.renameDog('늦은응답');
      await server.mutationStarted!.future;
      final persisted = storage.payload;
      active = false;
      server.mutationRelease!.complete();
      await saving;
      expect(c.state.name, '보리');
      expect(storage.payload, persisted);
      expect(jsonDecode(storage.payload!)['pendingMutation'], isNotNull);
    },
  );

  test('create saves server before completion and retries exact persisted request after restart', () async {
    final server = Profiles()..loseResponse = true;
    final storage = MemoryStorage();
    var c = await controller(server, storage);
    await c.chooseCatalog();
    await c.selectBreed('pug');
    await c.confirmCandidate();
    await c.updateName('보리');
    await c.updateSex(DogSex.female);
    await c.submitName();
    await c.complete();
    expect(c.state.isComplete, isFalse);
    expect(c.hasPendingMutation, isTrue);
    final id = server.ids.single;
    c.dispose();
    server.loseResponse = false;
    c = await controller(server, storage);
    await c.retryMutation();
    expect(server.ids, [id, id]);
    expect(server.payloads.toSet().length, 1);
    expect(c.state.isComplete, isTrue);
    expect(c.state.firstMetAtUTC, DateTime.utc(2026, 10, 17));
    expect(c.hasPendingMutation, isFalse);
  });

  test('server source wins local completed state and invalid settings do not call server', () async {
    final server = Profiles()..current = view(name: '서버');
    final storage = MemoryStorage();
    final c = await controller(server, storage);
    await c.renameDog('🐕');
    await c.changeGoal('0');
    expect(c.error, FirstMeetingError.validation);
    expect(server.ids, isEmpty);
    await c.renameDog('새이름');
    expect(c.state.name, '새이름');
    await c.changeGoal('8000');
    expect(c.state.goal, 8000);
    expect(c.profile!.revision, 3);
    server.current = view(name: '다른기기', revision: 8);
    await c.restore();
    expect(c.state.name, '다른기기');
    expect(jsonDecode(storage.payload!)['name'], '새이름');
  });

  test(
    'revision conflict refreshes and requires explicit new request',
    () async {
      final server = Profiles()..current = view();
      final c = await controller(server, MemoryStorage());
      server.current = view(name: '최신', revision: 9);
      server.conflict = true;
      await c.renameDog('내입력');
      expect(c.profileError, 'staleRevision');
      expect(c.state.name, '최신');
      expect(c.hasPendingMutation, isFalse);
      server.conflict = false;
      await c.renameDog('내입력');
      expect(server.ids.toSet().length, 2);
      expect(server.payloads.last, '내입력/9');
    },
  );

  test(
    'A late restoration cannot overwrite B and logout invalidates queued work',
    () async {
      var account = 'A';
      final a = Profiles()..reading = Completer<ProfileView?>();
      final aStorage = MemoryStorage();
      final ca = FirstMeetingController(
        storage: aStorage,
        profileRepository: a,
        isCurrentAccount: () => account == 'A',
      );
      final restoring = ca.initialize();
      account = 'B';
      final b = Profiles()..current = view(name: 'B');
      final cb = await controller(
        b,
        MemoryStorage(),
        active: () => account == 'B',
      );
      a.reading!.complete(view(name: 'A'));
      await restoring;
      expect(ca.state.isComplete, isFalse);
      expect(cb.state.name, 'B');
      expect(aStorage.payload, isNull);
      account = '';
      await cb.renameDog('로그아웃후');
      expect(b.ids, isEmpty);
    },
  );

  test('account drafts remain isolated and absent server never trusts local completion', () async {
    final aStorage = MemoryStorage();
    final bStorage = MemoryStorage();
    final a = await controller(Profiles(), aStorage);
    await a.chooseCatalog();
    final b = await controller(Profiles(), bStorage);
    expect(b.state.step, FirstMeetingStep.method);
    final restored = await controller(Profiles(), aStorage);
    expect(restored.state.step, FirstMeetingStep.catalog);
    final stale = await controller(Profiles()..current = view(), aStorage);
    await stale.renameDog('로컬');
    final missing = await controller(Profiles(), aStorage);
    expect(missing.state.isComplete, isFalse);
  });

  test('settings failure retains payload and reads latest rather than replay snapshot', () async {
    final server = Profiles()..current = view();
    final storage = MemoryStorage();
    final c = await controller(server, storage);
    server.loseResponse = true;
    await c.changeGoal('7000');
    expect(c.state.goal, 5000);
    server.loseResponse = false;
    server.current = view(name: '최신', goal: 9000, revision: 10);
    await c.retryMutation();
    expect(server.ids.toSet().length, 1);
    expect(c.state.goal, 9000);
    expect(c.state.name, '최신');
  });
}
