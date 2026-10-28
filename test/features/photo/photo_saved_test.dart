import 'package:balmatchum_app/features/photo/photo_editor.dart'
    show DogSticker, PhotoPhase;
import 'package:balmatchum_app/features/photo/photo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import 'photo_edit_test.dart' show editing;
import 'photo_editor_test.dart' show FakePhotoAdapter;
import 'photo_screen_test.dart' show idle;

/// Taps [key] and waits for the editor's platform work.
Future<void> press(
  WidgetTester tester,
  PhotoScreenState state,
  String key,
) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.runAsync(() => tester.tap(find.byKey(ValueKey(key))));
  await tester.runAsync(() => idle(state));
  await tester.pumpAndSettle();
}

VoidCallback? action(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed;

void main() {
  testWidgets('a real save opens the saved view: no selection, one share', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final adapter = FakePhotoAdapter();
    final state = await editing(tester, adapter);
    await press(tester, state, 'photo_save');
    expect(state.editor.phase, PhotoPhase.saved);
    expect(find.byType(PhotoSelectionOverlay), findsNothing);
    expect(find.byKey(const ValueKey('photo_hint')), findsNothing);
    // The top save is a non-pressable state now.
    expect(action(tester, 'photo_save'), isNull);
    // The success is announced as it appears.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('photo_saved_notice'))),
      isSemantics(isLiveRegion: true),
    );
    expect(find.byKey(const ValueKey('photo_flip')), findsNothing);
    expect(find.byKey(const ValueKey('photo_reset')), findsNothing);
    expect(
      tester.widget(find.byKey(const ValueKey('photo_share'))),
      isA<FilledButton>(),
    );
    // Nothing edits the saved picture, by hand or by assistive actions.
    final canvas = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('photo_canvas')),
    );
    expect(canvas.onScaleUpdate, isNull);
    final node = tester.getSemantics(
      find.byKey(const ValueKey('photo_canvas')),
    );
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.customAction),
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('a failed save, typed or not, never reads as saved', (
    tester,
  ) async {
    final adapter = FakePhotoAdapter();
    final state = await editing(tester, adapter);
    for (final failure in [const PhotoFailure('no space'), StateError('x')]) {
      adapter.failure = failure;
      await press(tester, state, 'photo_save');
      expect(state.editor.phase, PhotoPhase.edit, reason: '$failure');
      expect(find.byKey(const ValueKey('photo_saved_notice')), findsNothing);
      expect(find.byKey(const ValueKey('photo_share')), findsNothing);
      expect(action(tester, 'photo_save'), isNotNull);
      expect(find.byType(PhotoSelectionOverlay), findsOneWidget);
    }
  });

  testWidgets('back to editing keeps the edit; a change makes it unsaved', (
    tester,
  ) async {
    final adapter = FakePhotoAdapter();
    final state = await editing(tester, adapter);
    state.editor.edit(const DogSticker(x: .3, scale: 1.3, rotation: .4));
    await tester.pump();
    await press(tester, state, 'photo_save');
    final photo = state.editor.photo;
    final sticker = state.editor.sticker;
    await tester.tap(find.byKey(const ValueKey('photo_reedit')));
    await tester.pumpAndSettle();
    expect(state.editor.phase, PhotoPhase.edit);
    expect(state.editor.photo, same(photo));
    expect(state.editor.sticker, same(sticker));
    expect(find.byType(PhotoSelectionOverlay), findsOneWidget);
    // Unchanged, it is still the saved picture and cannot be saved again.
    expect(action(tester, 'photo_save'), isNull);
    expect(find.byKey(const ValueKey('photo_share')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('photo_flip')));
    await tester.pump();
    expect(state.editor.saved, isFalse);
    expect(action(tester, 'photo_save'), isNotNull);
    // A reset counts as a change too.
    await press(tester, state, 'photo_save');
    await tester.tap(find.byKey(const ValueKey('photo_reedit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo_reset')));
    await tester.pump();
    expect(state.editor.saved, isFalse);
  });

  testWidgets('the share sends the saved PNG from the button, and stays', (
    tester,
  ) async {
    final adapter = ShareRecorder();
    final state = await editing(tester, adapter);
    await press(tester, state, 'photo_save');
    final saved = adapter.saved!;
    for (final result in [
      PhotoShareResult.cancelled,
      PhotoShareResult.unavailable,
      PhotoShareResult.selected,
    ]) {
      adapter.shareResult = result;
      await press(tester, state, 'photo_share');
      expect(adapter.shared, orderedEquals(saved));
      // Not a failure and not a sent confirmation: the saved view stays.
      expect(state.editor.isError, isFalse, reason: '$result');
      expect(state.editor.phase, PhotoPhase.saved, reason: '$result');
      expect(state.editor.savedPng, orderedEquals(saved));
    }
    final button = tester.getRect(find.byKey(const ValueKey('photo_share')));
    expect(adapter.origin, button);
    // A failing share keeps the saved picture as well.
    adapter.failure = const PhotoFailure('share broke');
    await press(tester, state, 'photo_share');
    expect(state.editor.isError, isTrue);
    expect(state.editor.phase, PhotoPhase.saved);
  });

  testWidgets('a new photo starts over unsaved', (tester) async {
    final adapter = FakePhotoAdapter();
    final state = await editing(tester, adapter);
    await press(tester, state, 'photo_save');
    adapter.next = adapter.saved;
    await tester.runAsync(() => state.editor.pick(PhotoSource.gallery));
    await tester.pumpAndSettle();
    expect(state.editor.phase, PhotoPhase.edit);
    expect(state.editor.saved, isFalse);
    expect(action(tester, 'photo_save'), isNotNull);
  });

  testWidgets('on the Duo the saved view keeps the rail and its share', (
    tester,
  ) async {
    useDuoViewport(tester, 'outer portrait');
    final adapter = FakePhotoAdapter();
    final state = await editing(tester, adapter, wrap: duoHost);
    await press(tester, state, 'photo_save');
    expect(find.byKey(const ValueKey('duo_rail_back')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('photo_share')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

/// Remembers where the share sheet was anchored.
class ShareRecorder extends FakePhotoAdapter {
  Rect? origin;

  @override
  Future<PhotoShareResult> share(Uint8List png, Rect origin) {
    this.origin = origin;
    return super.share(png, origin);
  }
}
