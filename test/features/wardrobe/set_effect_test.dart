import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/wardrobe/set_effect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EffectPresets presets() => EffectPresets(
  jsonDecode(File(EffectPresets.asset).readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  final all = presets();
  final names = (all.json['presets'] as Map<String, dynamic>).keys.toList();

  test('every preset closes its loop and lights something', () {
    expect(names, containsAll(['snow', 'holiday', 'seollal']));
    for (final name in names) {
      final engine = all.engine(name)!;
      expect(engine.frame(engine.n), engine.frame(0), reason: name);
      var lit = 0;
      for (var t = 0; t < engine.n; t += 6) {
        lit += engine.frame(t).length;
      }
      expect(lit, greaterThan(0), reason: name);
    }
  });

  test('reduced motion leaves out the fireworks only', () {
    final holiday = all.engine('holiday')!;
    final withBursts = [
      for (var t = 0; t < holiday.n; t++) holiday.frame(t).length,
    ];
    final still = [
      for (var t = 0; t < holiday.n; t++)
        holiday.frame(t, bursts: false).length,
    ];
    final snow = all.engine('snow')!;

    expect(
      withBursts.reduce((a, b) => a + b),
      greaterThan(still.reduce((a, b) => a + b)),
    );
    expect(still.every((n) => n > 0), isTrue);
    expect(snow.frame(5, bursts: false), snow.frame(5));
  });

  testWidgets('the effect ticks, and stands still under reduced motion', (
    tester,
  ) async {
    Widget host({required bool still}) => MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 390,
          height: 260,
          child: SetEffect(preset: 'snow'),
        ),
      ),
    );

    await tester.runAsync(() => EffectPresets.load());
    await tester.pumpWidget(host(still: false));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byKey(const ValueKey('set_effect_snow')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(host(still: true));
    await tester.pump();
    expect(find.byKey(const ValueKey('set_effect_snow')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(
      TickerMode(enabled: false, child: host(still: false)),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
