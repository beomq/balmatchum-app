import 'dart:async';

import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/first_meeting/onboarding_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import 'domain/first_meeting_test.dart' show MemoryStorage;
import 'name_input_test.dart' show PausedStore;

final _field = find.byKey(const ValueKey('meeting_name'));
final _line = find.byKey(const ValueKey('meeting_name_line'));
final _note = find.byKey(const ValueKey('meeting_name_breed'));
final _count = find.byKey(const ValueKey('meeting_name_count'));
final _help = find.byKey(const ValueKey('meeting_name_help'));
final _save = find.byKey(const ValueKey('meeting_name_submit'));
final _back = find.byKey(const ValueKey('meeting_back'));
const _most = FirstMeetingController.maxNameLength;
Finder _sex(DogSex sex) => find.byKey(ValueKey('meeting_sex_${sex.name}'));

/// A Dev first meeting at the name step with [breed] chosen.
Future<FirstMeetingController> atName({
  FirstMeetingStorage? storage,
  String breed = 'pug',
  DogSex? sex,
}) async {
  final c = FirstMeetingController(storage: storage ?? MemoryStorage());
  await c.initialize();
  await c.enter();
  await c.chooseCatalog();
  await c.selectBreed(breed);
  await c.confirmCandidate();
  if (sex != null) await c.updateSex(sex);
  expect(c.state.step, FirstMeetingStep.name);
  return c;
}

const _iphone = (Size(402, 874), FakeViewPadding(top: 186, bottom: 102));

