import 'dart:async';

import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/daily_activity/today_reward_sheet.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/home_goal_card.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_widgets.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_app/features/records/status_widgets.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import '../billing/billing_http_harness.dart' show presentBilling;
import '../daily_activity/product_controller_test.dart'
    show AccountRepository, outfitStore, record, themeStore;
import '../quiz/authenticated_quiz_test.dart' show Quizzes, question;
import 'domain/authenticated_profile_test.dart' show Profiles, view;
import 'domain/first_meeting_test.dart' show MemoryStorage;

String get todayKey => ProductRepository.dateKey(ProductRepository.today);

/// The KST date [ago] days before today.
String dayKey(int ago) => ProductRepository.dateKey(
  ProductRepository.today.subtract(Duration(days: ago)),
);

DailyStepsResult available(int count, [String? date]) => DailyStepsResult(
  DailyStepsStatus.available,
  {'count': count, 'date': date ?? todayKey},
);

/// A signed-in account's server: today's record and the wallet move with a
/// claim the way the server answers them.
class HomeServer extends AccountRepository {
  DailyRecord today = record().copyWith(
    date: todayKey,
    claimablePoints: 68,
    adClaimablePoints: 136,
  );
  int balance = 359;
  @override
  Future<DailyRecord> day(DateTime date) async {
    calls.add('day');
    return today;
  }

  @override
  Future<WalletView> wallet() async {
    calls.add('wallet');
    return WalletView(
      balance: balance,
      streamGeneration: 0,
      policyVersion: 'steps-v1-20261019',
    );
  }

  @override
  Future<RewardGrant> claim(String date, String requestId, int revision) async {
    calls.add('claim');
    final amount = today.claimablePoints!;
    today = today.copyWith(
      revision: revision + 1,
      rewardStatus: 'adRequired',
      claimablePoints: 0,
      grantedPoints: today.grantedPoints + amount,
    );
    balance += amount;
    return RewardGrant(
      ledgerId: 1,
      date: date,
      amount: amount,
      fromUnits: 0,
      throughUnits: amount,
      grantedAt: DateTime.utc(2026, 10, 28),
    );
  }
}

/// A free user whose extra question waits for an ad, so a paid-benefit
/// observation would be due on the quiz screen.
class PremiumQuizzes extends Quizzes {
  PremiumQuizzes() : super(billing: presentBilling()) {
    current = QuizToday(
      date: todayKey,
      status: 'ready',
      free: question(1, answered: true),
      extraStatus: 'adRequired',
      extraRevision: 1,
      premiumStatus: 'notChecked',
    );
  }
  int premiumReads = 0;
  @override
  Future<QuizToday> getTodayWithPremium() async {
    premiumReads++;
    return current.copyWith(premiumStatus: 'inactive');
  }
}

