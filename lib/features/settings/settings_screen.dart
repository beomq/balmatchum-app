import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appBuildName;

import '../daily_activity/daily_steps_controller.dart';
import '../first_meeting/domain/first_meeting.dart';
import '../first_meeting/meeting_theme.dart';
import '../first_meeting/meeting_widgets.dart';
import '../records/product_page.dart';
import '../wardrobe/dog_sprite.dart';
import '../watch_sync/watch_bridge.dart';
import 'settings_widgets.dart';

/// V2 SET (`o39c7Y`): the profile card, the 활동, 계정 and 구매 · 정보
/// groups, the red account deletion entry and the version. Opening it sends
/// nothing: no permission prompt, no step read and no deletion (guide 6.4).
///
/// A null destination hides its row. The login method and sync rows are not
/// drawn: the session keeps no provider and no last sync time.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.controller,
    required this.onBack,
    required this.onHome,
    this.dailySteps,
    this.dogLayer,
    this.onOpenSteps,
    this.onOpenPhoto,
    this.onOpenLogout,
    this.onOpenBilling,
    this.onOpenServiceInfo,
    this.onOpenDeletion,
    this.version = appBuildName,
    super.key,
  });

  final FirstMeetingController controller;
  final VoidCallback onBack;
  final VoidCallback onHome;

  /// The home's last step read, shown as it is; settings never reads.
  final DailyStepsController? dailySteps;

  /// The worn outfit over the profile sprite, as the home stage draws it.
  final String? dogLayer;
  final VoidCallback? onOpenSteps;
  final VoidCallback? onOpenPhoto;
  final VoidCallback? onOpenLogout;
  final VoidCallback? onOpenBilling;
  final VoidCallback? onOpenServiceInfo;
  final VoidCallback? onOpenDeletion;

  /// The build name the app was compiled with; null hides the version.
  final String? version;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, ?dailySteps]),
    builder: (context, _) {
      final c = controller;
      final s = c.state;
      final version = this.version;
      final account = [
        if (onOpenLogout case final open?)
          SettingsRow(
            key: const ValueKey('settings_logout'),
            icon: 'logout-sign-out',
            title: '로그아웃',
            value: '이 기기에서 나가기',
            onTap: open,
          ),
      ];
      final service = [
        if (onOpenBilling case final open?)
          SettingsRow(
            key: const ValueKey('settings_billing'),
            icon: 'service-sparkle',
            title: '광고 없이 함께 걷기',
            // The product line-up is the owner's call (9.1 ⑧); this names
            // what the existing purchase screen does.
            value: '구매 및 복원',
            onTap: open,
          ),
        if (onOpenServiceInfo case final open?)
          SettingsRow(
            key: const ValueKey('settings_info'),
            icon: 'info',
            // No terms URL (9.1 ④) and no help yet: the row names what the
            // page holds instead of Pen's 도움말 · 약관 · 개인정보.
            title: '서비스 정보',
            value: version == null ? '개인정보처리방침' : '개인정보처리방침 · 앱 버전',
            onTap: open,
          ),
      ];
      return ProductPage(
        onBack: onBack,
        onHome: onHome,
        title: '설정',
        children: [
          if (c.hasPendingMutation) ...[
            ProductPanel(
              color: ProductColors.warningSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s3,
                children: [
                  const Text('저장 결과를 확인하지 못했어요.'),
                  OutlinedButton(
                    key: const ValueKey('settings_retry'),
                    onPressed: c.isBusy ? null : c.retryMutation,
                    child: const Text('저장 결과 확인 · 재시도'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SettingsMetrics.gap),
          ],
          _ProfileCard(
            state: s,
            dogLayer: dogLayer,
            onRename: () => _edit(context, _Field.name),
          ),
          const SizedBox(height: SettingsMetrics.gap),
          SettingsGroup(
            label: '활동',
            children: [
              SettingsRow(
                key: const ValueKey('settings_goal_row'),
                icon: 'goal-target',
                title: '하루 걸음 목표',
                value: '${formatCount(s.goal)}걸음',
                valueKey: const ValueKey('settings_goal_value'),
                onTap: () => _edit(context, _Field.goal),
              ),
              if (onOpenSteps case final open?)
                SettingsRow(
                  key: const ValueKey('settings_steps'),
                  icon: 'permission-steps',
                  title: '걸음 권한',
                  value: stepsReadState(dailySteps),
                  valueKey: const ValueKey('settings_steps_value'),
                  onTap: open,
                ),
              if (onOpenPhoto case final open?)
                SettingsRow(
                  key: const ValueKey('settings_photo'),
                  icon: 'permission-photo',
                  title: '사진 권한',
                  // No status is read before 9.1 ⑥; this is what it is for.
                  value: '사진 고르기와 저장에 써요',
                  onTap: open,
                ),
            ],
          ),
          if (account.isNotEmpty) ...[
            const SizedBox(height: SettingsMetrics.gap),
            SettingsGroup(label: '계정', children: account),
          ],
          if (service.isNotEmpty) ...[
            const SizedBox(height: SettingsMetrics.gap),
            SettingsGroup(label: '구매 · 정보', children: service),
          ],
          if (onOpenDeletion case final open?) ...[
            const SizedBox(height: SettingsMetrics.gap),
            // Destructive entry: red text below every group (guide 3.3).
            InkWell(
              key: const ValueKey('settings_delete_account'),
              onTap: open,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '계정 탈퇴',
                          style: meetingType(
                            14,
                            20,
                            FontWeight.w600,
                            MeetingColors.error,
                          ),
                        ),
                      ),
                      const PixelIcon('caret-right', size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (version != null) ...[
            const SizedBox(height: SettingsMetrics.gap),
            // Pen's subtle ink is 3.2:1 on the surface; muted keeps 12 pt
            // text at AA.
            Text(
              '발맞춤 $version',
              key: const ValueKey('settings_version'),
              textAlign: TextAlign.center,
              style: meetingType(12, 16, FontWeight.w600, MeetingColors.muted),
            ),
          ],
        ],
      );
    },
  );

  Future<void> _edit(BuildContext context, _Field field) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _EditSheet(controller: controller, field: field),
      );
}

/// The steps row's state from the home's last device read (guide 6.4 rule
/// 4). HealthKit never tells an app whether reading was allowed, so this
/// names what the last read returned, never "allowed"; null before a read.
String? stepsReadState(DailyStepsController? steps) {
  if (steps == null) return null;
  final result = steps.result;
  if (result == null) return steps.isLoading ? '걸음 확인 중' : null;
  return switch (result.status) {
    DailyStepsStatus.available =>
      steps.count == null ? '걸음을 못 읽었어요' : '걸음을 읽고 있어요',
    DailyStepsStatus.empty => '오늘 기록된 걸음이 없어요',
    DailyStepsStatus.capabilityUnavailable => '이 기기에서는 걸음을 읽을 수 없어요',
    DailyStepsStatus.providerUpdateRequired => 'Health Connect 설치나 업데이트가 필요해요',
    DailyStepsStatus.permissionDenied ||
    DailyStepsStatus.unavailable ||
    DailyStepsStatus.error => '걸음을 못 읽었어요',
  };
}

/// `Profile Card`: the user's own sprite, name, breed and days together,
/// with 이름 바꾸기 opening the name sheet.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.state,
    required this.dogLayer,
    required this.onRename,
  });
  final FirstMeetingState state;
  final String? dogLayer;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final dog = state.candidate;
    final days = state.daysTogether(DateTime.now());
    return Material(
      color: MeetingColors.raised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: MeetingColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('settings_profile'),
        onTap: onRename,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            spacing: Space.s3,
            children: [
              if (dog != null)
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: ProductColors.recordSoft,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: DogSprite(
                    asset: dog.spritePath,
                    layer: dogLayer,
                    spriteKey: const ValueKey('settings_profile_dog'),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      state.name,
                      key: const ValueKey('settings_profile_name'),
                      style: meetingType(18, 24, FontWeight.w800),
                    ),
                    Text(
                      [
                        ?dog?.name,
                        if (days != null) '함께한 지 $days일',
                      ].join(' · '),
                      key: const ValueKey('settings_profile_meta'),
                      style: meetingType(
                        13,
                        18,
                        FontWeight.w500,
                        MeetingColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(
                    '이름 바꾸기',
                    style: meetingType(
                      13,
                      18,
                      FontWeight.w700,
                      MeetingColors.muted,
                    ),
                  ),
                  const PixelIcon('caret-right', size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Field { name, goal }

/// The name or goal edit sheet (SET-01). Its input lives and dies with the
/// sheet; the list changes only when the server confirms the save, and an
/// unconfirmed save is retried with its original request.
class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.controller, required this.field});
  final FirstMeetingController controller;
  final _Field field;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  FirstMeetingController get c => widget.controller;
  bool get isName => widget.field == _Field.name;
  late final input = TextEditingController(
    text: isName ? c.state.name : '${c.state.goal}',
  );

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> save() =>
      finish(isName ? c.renameDog(input.text) : c.changeGoal(input.text));

  /// Closes once the change is confirmed; a failure keeps the sheet open
  /// with its message and, for an unconfirmed save, the retry.
  Future<void> finish(Future<void> request) async {
    await request;
    if (!mounted) return;
    if (c.error == null && c.profileError == null && !c.hasPendingMutation) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final locked = c.isBusy || c.hasPendingMutation;
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Space.s6,
            Space.s6,
            Space.s6,
            Space.s6 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              isName
                  ? const MeetingHeading(
                      '이름 바꾸기',
                      '한글·영문·숫자·공백 1–12글자로 지어 주세요.',
                    )
                  : const MeetingHeading('걸음 목표 바꾸기', '목표를 채우지 못해도 벌점은 없어요.'),
              if (!isName) ...[
                ProductPanel(
                  color: MeetingColors.soft,
                  child: SettingsNote(
                    '현재 목표',
                    '${formatCount(c.state.goal)}걸음',
                  ),
                ),
                const SizedBox(height: Space.s4),
              ],
              TextField(
                key: ValueKey(isName ? 'settings_name' : 'settings_goal'),
                controller: input,
                enabled: !locked,
                keyboardType: isName ? null : TextInputType.number,
                decoration: InputDecoration(
                  labelText: isName ? '강아지 이름' : '하루 걸음 목표',
                  suffixText: isName ? null : '걸음',
                  // The range every saved goal keeps (9.1 ②).
                  helperText: isName
                      ? null
                      : '${formatCount(FirstMeetingController.minGoal)}~'
                            '${formatCount(FirstMeetingController.maxGoal)}걸음',
                ),
              ),
              if (c.error != null || c.profileError != null) ...[
                const SizedBox(height: Space.s3),
                Text(
                  c.profileError == 'staleRevision'
                      ? '다른 기기에서 변경되었어요. 최신 정보를 확인하고 다시 저장해 주세요.'
                      : '저장하지 못했어요. 입력 또는 연결 상태를 확인해 주세요.',
                  key: const ValueKey('settings_edit_error'),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: MeetingColors.error),
                ),
              ],
              if (c.hasPendingMutation) ...[
                const SizedBox(height: Space.s3),
                OutlinedButton(
                  key: const ValueKey('settings_edit_retry'),
                  onPressed: c.isBusy ? null : () => finish(c.retryMutation()),
                  child: const Text('저장 결과 확인 · 재시도'),
                ),
              ],
              const SizedBox(height: Space.s4),
              FilledButton(
                key: ValueKey(
                  isName ? 'settings_name_save' : 'settings_goal_save',
                ),
                onPressed: locked ? null : save,
                child: Text(isName ? '이름 저장' : '목표 저장'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