/// An iPhone 17 safe area, or [size] with no insets.
Future<void> show(
  WidgetTester tester,
  FirstMeetingController c, {
  Size size = const Size(402, 874),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  if (size == _iphone.$1) tester.view.padding = _iphone.$2;
  addTearDown(tester.view.reset);
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
}

/// The shown text, without the word joiners the bubble wraps by.
String _text(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).data!.replaceAll('\u2060', '');

String _saveLabel(WidgetTester tester) =>
    _text(tester, find.descendant(of: _save, matching: find.byType(Text)));

VoidCallback? _saveOn(WidgetTester tester) =>
    tester.widget<FilledButton>(_save).onPressed;

/// Sends [text] through the IME path, as the platform keyboard does.
Future<void> type(WidgetTester tester, String text) async {
  await tester.showKeyboard(_field);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the 2/3 step bar holds the only back on a phone', (
    tester,
  ) async {
    final c = await atName();
    addTearDown(c.dispose);
    await show(tester, c);
    final nav = tester.widget<OnboardingStepNav>(
      find.byType(OnboardingStepNav),
    );
    expect((nav.step, nav.total), (2, 3));
    expect(_back.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('duo_rail_back')), findsNothing);
  });

  testWidgets('the stage shows the chosen breed, not a fixed one', (
    tester,
  ) async {
    for (final id in ['pug', 'jindo']) {
      // Given the name step after choosing this breed.
      await tester.pumpWidget(const SizedBox.shrink());
      final c = await atName(breed: id);
      addTearDown(c.dispose);
      await show(tester, c);
      final breed = FirstMeetingCatalog.byId(id);
      // Then its sprite stands on the stage and its name leads the note.
      expect(
        find.descendant(
          of: find.byType(DogNameStage),
          matching: find.image(AssetImage(breed.spritePath)),
        ),
        findsOneWidget,
      );
      expect(_text(tester, _note), startsWith('${breed.name} '));
    }
  });

  testWidgets('the bubble and the count follow Korean input at once', (
    tester,
  ) async {
    // Given an empty name whose saves are held open.
    final store = PausedStore();
    final c = await atName(storage: store, sex: DogSex.female);
    addTearDown(c.dispose);
    await show(tester, c);
    final neutral = _text(tester, _line);
    expect(_text(tester, _count), '0/$_most');
    await tester.showKeyboard(_field);
    for (final (value, shown, count) in const [
      (
        TextEditingValue(
          text: '코',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
        '코',
        1,
      ),
      (
        TextEditingValue(
          text: '코코',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
        '코코',
        2,
      ),
      (
        TextEditingValue(
          text: '  코코  ',
          selection: TextSelection.collapsed(offset: 6),
        ),
        '코코',
        2,
      ),
    ]) {
      store.writeStarted = Completer<void>();
      store.writeReleased = Completer<void>();
      // When the IME sends the edit and its save is still in flight.
      tester.testTextInput.updateEditingValue(value);
      await store.writeStarted!.future.timeout(const Duration(seconds: 5));
      await tester.pump();
      // Then the bubble and the count already show it, trimmed like the save.
      expect(_text(tester, _line), contains(shown));
      expect(_text(tester, _count), '$count/$_most');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: _field, matching: find.byType(EditableText)),
            )
            .controller
            .value,
        value,
      );
      store.writeReleased!.complete();
      await tester.pump();
    }
    // And clearing the field brings the neutral line back.
    store.writeStarted = null;
    store.writeReleased = null;
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
    await tester.pumpAndSettle();
    expect(_text(tester, _line), neutral);
    expect(_text(tester, _count), '0/$_most');
  });

  testWidgets('the save and the line take 로 or 으로, 야 or 이야 by sound', (
    tester,
  ) async {
    final c = await atName(sex: DogSex.male);
    addTearDown(c.dispose);
    await show(tester, c);
    // The particle follows the last sound; digits are read in Korean.
    for (final (name, ro, iya) in const [
      ('코코', '코코로 ', '코코야'),
      ('몽글', '몽글로 ', '몽글이야'),
      ('초롱', '초롱으로 ', '초롱이야'),
      ('보리 3', '보리 3으로 ', '보리 3이야'),
      ('보리 7', '보리 7로 ', '보리 7이야'),
      ('보리 2', '보리 2로 ', '보리 2야'),
      ('Max', 'Max로 ', 'Max야'),
    ]) {
      await type(tester, name);
      expect(_saveLabel(tester), startsWith(ro), reason: name);
      expect(_text(tester, _line), contains(iya), reason: name);
    }
  });

  testWidgets('an empty, long, spaced or odd name or no sex cannot save', (
    tester,
  ) async {
    final c = await atName();
    addTearDown(c.dispose);
    await show(tester, c);
    final neutral = _saveLabel(tester);
    // Given no sex chosen, even a valid name cannot save.
    await type(tester, '보리');
    expect(_saveOn(tester), isNull);
    await tester.tap(_sex(DogSex.female));
    await tester.pumpAndSettle();
    expect(_saveOn(tester), isNotNull);
    for (final (name, tooLong) in const [
      ('', false),
      ('   ', false),
      ('가나다라마바사아자차카타파', true),
      ('보리!', false),
    ]) {
      // When the name is empty, blank, 13 characters or has other characters.
      await type(tester, name);
      // Then the save is off, its label names no one and the line is neutral.
      expect(_saveOn(tester), isNull, reason: name);
      expect(_saveLabel(tester), neutral, reason: name);
      expect(c.state.step, FirstMeetingStep.name);
      // And a broken rule turns the note under the field red.
      final red = name.trim().isNotEmpty;
      expect(
        tester.widget<Text>(_help).style?.color,
        red ? MeetingColors.error : MeetingColors.muted,
        reason: name,
      );
      expect(
        tester.widget<Text>(_count).style?.color,
        red ? MeetingColors.error : MeetingColors.muted,
        reason: name,
      );
      if (tooLong) expect(_text(tester, _count), '13/$_most');
    }
  });

  testWidgets('a valid name saves once and opens the goal step', (
    tester,
  ) async {
    // Given a name and a sex, with every save counted.
    final storage = MemoryStorage();
    final c = await atName(storage: storage, sex: DogSex.female);
    addTearDown(c.dispose);
    await show(tester, c);
    await type(tester, ' 보리 ');
    await tester.ensureVisible(_save);
    await tester.pumpAndSettle();
    final writes = storage.writes;
    // When the save is tapped twice in one frame.
    await tester.tap(_save);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    // Then one save moves on with the trimmed name.
    expect(storage.writes - writes, 1);
    expect(c.state.step, FirstMeetingStep.goal);
    expect(c.state.name, '보리');
  });

  testWidgets('a save in flight locks the save and the sex choice', (
    tester,
  ) async {
    // Given a valid name whose next write is held open.
    final store = PausedStore();
    final c = await atName(storage: store, sex: DogSex.female);
    addTearDown(c.dispose);
    await show(tester, c);
    await type(tester, '보리');
    expect(_saveOn(tester), isNotNull);
    store.writeStarted = Completer<void>();
    store.writeReleased = Completer<void>();
    // When the sex changes and its save has not finished.
    final saving = c.updateSex(DogSex.male);
    await store.writeStarted!.future.timeout(const Duration(seconds: 5));
    await tester.pump();
    // Then neither the save nor the sex options take a tap.
    expect(_saveOn(tester), isNull);
    expect(tester.widget<InkWell>(_sex(DogSex.female)).onTap, isNull);
    store.writeReleased!.complete();
    await saving;
    await tester.pumpAndSettle();
    expect(_saveOn(tester), isNotNull);
  });

  testWidgets('sex starts unchosen and the two options pick their own', (
    tester,
  ) async {
    final c = await atName();
    addTearDown(c.dispose);
    await show(tester, c);
    bool chosen(DogSex sex) => tester
        .widget<Semantics>(
          find.ancestor(of: _sex(sex), matching: find.byType(Semantics)).first,
        )
        .properties
        .selected!;
    // Given no default, neither option is chosen.
    expect(c.state.sex, isNull);
    expect(chosen(DogSex.female), isFalse);
    expect(chosen(DogSex.male), isFalse);
    // When 수컷, then 암컷 is tapped, each becomes the only chosen one.
    for (final sex in [DogSex.male, DogSex.female]) {
      await tester.tap(_sex(sex));
      await tester.pumpAndSettle();
      expect(c.state.sex, sex);
      expect(chosen(sex), isTrue);
      expect(chosen(DogSex.values.firstWhere((s) => s != sex)), isFalse);
    }
  });

  testWidgets('going back and returning keeps the name and the sex', (
    tester,
  ) async {
    // Given a typed name and a chosen sex.
    final c = await atName();
    addTearDown(c.dispose);
    await show(tester, c);
    await type(tester, '보리');
    await tester.tap(_sex(DogSex.male));
    await tester.pumpAndSettle();
    // When back opens the confirm step and the same breed is confirmed again.
    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(c.state.step, FirstMeetingStep.confirm);
    await c.confirmCandidate();
    await tester.pumpAndSettle();
    // Then the field, the bubble and the sex come back as they were.
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: _field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      '보리',
    );
    expect(_text(tester, _line), contains('보리'));
    expect(c.state.sex, DogSex.male);
    expect(_saveLabel(tester), startsWith('보리로 '));
  });

  for (final duo in [false, true]) {
    testWidgets('an open keyboard keeps the field and the save in reach on '
        '${duo ? 'Duo outer' : 'iPhone 17'}', (tester) async {
      // Given the name step with a name and a sex.
      final c = await atName(sex: DogSex.female);
      addTearDown(c.dispose);
      if (duo) {
        useDuoViewport(tester, 'outer portrait');
        await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
        await tester.pumpAndSettle();
      } else {
        await show(tester, c);
      }
      await type(tester, '보리');
      // When the keyboard takes the lower part of the screen.
      tester.view.viewInsets = FakeViewPadding(bottom: duo ? 900 : 1008);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      // Then the field shows above it and the save is one scroll away.
      expect(_field.hitTestable(), findsOneWidget);
      await tester.ensureVisible(_save);
      await tester.pumpAndSettle();
      expect(_save.hitTestable(), findsOneWidget);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(c.state.step, FirstMeetingStep.goal);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, scale) in [
    (const Size(320, 568), 1.15),
    (const Size(402, 874), 1.15),
    (const Size(320, 568), 2.0),
  ]) {
    testWidgets('large text keeps the stage, note and sex apart at '
        '${size.width.toInt()} x$scale', (tester) async {
      // Given the longest breed and a 12-character name at a large text size.
      final c = await atName(breed: 'labrador-retriever', sex: DogSex.female);
      addTearDown(c.dispose);
      await show(tester, c, size: size, scale: scale);
      await type(tester, '가나다라마바사아자차카타');
      expect(_saveOn(tester), isNotNull);
      // Then the bubble and the note sit inside the stage, apart, and the
      // field, its note and the sex choice follow without overlapping.
      final stage = tester.getRect(find.byType(DogNameStage));
      final line = tester.getRect(_line);
      final note = tester.getRect(_note);
      expect(
        stage.contains(line.topLeft) && stage.contains(line.bottomRight),
        isTrue,
      );
      expect(
        stage.contains(note.topLeft) && stage.contains(note.bottomRight),
        isTrue,
      );
      expect(line.bottom, lessThanOrEqualTo(note.top));
      final field = tester.getRect(_field);
      final help = tester.getRect(_help);
      final sex = tester.getRect(find.byType(SexSegment));
      expect(stage.bottom, lessThanOrEqualTo(field.top));
      expect(field.bottom, lessThanOrEqualTo(help.top));
      expect(help.bottom, lessThanOrEqualTo(sex.top));
      await tester.ensureVisible(_save);
      await tester.pumpAndSettle();
      expect(_save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
