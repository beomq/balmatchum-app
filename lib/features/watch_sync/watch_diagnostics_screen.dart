import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../location_experiment/location_experiment_screen.dart';
import 'watch_bridge.dart';

class WatchDiagnosticsScreen extends ConsumerStatefulWidget {
  const WatchDiagnosticsScreen({super.key});

  @override
  ConsumerState<WatchDiagnosticsScreen> createState() =>
      _WatchDiagnosticsState();
}

class _WatchDiagnosticsState extends ConsumerState<WatchDiagnosticsScreen> {
  bool busy = false;
  String message = '실기기 전송 NOT RUN';

  Future<void> run(Future<String> Function() operation) async {
    setState(() => busy = true);
    try {
      final result = await operation();
      if (mounted) setState(() => message = result);
    } on Exception {
      if (mounted) setState(() => message = '요청 실패: 인증 또는 기기 설정을 확인하세요.');
    } on StateError {
      if (mounted) setState(() => message = '인증된 계정이 없어 동기화하지 않았습니다.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!phoneLocationExperimentEnabled) return const SizedBox.shrink();
    final service = ref.watch(watchSyncServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('개발 Watch 진단')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'DEBUG / dev 전용 · 실제 계정만 사용합니다.\nSimulator transferFile 미지원',
          ),
          if (service == null) const Text('iPhone 및 SERVER_URL 설정이 필요합니다.'),
          FilledButton(
            onPressed: busy || service == null
                ? null
                : () => run(() async {
                    await service.resumeAndSync();
                    return '인증 확인 및 현재 계정 inbox 동기화 완료';
                  }),
            child: const Text('인증 확인 후 동기화'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    final result = service == null
                        ? await WatchBridge().requestDailySteps()
                        : await service.requestDailySteps();
                    return 'HealthKit: ${result.status.name}';
                  }),
            child: const Text('오늘 걸음 권한 요청 및 읽기'),
          ),
          Text(message),
        ],
      ),
    );
  }
}
