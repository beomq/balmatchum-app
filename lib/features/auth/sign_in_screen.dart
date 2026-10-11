import 'package:flutter/material.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

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
  const SignInScreen({required this.starter, super.key});

  final SignInStarter starter;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _starting = false;
  SignInOutcome? _outcome;
  bool _failed = false;

  Future<void> _start(SignInProvider provider) async {
    if (_starting) return;
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
                  Text('로그인', style: textTheme.headlineMedium),
                  const SizedBox(height: _SignInLayout.sectionGap),
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
                          : _failed
                          ? '로그인을 시작하지 못했습니다. 다시 시도해 주세요.'
                          : switch (_outcome) {
                              SignInOutcome.notConnected || null => '로그인 연결 전',
                            },
                      key: ValueKey(
                        _failed ? 'sign_in_error' : 'sign_in_status',
                      ),
                      style: textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
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
