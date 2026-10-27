import 'package:flutter/material.dart';

import '../watch_sync/watch_bridge.dart';
import 'daily_steps_controller.dart';

/// The observation is separate from the server's reward confirmation.
class DailyStepsReadout extends StatelessWidget {
  const DailyStepsReadout({required this.controller, super.key});

  final DailyStepsController? controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${controller?.count ?? '—'} 걸음',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      Text(switch (controller?.result?.status) {
        DailyStepsStatus.available => '${controller!.date} · 한국 기준',
        DailyStepsStatus.capabilityUnavailable => '이 기기에서는 걸음 조회를 지원하지 않아요.',
        DailyStepsStatus.unavailable => '걸음 자료를 확인할 수 없어요.',
        DailyStepsStatus.providerUpdateRequired =>
          'Health Connect를 설치하거나 업데이트한 뒤 다시 조회해 주세요.',
        DailyStepsStatus.permissionDenied =>
          '걸음 읽기 권한이 없어요. Health Connect에서 권한을 허용해 주세요.',
        DailyStepsStatus.empty => '아직 확인할 걸음 자료가 없어요.',
        DailyStepsStatus.error => '걸음을 불러오지 못했어요. 다시 시도해 주세요.',
        null => '걸음 정보를 아직 조회하지 않았어요.',
      }),
      if (controller case final steps?)
        TextButton(
          onPressed: steps.isLoading ? null : steps.refresh,
          child: Text(steps.isLoading ? '조회 중' : '걸음 새로고침'),
        ),
    ],
  );
}
