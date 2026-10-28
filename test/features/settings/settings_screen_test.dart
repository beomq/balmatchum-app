import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_app/features/settings/settings_screen.dart';
import 'package:balmatchum_app/features/settings/settings_widgets.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appBuildName;
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import '../first_meeting/domain/authenticated_profile_test.dart'
    show Profiles, view;
import '../first_meeting/domain/first_meeting_test.dart' show MemoryStorage;

Future<FirstMeetingController> signedIn(Profiles server) async {
  final c = FirstMeetingController(
    storage: MemoryStorage(),
    profileRepository: server,
  );
  await c.initialize();
  return c;
}

/// Every destination given, each recording its own id.
SettingsScreen settings(
  FirstMeetingController c, {
  List<String>? taps,
  DailyStepsController? steps,
  String? version = '1.2.3',
}) {
  VoidCallback open(String id) =>
      () => taps?.add(id);
  return SettingsScreen(
    controller: c,
    dailySteps: steps,
    onBack: open('back'),
    onHome: open('home'),
    onOpenSteps: open('steps'),
    onOpenPhoto: open('photo'),
    onOpenLogout: open('logout'),
    onOpenBilling: open('billing'),
    onOpenServiceInfo: open('info'),
    onOpenDeletion: open('delete'),
    version: version,
  );
}

Widget host(Widget screen, {TargetPlatform? platform, double scale = 1}) =>
    MaterialApp(
      theme: meetingTheme().copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen,
    );

DailyStepsController readOnce(DailyStepsStatus status) => DailyStepsController(
  readSteps: () async => DailyStepsResult(
    status,
    status == DailyStepsStatus.available
        ? const {'count': 6840, 'date': '2026-10-28'}
        : null,
  ),
);

void useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('groups follow Pen with no location, sync or login row', (
    tester,
  ) async {
    useTallPhone(tester);
    final c = await signedIn(Profiles()..current = view());
    addTearDown(c.dispose);
    await tester.pumpWidget(host(settings(c)));
    await tester.pumpAndSettle();
    // Pen order from the top: profile, 활동, 계정, 구매 · 정보, deletion,
    // version.
    const order = [
      'settings_profile',
      'settings_goal_row',
      'settings_steps',
      'settings_photo',
      'settings_logout',
      'settings_billing',
      'settings_info',
      'settings_delete_account',
      'settings_version',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        tester.getRect(find.byKey(ValueKey(order[i]))).top,
        greaterThan(tester.getRect(find.byKey(ValueKey(order[i - 1]))).top),
        reason: order[i],
      );
    }
    // 활동 3, 계정 1, 구매 · 정보 2: location, sync and login are not drawn.
    final groups = find.byType(SettingsGroup);
    expect(groups, findsNWidgets(3));
    for (final (index, rows) in [(0, 3), (1, 1), (2, 2)]) {
      expect(
        find.descendant(
          of: groups.at(index),
          matching: find.byType(SettingsRow),
        ),
        findsNWidgets(rows),
      );
    }
    // No primary on the list, and deletion is red text under the groups.
    expect(find.byType(FilledButton), findsNothing);
    final delete = find.byKey(const ValueKey('settings_delete_account'));
    final label = tester.widget<Text>(
      find.descendant(of: delete, matching: find.byType(Text)),
    );
    expect(label.style?.color, MeetingColors.error);
    expect(
      tester.getRect(delete).top,
      greaterThan(tester.getRect(groups.last).bottom),
    );
    expect(find.textContaining('Dev 체험'), findsNothing);
    expect(find.textContaining('개발'), findsNothing);
  });

  testWidgets('opening settings sends no request and reads no steps', (
    tester,
  ) async {
    final server = Profiles()..current = view();
    final c = await signedIn(server);
    addTearDown(c.dispose);
    var reads = 0;
    final steps = DailyStepsController(
      readSteps: () async {
        reads++;
        return const DailyStepsResult(DailyStepsStatus.empty, null);
      },
    );
    addTearDown(steps.dispose);
    final taps = <String>[];
    await tester.pumpWidget(host(settings(c, taps: taps, steps: steps)));
    await tester.pumpAndSettle();
    // No destination opened, deletion included; no step read that could
    // prompt for a permission; no profile write.
    expect(taps, isEmpty);
    expect(reads, 0);
    expect(server.ids, isEmpty);
    // Before any read the steps row shows no value at all.
    expect(find.byKey(const ValueKey('settings_steps_value')), findsNothing);
  });

  testWidgets('the steps row names the last read and never allowed on iOS', (
    tester,
  ) async {
    final c = await signedIn(Profiles()..current = view());
    addTearDown(c.dispose);
    final values = <DailyStepsStatus, String?>{};
    for (final status in DailyStepsStatus.values) {
      final steps = readOnce(status);
      await steps.refresh();
      await tester.pumpWidget(
        host(settings(c, steps: steps), platform: TargetPlatform.iOS),
      );
      await tester.pumpAndSettle();
      values[status] = tester
          .widget<Text>(find.byKey(const ValueKey('settings_steps_value')))
          .data;
      expect(values[status], stepsReadState(steps));
      // HealthKit cannot tell an app that reading is allowed (guide 6.4).
      expect(find.textContaining('허용됨'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      steps.dispose();
    }
    expect(values.values, everyElement(isNotEmpty));
    expect(
      values[DailyStepsStatus.available],
      isNot(values[DailyStepsStatus.error]),
    );
  });

  testWidgets('the name changes only after the server confirms it', (
    tester,
  ) async {
    final server = Profiles()..current = view(name: '보리');
    final c = await signedIn(server);
    addTearDown(c.dispose);
    await tester.pumpWidget(host(settings(c)));
    await tester.pumpAndSettle();
    String? name() => tester
        .widget<Text>(find.byKey(const ValueKey('settings_profile_name')))
        .data;
    expect(find.byKey(const ValueKey('settings_name')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings_profile')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('settings_name'));
    final save = find.byKey(const ValueKey('settings_name_save'));
    await tester.enterText(field, '!!');
    expect(name(), '보리');
    await tester.tap(save);
    await tester.pumpAndSettle();
    // An invalid name keeps the sheet, its message and the old name.
    expect(find.byKey(const ValueKey('settings_edit_error')), findsOneWidget);
    expect(name(), '보리');
    expect(server.ids, isEmpty);
    await tester.enterText(field, '새친구');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(name(), '새친구');
    expect(server.current!.name, '새친구');
  });

  testWidgets('an unconfirmed goal is retried with its original request', (
    tester,
  ) async {
    final server = Profiles()..current = view(goal: 5000);
    final c = await signedIn(server);
    addTearDown(c.dispose);
    await tester.pumpWidget(host(settings(c)));
    await tester.pumpAndSettle();
    String goal() => tester
        .widget<Text>(find.byKey(const ValueKey('settings_goal_value')))
        .data!;
    final before = goal();
    await tester.tap(find.byKey(const ValueKey('settings_goal_row')));
    await tester.pumpAndSettle();
    server.loseResponse = true;
    await tester.enterText(find.byKey(const ValueKey('settings_goal')), '7000');
    await tester.tap(find.byKey(const ValueKey('settings_goal_save')));
    await tester.pumpAndSettle();
    // Unconfirmed: the list keeps the old goal and the sheet offers only
    // the retry.
    expect(c.hasPendingMutation, isTrue);
    expect(goal(), before);
    expect(find.byKey(const ValueKey('settings_retry')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('settings_goal_save')),
          )
          .onPressed,
      isNull,
    );
    server.loseResponse = false;
    await tester.tap(find.byKey(const ValueKey('settings_edit_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings_goal')), findsNothing);
    expect(c.state.goal, 7000);
    expect(goal(), contains('7,000'));
    expect(find.byKey(const ValueKey('settings_retry')), findsNothing);
    // The retry resent the same request id.
    expect(server.ids, hasLength(2));
    expect(server.ids.toSet(), hasLength(1));
  });

  testWidgets('a conflict keeps the sheet and shows the newer name', (
    tester,
  ) async {
    final server = Profiles()..current = view(name: '보리');
    final c = await signedIn(server);
    addTearDown(c.dispose);
    await tester.pumpWidget(host(settings(c)));
    await tester.pumpAndSettle();
    String? name() => tester
        .widget<Text>(find.byKey(const ValueKey('settings_profile_name')))
        .data;
    await tester.tap(find.byKey(const ValueKey('settings_profile')));
    await tester.pumpAndSettle();
    // Another device renamed the dog first.
    server.current = view(name: '구름', revision: 2);
    server.conflict = true;
    await tester.enterText(find.byKey(const ValueKey('settings_name')), '새친구');
    await tester.tap(find.byKey(const ValueKey('settings_name_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings_edit_error')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_name')), findsOneWidget);
    expect(name(), '구름');
    server.conflict = false;
    await tester.tap(find.byKey(const ValueKey('settings_name_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings_name')), findsNothing);
    expect(name(), '새친구');
  });

  testWidgets('each row opens its own destination', (tester) async {
    useTallPhone(tester);
    final c = await signedIn(Profiles()..current = view());
    addTearDown(c.dispose);
    final taps = <String>[];
    await tester.pumpWidget(host(settings(c, taps: taps)));
    await tester.pumpAndSettle();
    for (final key in [
      'settings_steps',
      'settings_photo',
      'settings_logout',
      'settings_billing',
      'settings_info',
      'settings_delete_account',
      'product_back',
      'product_home',
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }
    expect(taps, [
      'steps',
      'photo',
      'logout',
      'billing',
      'info',
      'delete',
      'back',
      'home',
    ]);
  });

  testWidgets('a missing destination and version hide their rows', (
    tester,
  ) async {
    final c = await signedIn(Profiles()..current = view());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      host(
        SettingsScreen(
          controller: c,
          onBack: () {},
          onHome: () {},
          version: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsGroup), findsOneWidget);
    expect(find.byType(SettingsRow), findsOneWidget);
    for (final key in [
      'settings_logout',
      'settings_billing',
      'settings_delete_account',
      'settings_version',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    await tester.pumpWidget(host(settings(c, version: '4.5.6')));
    await tester.pumpAndSettle();
    final version = find.byKey(const ValueKey('settings_version'));
    await tester.ensureVisible(version);
    expect(tester.widget<Text>(version).data, contains('4.5.6'));
    // By default it is the build name the app was compiled with.
    await tester.pumpWidget(
      host(SettingsScreen(controller: c, onBack: () {}, onHome: () {})),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(version);
    expect(appBuildName, isNotNull);
    expect(tester.widget<Text>(version).data, contains(appBuildName!));
  });

  for (final width in [320.0, 390.0, 768.0]) {
    for (final scale in [1.0, 1.15]) {
      testWidgets('settings scroll to the bottom at $width, text x$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = await signedIn(Profiles()..current = view());
        addTearDown(c.dispose);
        await tester.pumpWidget(host(settings(c), scale: scale));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('settings_version')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings_delete_account')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final viewport in duoViewports.keys) {
    testWidgets('settings fit Duo $viewport', (tester) async {
      useDuoViewport(tester, viewport);
      final c = await signedIn(Profiles()..current = view());
      addTearDown(c.dispose);
      final taps = <String>[];
      await tester.pumpWidget(duoHost(settings(c, taps: taps)));
      await tester.pumpAndSettle();
      final rail = find.byType(DuoRail).evaluate().isNotEmpty;
      if (viewport == 'outer portrait') {
        // The rail carries back and home; the title keeps its own row.
        expect(rail, isTrue);
        expect(find.byType(ProductTopBar), findsNothing);
        expect(find.byKey(const ValueKey('product_title')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('duo_rail_back')));
        await tester.tap(find.byKey(const ValueKey('duo_rail_home')));
        expect(taps, ['back', 'home']);
      }
      final delete = find.byKey(const ValueKey('settings_delete_account'));
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      expect(delete.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
