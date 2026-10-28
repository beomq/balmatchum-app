import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

import '../../app/dependencies.dart';
import 'sign_in_starter.dart';

// Extend the bootstrap screen's spacing and Material typography with the
// assignment's shared social-button geometry, without overriding brand styles.
abstract final class _SignInLayout {
  static const pageInset = 24.0;
  static const sectionGap = 24.0;
  static const messageGap = 16.0;
  static const buttonGap = 12.0;
  static const buttonHeight = 56.0;
  static const maxWidth = 400.0;
}

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    // The server has no Apple Android/web callback route, so Apple login is
    // native-only; ThemeData.platform keeps this injectable for tests.
    final showApple = theme.platform != TargetPlatform.android;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(_SignInLayout.pageInset),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _SignInLayout.maxWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('로그인', style: textTheme.headlineSmall),
                  if (widget.notice != null)
                    Semantics(liveRegion: true, child: Text(widget.notice!)),
                  const SizedBox(height: _SignInLayout.sectionGap),
                  CheckboxListTile(
                    key: const ValueKey('sign_in_age_confirmation'),
                    value: _ageConfirmed,
                    onChanged: _starting
                        ? null
                        : (value) => setState(() {
                            _ageConfirmed = value ?? false;
                            _ageRequired = false;
                          }),
                    title: const Text('만 14세 이상입니다'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: _SignInLayout.buttonGap),
                  SocialButtonList.vertical(
                    shape: SocialButtonShape.rounded,
                    appearance: SocialButtonAppearance.light,
                    locale: const Locale('ko'),
                    size: _SignInLayout.buttonHeight,
                    spacing: _SignInLayout.buttonGap,
                    items: [
                      SocialButton(
                        social: Social.google,
                        logo: 'assets/social/google.png',
                        appearance: SocialButtonAppearance.light,
                        onPressed: _starting
                            ? null
                            : () => _start(SignInProvider.google),
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
                    ],
                  ),
                  const SizedBox(height: _SignInLayout.messageGap),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _starting
                          ? '로그인 연결 확인 중'
                          : _ageRequired
                          ? '만 14세 이상인지 확인해 주세요.'
                          : _failed
                          ? '로그인을 시작하지 못했습니다. 다시 시도해 주세요.'
                          : switch (_outcome?.status) {
                              SignInStatus.notConnected || null => '로그인 연결 전',
                              SignInStatus.signedIn => '로그인되었습니다.',
                              SignInStatus.cancelled => '로그인을 취소했습니다.',
                              SignInStatus.failed => switch (_outcome?.code) {
                                'configurationMissing' => '로그인 설정이 준비되지 않았습니다.',
                                'unsupportedProvider' => '지원하지 않는 로그인 제공자입니다.',
                                'invalidAttempt' =>
                                  '로그인 요청이 만료되었습니다. 다시 시도해 주세요.',
                                'invalidToken' =>
                                  '로그인 정보를 확인하지 못했습니다. 다시 시도해 주세요.',
                                'missingIdToken' =>
                                  '카카오 OpenID Connect 설정을 확인해 주세요.',
                                'networkError' => '네트워크 연결을 확인하고 다시 시도해 주세요.',
                                'serverError' =>
                                  '서버에서 로그인을 확인하지 못했습니다. 다시 시도해 주세요.',
                                'sessionStorageError' =>
                                  '로그인 정보를 기기에 저장하지 못했습니다. 다시 시도해 주세요.',
                                _ => '로그인을 완료하지 못했습니다. 다시 시도해 주세요.',
                              },
                            },
                      key: ValueKey(
                        _ageRequired
                            ? 'sign_in_age_required'
                            : _failed || _outcome?.status == SignInStatus.failed
                            ? 'sign_in_error'
                            : 'sign_in_status',
                      ),
                      style: textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('sign_in_privacy_policy'),
                    onPressed: _openPrivacyPolicy,
                    child: const Text('개인정보처리방침'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
