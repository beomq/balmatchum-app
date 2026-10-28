import 'package:balmatchum_app/features/auth/account_deletion_dialog.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('permanent deletion is the one red confirmation', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => const AccountDeletionDialog(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('account_deletion_confirm'));
    // The painted fill, after the theme's primary-strong default (guide 3.3).
    final fill = tester.widget<Material>(
      find.descendant(of: confirm, matching: find.byType(Material)),
    );
    expect(fill.color, MeetingColors.error);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
