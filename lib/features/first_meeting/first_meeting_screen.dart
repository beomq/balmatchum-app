import 'dart:async';

import 'package:flutter/material.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

import 'data/first_meeting_file_storage.dart';
import 'domain/first_meeting.dart';
import 'meeting_theme.dart';
import 'meeting_widgets.dart';

class FirstMeetingScreen extends StatefulWidget {
  const FirstMeetingScreen({this.controller, super.key});
  final FirstMeetingController? controller;
  @override
  State<FirstMeetingScreen> createState() => _FirstMeetingScreenState();
}

class _FirstMeetingScreenState extends State<FirstMeetingScreen> {
  FirstMeetingController? controller;
  String? loadError;
  final name = TextEditingController();
  final goal = TextEditingController();
  final pageStorage = PageStorageBucket();

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final value =
          widget.controller ??
          FirstMeetingController(storage: FirstMeetingFileStorage.device());
      await value.initialize();
      if (!mounted) {
        if (widget.controller == null) value.dispose();
        return;
      }
      controller = value;
      name.text = value.state.name;
      goal.text = value.state.goalInput;
      value.addListener(changed);
      setState(() {});
    } on Exception {
      if (mounted) setState(() => loadError = '체험 기록을 읽지 못했습니다. 다시 시도해 주세요.');
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller?.removeListener(changed);
    if (widget.controller == null) controller?.dispose();
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
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
      content: const Text('이번 Dev 체험 범위에 포함되지 않은 기능입니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) {
      return MeetingPage(
        children: [
          Text(loadError ?? '이 기기의 체험 기록을 읽고 있어요.'),
          if (loadError != null)
            FilledButton(onPressed: load, child: const Text('다시 시도')),
        ],
      );
    }
    final s = c.state;
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
          showHeader: s.step != FirstMeetingStep.home,
          wide:
              s.step == FirstMeetingStep.catalog ||
              s.step == FirstMeetingStep.home,
          onBack:
              s.step == FirstMeetingStep.login ||
                  s.step == FirstMeetingStep.home ||
                  c.isBusy
              ? null
              : c.back,
          children: [
            if (c.error != null) ...[
              MeetingNotice('저장 상태를 확인해 주세요', switch (c.error!) {
                FirstMeetingError.corruption =>
                  '체험 기록이 손상되었습니다. 자동으로 덮어쓰지 않았습니다.',
                FirstMeetingError.storage =>
                  '기기에 저장하지 못했습니다. 입력을 유지했으니 다시 시도해 주세요.',
                FirstMeetingError.validation => '이름·성별과 양의 정수 목표를 확인해 주세요.',
              }),
              const SizedBox(height: 16),
              if (c.error == FirstMeetingError.corruption)
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
              ...screen(c),
          ],
        ),
      ),
    );
  }

  List<Widget> screen(FirstMeetingController c) {
    final s = c.state;
    final enabled = !c.isBusy;
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
          const MeetingHeading('함께할 친구를 골라 주세요', '30종 · 8개 그룹의 친구들을 만나 보세요.'),
          for (final group in FirstMeetingCatalog.groups) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '${group.id} · ${group.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            LayoutBuilder(
              builder: (context, bounds) {
                final columns = bounds.maxWidth < 320
                    ? 2
                    : ((bounds.maxWidth + 16) / 180).floor().clamp(2, 4);
                final width = (bounds.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final breed in group.breeds)
                      SizedBox(
                        width: width,
                        child: dogCard(breed, c, CandidateOrigin.catalog),
                      ),
                  ],
                );
              },
            ),
          ],
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
              color: const Color(0xFFE8EFE5),
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
          const MeetingNotice('최종 선택 안내', '완료 뒤에는 품종을 바꿀 수 없습니다.'),
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
                              : const Color(0xFFFFF9F0),
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
        return [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${s.name} · 함께한 지 $days일',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: reset,
                        tooltip: 'Dev 체험 초기화',
                        icon: Image.asset(
                          'assets/first_meeting/icons/settings.png',
                          width: 32,
                          height: 32,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: MediaQuery.sizeOf(context).height < 600
                          ? 220
                          : 330,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/first_meeting/sunny.png',
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 18,
                            left: 18,
                            right: 18,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '오늘도 네 옆에서 걸을게',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontFamily: 'Galmuri11'),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(40, 65, 40, 16),
                            child: Image.asset(
                              s.candidate!.spritePath,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('오늘 걸음 · 목표 ${s.goal}'),
                        const SizedBox(height: 12),
                        Text(
                          '— 걸음',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const Text('걸음 정보를 조회하지 않은 체험 화면이에요.'),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, bounds) {
                            final stack =
                                bounds.maxWidth < 280 ||
                                MediaQuery.textScalerOf(context).scale(16) > 21;
                            final actions = [
                              OutlinedButton(
                                onPressed: () => unavailable('기록 보기'),
                                child: const Text('기록 보기'),
                              ),
                              FilledButton(
                                onPressed: () => unavailable('포인트 받기'),
                                child: const Text('포인트 받기'),
                              ),
                            ];
                            return stack
                                ? Column(
                                    children: [
                                      actions[0],
                                      const SizedBox(height: 8),
                                      actions[1],
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: actions[0]),
                                      const SizedBox(width: 8),
                                      Expanded(child: actions[1]),
                                    ],
                                  );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final entry in [
                        ('기록', 'calendar-record'),
                        ('퀴즈', 'question-quiz'),
                        ('꾸미기', 'wardrobe'),
                        ('사진', 'camera-photo'),
                      ])
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(72, 80),
                          ),
                          onPressed: () => unavailable(entry.$1),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/first_meeting/icons/${entry.$2}.png',
                                width: 32,
                                height: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(entry.$1),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Dev 체험 · 이 기기에 저장', textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ];
    }
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
