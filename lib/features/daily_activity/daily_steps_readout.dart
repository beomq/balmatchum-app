import 'package:flutter/material.dart';

import '../records/product_page.dart' show formatCount;
import '../watch_sync/watch_bridge.dart';
import 'daily_steps_controller.dart';

/// The observation is separate from the server's reward confirmation.
/// Reads run on their own; only a failed read offers a retry (guide 3.1).
class DailyStepsReadout extends StatelessWidget {
  const DailyStepsReadout({required this.controller, this.onRetry, super.key});

  final DailyStepsController? controller;

  /// The screen's refresh after a failed read; a device read when null.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final steps = controller;
    final count = steps?.count;
    final status = steps?.result?.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${count == null ? '—' : formatCount(count)}걸음',
          key: const ValueKey('daily_steps_count'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          steps?.isLoading ?? false
              ? '조회 중'
              : switch (status) {
                  DailyStepsStatus.available => '${steps!.date} · 한국 기준',
                  DailyStepsStatus.capabilityUnavailable =>
                    '이 기기에서는 걸음 조회를 지원하지 않아요.',
                  DailyStepsStatus.unavailable => '걸음 자료를 확인할 수 없어요.',
                  DailyStepsStatus.providerUpdateRequired =>
                    'Health Connect를 설치하거나 업데이트한 뒤 다시 조회해 주세요.',
                  DailyStepsStatus.permissionDenied =>
                    '걸음 읽기 권한이 없어요. Health Connect에서 권한을 허용해 주세요.',
                  DailyStepsStatus.empty => '아직 확인할 걸음 자료가 없어요.',
                  DailyStepsStatus.error => '걸음을 불러오지 못했어요. 다시 시도해 주세요.',
                  null => '걸음 정보를 아직 조회하지 않았어요.',
                },
        ),
        if (steps != null && !steps.isLoading && _retryable(status))
          TextButton(
            key: const ValueKey('daily_steps_retry'),
            onPressed: onRetry ?? steps.refresh,
            child: const Text('다시 불러오기'),
          ),
      ],
    );
  }
}

/// Failed reads a retry can fix. Unsupported devices and empty days are
/// final answers, not failures.
bool _retryable(DailyStepsStatus? status) => switch (status) {
  DailyStepsStatus.error ||
  DailyStepsStatus.unavailable ||
  DailyStepsStatus.permissionDenied ||
  DailyStepsStatus.providerUpdateRequired => true,
  _ => false,
};
