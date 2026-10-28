import 'dart:async';

import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart' show PixelIcon;
import 'ads_controller.dart';

/// Caller owns the account-scoped controller and disposes it after this returns.
Future<void> showAdsSheet(
  BuildContext context, {
  required AdsController controller,
  required String purpose,
  required String targetDate,
  required int targetRevision,
  bool autoContinue = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => AdsSheet(
    controller: controller,
    purpose: purpose,
    targetDate: targetDate,
    targetRevision: targetRevision,
    autoContinue: autoContinue,
  ),
).whenComplete(controller.cancel);

class AdsSheet extends StatefulWidget {
  const AdsSheet({
    super.key,
    required this.controller,
    required this.purpose,
    required this.targetDate,
    required this.targetRevision,
    this.autoContinue = false,
  });
  final AdsController controller;
  final String purpose;
  final String targetDate;
  final int targetRevision;

  /// The caller's own button already asked for the ad: start it on open and
  /// close once the server verified the view. The caller decides what a
  /// verified view grants; this sheet still grants nothing.
  final bool autoContinue;
  @override
  State<AdsSheet> createState() => _AdsSheetState();
}

class _AdsSheetState extends State<AdsSheet> with WidgetsBindingObserver {
  bool closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoContinue) {
      widget.controller.addListener(closeWhenVerified);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(start());
      });
    }
  }

  Future<void> start() => widget.controller.start(
    purpose: widget.purpose,
    targetDate: widget.targetDate,
    targetRevision: widget.targetRevision,
  );

  void closeWhenVerified() {
    if (closing || !mounted || widget.controller.status != AdsStatus.verified) {
      return;
    }
    closing = true;
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.controller.status == AdsStatus.pending) {
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(closeWhenVerified);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '광고 시청 확인',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('ads_close'),
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(context).pop(),
                      // Dialog/Today Reward close: 44px control with a line.
                      style: IconButton.styleFrom(
                        fixedSize: const Size(44, 44),
                        side: const BorderSide(color: MeetingColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const PixelIcon('close-x', size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _message(controller.status),
                    key: ValueKey('ads_status_${controller.status.name}'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.autoContinue
                      ? '광고를 끝까지 보면 서버에서 확인한 뒤 바로 적용돼요.'
                      : '시청 완료 신호만으로 보상이 지급되지 않습니다. 서버 확인 후 혜택 적용은 별도 처리됩니다.',
                ),
                const SizedBox(height: 20),
                if (controller.busy) const LinearProgressIndicator(),
                if (controller.status == AdsStatus.idle)
                  FilledButton(
                    key: const ValueKey('ads_start'),
                    onPressed: start,
                    child: const Text('광고 보기'),
                  ),
                if (controller.canRefresh)
                  OutlinedButton(
                    key: const ValueKey('ads_refresh'),
                    onPressed: controller.refresh,
                    child: const Text('서버 상태 확인'),
                  ),
                if ([
                  AdsStatus.failed,
                  AdsStatus.missingConfiguration,
                  AdsStatus.consentRequired,
                ].contains(controller.status))
                  FilledButton(
                    key: const ValueKey('ads_retry'),
                    onPressed: () => controller.retry(
                      purpose: widget.purpose,
                      targetDate: widget.targetDate,
                      targetRevision: widget.targetRevision,
                    ),
                    child: const Text('다시 시도'),
                  ),
                if (controller.sdk.privacyOptionsRequired)
                  TextButton(
                    onPressed: () async {
                      try {
                        await controller.sdk.privacyOptions();
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('개인정보 옵션을 열지 못했습니다.')),
                          );
                        }
                      }
                    },
                    child: const Text('광고 개인정보 옵션'),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _message(AdsStatus status) => switch (status) {
  AdsStatus.idle => '광고를 보고 서버에서 시청 여부를 확인합니다.',
  AdsStatus.preparing => '광고 설정과 개인정보 동의를 확인하고 있습니다.',
  AdsStatus.creating => '서버에 시청 요청을 만들고 있습니다.',
  AdsStatus.loading => '광고를 불러오고 있습니다.',
  AdsStatus.showing => '광고를 시청 중입니다.',
  AdsStatus.checking => '서버 확인 중입니다.',
  AdsStatus.missingConfiguration => '광고 App ID 설정이 없어 사용할 수 없습니다.',
  AdsStatus.consentRequired => '광고 요청을 위한 개인정보 동의가 필요합니다.',
  AdsStatus.failed => '요청을 완료하지 못했습니다. 다시 시도하거나 상태를 확인하세요.',
  AdsStatus.cancelled => '시청 요청이 취소되었습니다. 계정이 바뀌었다면 다시 열어 주세요.',
  AdsStatus.pending => '서버의 시청 확인을 기다리고 있습니다. 잠시 후 상태 확인을 눌러 주세요.',
  AdsStatus.verified => '서버에서 시청을 확인했습니다. 아직 보상이 지급된 것은 아닙니다.',
  AdsStatus.consumed => '이미 서버에서 사용한 시청 확인입니다.',
  AdsStatus.expired => '시청 확인 유효 기간이 지났습니다.',
};
