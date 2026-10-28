import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException, appBuildName;

import '../../app/dependencies.dart';
import '../auth/kakao_auth_service.dart';
import '../daily_activity/daily_steps_controller.dart';
import '../first_meeting/meeting_theme.dart';
import '../first_meeting/meeting_widgets.dart';
import '../records/product_page.dart';
import 'settings_screen.dart';
import 'settings_widgets.dart';

/// The permissions settings explains (SET-02, SET-04).
enum SettingsPermission { steps, photo }

/// SET-02 걸음 권한 and SET-04 사진 권한. Before 9.1 ⑥ these explain and
/// show no granted or denied value; neither page asks for a permission or
/// opens the system settings.
class PermissionScreen extends StatelessWidget {
  const PermissionScreen({
    required this.permission,
    required this.onBack,
    required this.onHome,
    this.dailySteps,
    super.key,
  });
  final SettingsPermission permission;
  final VoidCallback onBack;
  final VoidCallback onHome;

  /// The home's last step read for [SettingsPermission.steps].
  final DailyStepsController? dailySteps;

  @override
  Widget build(BuildContext context) {
    final steps = dailySteps;
    return steps == null
        ? _page(context)
        : ListenableBuilder(
            listenable: steps,
            builder: (context, _) => _page(context),
          );
  }

  Widget _page(BuildContext context) {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final health = ios ? '건강 앱' : 'Health Connect';
    final isSteps = permission == SettingsPermission.steps;
    return ProductPage(
      onBack: onBack,
      onHome: onHome,
      children: [
        isSteps
            ? const MeetingHeading('걸음 권한', '오늘 걸음을 읽는 권한이에요.')
            : const MeetingHeading('사진 권한', '사진을 고르고 저장할 때 쓰는 권한이에요.'),
        // `Permission Status`: primary-soft well with the 32 pt icon.
        Container(
          padding: const EdgeInsets.all(Space.s4),
          decoration: const BoxDecoration(
            color: MeetingColors.soft,
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          child: Row(
            spacing: Space.s3,
            children: [
              PixelIcon(isSteps ? 'permission-steps' : 'permission-photo'),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.s1,
                  children: [
                    Text(
                      isSteps ? '마지막 걸음 조회' : '사진 권한',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      isSteps
                          ? stepsReadState(dailySteps) ?? '아직 읽지 않았어요'
                          : '허용 여부는 설정 앱에서 확인해요',
                      key: const ValueKey('settings_permission_state'),
                      style: meetingType(
                        13,
                        18,
                        FontWeight.w600,
                        MeetingColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.s4),
        ProductPanel(
          child: SettingsNote(
            '사용 목적',
            isSteps
                ? '$health에 기록된 오늘 걸음을 읽어 오늘 걸음과 목표 진행을 보여 줘요. '
                      '걸음을 기록하거나 바꾸지는 않아요.'
                : '반려견과 함께 편집할 사진을 고르고, 완성한 사진을 기기에 저장해요.',
          ),
        ),
        if (isSteps) ...[
          const SizedBox(height: Space.s4),
          const ProductPanel(
            color: ProductColors.warningSoft,
            child: SettingsNote('걸음을 못 읽을 때', '0걸음으로 세지 않고 확인할 수 없다고 보여 줘요.'),
          ),
        ],
        const SizedBox(height: Space.s4),
        Text(
          isSteps
              ? '${ios ? '아이폰은 걸음 읽기를 허용했는지 앱에 알려 주지 않아서, ' : ''}'
                    '마지막으로 걸음을 읽은 결과를 보여 줘요. '
                    '권한은 $health에서 바꿀 수 있어요.'
              : '권한은 설정 앱 > 발맞춤에서 바꿀 수 있어요.',
          key: const ValueKey('settings_permission_guide'),
        ),
      ],
    );
  }
}

/// SET-09 서비스 정보: the privacy policy and the app version. Terms wait
/// for their public URL (9.1 ④) and help for its content.
class ServiceInfoScreen extends StatelessWidget {
  const ServiceInfoScreen({
    required this.onBack,
    required this.onHome,
    this.openUrl = openExternalUrl,
    this.version = appBuildName,
    super.key,
  });
  final VoidCallback onBack;
  final VoidCallback onHome;
  final Future<bool> Function(Uri url) openUrl;

  /// The build name the app was compiled with; null hides the row.
  final String? version;

  @override
  Widget build(BuildContext context) {
    final version = this.version;
    return ProductPage(
      onBack: onBack,
      onHome: onHome,
      children: [
        const MeetingHeading('서비스 정보', '개인정보처리방침과 앱 정보를 확인해요.'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const ValueKey('settings_privacy_policy'),
              title: '개인정보처리방침',
              value: '수집·보관·삭제 안내',
              onTap: () => _openPrivacyPolicy(context),
            ),
            if (version != null)
              SettingsRow(
                key: const ValueKey('settings_app_version'),
                title: '앱 버전',
                value: '발맞춤 $version',
                valueKey: const ValueKey('settings_app_version_value'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    bool opened;
    try {
      opened = await openUrl(Uri.parse(privacyPolicyUrl));
    } on PlatformException {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('개인정보처리방침을 열지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }
}

/// SET-07 로그아웃 확인, then the existing logout. Only a cleared device
/// leaves the page; a failure stays here with its notice.
class LogoutScreen extends StatefulWidget {
  const LogoutScreen({
    required this.onLogout,
    required this.onBack,
    required this.onHome,
    super.key,
  });
  final Future<LogoutOutcome> Function() onLogout;
  final VoidCallback onBack;
  final VoidCallback onHome;

  @override
  State<LogoutScreen> createState() => _LogoutScreenState();
}

class _LogoutScreenState extends State<LogoutScreen> {
  bool busy = false;

  Future<void> logout() async {
    if (busy) return;
    setState(() => busy = true);
    var cleared = false;
    try {
      cleared = (await widget.onLogout()).session.localCleared;
    } on Exception {
      cleared = false;
    }
    if (!mounted) return;
    if (cleared) {
      // The cleared session replaces the signed-in routes; leave the page
      // as the settings sheet closed before.
      widget.onBack();
      return;
    }
    setState(() => busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '로그아웃하지 못했어요. 다시 시도해 주세요.',
          key: ValueKey('logout_failed'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsConfirmPage(
    title: '로그아웃할까요?',
    description: '이 기기에서 계정을 나가요.',
    notices: const [
      ProductPanel(
        child: SettingsNote(
          '계정과 기록은 남아요',
          '로그아웃은 이 기기에서만 나가는 거예요. 같은 소셜 계정으로 다시 로그인하면 이어서 쓸 수 있어요.',
        ),
      ),
    ],
    confirm: FilledButton(
      key: const ValueKey('logout_confirm'),
      onPressed: busy ? null : logout,
      child: const Text('로그아웃'),
    ),
    busy: busy,
    onBack: widget.onBack,
    onHome: widget.onHome,
    lockKey: const ValueKey('logout_lock'),
    cancelKey: const ValueKey('logout_cancel'),
    progressKey: const ValueKey('logout_progress'),
  );
}
