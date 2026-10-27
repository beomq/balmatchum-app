import 'dart:async';

import 'package:balmatchum_app/features/records/record_map.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_test/flutter_test.dart';

Widget mapHost({required Widget home}) => MaterialApp(
  home: SingleChildScrollView(
    child: Center(child: SizedBox(width: 390, child: home)),
  ),
);

RouteSegment route(String id, List<(double, double)> points) => RouteSegment(
  id: id,
  source: 'phone',
  points: [
    for (final (lat, lng) in points)
      RoutePointView(
        recordedAt: DateTime.utc(2026, 10, 19),
        latitude: lat,
        longitude: lng,
      ),
  ],
);

class MapController extends Fake implements NaverMapController {
  final added = <Set<NAddableOverlay>>[];
  final cameras = <NCameraUpdate>[];
  Completer<void>? pending;
  bool fail = false;

  @override
  Future<void> addOverlayAll(Set<NAddableOverlay> overlays) async {
    added.add(overlays);
    if (fail) throw Exception('native overlay error');
    await pending?.future;
  }

  @override
  Future<bool> updateCamera(NCameraUpdate update) async {
    cameras.add(update);
    return true;
  }
}

void main() {
  final routes = [
    route('a', [(37, 127), (37.1, 127.1)]),
    route('empty', []),
    route('b', [(38, 128), (38.1, 128.1)]),
    route('single', [(36, 126)]),
  ];

  test('stored segments map exactly without bridging gaps', () {
    final geometry = RecordedRouteGeometry(routes);
    final overlays = geometry.overlays();
    final lines = overlays.whereType<NPolylineOverlay>().toList();
    expect(lines, hasLength(2));
    expect(lines[0].coords, [
      const NLatLng(37, 127),
      const NLatLng(37.1, 127.1),
    ]);
    expect(lines[1].coords, [
      const NLatLng(38, 128),
      const NLatLng(38.1, 128.1),
    ]);
    expect(
      overlays.whereType<NMarker>().single.position,
      const NLatLng(36, 126),
    );
    expect(geometry.bounds!.southWest, const NLatLng(36, 126));
    expect(geometry.bounds!.northEast, const NLatLng(38.1, 128.1));
    final camera = geometry.camera().toNPayload().map;
    expect(camera['boundsPadding'], {
      'left': 24.0,
      'top': 24.0,
      'right': 24.0,
      'bottom': 24.0,
    });
    expect(camera['animation'], 'none');
  });

  test('empty geometry has no invented bounds or overlays', () {
    final geometry = RecordedRouteGeometry([route('empty', [])]);
    expect(geometry.overlays(), isEmpty);
    expect(geometry.bounds, isNull);
  });

  test('single point camera targets only its stored coordinate', () {
    final geometry = RecordedRouteGeometry([
      route('one', [(37, 127)]),
    ]);
    final camera = geometry.camera().toNPayload().map;
    expect(camera['target'], {'lat': 37.0, 'lng': 127.0});
    expect(camera['zoom'], 16);
  });

  test('missing key never initializes SDK', () async {
    final runtime = RecordMapRuntime();
    var calls = 0;
    await runtime.initialize(
      clientId: '  ',
      initializeSdk: (_, _) async => calls++,
    );
    expect(calls, 0);
    expect(runtime.value, RecordMapStatus.unconfigured);
  });

  test('init success and delayed auth failure are separate states', () async {
    final runtime = RecordMapRuntime();
    late VoidCallback failed;
    await runtime.initialize(
      clientId: 'configured-test',
      initializeSdk: (_, callback) async => failed = callback,
    );
    expect(runtime.value, RecordMapStatus.ready);
    failed();
    expect(runtime.value, RecordMapStatus.unavailable);
  });

  test(
    'initialization exceptions and synchronous auth failure stay failed',
    () async {
      final runtime = RecordMapRuntime();
      await runtime.initialize(
        clientId: 'configured-test',
        initializeSdk: (_, _) async => throw Exception('offline'),
      );
      expect(runtime.value, RecordMapStatus.unavailable);
      await runtime.initialize(
        clientId: 'configured-test',
        initializeSdk: (_, callback) async => callback(),
      );
      expect(runtime.value, RecordMapStatus.unavailable);
    },
  );

  testWidgets(
    'unconfigured and auth failed surface never construct native map',
    (tester) async {
      final runtime = RecordMapRuntime();
      var maps = 0;
      await tester.pumpWidget(
        mapHost(
          home: RecordedRouteMap(
            routes: routes,
            runtime: runtime,
            outline: const SizedBox(key: ValueKey('outline')),
            mapBuilder: (_, _, _) {
              maps++;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(maps, 0);
      expect(find.byKey(const ValueKey('outline')), findsOneWidget);
      runtime.value = RecordMapStatus.unavailable;
      await tester.pump();
      expect(maps, 0);
      expect(
        find.byKey(const ValueKey('records_map_unavailable')),
        findsOneWidget,
      );
    },
  );

  testWidgets('empty map constructs no native view', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      mapHost(
        home: RecordedRouteMap(
          routes: [],
          runtime: ValueNotifier(RecordMapStatus.ready),
          outline: const SizedBox(),
          mapBuilder: (_, _, _) {
            calls++;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(calls, 0);
  });

  testWidgets(
    'ready callback adds overlays then fits camera; loaded ends wait',
    (tester) async {
      late Future<void> Function(NaverMapController) ready;
      late VoidCallback loaded;
      await tester.pumpWidget(
        mapHost(
          home: RecordedRouteMap(
            routes: routes,
            runtime: ValueNotifier(RecordMapStatus.ready),
            outline: const SizedBox(),
            mapBuilder: (_, r, l) {
              ready = r;
              loaded = l;
              return const SizedBox();
            },
          ),
        ),
      );
      final controller = MapController();
      await ready(controller);
      expect(controller.added.single, hasLength(3));
      expect(controller.cameras, hasLength(1));
      loaded();
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      expect(
        find.byKey(const ValueKey('records_map_unavailable')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'offline tile timeout and native overlay error preserve outline',
    (tester) async {
      late Future<void> Function(NaverMapController) ready;
      Widget host(Key key) => mapHost(
        home: RecordedRouteMap(
          key: key,
          routes: routes,
          runtime: ValueNotifier(RecordMapStatus.ready),
          outline: const SizedBox(key: ValueKey('outline')),
          mapBuilder: (_, r, _) {
            ready = r;
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(host(const ValueKey('timeout')));
      await tester.pump(const Duration(seconds: 15));
      expect(find.byKey(const ValueKey('outline')), findsOneWidget);
      await tester.pumpWidget(host(const ValueKey('error')));
      await ready(MapController()..fail = true);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('records_map_unavailable')),
        findsOneWidget,
      );
    },
  );

  testWidgets('deleted or replaced map ignores in-flight native completion', (
    tester,
  ) async {
    late Future<void> Function(NaverMapController) ready;
    late VoidCallback loaded;
    final runtime = ValueNotifier(RecordMapStatus.ready);
    Widget host(List<RouteSegment> value) => mapHost(
      home: RecordedRouteMap(
        routes: value,
        runtime: runtime,
        outline: const SizedBox(),
        mapBuilder: (_, r, l) {
          ready = r;
          loaded = l;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(host(routes));
    final oldReady = ready;
    final oldLoaded = loaded;
    final controller = MapController()..pending = Completer<void>();
    final pending = ready(controller);
    await tester.pumpWidget(
      host([
        route('replacement', [(35, 125)]),
      ]),
    );
    controller.pending!.complete();
    await pending;
    oldLoaded();
    await oldReady(controller);
    expect(controller.cameras, isEmpty);
    expect(controller.added, hasLength(1));
    final deletedReady = ready;
    final deletedLoaded = loaded;
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await deletedReady(controller);
    deletedLoaded();
    runtime.value = RecordMapStatus.unavailable;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.added, hasLength(1));
  });
}
