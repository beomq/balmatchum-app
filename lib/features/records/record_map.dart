import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import 'product_page.dart';
import 'records_models.dart';

const naverMapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

enum RecordMapStatus { unconfigured, initializing, ready, unavailable }

/// App-owned SDK state, including authentication failures arriving after init.
/// No location source, tracking or permission request is installed here.
class RecordMapRuntime extends ValueNotifier<RecordMapStatus> {
  RecordMapRuntime() : super(RecordMapStatus.unconfigured);

  Future<void> initialize({
    required String clientId,
    Future<void> Function(String, VoidCallback)? initializeSdk,
  }) async {
    if (clientId.trim().isEmpty) return;
    value = RecordMapStatus.initializing;
    try {
      await (initializeSdk ??
              (id, failed) => FlutterNaverMap().init(
                clientId: id,
                onAuthFailed: (_) => failed(),
              ))(clientId.trim(), () => value = RecordMapStatus.unavailable)
          .timeout(const Duration(seconds: 15));
      if (value == RecordMapStatus.initializing) value = RecordMapStatus.ready;
    } on Exception {
      value = RecordMapStatus.unavailable;
    }
  }
}

final recordMapRuntime = RecordMapRuntime();

/// One overlay per stored segment. Empty segments never create coordinates;
/// single-point segments are markers, not fabricated lines.
class RecordedRouteGeometry {
  RecordedRouteGeometry(List<RouteSegment> routes)
    : segments = [
        for (final route in routes)
          if (route.points.isNotEmpty)
            [for (final p in route.points) NLatLng(p.latitude, p.longitude)],
      ];

  final List<List<NLatLng>> segments;
  List<NLatLng> get points => [for (final segment in segments) ...segment];
  NLatLngBounds? get bounds =>
      segments.isEmpty ? null : NLatLngBounds.from(points);

  Set<NAddableOverlay> overlays() => {
    for (final (index, segment) in segments.indexed)
      if (segment.length == 1)
        NMarker(id: 'record-point-$index', position: segment.single)
      else
        NPolylineOverlay(
          id: 'record-segment-$index',
          coords: segment,
          color: ProductColors.record,
          width: 4,
          lineCap: NLineCap.round,
          lineJoin: NLineJoin.round,
        ),
  };

  NCameraUpdate camera() {
    final b = bounds!;
    final update = b.southWest == b.northEast
        ? NCameraUpdate.scrollAndZoomTo(target: b.southWest, zoom: 16)
        : NCameraUpdate.fitBounds(b, padding: const EdgeInsets.all(Space.s6));
    update.setAnimation(animation: NCameraAnimation.none);
    return update;
  }
}

typedef RecordedMapBuilder = Widget Function(
  RecordedRouteGeometry geometry,
  Future<void> Function(NaverMapController) onReady,
  VoidCallback onLoaded,
);

/// The parent removes this widget immediately when a day is deleted/reloaded.
/// A keyed map is recreated for a different route snapshot, so stale native
/// completion never adds overlays or moves a newer record's camera.
class RecordedRouteMap extends StatefulWidget {
  const RecordedRouteMap({
    required this.routes,
    required this.outline,
    this.runtime,
    this.mapBuilder,
    super.key,
  });

  final List<RouteSegment> routes;
  final Widget outline;
  final ValueListenable<RecordMapStatus>? runtime;
  final RecordedMapBuilder? mapBuilder;

  @override
  State<RecordedRouteMap> createState() => _RecordedRouteMapState();
}

class _RecordedRouteMapState extends State<RecordedRouteMap> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RecordMapStatus>(
    valueListenable: widget.runtime ?? recordMapRuntime,
    builder: (context, status, _) {
      if (RecordedRouteGeometry(widget.routes).segments.isEmpty) {
        return const SizedBox.shrink();
      }
      return status == RecordMapStatus.ready
          ? _NativeRecordedMap(
              key: ObjectKey(widget.routes),
              geometry: RecordedRouteGeometry(widget.routes),
              mapBuilder: widget.mapBuilder,
              outline: widget.outline,
            )
          : _MapOutline(status: status, outline: widget.outline);
    },
  );
}

class _MapOutline extends StatelessWidget {
  const _MapOutline({required this.status, required this.outline});
  final RecordMapStatus status;
  final Widget outline;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(switch (status) {
        RecordMapStatus.unconfigured => '네이버 지도 설정이 없어 지도를 표시할 수 없어요.',
        RecordMapStatus.initializing => '네이버 지도를 준비하고 있어요.',
        _ => '지도를 불러오지 못했어요. 네트워크 또는 지도 설정을 확인해 주세요.',
      }, key: ValueKey('records_map_${status.name}')),
      const SizedBox(height: Space.s2),
      const Text('저장된 좌표 윤곽 · 지도 아님'),
      const SizedBox(height: Space.s2),
      outline,
    ],
  );
}

class _NativeRecordedMap extends StatefulWidget {
  const _NativeRecordedMap({
    required this.geometry,
    required this.outline,
    this.mapBuilder,
    super.key,
  });
  final RecordedRouteGeometry geometry;
  final Widget outline;
  final RecordedMapBuilder? mapBuilder;

  @override
  State<_NativeRecordedMap> createState() => _NativeRecordedMapState();
}

class _NativeRecordedMapState extends State<_NativeRecordedMap> {
  Timer? _deadline;
  bool _failed = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // SDK has no general tile/network error event. Do not claim tiles loaded
    // until onMapLoaded; bound the initial wait and retain the honest outline.
    _deadline = Timer(const Duration(seconds: 15), _fail);
  }

  void _fail() {
    if (!mounted || _failed) return;
    _deadline?.cancel();
    setState(() => _failed = true);
  }

  Future<void> _ready(NaverMapController controller) async {
    if (!mounted || _failed) return;
    try {
      await controller.addOverlayAll(widget.geometry.overlays());
      if (!mounted || _failed) return;
      await controller.updateCamera(widget.geometry.camera());
    } on Exception {
      _fail();
    }
  }

  void _onLoaded() {
    if (!mounted || _failed) return;
    _deadline?.cancel();
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _deadline?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _MapOutline(
        status: RecordMapStatus.unavailable,
        outline: widget.outline,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_loaded)
          const Padding(
            padding: EdgeInsets.only(bottom: Space.s2),
            child: Text('지도 배경을 불러오는 중이에요. 오프라인에서는 표시되지 않을 수 있어요.'),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child:
                widget.mapBuilder?.call(widget.geometry, _ready, _onLoaded) ??
                NaverMap(
                  key: const ValueKey('records_naver_map'),
                  options: NaverMapViewOptions(
                    initialCameraPosition: NCameraPosition(
                      target: widget.geometry.points.first,
                      zoom: 16,
                    ),
                    locationButtonEnable: false,
                    consumeSymbolTapEvents: true,
                  ),
                  onMapReady: (controller) => unawaited(_ready(controller)),
                  onMapLoaded: _onLoaded,
                ),
          ),
        ),
      ],
    );
  }
}
