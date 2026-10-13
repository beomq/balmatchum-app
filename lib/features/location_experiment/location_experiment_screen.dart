import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'location_experiment.dart';
import 'platform_experiment_adapter.dart';

bool get phoneLocationExperimentEnabled => kDebugMode && appFlavor == 'dev';

/// Parent may register this entry only on its diagnostic route. The widget
/// independently enforces the build/flavor gate before allocating any plugin.
class PhoneLocationExperimentScreen extends StatefulWidget {
  const PhoneLocationExperimentScreen({super.key});
  @override
  State<PhoneLocationExperimentScreen> createState() => _ScreenState();
}

class _ScreenState extends State<PhoneLocationExperimentScreen>
    with WidgetsBindingObserver {
  LocationExperiment? experiment;
  String? failure;
  bool busy = false;
  final interval = TextEditingController();
  final distance = TextEditingController();
  final scenario = TextEditingController();
  final device = TextEditingController();
  final appBuild = TextEditingController();
  String source = 'simulator';
  String accuracy = 'high';
  bool background = false, pause = false, offline = false;

  @override
  void initState() {
    super.initState();
    if (phoneLocationExperimentEnabled) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    try {
      final store = await FileExperimentStore.create();
      if (!mounted) return;
      final value = LocationExperiment(
        clock: StopwatchExperimentClock(),
        sensor: PluginExperimentSensor(),
        store: store,
      );
      await value.initialize();
      if (!mounted) {
        value.dispose();
        return;
      }
      experiment = value;
      value.addListener(_changed);
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await action();
    } catch (e) {
      failure = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      experiment
          ?.annotate('lifecycle', {'state': state.name})
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final value = experiment;
    value?.removeListener(_changed);
    if (value != null) {
      unawaited(
        value
            .stop('diagnosticClosed')
            .whenComplete(value.dispose)
            .catchError((Object _) {}),
      );
    }
    interval.dispose();
    distance.dispose();
    scenario.dispose();
    device.dispose();
    appBuild.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!phoneLocationExperimentEnabled) return const SizedBox.shrink();
    final value = experiment;
    final active = value?.running ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('개발 위치 실험')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'DEBUG / dev 전용 · 실측 NOT RUN\n좌표는 로컬에만 저장됩니다. 제품 산책 기능이 아닙니다.',
            ),
            if (value == null && failure == null) const Text('로컬 기록을 읽는 중입니다.'),
            if (failure ?? value?.error case final String message)
              SelectableText('실험 오류: $message'),
            DropdownButtonFormField<String>(
              initialValue: source,
              decoration: const InputDecoration(labelText: '실행 기기 유형 (실험자 확인)'),
              items: const [
                DropdownMenuItem(value: 'simulator', child: Text('시뮬레이터')),
                DropdownMenuItem(value: 'physical', child: Text('실제 기기')),
              ],
              onChanged: active || busy
                  ? null
                  : (v) => setState(() => source = v!),
            ),
            TextField(
              controller: device,
              enabled: !active && !busy,
              decoration: const InputDecoration(
                labelText: '기기 모델 (예: iPhone 15 Pro)',
              ),
            ),
            TextField(
              controller: appBuild,
              enabled: !active && !busy,
              decoration: const InputDecoration(labelText: '시험 앱 빌드 번호 또는 커밋'),
            ),
            TextField(
              controller: scenario,
              enabled: !active && !busy,
              decoration: const InputDecoration(labelText: '조건 (정지/이동/실내 등)'),
            ),
            TextField(
              controller: interval,
              enabled: !active && !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '요청 간격 / gap 기준 (초, 양수)',
              ),
            ),
            TextField(
              controller: distance,
              enabled: !active && !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '거리 필터 (미터, 0 이상)'),
            ),
            DropdownButtonFormField<String>(
              initialValue: accuracy,
              decoration: const InputDecoration(labelText: '요청 정확도'),
              items: [
                'low',
                'medium',
                'high',
                'best',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: active || busy
                  ? null
                  : (v) => setState(() => accuracy = v!),
            ),
            SwitchListTile(
              title: const Text('백그라운드 업데이트 요청'),
              value: background,
              onChanged: active || busy
                  ? null
                  : (v) => setState(() => background = v),
            ),
            SwitchListTile(
              title: const Text('iOS 자동 일시 정지 허용'),
              value: pause,
              onChanged: active || busy
                  ? null
                  : (v) => setState(() => pause = v),
            ),
            const Text(
              '간격은 Android 요청값입니다. iOS는 고정 간격을 보장하지 않습니다.\n백그라운드는 부모의 네이티브 권한 설정 후 검증해야 합니다.',
            ),
            SwitchListTile(
              title: const Text('오프라인 조건 (실험자 관찰)'),
              value: offline,
              onChanged: busy
                  ? null
                  : (v) {
                      setState(() => offline = v);
                      unawaited(
                        _action(
                          () async => value?.annotate('offline', {
                            'value': v,
                            'source':
                                'operator annotation; not connectivity probe',
                          }),
                        ),
                      );
                    },
            ),
            FilledButton(
              onPressed: value == null || busy
                  ? null
                  : () => _action(() async {
                      if (active) {
                        await value.stop('operatorStopped');
                        return;
                      }
                      if (device.text.trim().isEmpty ||
                          appBuild.text.trim().isEmpty) {
                        throw const FormatException('기기 모델과 앱 빌드를 입력해 주세요.');
                      }
                      value.provenance.addAll({
                        'source': source,
                        'device': device.text.trim(),
                        'appBuild': appBuild.text.trim(),
                        'os': Platform.operatingSystem,
                        'osVersion': Platform.operatingSystemVersion,
                        'verification':
                            'device/source/build are operator supplied',
                      });
                      await value.start(
                        ExperimentInput(
                          intervalSeconds: int.parse(interval.text),
                          distanceMeters: int.parse(distance.text),
                          accuracy: accuracy,
                          background: background,
                          pauseAutomatically: pause,
                          scenario: scenario.text,
                        ),
                      );
                      await value.annotate('offline', {
                        'value': offline,
                        'source': 'operator annotation',
                      });
                    }),
              child: Text(
                busy
                    ? '기록 처리 중'
                    : active
                    ? '진단 실험 종료'
                    : '진단 실험 시작',
              ),
            ),
            TextButton(
              onPressed: value == null || busy
                  ? null
                  : () => _action(() async {
                      await value.annotate('checkpoint', {
                        'source': 'operator',
                      });
                    }),
              child: const Text('관찰 시점 기록'),
            ),
            if (value != null)
              ...value.runs.reversed.map((run) {
                final record = run as Map<String, Object?>;
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SelectableText(
                    '${record['startedAt']} · ${record['status']}\n'
                    '${LocationExperiment.metrics(record)}\n'
                    '이벤트 ${(record['events'] as List).length} · 로컬 원본 보존',
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
