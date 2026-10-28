import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

import '../../app/dependencies.dart';
import '../../app/duo_rail.dart';
import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart' show Space;
import 'sign_in_starter.dart';

/// Pen `QO6i9` (AUTH-01) on the shared scale. The provider buttons keep the
/// assignment's 56 pt height and 12 pt gap: the owner fixed only their order
/// (9.1 ③).
abstract final class _SignInLayout {
  static const gutter = Space.s5;
  static const gap = Space.s3;
  static const buttonGap = 12.0;
  static const buttonHeight = 56.0;
  static const maxWidth = 400.0;

  /// The splash never shrinks below this; past it the whole page scrolls.
  static const splashMin = 160.0;

  /// Pen `Age Checkbox` is 22 pt; Material draws 18.
  static const checkboxScale = 22 / 18;
}

const _splash = 'assets/brand/balmatchum_splash.png';

/// Internal setup failures read as one thing the user can do: try later.
const _unavailable = '지금은 이 방법으로 로그인할 수 없어요. 잠시 후 다시 시도해 주세요.';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    required this.starter,
    this.notice,
    this.openUrl = openExternalUrl,
    super.key,
  });

  final SignInStarter starter;
  final String? notice;
  final Future<bool> Function(Uri url) openUrl;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _starting = false;
  SignInOutcome? _outcome;
  bool _failed = false;
  // Asked on every visit and never stored: only users aged 14+ may sign in.
  bool _ageConfirmed = false;
  bool _ageRequired = false;

  Future<void> _start(SignInProvider provider) async {
    if (_starting) return;
    // Provider buttons stay enabled per brand guidelines; gate the tap here.
    if (!_ageConfirmed) {
      setState(() => _ageRequired = true);
      return;
    }
    setState(() {
      _starting = true;
      _outcome = null;
      _failed = false;
    });
    try {
      final outcome = await widget.starter.start(provider);
      if (mounted) setState(() => _outcome = outcome);
    } on Exception {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    bool opened;
    try {
      opened = await widget.openUrl(Uri.parse(privacyPolicyUrl));
    } on PlatformException {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('개인정보처리방침을 열지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  /// The progress, age, result or failure line with its key. Nothing shows
  /// at rest (guide 4.1-4).
  (String, String)? _status() {
    if (_starting) return ('sign_in_status', '로그인 연결 확인 중');
    if (_ageRequired) return ('sign_in_age_required', '만 14세 이상인지 확인해 주세요.');
    if (_failed) return ('sign_in_error', '로그인을 시작하지 못했습니다. 다시 시도해 주세요.');
    final outcome = _outcome;
    if (outcome == null) return null;
    return switch (outcome.status) {
      SignInStatus.notConnected => ('sign_in_status', _unavailable),
      SignInStatus.signedIn => ('sign_in_status', '로그인되었습니다.'),
      SignInStatus.cancelled => ('sign_in_status', '로그인을 취소했습니다.'),
      SignInStatus.failed => (
        'sign_in_error',
        switch (outcome.code) {
          'configurationMissing' ||
          'unsupportedProvider' ||
          'missingIdToken' => _unavailable,
          'invalidAttempt' => '로그인 요청이 만료되었습니다. 다시 시도해 주세요.',
          'invalidToken' => '로그인 정보를 확인하지 못했습니다. 다시 시도해 주세요.',
          'networkError' => '네트워크 연결을 확인하고 다시 시도해 주세요.',
          'serverError' => '서버에서 로그인을 확인하지 못했습니다. 다시 시도해 주세요.',
          'sessionStorageError' => '로그인 정보를 기기에 저장하지 못했습니다. 다시 시도해 주세요.',
          _ => '로그인을 완료하지 못했습니다. 다시 시도해 주세요.',
        },
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    // The server has no Apple Android/web callback route, so Apple login is
    // native-only; ThemeData.platform keeps this injectable for tests.
    final showApple = theme.platform != TargetPlatform.android;
    // No rail actions here; the Duo side column is still painted.
    const railSpec = DuoRailSpec();
    final railMode = duoRailMode(MediaQuery.of(context), railSpec);
    final status = _status();
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        _SignInLayout.gutter,
        0,
        _SignInLayout.gutter,
        _SignInLayout.gap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _SignInLayout.gap,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s1,
            children: [
              Semantics(
                header: true,
                child: Text(
                  '내 강아지와 매일 같이 걸어요',
                  key: const ValueKey('sign_in_title'),
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall,
                ),
              ),
              Text(
                '걸을수록 포인트가 쌓이고, 강아지를 꾸밀 수 있어요',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
            ],
          ),
          if (widget.notice != null)
            Semantics(
              liveRegion: true,
              child: Text(
                widget.notice!,
                key: const ValueKey('sign_in_notice'),
                textAlign: TextAlign.center,
              ),
            ),
          CheckboxListTile(
            key: const ValueKey('sign_in_age_confirmation'),
            value: _ageConfirmed,
            onChanged: _starting
                ? null
                : (value) => setState(() {
                    _ageConfirmed = value ?? false;
                    _ageRequired = false;
                  }),
            title: Wrap(
              spacing: Space.s2,
              runSpacing: Space.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '만 14세 이상이에요',
                  style: meetingType(14, 20, FontWeight.w700),
                ),
                const _RequiredTag(),
              ],
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            // The 22 pt box is painted in a 40 pt slot, 9 pt from its label.
            horizontalTitleGap: 0,
            minLeadingWidth: 0,
            minTileHeight: 44,
            checkboxScaleFactor: _SignInLayout.checkboxScale,
            // 5 scaled by 22/18 is Pen's 6 pt corner.
            checkboxShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            activeColor: MeetingColors.primaryStrong,
            checkColor: MeetingColors.raised,
            side: const BorderSide(color: MeetingColors.primary, width: 2),
          ),
          SocialButtonList.vertical(
            shape: SocialButtonShape.rounded,
            appearance: SocialButtonAppearance.light,
            locale: const Locale('ko'),
            size: _SignInLayout.buttonHeight,
            spacing: _SignInLayout.buttonGap,
            // Owner order (9.1 ③): Kakao, Naver, Apple, Google.
            items: [
              SocialButton(
                social: Social.kakao,
                logo: 'assets/social/kakao.png',
                appearance: SocialButtonAppearance.providerDefault,
                onPressed: _starting
                    ? null
                    : () => _start(SignInProvider.kakao),
              ),
              SocialButton(
                social: Social.naver,
                logo: 'assets/social/naver.png',
                appearance: SocialButtonAppearance.light,
                onPressed: _starting
                    ? null
                    : () => _start(SignInProvider.naver),
              ),
              if (showApple)
                SocialButton(
                  social: Social.apple,
                  logo: 'assets/social/apple.png',
                  appearance: SocialButtonAppearance.providerDefault,
                  onPressed: _starting
                      ? null
                      : () => _start(SignInProvider.apple),
                ),
              SocialButton(
                social: Social.google,
                logo: 'assets/social/google.png',
                appearance: SocialButtonAppearance.light,
                onPressed: _starting
                    ? null
                    : () => _start(SignInProvider.google),
              ),
            ],
          ),
          if (status case (final key, final message))
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                key: ValueKey(key),
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
          Text(
            '다른 소셜 계정으로 로그인하면 별도 계정으로 시작해요',
            key: const ValueKey('sign_in_account_note'),
            textAlign: TextAlign.center,
            style: textTheme.bodySmall,
          ),
          // No terms link until its public URL exists (9.1 ④).
          Center(
            child: TextButton(
              key: const ValueKey('sign_in_privacy_policy'),
              onPressed: _openPrivacyPolicy,
              style: TextButton.styleFrom(
                foregroundColor: MeetingColors.muted,
                textStyle: meetingType(12, 16, FontWeight.w600),
              ),
              child: const Text('개인정보처리방침'),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _SignInLayout.maxWidth,
                    ),
                    child: _SplashLayout(
                      minHeight: bounds.maxHeight,
                      splash: Image.asset(
                        _splash,
                        key: const ValueKey('sign_in_splash'),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        semanticLabel: '발맞춤',
                      ),
                      body: body,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (railMode != null) DuoRail(spec: railSpec, mode: railMode),
        ],
      ),
    );
  }
}

/// Pen `Age Required Tag`: 필수 on a warning-soft pill.
class _RequiredTag extends StatelessWidget {
  const _RequiredTag();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: MeetingColors.warningSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        '필수',
        style: meetingType(11, 14, FontWeight.w800, MeetingColors.error),
      ),
    ),
  );
}

