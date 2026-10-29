import 'dart:async';

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/photo/photo_screen.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_app/features/wardrobe/dog_sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import 'photo_editor_test.dart' show FakePhotoAdapter, photoFixture;
import 'photo_screen_test.dart' show PendingPhotoAdapter, idle;

const pug = 'assets/first_meeting/dogs/pug.png';

Future<PhotoScreenState> open(
  WidgetTester tester,
  FakePhotoAdapter adapter, {
  String name = '콩이',
  Widget Function(Widget)? wrap,
}) async {
  final screen = PhotoScreen(
    dogAssetPath: pug,
    dogName: name,
    adapter: adapter,
    onBack: () {},
    onHome: () {},
  );
  await tester.runAsync(
    () => tester.pumpWidget(
      wrap?.call(screen) ?? MaterialApp(theme: meetingTheme(), home: screen),
    ),
  );
  final state = tester.state<PhotoScreenState>(find.byType(PhotoScreen));
  await tester.runAsync(() => idle(state));
  await tester.pumpAndSettle();
  return state;
}

Future<void> tapAndWait(
  WidgetTester tester,
  PhotoScreenState state,
  String key,
) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.runAsync(() => tester.tap(find.byKey(ValueKey(key))));
  await tester.runAsync(() => idle(state));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('before a photo: the example and one pick, nothing to save', (
    tester,
  ) async {
    await open(tester, FakePhotoAdapter());
    expect(find.byKey(const ValueKey('photo_example')), findsOneWidget);
    // The user's own companion, not a fixed example dog.
    expect(
      tester
          .widget<DogSprite>(
            find.descendant(
              of: find.byKey(const ValueKey('photo_example')),
              matching: find.byType(DogSprite),
            ),
          )
          .asset,
      pug,
    );
    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('photo_gallery'))),
      isA<FilledButton>(),
    );
    expect(
      tester.widget(find.byKey(const ValueKey('photo_camera'))),
      isA<TextButton>(),
    );
    for (final key in [
      'photo_save',
      'photo_share',
      'photo_flip',
      'photo_reset',
      'photo_canvas',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(find.byType(Slider), findsNothing);
    // The title and the copy carry the user's companion name.
    expect(
      tester.widget<ProductTitle>(find.byType(ProductTitle)).title,
      startsWith('콩이'),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('photo_start_title')))
          .semanticsLabel,
      contains('콩이'),
    );
    expect(find.textContaining('코코'), findsNothing);
  });

  testWidgets('a cancelled pick stays; a picked photo opens the editor', (
    tester,
  ) async {
    final adapter = FakePhotoAdapter();
    final state = await open(tester, adapter);
    await tapAndWait(tester, state, 'photo_gallery');
    expect(adapter.source, PhotoSource.gallery);
    expect(state.editor.photo, isNull);
    expect(find.byKey(const ValueKey('photo_example')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_pick_error')), findsNothing);
    adapter.next = await tester.runAsync(photoFixture);
    await tapAndWait(tester, state, 'photo_camera');
    expect(adapter.source, PhotoSource.camera);
    expect(state.editor.photo, isNotNull);
    expect(find.byKey(const ValueKey('photo_example')), findsNothing);
    expect(find.byKey(const ValueKey('photo_canvas')), findsOneWidget);
  });

  testWidgets('a denied permission stays here with guidance and a retry', (
    tester,
  ) async {
    final adapter = FakePhotoAdapter()
      ..failure = const PhotoFailure('denied by the OS');
    final state = await open(tester, adapter);
    await tapAndWait(tester, state, 'photo_camera');
    expect(find.byKey(const ValueKey('photo_pick_error')), findsOneWidget);
    // The adapter's own message, word for word.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('photo_status'))).data,
      'denied by the OS',
    );
    expect(find.byKey(const ValueKey('photo_example')), findsOneWidget);
    adapter
      ..failure = null
      ..next = await tester.runAsync(photoFixture);
    await tapAndWait(tester, state, 'photo_pick_retry');
    // The retry asks the same source again.
    expect(adapter.source, PhotoSource.camera);
    expect(find.byKey(const ValueKey('photo_canvas')), findsOneWidget);
  });

  testWidgets('a photo that cannot be read keeps the start and says so', (
    tester,
  ) async {
    final adapter = FakePhotoAdapter()..next = Uint8List.fromList([1, 2, 3]);
    final state = await open(tester, adapter);
    await tapAndWait(tester, state, 'photo_gallery');
    expect(state.editor.photo, isNull);
    expect(find.byKey(const ValueKey('photo_pick_error')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_pick_retry')), findsOneWidget);
  });

  testWidgets('a pick in flight locks both picks and the way out', (
    tester,
  ) async {
    final adapter = PendingPhotoAdapter();
    final state = await open(tester, adapter);
    adapter.pendingPick = Completer<Uint8List?>();
    final picking = state.editor.pick(PhotoSource.gallery);
    await tester.pump();
    for (final key in ['photo_gallery', 'photo_camera']) {
      expect(
        tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
        reason: key,
      );
    }
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('photo_back')))
          .onPressed,
      isNull,
    );
    adapter.pendingPick!.complete(null);
    await picking;
    await tester.pump();
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.byKey(const ValueKey('photo_gallery')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('the Duo rail takes back and home; the start keeps its title', (
    tester,
  ) async {
    useDuoViewport(tester, 'outer portrait');
    await open(tester, FakePhotoAdapter(), wrap: duoHost);
    expect(find.byKey(const ValueKey('photo_back')), findsNothing);
    expect(find.byKey(const ValueKey('photo_home')), findsNothing);
    expect(find.byType(ProductTitle), findsOneWidget);
    final pick = find.byKey(const ValueKey('photo_gallery'));
    await tester.ensureVisible(pick);
    expect(pick.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(1024, 768)]) {
    testWidgets('the start fits $size at 1.15x', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await open(
        tester,
        FakePhotoAdapter(),
        wrap: (screen) => MaterialApp(
          theme: meetingTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.15)),
            child: child!,
          ),
          home: screen,
        ),
      );
      final pick = find.byKey(const ValueKey('photo_gallery'));
      await tester.ensureVisible(pick);
      expect(pick.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
