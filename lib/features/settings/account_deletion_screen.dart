import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart';
import 'settings_widgets.dart';

/// SET-15 계정 탈퇴 최종 확인 (`HFq6h`), the only confirmation before the
/// existing deletion service runs. It keeps the release notices word for
/// word (launch plan 33) and the button that says the deletion is
/// immediate. Entering, cancel, back and home delete nothing; one confirm
/// sends one request, and the page stays locked until it answers.
class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({
    required this.onDelete,
    required this.onBack,
    required this.onHome,
    super.key,
  });
  final Future<void> Function() onDelete;
  final VoidCallback onBack;
  final VoidCallback onHome;

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  bool deleting = false;

  Future<void> delete() async {
    if (deleting) return;
    setState(() => deleting = true);
    try {
      await widget.onDelete();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '탈퇴 처리를 완료하지 못했어요. 다시 시도해 주세요.',
              key: ValueKey('account_deletion_failed'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsConfirmPage(
    title: '계정 탈퇴 최종 확인',
    description: '확인하면 계정이 바로 삭제되고 되돌릴 수 없어요.',
    notices: const [
      ProductPanel(
        key: ValueKey('account_deletion_records'),
        color: ProductColors.warningSoft,
        child: SettingsNote(
          '되돌릴 수 없어요',
          '걸음 기록과 보유 포인트가 삭제되며 복구할 수 없어요. 소셜 계정 자체는 삭제되지 않아요.',
        ),
      ),
      ProductPanel(
        key: ValueKey('account_deletion_subscription'),
        child: SettingsNote(
          '구독은 따로 해지해요',
          '구독은 자동으로 해지되지 않아요. 탈퇴 전에 App Store / Google Play에서 구독을 해지해 주세요.',
        ),
      ),
    ],
    // Destructive confirmation is red, like a day deletion (guide 3.3).
    confirm: FilledButton(
      key: const ValueKey('account_deletion_confirm'),
      style: FilledButton.styleFrom(backgroundColor: MeetingColors.error),
      onPressed: deleting ? null : delete,
      child: const Text('계정 영구 삭제'),
    ),
    busy: deleting,
    onBack: widget.onBack,
    onHome: widget.onHome,
    lockKey: const ValueKey('account_deletion_lock'),
    cancelKey: const ValueKey('account_deletion_cancel'),
    progressKey: const ValueKey('account_deletion_progress'),
  );
}
