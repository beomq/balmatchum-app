import 'package:balmatchum_app/features/first_meeting/breed_pager.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/first_meeting/onboarding_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'domain/first_meeting_test.dart' show MemoryStorage;
import 'meeting_ui_test.dart' show MemoryStore;

const _breeds = FirstMeetingCatalog.breeds;
final _position = find.byKey(const ValueKey('breed_pager_position'));
final _next = find.byKey(const ValueKey('breed_pager_next'));
final _previous = find.byKey(const ValueKey('breed_pager_previous'));
final _pager = find.byKey(const ValueKey('breed_pager'));
final _strip = find.byKey(const ValueKey('breed_group_tabs'));
final _choose = find.byKey(const ValueKey('breed_choose'));
final _recommend = find.byKey(const ValueKey('breed_recommend'));

Finder _card(DogBreed breed) => find.byKey(ValueKey('breed_${breed.id}'));
Finder _tab(String group) => find.byKey(ValueKey('breed_group_$group'));

String _shown(WidgetTester tester) => tester.widget<Text>(_position).data!;

bool _enabled(WidgetTester tester, Finder button) =>
    tester
        .widget<IconButton>(
          find.descendant(of: button, matching: find.byType(IconButton)),
        )
        .onPressed !=
    null;

bool _tabSelected(WidgetTester tester, String group) => tester
    .widget<BreedGroupTab>(
      find.ancestor(of: _tab(group), matching: find.byType(BreedGroupTab)),
    )
    .selected;

/// The pick button's label, which names the centered breed.
String _pick(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _choose, matching: find.byType(Text)))
    .data!;

double _opacity(WidgetTester tester, Finder card) => tester
    .widget<Opacity>(
      find.ancestor(of: card, matching: find.byType(Opacity)).first,
    )
    .opacity;

