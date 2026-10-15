import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../watch_sync/watch_bridge.dart';

/// A device observation is not a server reward confirmation.
class DailyStepsController extends ChangeNotifier {
  DailyStepsController({required this.readSteps});

  final Future<DailyStepsResult> Function() readSteps;
  DailyStepsResult? result;
  bool isLoading = false;
  bool _disposed = false;

  int? get count => result?.dailySteps?['count'] as int?;
  String? get date => result?.dailySteps?['date'] as String?;

  Future<void> refresh() async {
    if (isLoading || _disposed) return;
    isLoading = true;
    // Do not show yesterday's total or a previous successful read on failure.
    result = null;
    notifyListeners();
    DailyStepsResult next;
    try {
      next = await readSteps();
    } on MissingPluginException {
      next = const DailyStepsResult(
        DailyStepsStatus.capabilityUnavailable,
        null,
      );
    } on Exception {
      next = const DailyStepsResult(DailyStepsStatus.error, null);
    }
    if (_disposed) return;
    result = next;
    isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
