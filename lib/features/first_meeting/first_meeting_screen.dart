import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

import '../../app/dependencies.dart';
import '../../app/duo_rail.dart';
import '../daily_activity/daily_steps_controller.dart';
import '../daily_activity/product_controller.dart';
import '../daily_activity/record_mapping.dart';
import '../daily_activity/product_repository.dart';
import '../daily_activity/today_reward_sheet.dart';
import '../quiz/quiz_controller.dart';
import '../records/product_page.dart'
    show PixelIcon, fixtureLabelsVisible, formatCount;
import '../records/status_widgets.dart';
import '../auth/kakao_auth_service.dart';
import '../auth/account_deletion_dialog.dart';
import '../wardrobe/dog_sprite.dart';
import 'breed_pager.dart';
import 'domain/first_meeting.dart';
import 'home_goal_card.dart';
import 'meeting_theme.dart';
import 'meeting_widgets.dart';

class FirstMeetingScreen extends StatefulWidget {
  const FirstMeetingScreen({
    required this.controller,
    this.dailySteps,
    this.onOpenPhoto,
    this.onOpenRecords,
    this.onOpenQuiz,
    this.onOpenWardrobe,
    this.onOpenBilling,
    this.product,
    this.quiz,
    this.onLogout,
    this.onDeleteAccount,
    this.openUrl = openExternalUrl,
    super.key,
  });
  final FirstMeetingController controller;
  final DailyStepsController? dailySteps;
  final VoidCallback? onOpenPhoto;
  final VoidCallback? onOpenRecords;
  final VoidCallback? onOpenQuiz;
  final VoidCallback? onOpenWardrobe;
  final VoidCallback? onOpenBilling;
  final ProductController? product;

  /// A signed-in account's quiz, read for the home's quiz tile.
  final QuizController? quiz;
  final Future<LogoutOutcome> Function()? onLogout;
  final Future<void> Function()? onDeleteAccount;
  final Future<bool> Function(Uri url) openUrl;
  @override
  State<FirstMeetingScreen> createState() => _FirstMeetingScreenState();
}

class _FirstMeetingScreenState extends State<FirstMeetingScreen> {
  FirstMeetingController? controller;
  final deletingAccount = ValueNotifier(false);
  String? loadError;
  final name = TextEditingController();
  final goal = TextEditingController();
  final pageStorage = PageStorageBucket();
  late final AppLifecycleListener lifecycle;

  /// The home's entry refresh already ran for the current product.
  bool homeRefreshed = false;

  @override
  void initState() {
    super.initState();
    widget.dailySteps?.addListener(changed);
    widget.product?.addListener(changed);
    widget.quiz?.addListener(changed);
    // Coming back to the app refreshes the home like a pull (guide 3.1).
    lifecycle = AppLifecycleListener(
      onShow: () {
        if (controller?.state.step == FirstMeetingStep.home) {
          unawaited(refreshHome());
        }
      },
    );
    unawaited(load());
  }