/// The splash over the login group (guide 4.1-1). The group keeps its own
/// height and the splash takes what it leaves of [minHeight], down to
/// [_SignInLayout.splashMin]; a taller page scrolls. This lays the group out
/// first instead of an intrinsic pass, which the provider list's
/// LayoutBuilder does not support.
class _SplashLayout extends MultiChildRenderObjectWidget {
  _SplashLayout({
    required this.minHeight,
    required Widget splash,
    required Widget body,
  }) : super(children: [splash, body]);

  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSplashLayout(minHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSplashLayout renderObject,
  ) {
    renderObject.minHeight = minHeight;
  }
}

class _SplashParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSplashLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SplashParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SplashParentData> {
  _RenderSplashLayout(this._minHeight);

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SplashParentData) {
      child.parentData = _SplashParentData();
    }
  }

  @override
  void performLayout() {
    final splash = firstChild!;
    final body = lastChild!;
    final width = constraints.maxWidth;
    body.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final splashHeight = math.max(
      _SignInLayout.splashMin,
      _minHeight - body.size.height,
    );
    splash.layout(BoxConstraints.tight(Size(width, splashHeight)));
    (body.parentData! as _SplashParentData).offset = Offset(0, splashHeight);
    size = constraints.constrain(Size(width, splashHeight + body.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
