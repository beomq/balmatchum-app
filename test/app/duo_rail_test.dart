import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/features/records/product_page.dart'
    show PixelIcon;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DuoRailItem item(String k, String label, List<String> taps) => DuoRailItem(
  key: ValueKey(k),
  label: label,
  icon: const Icon(Icons.circle),
  onPressed: () => taps.add(k),
);

void main() {
  final taps = <String>[];
  final home = DuoRailSpec(
    tools: [item('settings', '설정', taps)],
    destinations: [
      item('records', '기록', taps),
      item('quiz', '퀴즈', taps),
      item('wardrobe', '꾸미기', taps),
      item('photo', '사진', taps),
    ],
  );
  final sub = DuoRailSpec(
    tools: [item('back', '뒤로', taps), item('home', '홈', taps)],
  );
  const outer = MediaQueryData(
    size: Size(466, 678),
    padding: EdgeInsets.only(right: 84, bottom: 34),
  );

  test('the sub screen rail draws the pixel back and home', () {
    final [back, home] = duoBackHome(onBack: () {}, onHome: () {});
    expect(
      ((back.icon as Image).image as AssetImage).assetName,
      endsWith('/back.png'),
    );
    expect((home.icon as PixelIcon).name, 'home');
  });

  test('side detection needs one-sided inset', () {
    expect(duoRailSide(const EdgeInsets.only(right: 84)), DuoRailSide.right);
    expect(duoRailSide(const EdgeInsets.only(left: 84)), DuoRailSide.left);
    expect(duoRailSide(const EdgeInsets.only(left: 59, right: 59)), isNull);
    expect(duoRailSide(EdgeInsets.zero), isNull);
  });

  test('group heights and modes', () {
    expect(home.height(DuoRailMode.full), 352);
    expect(home.height(DuoRailMode.compact), 284);
    expect(sub.height(DuoRailMode.full), 100);
    expect(duoRailMode(outer, home), DuoRailMode.full);
    expect(duoRailMode(outer, sub), DuoRailMode.full);
    expect(
      duoRailMode(outer.copyWith(textScaler: const TextScaler.linear(2)), home),
      DuoRailMode.compact,
    );
    expect(
      duoRailMode(
        outer.copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
        home,
      ),
      isNull,
    );
    expect(
      duoRailMode(
        const MediaQueryData(
          size: Size(678, 466),
          padding: EdgeInsets.only(right: 84, bottom: 21),
        ),
        home,
      ),
      isNull,
    );
  });

  for (final (name, padding, axis) in [
    ('right column', const FakeViewPadding(right: 252, bottom: 102), 418.0),
    ('left column', const FakeViewPadding(left: 252, bottom: 102), 48.0),
  ]) {
    testWidgets('outer portrait placement: $name', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(466, 678) * 3;
      tester.view.padding = padding;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final mode = duoRailMode(MediaQuery.of(context), home)!;
              return Scaffold(
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    const SafeArea(child: SizedBox.expand()),
                    DuoRail(spec: home, mode: mode),
                  ],
                ),
              );
            },
          ),
        ),
      );
      for (final k in ['settings', 'records', 'quiz', 'wardrobe', 'photo']) {
        expect(
          tester.getRect(find.byKey(ValueKey(k))).center.dx,
          closeTo(axis, 1),
          reason: k,
        );
      }
      expect(
        tester.getRect(find.byKey(const ValueKey('photo'))).bottom,
        closeTo(642, 1),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('settings'))).top,
        closeTo(290, 1),
      );
      taps.clear();
      await tester.tap(find.byKey(const ValueKey('quiz')));
      expect(taps, ['quiz']);
      expect(tester.takeException(), isNull);
    });
  }
}