  @override
  void didUpdateWidget(FirstMeetingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quiz != widget.quiz) {
      oldWidget.quiz?.removeListener(changed);
      widget.quiz?.addListener(changed);
    }
    if (oldWidget.product != widget.product) {
      oldWidget.product?.removeListener(changed);
      widget.product?.addListener(changed);
      // The router hands over the product once the first meeting completes.
      homeRefreshed = false;
      enterHome();
    }
  }

  Future<void> load() async {
    try {
      final value = widget.controller;
      await value.initialize();
      if (!mounted) {
        return;
      }
      controller = value;
      name.text = value.state.name;
      goal.text = value.state.goalInput;
      value.addListener(changed);
      setState(() {});
      enterHome();
    } on Exception {
      if (mounted) setState(() => loadError = '체험 기록을 읽지 못했습니다. 다시 시도해 주세요.');
    }
  }

  Future<void> settings() async {
    final c = controller!;
    final settingsName = TextEditingController(text: c.state.name);
    final settingsGoal = TextEditingController(text: '${c.state.goal}');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([c, deletingAccount]),
        builder: (context, _) => AbsorbPointer(
          absorbing: deletingAccount.value,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const MeetingHeading('설정', '이름과 하루 목표를 변경할 수 있어요.'),
                  if (deletingAccount.value) const LinearProgressIndicator(),
                  TextField(
                    key: const ValueKey('settings_name'),
                    controller: settingsName,
                    enabled: !c.isBusy && !c.hasPendingMutation,
                    decoration: const InputDecoration(labelText: '강아지 이름'),
                  ),
                  const SizedBox(height: 12),
                  // Two equal saves: neither is the sheet's one primary (3.3).
                  OutlinedButton(
                    onPressed: c.isBusy || c.hasPendingMutation
                        ? null
                        : () => c.renameDog(settingsName.text),
                    child: const Text('이름 저장'),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const ValueKey('settings_goal'),
                    controller: settingsGoal,
                    enabled: !c.isBusy && !c.hasPendingMutation,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '하루 걸음 목표'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: c.isBusy || c.hasPendingMutation
                        ? null
                        : () => c.changeGoal(settingsGoal.text),
                    child: const Text('목표 저장'),
                  ),
                  if (c.error != null || c.profileError != null)
                    Text(
                      c.profileError == 'staleRevision'
                          ? '다른 기기에서 변경되었어요. 최신 정보를 확인하고 다시 저장해 주세요.'
                          : '저장하지 못했어요. 입력 또는 연결 상태를 확인해 주세요.',
                    ),
                  if (c.hasPendingMutation)
                    OutlinedButton(
                      onPressed: c.isBusy ? null : c.retryMutation,
                      child: const Text('저장 결과 확인 · 재시도'),
                    ),
                  Text(
                    '현재 이름 ${c.state.name} · '
                    '목표 ${formatCount(c.state.goal)}걸음',
                  ),
                  const SizedBox(height: 20),
                  if (widget.onOpenBilling != null) ...[
                    OutlinedButton(
                      key: const ValueKey('settings_billing'),
                      onPressed: c.isBusy
                          ? null
                          : () {
                              Navigator.pop(context);
                              widget.onOpenBilling!();
                            },
                      child: const Text('구매 및 복원'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton(
                    onPressed: c.isBusy || widget.onLogout == null
                        ? null
                        : () async {
                            final result = await widget.onLogout!();
                            if (context.mounted) {
                              if (result.session.localCleared) {
                                Navigator.pop(context);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('로그아웃하지 못했어요. 다시 시도해 주세요.'),
                                  ),
                                );
                              }
                            }
                          },
                    child: const Text('로그아웃'),
                  ),
                  TextButton(
                    key: const ValueKey('settings_privacy_policy'),
                    onPressed: openPrivacyPolicy,
                    child: const Text('개인정보처리방침'),
                  ),
                  if (widget.onDeleteAccount != null)
                    // Destructive entry: red text at the very bottom (3.3).
                    TextButton(
                      key: const ValueKey('settings_delete_account'),
                      style: TextButton.styleFrom(
                        foregroundColor: MeetingColors.error,
                      ),
                      onPressed: c.isBusy ? null : deleteAccount,
                      child: const Text('회원 탈퇴'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Modal route transitions may still reference the fields until unmounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      settingsName.dispose();
      settingsGoal.dispose();
    });
  }

  Future<void> openPrivacyPolicy() async {
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

  Future<void> deleteAccount() async {
    if (deletingAccount.value) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const AccountDeletionDialog(),
    );
    if (confirmed != true || !mounted) return;
    deletingAccount.value = true;
    try {
      await widget.onDeleteAccount!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('탈퇴 처리를 완료하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) deletingAccount.value = false;
    }
  }

  void changed() {
    if (!mounted) return;
    // A shared controller can notify while another route builds, such as the
    // quiz screen loading in its initState; repaint after that frame.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => changed());
      return;
    }
    setState(() {});
    enterHome();
  }

  /// Refreshes once per product when the home first shows. The post-frame hop
  /// lets the router hand over a product created with the completed meeting.
  void enterHome() {
    if (homeRefreshed || controller?.state.step != FirstMeetingStep.home) {
      return;
    }
    homeRefreshed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(refreshHome());
    });
  }

  /// Entry, app return, pull and retry share one refresh (guide 3.1). A real
  /// account reconnects first; the dev test user connects only by its button.
  Future<void> refreshHome() async {
    final product = widget.product;
    if (product != null && !product.connected && product.account != null) {
      await product.connect();
    }
    if (product != null && product.connected) {
      await product.sync();
      // A sync still running for another trigger reads these itself.
      if (!product.busy) await product.loadStreak();
    } else {
      await widget.dailySteps?.refresh();
    }
    // The tile shows today's quiz state; the quiz screen observes benefits.
    await widget.quiz?.load(observePremium: false);
  }

  @override
  void dispose() {
    lifecycle.dispose();
    widget.dailySteps?.removeListener(changed);
    widget.product?.removeListener(changed);
    widget.quiz?.removeListener(changed);
    controller?.removeListener(changed);
    deletingAccount.dispose();
    name.dispose();
    goal.dispose();
    super.dispose();
  }

  Future<void> reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dev 체험을 초기화할까요?'),
        content: const Text('이 기기의 체험 친구와 입력만 삭제합니다. 실제 계정 데이터는 변경하지 않습니다.'),
        actionsOverflowButtonSpacing: 8,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MeetingColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('체험 초기화'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller!.reset();
      name.text = controller!.state.name;
      goal.text = controller!.state.goalInput;
    }
  }

  void unavailable(String title) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      // An account build lands here only before today's record is loaded.
      content: Text(
        controller?.profileRepository == null
            ? '이번 Dev 체험 범위에 포함되지 않은 기능입니다.'
            : '기록을 불러오지 못했어요. 연결 상태를 확인해 주세요.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );

  Future<void> reward() async {
    final product = widget.product;
    final day = product?.today;
    if (product == null || !product.connected || day == null) {
      unavailable('포인트 받기');
      return;
    }
    if (day.date != ProductRepository.dateKey(ProductRepository.today)) {
      await product.connect();
      if (!mounted) return;
      if (product.today?.date !=
          ProductRepository.dateKey(ProductRepository.today)) {
        unavailable('오늘 포인트 조회');
        return;
      }
    }
    final dog = controller!.state.candidate!;
    final wardrobe = await showTodayRewardSheet(
      context,
      product: product,
      day: recordDay(product.today!),
      dogAsset: dog.spritePath,
      dogLayer: product.wornLayer(dog.id),
      canOpenWardrobe: widget.onOpenWardrobe != null,
    );
    // Navigates from the home once the sheet's route is gone.
    if (wardrobe && mounted) widget.onOpenWardrobe?.call();
  }

  /// Same labels and actions as the home header and shortcuts.
  DuoRailSpec homeRailSpec(FirstMeetingController c) {
    final quiz = widget.product?.quiz;
    return DuoRailSpec(
      tools: [
        DuoRailItem(
          key: const ValueKey('duo_rail_settings'),
          label: c.profileRepository == null ? 'Dev 체험 초기화' : '설정',
          icon: const PixelIcon('settings'),
          onPressed: c.profileRepository == null ? reset : settings,
        ),
      ],
      destinations: [
        for (final (id, label, icon, open) in [
          ('records', '기록', 'calendar-record', widget.onOpenRecords),
          ('quiz', '퀴즈', 'question-quiz', widget.onOpenQuiz),
          // Pen draws the decorate brush for this destination.
          ('wardrobe', '꾸미기', 'decorate-shortcut', widget.onOpenWardrobe),
          ('photo', '사진', 'camera-photo', widget.onOpenPhoto),
        ])
          DuoRailItem(
            key: ValueKey('duo_rail_$id'),
            label: label,
            icon: PixelIcon(icon),
            onPressed: open ?? () => unavailable(label),
            badgeLabel: id == 'quiz' && quiz != null && quiz.answerIndex == null
                ? '오늘 퀴즈 미응답'
                : null,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) {
      const empty = DuoRailSpec();
      final mode = duoRailMode(MediaQuery.of(context), empty);
      return MeetingPage(
        // Nothing to go back to yet; the Duo column is painted empty.
        rail: mode == null ? null : DuoRail(spec: empty, mode: mode),
        children: [
          Text(loadError ?? '이 기기의 체험 기록을 읽고 있어요.'),
          if (loadError != null)
            FilledButton(onPressed: load, child: const Text('다시 시도')),
        ],
      );
    }
    final s = c.state;
    final railSpec = switch (s.step) {
      FirstMeetingStep.home => homeRailSpec(c),
      // No back action: the column is painted without buttons.
      _ when !c.canGoBack => const DuoRailSpec(),
      // Same callback and enabled state as the top-bar back.
      _ => DuoRailSpec(tools: [duoBack(c.isBusy ? null : c.back)]),
    };
    final railMode = duoRailMode(MediaQuery.of(context), railSpec);
    return PopScope(
      canPop:
          s.step == FirstMeetingStep.login || s.step == FirstMeetingStep.home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !c.isBusy) unawaited(c.back());
      },
      child: PageStorage(
        bucket: pageStorage,
        child: MeetingPage(
          key: ValueKey(s.step),
          onRefresh: s.step == FirstMeetingStep.home ? refreshHome : null,
          showHeader: s.step != FirstMeetingStep.home,
          wide: s.step == FirstMeetingStep.home,
          // While the rail carries back, the header keeps its empty slot.
          onBack: railMode != null || !c.canGoBack || c.isBusy ? null : c.back,
          rail: railMode == null
              ? null
              : DuoRail(spec: railSpec, mode: railMode),
          children: [
            if (c.hasPendingMutation)
              OutlinedButton(
                onPressed: c.isBusy ? null : c.retryMutation,
                child: const Text('저장 결과 확인 · 재시도'),
              ),
            if (c.profileError != null) ...[
              MeetingNotice(
                '서버 프로필 확인',
                c.profileError == 'staleRevision'
                    ? '다른 기기에서 변경되었어요. 최신 정보를 확인하고 다시 시도해 주세요.'
                    : '프로필을 확인하지 못했어요. 다시 시도해 주세요.',
              ),
              if (!c.isRestored)
                OutlinedButton(
                  onPressed: c.isBusy ? null : c.initialize,
                  child: const Text('프로필 다시 읽기'),
                ),
            ],
            if (c.error != null) ...[
              MeetingNotice('저장 상태를 확인해 주세요', switch (c.error!) {
                FirstMeetingError.corruption =>
                  '체험 기록이 손상되었습니다. 자동으로 덮어쓰지 않았습니다.',
                FirstMeetingError.storage =>
                  '기기에 저장하지 못했습니다. 입력을 유지했으니 다시 시도해 주세요.',
                FirstMeetingError.validation => '이름·성별과 양의 정수 목표를 확인해 주세요.',
              }),
              const SizedBox(height: 16),
              if (c.error == FirstMeetingError.corruption &&
                  c.profileRepository == null)
                OutlinedButton(onPressed: reset, child: const Text('체험 초기화')),
              if (c.error == FirstMeetingError.storage && !c.isRestored)
                OutlinedButton(
                  onPressed: c.isBusy
                      ? null
                      : () async {
                          await c.initialize();
                          name.text = c.state.name;
                          goal.text = c.state.goalInput;
                        },
                  child: const Text('체험 기록 다시 읽기'),
                ),
            ],
            if (c.error != FirstMeetingError.corruption && c.isRestored)
              ...screen(c, railMode),
          ],
        ),
      ),
    );
  }

  List<Widget> screen(FirstMeetingController c, DuoRailMode? rail) {
    final s = c.state;
    final enabled = !c.isBusy && !c.hasPendingMutation;
    switch (s.step) {
      case FirstMeetingStep.login:
        return [
          Image.asset(
            'assets/first_meeting/brand.png',
            height: 140,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 14),
          const MeetingHeading('발맞춤에 로그인', '추가 회원정보 없이 소셜 계정으로 시작해요.'),
          SocialButtonList.vertical(
            shape: SocialButtonShape.rounded,
            appearance: SocialButtonAppearance.light,
            locale: const Locale('ko'),
            size: 48,
            spacing: 12,
            items: [
              for (final entry in [
                (Social.kakao, 'kakao'),
                (Social.naver, 'naver'),
                (Social.apple, 'apple'),
                (Social.google, 'google'),
              ])
                SocialButton(
                  social: entry.$1,
                  logo: 'assets/social/${entry.$2}.png',
                  appearance: entry.$1 == Social.google
                      ? SocialButtonAppearance.light
                      : SocialButtonAppearance.providerDefault,
                  onPressed: enabled ? c.enter : null,
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Dev 체험 · 이 기기에 저장', textAlign: TextAlign.center),
        ];
      case FirstMeetingStep.method:
        return [
          const MeetingHeading('어떤 친구를 만날까요?', '직접 고르거나 세 가지 질문으로 추천받을 수 있어요.'),
          MeetingChoice(
            title: '30종에서 직접 고르기',
            description: '8개 그룹의 모든 품종을 살펴봅니다.',
            icon: 'assets/first_meeting/icons/breed.png',
            onTap: enabled
                ? () => c.chooseMethod(FirstMeetingMethod.catalog)
                : null,
          ),
          MeetingChoice(
            title: '성향으로 추천받기',
            description: '2지선다 3문항으로 한 그룹을 찾습니다.',
            icon: 'assets/first_meeting/icons/survey.png',
            color: const Color(0xFFE8EFE5),
            onTap: enabled
                ? () => c.chooseMethod(FirstMeetingMethod.recommendation)
                : null,
          ),
          const MeetingNotice('선택 전 확인', '첫 만남을 완료한 뒤에는 품종을 바꿀 수 없어요.'),
        ];
      case FirstMeetingStep.question:
        const titles = [
          '어떤 분위기로 걷고 싶나요?',
          '어떤 길을 더 좋아하나요?',
          '어떤 친구와 함께하고 싶나요?',
        ];
        const choices = [
          ['여유롭게', '활기차게'],
          ['익숙한 길', '새로운 길'],
          ['자기 페이스로 나란히 걷는 친구', '자주 반응하며 교감하는 친구'],
        ];
        return [
          MeetingHeading(
            titles[s.questionIndex],
            '${s.questionIndex + 1} / 3 · 나와 어울리는 친구 찾기',
          ),
          for (var i = 0; i < 2; i++)
            MeetingChoice(
              title: choices[s.questionIndex][i],
              description: '이쪽이 더 좋아요',
              onTap: enabled ? () => c.answer(i == 1) : null,
            ),
        ];
      case FirstMeetingStep.results:
        return [
          MeetingHeading('이런 친구는 어때요?', s.group!.name),
          dogCard(s.representative!, c, CandidateOrigin.results, large: true),
          const SizedBox(height: 16),
          const Text('같은 그룹의 다른 친구'),
          const SizedBox(height: 12),
          for (final breed in s.otherCandidates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: dogCard(breed, c, CandidateOrigin.results),
            ),
          OutlinedButton(
            onPressed: enabled ? c.restartQuestions : null,
            child: const Text('질문 다시 답하기'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: enabled
                ? () => c.chooseMethod(FirstMeetingMethod.catalog)
                : null,
            child: const Text('30종 직접 고르기'),
          ),
        ];
      case FirstMeetingStep.catalog:
        return [
          const MeetingHeading('30종 직접 고르기', '넘겨 보고 카드를 누르면 최종 확인으로 이동'),
          BreedPager(
            initialBreedId: s.candidateOrigin == CandidateOrigin.catalog
                ? s.candidateBreedId
                : null,
            enabled: enabled,
            onSelect: (breed) =>
                c.selectCandidate(breed.id, origin: CandidateOrigin.catalog),
          ),
        ];
      case FirstMeetingStep.confirm:
        return [
          MeetingHeading(
            '${s.candidate!.name}와 만날까요?',
            '최종 선택 전에 품종과 변경 범위를 확인해 주세요.',
          ),
          Container(
            height: 280,
            decoration: BoxDecoration(
              color: MeetingColors.stage,
              border: Border.all(color: MeetingColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Image.asset(
              s.candidate!.spritePath,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
          ),
          const SizedBox(height: 18),
          const MeetingNotice(
            '최종 선택 안내',
            '완료 뒤에는 품종을 바꿀 수 없습니다.',
            warning: true,
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: enabled ? c.confirmCandidate : null,
            child: const Text('이 친구로 결정'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: enabled ? c.back : null,
            child: const Text('다시 고르기'),
          ),
        ];
      case FirstMeetingStep.name:
        return [
          const MeetingHeading('이름을 지어 주세요', '이름을 짓고 암컷·수컷을 선택해 주세요.'),
          const Text('강아지 이름'),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('meeting_name'),
            controller: name,
            onChanged: (value) => unawaited(c.updateName(value)),
            decoration: const InputDecoration(
              hintText: '강아지 이름',
              helperText: '한글·영문·숫자·공백 1–12글자',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 20),
          const Text('강아지 성별'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final sex in DogSex.values) ...[
                if (sex == DogSex.male) const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    selected: s.sex == sex,
                    button: true,
                    child: InkWell(
                      onTap: enabled ? () => c.updateSex(sex) : null,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 120),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: s.sex == sex
                              ? MeetingColors.soft
                              : MeetingColors.well,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: s.sex == sex
                                ? MeetingColors.primary
                                : MeetingColors.line,
                            width: s.sex == sex ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Image.asset(
                              'assets/first_meeting/icons/${sex.name}.png',
                              width: 32,
                              height: 32,
                            ),
                            const SizedBox(height: 6),
                            Text(sex == DogSex.female ? '암컷' : '수컷'),
                            Text(
                              s.sex == sex ? '선택됨' : '선택하기',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MeetingColors.soft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('선택한 친구', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(
                  s.candidate!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed:
                enabled &&
                    s.sex != null &&
                    FirstMeetingController.isValidName(name.text)
                ? c.submitName
                : null,
            child: const Text('이름과 성별 저장'),
          ),
        ];
      case FirstMeetingStep.goal:
        return [
          const MeetingHeading(
            '하루 목표를 정해 볼까요?',
            '기본 목표는 5,000걸음이에요. 나에게 맞게 정해 주세요.',
          ),
          TextField(
            key: const ValueKey('meeting_goal'),
            controller: goal,
            keyboardType: TextInputType.number,
            onChanged: (value) => unawaited(c.updateGoal(value)),
            decoration: const InputDecoration(
              labelText: '하루 걸음 목표',
              suffixText: '걸음',
            ),
          ),
          const SizedBox(height: 20),
          const MeetingNotice('가볍게 시작해요', '목표를 채우지 못해도 벌점은 없어요.'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: enabled ? c.complete : null,
            child: const Text('목표 저장하고 홈 보기'),
          ),
        ];
      case FirstMeetingStep.home:
        final today = DateTime.now().toUtc().add(const Duration(hours: 9));
        final met = s.firstMetAtUTC!.add(const Duration(hours: 9));
        final days =
            DateTime.utc(
              today.year,
              today.month,
              today.day,
            ).difference(DateTime.utc(met.year, met.month, met.day)).inDays +
            1;
        final product = widget.product;
        final todayKey = ProductRepository.dateKey(ProductRepository.today);
        final goal = HomeGoal.of(widget.dailySteps, s.goal, todayKey);
        final point = homeReward(product, todayKey);
        final streak = product?.streak;
        final wallet = product?.wallet;
        final streakShown = streak != null && streak.days > 0;
        return [
          MeetingHomeLayout(
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s.name} · 함께한 지 $days일',
                        textAlign: TextAlign.center,
                        // Pen's home header is a small muted line (5.1).
                        style: meetingType(
                          18,
                          24,
                          FontWeight.w700,
                          MeetingColors.muted,
                        ),
                      ),
                    ),
                    if (rail == null)
                      IconButton(
                        onPressed: c.profileRepository == null
                            ? reset
                            : settings,
                        tooltip: c.profileRepository == null
                            ? 'Dev 체험 초기화'
                            : '설정',
                        icon: Image.asset(
                          'assets/first_meeting/icons/settings.png',
                          width: 32,
                          height: 32,
                        ),
                      ),
                  ],
                ),
                // Unknown values leave their chip out; nothing reads as 0.
                if (streakShown || wallet != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (streakShown)
                        StatusChip(
                          streak.atLeast
                              ? '${streak.days}일 이상 연속 기록'
                              : '${streak.days}일 연속 기록',
                          icon: 'goal-target',
                          textKey: const ValueKey('home_streak'),
                        ),
                      if (wallet != null)
                        StatusChip(
                          '${formatCount(wallet.balance)}P'
                          '${fixtureLabelsVisible && wallet.fixtureLabel != null ? ' · 개발 검증용' : ''}',
                          icon: 'points',
                          textKey: const ValueKey('reward_wallet'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            scene: LayoutBuilder(
              builder: (context, bounds) => ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  // Pen's 358 x 250 stage at 390 pt, scaled with the body.
                  // Large text keeps the tall stage for its wrapped line.
                  height: MediaQuery.textScalerOf(context).scale(16) > 21
                      ? 330
                      : MediaQuery.sizeOf(context).height < 600
                      ? 220
                      : (bounds.maxWidth * 250 / 358).clamp(220.0, 330.0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (product?.store == null ||
                          product!.store!.equippedTheme == 'sunny')
                        Image.asset(
                          'assets/first_meeting/sunny.png',
                          fit: BoxFit.cover,
                        )
                      else
                        ColoredBox(
                          color: Color(
                            product.store!.items
                                .firstWhere(
                                  (item) =>
                                      item.themeId ==
                                      product.store!.equippedTheme,
                                )
                                .colorValue,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _bubble(goal, point),
                                key: const ValueKey('home_bubble'),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontFamily: 'Galmuri11'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Center(
                                child: DogSprite(
                                  asset: s.candidate!.spritePath,
                                  layer: product?.wornLayer(s.candidate!.id),
                                  layerKey: const ValueKey('home_dog_outfit'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            status: HomeGoalCard(
              goal: goal,
              reward: point,
              onReward: reward,
              onRetry: refreshHome,
              notices: [
                if (product != null) ...[
                  // Sync runs by itself (3.1). Only the dev build's test
                  // user, which has no account, connects by hand.
                  if (product.account == null && !product.connected)
                    TextButton(
                      key: const ValueKey('home_dev_connect'),
                      onPressed: product.busy ? null : product.connect,
                      child: const Text('개발 테스트 사용자 연결'),
                    ),
                  if (product.error != null) Text(product.error!),
                  if (product.error != null && product.account != null)
                    OutlinedButton(
                      key: const ValueKey('home_sync_retry'),
                      onPressed: product.busy ? null : refreshHome,
                      child: const Text('다시 시도'),
                    ),
                ],
              ],
            ),
            // The rail carries these destinations while it shows.
            shortcuts: rail != null
                ? null
                : MeetingShortcuts(
                    children: [
                      StatusTile(
                        key: const ValueKey('home_tile_records'),
                        icon: 'assets/first_meeting/icons/calendar-record.png',
                        title: '기록',
                        status: streak == null
                            ? null
                            : '이번 주 기록 ${streak.thisWeek}일',
                        statusKey: const ValueKey('home_tile_records_status'),
                        onTap: widget.onOpenRecords ?? () => unavailable('기록'),
                      ),
                      StatusTile(
                        key: const ValueKey('home_tile_quiz'),
                        icon: 'assets/first_meeting/icons/question-quiz.png',
                        title: '퀴즈',
                        status: quizStatus(todayKey),
                        statusKey: const ValueKey('home_tile_quiz_status'),
                        onTap: widget.onOpenQuiz ?? () => unavailable('퀴즈'),
                      ),
                      StatusTile(
                        key: const ValueKey('home_tile_wardrobe'),
                        icon:
                            'assets/first_meeting/icons/decorate-shortcut.png',
                        title: '꾸미기',
                        status: wardrobeStatus(),
                        statusKey: const ValueKey('home_tile_wardrobe_status'),
                        onTap:
                            widget.onOpenWardrobe ?? () => unavailable('꾸미기'),
                      ),
                      StatusTile(
                        key: const ValueKey('home_tile_photo'),
                        icon: 'assets/first_meeting/icons/camera-photo.png',
                        title: '사진',
                        // An invitation, not a claim that a photo exists.
                        status: '${_withWa(s.name)} 한 장',
                        statusKey: const ValueKey('home_tile_photo_status'),
                        onTap: widget.onOpenPhoto ?? () => unavailable('사진'),
                      ),
                    ],
                  ),
            // Only the Dev local flow says where it saves (owner, 10-28).
            footer: c.profileRepository == null
                ? const Text('Dev 체험 · 이 기기에 저장', textAlign: TextAlign.center)
                : null,
          ),
        ];
    }
  }

  /// The quiz tile's state; null while it is not known, never "done".
  String? quizStatus(String today) {
    if (widget.quiz case final quiz?) {
      final value = quiz.today;
      if (value == null || value.date != today) return null;
      return switch (value.status) {
        'ready' => switch (value.free) {
          null => null,
          final question =>
            question.answerIndex == null ? '아직 안 풀었어요' : '오늘 완료',
        },
        'contentUnavailable' || 'exhausted' => '문제 준비 중',
        _ => null,
      };
    }
    // The dev build reads its fixture question with the product.
    final question = widget.product?.quiz;
    if (question == null || question.date != today) return null;
    return question.answerIndex == null ? '아직 안 풀었어요' : '오늘 완료';
  }

  /// The outfit the stage draws, from the last confirmed server state; null
  /// while that state is not known.
  String? wardrobeStatus() {
    final outfits = widget.product?.outfits;
    if (outfits == null) return null;
    for (final item in outfits.items) {
      if (item.outfitId == outfits.equippedOutfit) return '착용 중 · ${item.name}';
    }
    return '착용한 옷 없음';
  }

  Widget dogCard(
    DogBreed breed,
    FirstMeetingController c,
    CandidateOrigin origin, {
    bool large = false,
  }) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      key: ValueKey('breed_${breed.id}'),
      onTap: c.isBusy ? null : () => c.selectBreed(breed.id, origin: origin),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Image.asset(
              breed.spritePath,
              height: large ? 220 : 120,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
            const SizedBox(height: 8),
            Text(
              breed.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

/// The companion's line. Numbers stay in the goal card and never repeat
/// here (guide 5.1); "almost there" is kept for the last stretch only.
String _bubble(HomeGoal goal, HomeReward point) {
  if (goal.state != StepsState.counted) {
    return goal.retryable ? '오늘 걸음을\n아직 못 가져왔어' : '오늘도 네 옆에서 걸을게';
  }
  if (point == HomeReward.claimed) {
    return goal.achieved ? '포인트 받았어!\n오늘 정말 잘 걸었어' : '포인트 받았어!\n남은 걸음도 같이 가자';
  }
  if (goal.achieved) return '오늘 목표 달성!\n같이 걸어서 좋았어';
  if (goal.percent >= 80) return '거의 다 왔어!\n조금만 더 같이 걷자';
  return '오늘도 네 옆에서 걸을게';
}

/// `{name}와` or `{name}과` by the name's last sound. Digits are read in
/// Korean; other characters take 와.
String _withWa(String name) {
  final value = name.trimRight();
  if (value.isEmpty) return name;
  final last = value.codeUnitAt(value.length - 1);
  final closed = last >= 0xAC00 && last <= 0xD7A3
      ? (last - 0xAC00) % 28 != 0
      // 영 일 삼 육 칠 팔 end in a consonant; 이 사 오 구 do not.
      : '013678'.contains(String.fromCharCode(last));
  return '$value${closed ? '과' : '와'}';
}
