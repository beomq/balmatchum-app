import 'dart:async';

import 'package:balmatchum_app/features/auth/account_deletion.dart';
import 'package:balmatchum_app/features/auth/account_provider_revocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final failingProvider in [null, 'kakao', 'google']) {
    test(
      'deletion attempts both providers and cleans up when $failingProvider fails',
      () async {
        // Given
        final events = <String>[];
        bool? revoked;
        final providers = AccountProviderRevocation(
          unlinkKakao: () async {
            events.add('kakao');
            if (failingProvider == 'kakao') throw Exception('provider offline');
          },
          disconnectGoogle: () async {
            events.add('google');
            if (failingProvider == 'google') {
              throw Exception('provider offline');
            }
          },
        );
        final deletion = AccountDeletion(
          markPending: () async {},
          clearPending: () async => events.add('done'),
          wasRemoteDeleted: () async => false,
          markRemoteDeleted: () async {},
          deleteRemote: () async => events.add('remote'),
          revokeProviders: () async => revoked = await providers.revoke(),
          clearLocal: () async => events.add('clear'),
          signOut: () async => events.add('logout'),
        );

        // When
        await deletion.delete();

        // Then
        expect(events, [
          'remote',
          'kakao',
          'google',
          'clear',
          'logout',
          'done',
        ]);
        expect(revoked, failingProvider == null);
      },
    );
  }

  for (final stalledProvider in ['kakao', 'google']) {
    testWidgets('deletion continues when $stalledProvider never responds', (
      tester,
    ) async {
      // Given: the fake clock controls the timeout, not a wall-clock sleep.
      final stalled = Completer<void>();
      final events = <String>[];
      bool? revoked;
      final providers = AccountProviderRevocation(
        unlinkKakao: () async {
          events.add('kakao');
          if (stalledProvider == 'kakao') await stalled.future;
        },
        disconnectGoogle: () async {
          events.add('google');
          if (stalledProvider == 'google') await stalled.future;
        },
      );
      final deletion = AccountDeletion(
        markPending: () async {},
        clearPending: () async => events.add('done'),
        wasRemoteDeleted: () async => false,
        markRemoteDeleted: () async {},
        deleteRemote: () async => events.add('remote'),
        revokeProviders: () async => revoked = await providers.revoke(),
        clearLocal: () async => events.add('clear'),
        signOut: () async => events.add('logout'),
      );

      // When
      final result = deletion.delete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));

      // Then
      expect(events, ['remote', 'kakao', 'google', 'clear', 'logout', 'done']);
      expect(revoked, isFalse);
      stalled.complete();
      await result;
    });
  }

  test('unconfigured providers never invoke native SDKs', () async {
    // Given
    final providers = AccountProviderRevocation();

    // When
    final revoked = await providers.revoke();

    // Then
    expect(revoked, isTrue);
  });
}
