import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';

class AccountDeletionDialog extends StatelessWidget {
  const AccountDeletionDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('계정을 삭제할까요?'),
    content: const Text(
      '걸음 기록과 보유 포인트가 삭제되며 복구할 수 없어요. 소셜 계정 자체는 삭제되지 않아요.\n\n'
      '구독은 자동으로 해지되지 않아요. 탈퇴 전에 App Store / Google Play에서 구독을 해지해 주세요.',
    ),
    actionsOverflowButtonSpacing: 8,
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('취소'),
      ),
      // Destructive confirmation is red, like a day deletion (guide 3.3).
      FilledButton(
        key: const ValueKey('account_deletion_confirm'),
        style: FilledButton.styleFrom(backgroundColor: MeetingColors.error),
        onPressed: () => Navigator.pop(context, true),
        child: const Text('계정 영구 삭제'),
      ),
    ],
  );
}
