import 'package:balmatchum_app/features/first_meeting/breed_pager.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'meeting_ui_test.dart' show MemoryStore;

const _breeds = FirstMeetingCatalog.breeds;
final _position = find.byKey(const ValueKey('breed_pager_position'));
final _next = find.byKey(const ValueKey('breed_pager_next'));
final _previous = find.byKey(const ValueKey('breed_pager_previous'));
final _pager = find.byKey(const ValueKey('breed_pager'));

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

Color? _tabColor(WidgetTester tester, String group) => tester
    .widget<Material>(
      find.ancestor(of: _tab(group), matching: find.byType(Material)).first,
    )
    .color;

Future<List<DogBreed>> _mount(
  WidgetTester tester, {
  String? initialBreedId,
  bool enabled = true,
}) async {
  final selected = <DogBreed>[];
  // A fresh tree, so each mount starts from its own initial breed.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      theme: meetingTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: BreedPager(
            initialBreedId: initialBreedId,
            enabled: enabled,
            onSelect: selected.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return selected;
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
    expect(_tabColor(tester, 'G1'), MeetingColors.soft);
    // When the card is swiped toward the next breed.
    await tester.fling(_pager, const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    // Then group 2 starts and its tab becomes the selected one.
    expect(_shown(tester), '3 / 30');
    expect(_card(_breeds[2]), findsOneWidget);
    expect(_tabColor(tester, 'G2'), MeetingColors.soft);
    expect(_tabColor(tester, 'G1'), MeetingColors.raised);
    // And a swipe back returns to G1.
    await tester.fling(_pager, const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(_shown(tester), '2 / 30');
    expect(_tabColor(tester, 'G1'), MeetingColors.soft);
  });

  testWidgets('group tabs jump to the first breed of each group', (
    tester,
  ) async {
    await _mount(tester);
    for (final group in FirstMeetingCatalog.groups.reversed) {
      // When a group tab is tapped.
      await tester.tap(_tab(group.id));
      await tester.pumpAndSettle();
      // Then the pager shows that group's first breed in catalog order.
      final first = group.breeds.first;
      expect(_shown(tester), '${_breeds.indexOf(first) + 1} / 30');
      expect(_card(first), findsOneWidget);
    }
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
          of: find.byKey(const ValueKey('breed_group_tabs')),
          matching: find.byType(Scrollable),
        ),
      );
      // Then the card fits the content width and every control is tappable.
      expect(tester.getSize(card).width, lessThanOrEqualTo(size.width - 24));
      for (final control in [card, _tab('G8'), _previous, _next]) {
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        expect(control.hitTestable(), findsOneWidget, reason: '$control');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