Future<List<DogBreed>> _mount(
  WidgetTester tester, {
  String? initialBreedId,
  bool enabled = true,
  double scale = 1,
}) async {
  final selected = <DogBreed>[];
  // The caller owns the shown card, as the catalog step does.
  var index = BreedPager.indexOf(initialBreedId);
  // A fresh tree, so each mount starts from its own initial breed.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      theme: meetingTheme(),
      home: MediaQuery.withClampedTextScaling(
        minScaleFactor: scale,
        maxScaleFactor: scale,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => BreedPager(
                index: index,
                enabled: enabled,
                onChanged: (value) => setState(() => index = value),
                onSelect: selected.add,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return selected;
}

/// The real catalog step of a Dev meeting on an iPhone 17 whose previous
/// catalog candidate is [candidate].
Future<FirstMeetingController> _catalog(
  WidgetTester tester, {
  MemoryStorage? storage,
  String? candidate,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
  addTearDown(tester.view.reset);
  final c = FirstMeetingController(storage: storage ?? MemoryStorage());
  addTearDown(c.dispose);
  await c.initialize();
  await c.enter();
  await c.chooseCatalog();
  if (candidate != null) {
    await c.selectBreed(candidate);
    await c.back();
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: meetingTheme(),
      home: FirstMeetingScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('pages all 30 breeds in catalog order, one same-size card each', (
    tester,
  ) async {
    // Given the pager with no previous candidate.
    await _mount(tester);
    expect(_shown(tester), '1 / 30');
    expect(_enabled(tester, _previous), isFalse);
    final sizes = <Size>{};
    for (var i = 0; i < _breeds.length; i++) {
      // When the next control has moved to card i.
      if (i > 0) {
        await tester.tap(_next);
        await tester.pumpAndSettle();
      }
      // Then card i shows that breed's shipped sprite and Korean name.
      final breed = _breeds[i];
      expect(_shown(tester), '${i + 1} / 30');
      expect(_card(breed), findsOneWidget);
      expect(
        find.descendant(
          of: _card(breed),
          matching: find.image(AssetImage(breed.spritePath)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _card(breed), matching: find.text(breed.name)),
        findsOneWidget,
      );
      sizes.add(tester.getSize(_card(breed)));
    }
    expect(sizes, hasLength(1));
    expect(_enabled(tester, _next), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipes follow the order across groups and move the tab', (
    tester,
  ) async {
    // Given the last G1 breed.
    await _mount(tester, initialBreedId: 'bulldog');
    expect(_shown(tester), '2 / 30');
    expect(_tabSelected(tester, 'G1'), isTrue);
    // When the card is swiped toward the next breed.
    await tester.fling(_pager, const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    // Then group 2 starts and its tab becomes the selected one.
    expect(_shown(tester), '3 / 30');
    expect(_card(_breeds[2]), findsOneWidget);
    expect(_tabSelected(tester, 'G2'), isTrue);
    expect(_tabSelected(tester, 'G1'), isFalse);
    // And a swipe back returns to G1.
    await tester.fling(_pager, const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(_shown(tester), '2 / 30');
    expect(_tabSelected(tester, 'G1'), isTrue);
  });

  testWidgets('group tabs jump to the first breed of each group', (
    tester,
  ) async {
    await _mount(tester);
    for (final group in FirstMeetingCatalog.groups.reversed) {
      // When a group tab is scrolled into the strip and tapped.
      await tester.ensureVisible(_tab(group.id));
      await tester.pumpAndSettle();
      await tester.tap(_tab(group.id));
      await tester.pumpAndSettle();
      // Then the pager shows that group's first breed in catalog order.
      final first = group.breeds.first;
      expect(_shown(tester), '${_breeds.indexOf(first) + 1} / 30');
      expect(_card(first), findsOneWidget);
    }
  });

  testWidgets('tabs carry the catalog names and follow the shown group', (
    tester,
  ) async {
    // Given the pager at the first breed.
    await _mount(tester);
    // Then each tab shows its group's user-facing name, sized to that name.
    for (final group in FirstMeetingCatalog.groups) {
      expect(
        tester
            .widget<Text>(
              find.descendant(of: _tab(group.id), matching: find.byType(Text)),
            )
            .data,
        group.name,
      );
    }
    expect(
      tester.getSize(_tab('G8')).width,
      greaterThan(tester.getSize(_tab('G1')).width),
    );
    final strip = tester.getRect(_strip);
    final tabs = tester.state<ScrollableState>(
      find.descendant(of: _strip, matching: find.byType(Scrollable)),
    );
    final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
    // When the arrows walk through every breed.
    for (var i = 1; i < _breeds.length; i++) {
      await tester.tap(_next);
      await tester.pumpAndSettle();
      // Then the shown group's tab is selected and fully inside the strip,
      // centered unless the strip rests at one of its ends.
      final group = _breeds[i].groupId;
      expect(_tabSelected(tester, group), isTrue);
      final tab = tester.getRect(_tab(group));
      expect(tab.left, greaterThanOrEqualTo(strip.left - .5), reason: group);
      expect(tab.right, lessThanOrEqualTo(strip.right + .5), reason: group);
      final offset = tabs.position.pixels;
      if (offset > tabs.position.minScrollExtent &&
          offset < tabs.position.maxScrollExtent) {
        expect(tab.center.dx, closeTo(strip.center.dx, 1), reason: group);
      }
      // And revealing a tab never scrolls the page itself.
      expect(page.position.pixels, 0);
    }
    expect(tabs.position.pixels, tabs.position.maxScrollExtent);
  });

  testWidgets('neighbours peek at the sides and never wrap at the ends', (
    tester,
  ) async {
    for (final (index, neighbour, absent) in const [(0, 1, 29), (29, 28, 0)]) {
      // Given the pager at one end of the catalog.
      await _mount(tester, initialBreedId: _breeds[index].id);
      final pager = tester.getRect(_pager);
      final center = tester.getRect(_card(_breeds[index]));
      final side = tester.getRect(_card(_breeds[neighbour]));
      // Then the shown card sits in the middle, whole and most prominent.
      expect(center.center.dx, closeTo(pager.center.dx, 1));
      expect(_opacity(tester, _card(_breeds[index])), 1);
      // And only the inner neighbour peeks in, smaller and faded.
      expect(side.height, lessThan(center.height));
      expect(_opacity(tester, _card(_breeds[neighbour])), lessThan(1));
      if (neighbour > index) {
        expect(side.left, greaterThan(center.right));
        expect(side.left, lessThan(pager.right));
      } else {
        expect(side.right, lessThan(center.left));
        expect(side.right, greaterThan(pager.left));
      }
      // And the other end's card is not wrapped around into view.
      expect(_card(_breeds[absent]), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on a neighbour brings it in without selecting', (
    tester,
  ) async {
    // Given the first card with the second peeking at the right.
    final selected = await _mount(tester);
    final pager = tester.getRect(_pager);
    final side = tester.getRect(_card(_breeds[1]));
    // When the visible part of the neighbour is tapped.
    await tester.tapAt(Offset((side.left + pager.right) / 2, side.center.dy));
    await tester.pumpAndSettle();
    // Then it becomes the shown card and nothing is selected yet.
    expect(_shown(tester), '2 / 30');
    expect(selected, isEmpty);
    // And a tap on it now selects exactly that breed.
    await tester.tap(_card(_breeds[1]));
    await tester.pump();
    expect(selected.map((b) => b.id), [_breeds[1].id]);
  });

  testWidgets('tapping a card selects only that breed while enabled', (
    tester,
  ) async {
    // Given the pager opened on the previous candidate.
    var selected = await _mount(tester, initialBreedId: 'samoyed');
    expect(_shown(tester), '28 / 30');
    // When its card is tapped.
    await tester.tap(_card(FirstMeetingCatalog.byId('samoyed')));
    await tester.pump();
    // Then exactly that breed is reported.
    expect(selected.map((b) => b.id), ['samoyed']);

    // Given a busy screen, a tap selects nothing.
    selected = await _mount(tester, initialBreedId: 'pug', enabled: false);
    await tester.tap(_card(FirstMeetingCatalog.byId('pug')));
    await tester.pump();
    expect(selected, isEmpty);
  });

  testWidgets('every card keeps one card and art size at 1.15x', (
    tester,
  ) async {
    // Given a narrow phone where the longest names no longer fit one line.
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(320, 568) * 3;
    addTearDown(tester.view.reset);
    await _mount(tester, scale: 1.15);
    final cards = <Size>{};
    final arts = <Size>{};
    for (var i = 0; i < _breeds.length; i++) {
      if (i > 0) {
        await tester.tap(_next);
        await tester.pumpAndSettle();
      }
      // Then every card and its art keep the same size.
      final card = _card(_breeds[i]);
      cards.add(tester.getSize(card));
      arts.add(
        tester.getSize(find.descendant(of: card, matching: find.byType(Image))),
      );
    }
    expect(cards, hasLength(1));
    expect(arts, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pick follows the shown breed with its particle', (
    tester,
  ) async {
    // The label's particle follows the name's last sound (로 / 으로).
    for (final (candidate, named) in const [
      ('pekingese', '페키니즈로 '),
      ('bulldog', '불독으로 '),
      ('bichon-frise', '비숑으로 '),
      ('jindo', '진돗개로 '),
      ('shiba-inu', '시바견으로 '),
      ('toy-poodle', '푸들로 '),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _catalog(tester, candidate: candidate);
      expect(_pick(tester), startsWith(named), reason: candidate);
    }
    // Given the first breed.
    await tester.pumpWidget(const SizedBox.shrink());
    await _catalog(tester);
    expect(_pick(tester), startsWith('페키니즈로 '));
    // When a swipe of less than a card, then a tab, moves the shown card.
    await tester.fling(_pager, const Offset(-150, 0), 1000);
    await tester.pumpAndSettle();
    // Then the label names the card in the middle each time.
    expect(_shown(tester), '2 / 30');
    expect(_pick(tester), startsWith('불독으로 '));
    await tester.tap(_tab('G3'));
    await tester.pumpAndSettle();
    expect(_shown(tester), '8 / 30');
    expect(_pick(tester), startsWith('닥스훈트로 '));
  });

  testWidgets('the card and the pick select the shown breed once', (
    tester,
  ) async {
    for (final both in [false, true]) {
      // Given the catalog showing 불독.
      await tester.pumpWidget(const SizedBox.shrink());
      final storage = MemoryStorage();
      final c = await _catalog(tester, storage: storage, candidate: 'bulldog');
      final writes = storage.writes;
      // When the pick is tapped twice, or the card and the pick, in a frame.
      await tester.tap(
        both ? _card(FirstMeetingCatalog.byId('bulldog')) : _choose,
      );
      await tester.tap(_choose);
      await tester.pumpAndSettle();
      // Then 불독 is chosen with a single save and the confirm step opens.
      expect(c.state.step, FirstMeetingStep.confirm, reason: '$both');
      expect(c.state.candidate!.id, 'bulldog', reason: '$both');
      expect(storage.writes - writes, 1, reason: '$both');
    }
  });

  testWidgets('the recommendation opens the questions from the catalog', (
    tester,
  ) async {
    // Given the catalog step.
    final c = await _catalog(tester);
    // When the recommendation under the pick is tapped.
    await tester.ensureVisible(_recommend);
    await tester.tap(_recommend);
    await tester.pumpAndSettle();
    // Then the three questions start.
    expect(c.state.step, FirstMeetingStep.question);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone shows one back, in the 1/3 step bar', (tester) async {
    // Given the catalog step on an iPhone 17.
    final c = await _catalog(tester);
    // Then the step bar reads 1 of 3 and holds the only back.
    final nav = tester.widget<OnboardingStepNav>(
      find.byType(OnboardingStepNav),
    );
    expect((nav.step, nav.total), (1, 3));
    final back = find.byKey(const ValueKey('meeting_back'));
    expect(back.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('duo_rail_back')), findsNothing);
    // When it is tapped, the method choice returns.
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(c.state.step, FirstMeetingStep.method);
  });

  for (final (size, scale) in [
    (const Size(320, 568), 1.0),
    (const Size(320, 568), 2.0),
    (const Size(402, 874), 1.0),
  ]) {
    testWidgets('catalog step fits ${size.width}x${size.height} text $scale', (
      tester,
    ) async {
      // Given the real catalog step at a phone viewport and text scale.
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final c = FirstMeetingController(storage: MemoryStore());
      addTearDown(c.dispose);
      await c.initialize();
      await c.enter();
      await c.chooseCatalog();
      await tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme(),
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: FirstMeetingScreen(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // When the last tab is scrolled in and each control is brought in view.
      final card = _card(_breeds.first);
      await tester.scrollUntilVisible(
        _tab('G8'),
        60,
        scrollable: find.descendant(
          of: _strip,
          matching: find.byType(Scrollable),
        ),
      );
      // Then the card fits the content width and every control is tappable.
      expect(tester.getSize(card).width, lessThanOrEqualTo(size.width - 24));
      for (final control in [
        card,
        _tab('G8'),
        _previous,
        _next,
        _choose,
        _recommend,
      ]) {
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        expect(control.hitTestable(), findsOneWidget, reason: '$control');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
