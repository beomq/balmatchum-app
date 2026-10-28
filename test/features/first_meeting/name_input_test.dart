import 'dart:async';

import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import 'domain/authenticated_profile_test.dart' show Profiles, view;
import 'meeting_ui_test.dart' show MemoryStore;

class PausedStore extends MemoryStore {
  Completer<void>? writeStarted;
  Completer<void>? writeReleased;

  @override
  Future<void> write(String payload) async {
    writeStarted?.complete();
    await writeReleased?.future;
    await super.write(payload);
  }
}

const koreanEdits = [
  TextEditingValue(
    text: 'ㅋ',
    selection: TextSelection.collapsed(offset: 1),
    composing: TextRange(start: 0, end: 1),
  ),
  TextEditingValue(
    text: '코',
    selection: TextSelection.collapsed(offset: 1),
    composing: TextRange(start: 0, end: 1),
  ),
  TextEditingValue(
    text: '코ㅋ',
    selection: TextSelection.collapsed(offset: 2),
    composing: TextRange(start: 1, end: 2),
  ),
  TextEditingValue(
    text: '코코',
    selection: TextSelection.collapsed(offset: 2),
    composing: TextRange(start: 1, end: 2),
  ),
  TextEditingValue(text: '코코', selection: TextSelection.collapsed(offset: 2)),
  TextEditingValue(text: '코코', selection: TextSelection.collapsed(offset: 1)),
  TextEditingValue(
    text: '코ㅋ코',
    selection: TextSelection.collapsed(offset: 2),
    composing: TextRange(start: 1, end: 2),
  ),
  TextEditingValue(text: '코', selection: TextSelection.collapsed(offset: 1)),
  TextEditingValue(
    text: '가나다라마바사아자차카타파',
    selection: TextSelection.collapsed(offset: 13),
    composing: TextRange(start: 12, end: 13),
  ),
  TextEditingValue(
    text: '가나다라마바사아자차카타파',
    selection: TextSelection.collapsed(offset: 13),
  ),
  TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
  TextEditingValue(
    text: '  코코  ',
    selection: TextSelection.collapsed(offset: 6),
  ),
];

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final settings in [false, true]) {
      testWidgets(
        '${settings ? 'settings' : 'onboarding'} preserves Korean IME on $platform while saving',
        (tester) async {
          // Given a real name field and a controllably pending storage write.
          final store = PausedStore();
          final profiles = Profiles();
          if (settings) profiles.current = view();
          final c = FirstMeetingController(
            storage: store,
            profileRepository: settings ? profiles : null,
          );
          addTearDown(c.dispose);
          await c.initialize();
          if (!settings) {
            await c.enter();
            await c.chooseCatalog();
            await c.selectBreed('pug');
            await c.confirmCandidate();
            await c.updateSex(DogSex.female);
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: meetingTheme().copyWith(platform: platform),
              home: FirstMeetingScreen(controller: c),
            ),
          );
          await tester.pumpAndSettle();
          if (settings) {
            await tester.tap(find.byTooltip('설정'));
            await tester.pumpAndSettle();
          }
          final field = find.byKey(
            ValueKey(settings ? 'settings_name' : 'meeting_name'),
          );
          await tester.showKeyboard(field);
          final editableFinder = find.descendant(
            of: field,
            matching: find.byType(EditableText),
          );
          final initialEditable = tester.state<EditableTextState>(
            editableFinder,
          );

          // When the IME composes, commits and deletes across busy frames.
          for (final edit in koreanEdits) {
            final savesText =
                !settings &&
                tester.widget<EditableText>(editableFinder).controller.text !=
                    edit.text;
            if (savesText) {
              store.writeStarted = Completer<void>();
              store.writeReleased = Completer<void>();
            }
            tester.testTextInput.updateEditingValue(edit);
            if (savesText) {
              await store.writeStarted!.future.timeout(
                const Duration(seconds: 5),
              );
            }
            await tester.pump();
            final editable = tester.widget<EditableText>(editableFinder);

            // Then the same editing session retains focus, caret and composing.
            expect(
              editable.focusNode.hasFocus,
              isTrue,
              reason: 'Lost keyboard focus for $edit during persistence',
            );
            expect(tester.state(editableFinder), same(initialEditable));
            expect(editable.controller.value, edit);
            expect(tester.takeException(), isNull);
            store.writeReleased?.complete();
            await tester.pump();
            expect(editable.controller.value, edit);
            expect(editable.focusNode.hasFocus, isTrue);
            store.writeStarted = null;
            store.writeReleased = null;
          }
          if (settings) {
            await tester.tap(find.text('이름 저장'));
            await tester.pumpAndSettle();
            expect(profiles.current!.name, '코코');
          } else {
            await tester.ensureVisible(find.text('이름과 성별 저장'));
            await tester.tap(find.text('이름과 성별 저장'));
            await tester.pumpAndSettle();
            expect(c.state.name, '코코');
            expect(c.state.step, FirstMeetingStep.goal);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'Duo outer rail toggle keeps the Korean name field on $platform',
      (tester) async {
        // Given the name step on the outer panel, where the rail carries back.
        useDuoViewport(tester, 'outer portrait');
        final store = PausedStore();
        final c = FirstMeetingController(storage: store);
        addTearDown(c.dispose);
        await c.initialize();
        await c.enter();
        await c.chooseCatalog();
        await c.selectBreed('pug');
        await c.confirmCandidate();
        await c.updateSex(DogSex.female);
        await tester.pumpWidget(
          MaterialApp(
            theme: meetingTheme().copyWith(platform: platform),
            home: FirstMeetingScreen(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        final railBack = find.byKey(const ValueKey('duo_rail_back'));
        final topBack = find.byKey(const ValueKey('meeting_back'));
        final field = find.byKey(const ValueKey('meeting_name'));
        final editableFinder = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        expect(railBack, findsOneWidget);
        final place = tester.getRect(field);

        // When the field takes focus and the keyboard inset hides the rail.
        await tester.showKeyboard(field);
        final initialEditable = tester.state<EditableTextState>(editableFinder);
        tester.view.viewInsets = const FakeViewPadding(bottom: 900);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();

        void expectSameField(String reason) {
          final editable = tester.widget<EditableText>(editableFinder);
          expect(editable.focusNode.hasFocus, isTrue, reason: reason);
          expect(
            tester.state(editableFinder),
            same(initialEditable),
            reason: reason,
          );
          // A dropped or resized back slot would move the field under the IME.
          expect(tester.getRect(field), place, reason: reason);
          expect(tester.takeException(), isNull);
        }

        expect(railBack, findsNothing);
        expect(topBack, findsOneWidget);
        expectSameField('keyboard opened');

        // And the IME composes, commits and deletes across busy frames.
        Future<void> compose(Iterable<TextEditingValue> edits) async {
          for (final edit in edits) {
            final saves =
                tester.widget<EditableText>(editableFinder).controller.text !=
                edit.text;
            if (saves) {
              store.writeStarted = Completer<void>();
              store.writeReleased = Completer<void>();
            }
            tester.testTextInput.updateEditingValue(edit);
            if (saves) {
              await store.writeStarted!.future.timeout(
                const Duration(seconds: 5),
              );
            }
            await tester.pump();
            // Then the same editing session keeps focus, value and place.
            expectSameField('busy $edit');
            expect(
              tester.widget<EditableText>(editableFinder).controller.value,
              edit,
            );
            store.writeReleased?.complete();
            await tester.pump();
            expectSameField('saved $edit');
            expect(
              tester.widget<EditableText>(editableFinder).controller.value,
              edit,
            );
            store.writeStarted = null;
            store.writeReleased = null;
          }
        }

        await compose(koreanEdits);

        // When the keyboard closes, the rail returns beside the focused field.
        tester.view.resetViewInsets();
        await tester.pump();
        expect(railBack, findsOneWidget);
        expect(topBack, findsNothing);
        expectSameField('keyboard closed');
        // Then hardware-keyboard composition still keeps the same session.
        await compose(koreanEdits.take(4));
        expect(c.state.name, '코코');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