void main() {
  late DailyStepsResult next;
  late int reads;
  Completer<DailyStepsResult>? gate;
  late DailyStepsController steps;
  setUp(() {
    next = const DailyStepsResult(DailyStepsStatus.empty, null);
    reads = 0;
    gate = null;
    steps = DailyStepsController(
      readSteps: () async {
        reads++;
        return gate?.future ?? next;
      },
    );
  });
  tearDown(() => steps.dispose());

  FirstMeetingController account({String name = '보리'}) {
    final c = FirstMeetingController(
      storage: MemoryStorage(),
      profileRepository: Profiles()..current = view(goal: 8000, name: name),
    );
    addTearDown(c.dispose);
    return c;
  }

  ProductController productFor(AccountRepository server) {
    final product = ProductController(server, steps, null, account: 'A');
    addTearDown(() {
      product.dispose();
      server.client.close();
    });
    return product;
  }

  /// The home after its entry refresh, then [read] from the device. The
  /// entry sync reads an empty day, so it never uploads to the fake client.
  Future<void> pumpHome(
    WidgetTester tester, {
    required ProductController? product,
    FirstMeetingController? meeting,
    QuizController? quiz,
    DailyStepsResult? read,
    VoidCallback? onOpenRecords,
    VoidCallback? onOpenQuiz,
    VoidCallback? onOpenWardrobe,
    VoidCallback? onOpenPhoto,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(
          controller: meeting ?? account(),
          dailySteps: steps,
          product: product,
          quiz: quiz,
          onOpenRecords: onOpenRecords,
          onOpenQuiz: onOpenQuiz,
          onOpenWardrobe: onOpenWardrobe,
          onOpenPhoto: onOpenPhoto,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (read != null) {
      next = read;
      await steps.refresh();
      await tester.pumpAndSettle();
    }
  }

  Finder key(String value) => find.byKey(ValueKey(value));
  String text(WidgetTester tester, String value) =>
      tester.widget<Text>(key(value)).data!;
  GoalRing ring(WidgetTester tester) =>
      tester.widget<GoalRing>(find.byType(GoalRing));
  ButtonStyleButton point(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(key('home_reward'));

  group('state', () {
    Future<HomeGoal> goalOf(DailyStepsResult result) async {
      next = result;
      await steps.refresh();
      return HomeGoal.of(steps, 8000, todayKey);
    }

    test(
      "the ring takes only today's count and clamps only the share",
      () async {
        final progress = await goalOf(available(6840));
        expect(progress.state, StepsState.counted);
        expect(progress.progress, closeTo(.855, 1e-9));
        expect(progress.remaining, 1160);
        expect(progress.percent, 86);
        expect(progress.achieved, isFalse);
        expect((await goalOf(available(7999))).percent, 99);
        final exact = await goalOf(available(8000));
        expect(exact.achieved, isTrue);
        expect(exact.excess, 0);
        final over = await goalOf(available(8420));
        expect(over.progress, 1);
        expect(over.count, 8420);
        expect(over.excess, 420);
        final zero = await goalOf(available(0));
        expect(zero.count, 0);
        expect(zero.progress, 0);
        final yesterday = await goalOf(available(6840, dayKey(1)));
        expect(yesterday.state, StepsState.notToday);
        expect(yesterday.count, isNull);
        expect(yesterday.retryable, isTrue);
      },
    );

    test('reading, empty and unsupported days are not failures', () async {
      for (final (status, retryable) in [
        (DailyStepsStatus.empty, false),
        (DailyStepsStatus.capabilityUnavailable, false),
        (DailyStepsStatus.error, true),
        (DailyStepsStatus.unavailable, true),
        (DailyStepsStatus.permissionDenied, true),
        (DailyStepsStatus.providerUpdateRequired, true),
      ]) {
        final goal = await goalOf(DailyStepsResult(status, null));
        expect(goal.count, isNull, reason: '$status');
        expect(goal.retryable, retryable, reason: '$status');
      }
      gate = Completer();
      final reading = steps.refresh();
      final checking = HomeGoal.of(steps, 8000, todayKey);
      expect(checking.state, StepsState.checking);
      expect(checking.retryable, isFalse);
      gate!.complete(available(1));
      await reading;
    });

    test('the point action follows the server record, not the goal', () {
      final product = productFor(AccountRepository());
      HomeReward of(DailyRecord? value, {bool busy = false}) {
        product
          ..today = value
          ..busy = busy;
        return homeReward(product, todayKey);
      }

      final today = record().copyWith(date: todayKey);
      expect(homeReward(null, todayKey), HomeReward.open);
      expect(of(null, busy: true), HomeReward.checking);
      expect(of(null), HomeReward.open);
      expect(of(today.copyWith(rewardStatus: 'pending')), HomeReward.checking);
      expect(of(today), HomeReward.open);
      expect(
        of(today.copyWith(rewardStatus: 'adRequired', claimablePoints: 0)),
        HomeReward.open,
      );
      expect(
        of(today.copyWith(rewardStatus: 'settled', grantedPoints: 68)),
        HomeReward.claimed,
      );
      // Settled with nothing granted is not "received".
      expect(of(today.copyWith(rewardStatus: 'settled')), HomeReward.open);
      // Yesterday's settled record says nothing about today (KST change).
      expect(
        of(
          today.copyWith(
            date: dayKey(1),
            rewardStatus: 'settled',
            grantedPoints: 68,
          ),
        ),
        HomeReward.open,
      );
      product
        ..today = null
        ..busy = false;
    });
  });

  testWidgets('progress: the ring shows the share, the bubble no number', (
    tester,
  ) async {
    await pumpHome(
      tester,
      product: productFor(HomeServer()),
      read: available(6840),
    );
    expect(text(tester, 'daily_steps_count'), '6,840');
    expect(ring(tester).progress, closeTo(.855, 1e-9));
    expect(ring(tester).color, MeetingColors.primary);
    expect(point(tester), isA<FilledButton>());
    expect(point(tester).onPressed, isNotNull);
    expect(key('daily_steps_retry'), findsNothing);
    expect(text(tester, 'home_bubble'), isNot(matches(RegExp(r'\d'))));
    expect(find.text('기록 보기'), findsNothing);
  });

  testWidgets('a reached goal fills the ring and leaves points to the server', (
    tester,
  ) async {
    await pumpHome(
      tester,
      product: productFor(HomeServer()),
      read: available(8000),
    );
    expect(ring(tester).progress, 1);
    expect(ring(tester).color, ProductColors.record);
    // Reaching the goal exactly has no "0 steps more" line.
    expect(key('home_goal_body'), findsNothing);
    expect(point(tester).onPressed, isNotNull);
    expect(text(tester, 'home_bubble'), isNot(matches(RegExp(r'\d'))));
    next = available(8420);
    await steps.refresh();
    await tester.pump();
    expect(text(tester, 'daily_steps_count'), '8,420');
    expect(text(tester, 'home_goal_body'), contains('420'));
    expect(point(tester).onPressed, isNotNull);
  });

  testWidgets('received points keep the ring on the real steps', (
    tester,
  ) async {
    final server = HomeServer();
    server.today = server.today.copyWith(
      rewardStatus: 'settled',
      claimablePoints: 0,
      adClaimablePoints: 0,
      grantedPoints: 68,
    );
    await pumpHome(tester, product: productFor(server), read: available(4000));
    expect(ring(tester).progress, .5);
    expect(point(tester).onPressed, isNull);
    next = available(8420);
    await steps.refresh();
    await tester.pump();
    expect(ring(tester).progress, 1);
    expect(point(tester).onPressed, isNull);
  });

  testWidgets('a record the server still confirms offers no amount', (
    tester,
  ) async {
    final server = HomeServer();
    server.today = server.today.copyWith(rewardStatus: 'pending');
    await pumpHome(tester, product: productFor(server), read: available(6840));
    expect(point(tester).onPressed, isNull);
  });

  testWidgets("reading, failing and yesterday's count never show a number", (
    tester,
  ) async {
    final server = HomeServer();
    await pumpHome(tester, product: productFor(server), read: available(6840));
    final retry = key('daily_steps_retry');
    gate = Completer();
    unawaited(steps.refresh());
    await tester.pump();
    expect(text(tester, 'daily_steps_count'), '–');
    expect(retry, findsNothing);
    gate!.complete(const DailyStepsResult(DailyStepsStatus.error, null));
    gate = null;
    await tester.pumpAndSettle();
    // The earlier 6,840 is gone, not kept as today's count.
    expect(text(tester, 'daily_steps_count'), '–');
    expect(ring(tester).progress, isNull);
    expect(retry, findsOneWidget);
    // The retry runs the home refresh: one device read, one server read.
    final dayReads = server.calls.where((c) => c == 'day').length;
    final deviceReads = reads;
    next = const DailyStepsResult(DailyStepsStatus.empty, null);
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(reads, deviceReads + 1);
    expect(server.calls.where((c) => c == 'day'), hasLength(dayReads + 1));
    expect(retry, findsNothing);
    next = available(6840, dayKey(1));
    await steps.refresh();
    await tester.pump();
    expect(text(tester, 'daily_steps_count'), '–');
    expect(retry, findsOneWidget);
  });

  testWidgets('the streak counts recorded days; an unknown one shows none', (
    tester,
  ) async {
    final server = HomeServer()
      ..recentDays = [
        for (var i = 0; i < 6; i++) record().copyWith(date: dayKey(i)),
      ];
    await pumpHome(tester, product: productFor(server));
    expect(server.calls.where((c) => c == 'days'), hasLength(1));
    expect(text(tester, 'home_streak'), startsWith('6일'));
    expect(key('home_tile_records_status'), findsOneWidget);
    server.recentDays = null;
    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(server.calls.where((c) => c == 'days'), hasLength(2));
    expect(key('home_streak'), findsNothing);
    expect(key('home_tile_records_status'), findsNothing);
  });

  /// The [PixelIcon] inside [scope].
  String pixel(WidgetTester tester, Finder scope) => tester
      .widget<PixelIcon>(
        find.descendant(of: scope, matching: find.byType(PixelIcon)),
      )
      .name;
  Finder chipOf(String label) =>
      find.ancestor(of: key(label), matching: find.byType(StatusChip));

  testWidgets('chips, the points button and tiles carry the Pen pixel icons', (
    tester,
  ) async {
    final server = HomeServer()
      ..recentDays = [
        for (var i = 0; i < 6; i++) record().copyWith(date: dayKey(i)),
      ];
    await pumpHome(tester, product: productFor(server));
    expect(pixel(tester, chipOf('home_streak')), 'goal-target');
    expect(pixel(tester, chipOf('reward_wallet')), 'points');
    expect(pixel(tester, key('home_reward')), 'points');
    final wardrobe = tester.widget<Image>(
      find.descendant(
        of: key('home_tile_wardrobe'),
        matching: find.byType(Image),
      ),
    );
    expect(
      (wardrobe.image as AssetImage).assetName,
      endsWith('/decorate-shortcut.png'),
    );
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('the home stage draws the equipped weather picture', (
    tester,
  ) async {
    final server = HomeServer()
      ..store = themeStore(cloudyOwned: true).copyWith(equippedTheme: 'cloudy');
    await pumpHome(tester, product: productFor(server));
    expect(
      find.image(const AssetImage('assets/first_meeting/cloudy.png')),
      findsOneWidget,
    );
  });

  testWidgets('the Duo home rail uses the pixel icons Pen shows', (
    tester,
  ) async {
    useDuoViewport(tester, 'outer portrait');
    await pumpHome(tester, product: productFor(HomeServer()));
    expect(pixel(tester, key('duo_rail_settings')), 'settings');
    expect(pixel(tester, key('duo_rail_wardrobe')), 'decorate-shortcut');
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('a signed-in home has no footer line', (tester) async {
    await pumpHome(tester, product: productFor(HomeServer()));
    expect(
      tester.widget<MeetingHomeLayout>(find.byType(MeetingHomeLayout)).footer,
      isNull,
    );
    expect(find.text('계정에 저장된 친구'), findsNothing);
  });

  testWidgets('the Dev local flow keeps its storage line', (tester) async {
    final local = FirstMeetingController(storage: MemoryStorage());
    addTearDown(local.dispose);
    await local.initialize();
    await local.enter();
    await local.chooseMethod(FirstMeetingMethod.catalog);
    await local.selectBreed('shih-tzu');
    await local.confirmCandidate();
    await local.updateName('몽글');
    await local.updateSex(DogSex.female);
    await local.submitName();
    await local.complete();
    await pumpHome(tester, product: null, meeting: local);
    expect(
      tester.widget<MeetingHomeLayout>(find.byType(MeetingHomeLayout)).footer,
      isNotNull,
    );
  });

  testWidgets("tiles carry their destination's state and open it", (
    tester,
  ) async {
    final server = HomeServer()
      ..wardrobeOutfits = outfitStore(owned: true, equipped: 'vest-low-v');
    final quizzes = Quizzes()
      ..current = QuizToday(
        date: todayKey,
        status: 'ready',
        free: question(1),
        extraStatus: 'freeRequired',
        premiumStatus: 'notChecked',
      );
    final quiz = QuizController(quizzes, isCurrentAccount: () => true);
    addTearDown(() {
      quiz.dispose();
      quizzes.client.close();
    });
    final opened = <String>[];
    await pumpHome(
      tester,
      product: productFor(server),
      quiz: quiz,
      onOpenRecords: () => opened.add('records'),
      onOpenQuiz: () => opened.add('quiz'),
      onOpenWardrobe: () => opened.add('wardrobe'),
      onOpenPhoto: () => opened.add('photo'),
    );
    String status(String id) => text(tester, 'home_tile_${id}_status');
    expect(status('wardrobe'), contains('Vest'));
    final unanswered = status('quiz');
    quizzes.current = quizzes.current.copyWith(
      free: question(1, answered: true),
    );
    await quiz.load();
    await tester.pump();
    final answered = status('quiz');
    quizzes.current = quizzes.current.copyWith(
      status: 'contentUnavailable',
      free: null,
    );
    await quiz.load();
    await tester.pump();
    expect({unanswered, answered, status('quiz')}, hasLength(3));
    // Another day's state is not today's; nothing is claimed for it.
    quizzes.current = quizzes.current.copyWith(date: dayKey(1));
    await quiz.load();
    await tester.pump();
    expect(key('home_tile_quiz_status'), findsNothing);
    for (final id in ['records', 'quiz', 'wardrobe', 'photo']) {
      final tile = key('home_tile_$id');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
    }
    expect(opened, ['records', 'quiz', 'wardrobe', 'photo']);
  });

  testWidgets("the photo tile uses the name's own particle", (tester) async {
    for (final (name, expected) in [
      ('보리', '보리와'),
      ('몽글', '몽글과'),
      ('코코 3', '코코 3과'),
      ('Max', 'Max와'),
    ]) {
      await pumpHome(tester, product: null, meeting: account(name: name));
      expect(text(tester, 'home_tile_photo_status'), startsWith(expected));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('the home reads quiz state without observing paid benefits', (
    tester,
  ) async {
    final quizzes = PremiumQuizzes();
    final quiz = QuizController(quizzes, isCurrentAccount: () => true);
    addTearDown(() {
      quiz.dispose();
      quizzes.client.close();
      quizzes.billing!.client.close();
    });
    await pumpHome(tester, product: productFor(HomeServer()), quiz: quiz);
    expect(quiz.today, isNotNull);
    expect(quizzes.premiumReads, 0);
    // The quiz screen's own load still observes them.
    await quiz.load();
    expect(quizzes.premiumReads, 1);
  });

  testWidgets('a quiz screen loading as it opens leaves the home intact', (
    tester,
  ) async {
    final quizzes = Quizzes()
      ..current = QuizToday(
        date: todayKey,
        status: 'ready',
        free: question(1),
        extraStatus: 'freeRequired',
        premiumStatus: 'notChecked',
      );
    final quiz = QuizController(quizzes, isCurrentAccount: () => true);
    addTearDown(() {
      quiz.dispose();
      quizzes.client.close();
    });
    await pumpHome(tester, product: productFor(HomeServer()), quiz: quiz);
    // The quiz screen loads in its initState; the home shares the controller.
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => AuthenticatedQuizScreen(
                controller: quiz,
                dogAsset: 'assets/first_meeting/dogs/pug.png',
                onBack: () {},
                onHome: () {},
              ),
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AuthenticatedQuizScreen), findsOneWidget);
  });

  testWidgets('the Duo rail carries tiles and settings; chips and card stay', (
    tester,
  ) async {
    useDuoViewport(tester, 'outer portrait');
    await pumpHome(tester, product: productFor(HomeServer()));
    expect(find.byType(DuoRail), findsOneWidget);
    expect(find.byType(MeetingShortcuts), findsNothing);
    expect(find.byType(StatusChip), findsWidgets);
    expect(find.byType(HomeGoalCard), findsOneWidget);
    final reward = key('home_reward');
    await tester.ensureVisible(reward);
    expect(reward.hitTestable(), findsOneWidget);
    expect(find.text('기록 보기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('large text keeps the card action and tiles reachable $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHome(
        tester,
        product: productFor(HomeServer()),
        read: available(6840),
      );
      for (final value in [
        'home_reward',
        'home_tile_records',
        'home_tile_photo',
      ]) {
        await tester.ensureVisible(key(value));
        await tester.pumpAndSettle();
        expect(key(value).hitTestable(), findsOneWidget, reason: value);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the sheet opens the wardrobe once, from the home', (
    tester,
  ) async {
    final server = HomeServer();
    var wardrobe = 0;
    await pumpHome(
      tester,
      product: productFor(server),
      read: available(6840),
      onOpenWardrobe: () => wardrobe++,
    );
    await tester.ensureVisible(key('home_reward'));
    await tester.tap(key('home_reward'));
    await tester.pumpAndSettle();
    await tester.tap(key('reward_free_claim'));
    await tester.pumpAndSettle();
    expect(key('reward_granted_title'), findsOneWidget);
    expect(wardrobe, 0);
    await tester.tap(key('reward_open_wardrobe'));
    await tester.pumpAndSettle();
    expect(wardrobe, 1);
    expect(find.byType(TodayRewardSheet), findsNothing);
    // The ad part is left, so today's points stay open; the chip is the
    // server's new balance.
    expect(point(tester).onPressed, isNotNull);
    expect(text(tester, 'reward_wallet'), '427P');
    expect(ring(tester).progress, closeTo(.855, 1e-9));
  });
}
