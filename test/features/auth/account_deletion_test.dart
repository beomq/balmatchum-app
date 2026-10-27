import 'package:balmatchum_app/features/auth/account_deletion.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('revokes providers after confirmed deletion before cleanup', () async {
    // Given
    final events = <String>[];
    final deletion = AccountDeletion(
      markPending: () async {},
      clearPending: () async {},
      wasRemoteDeleted: () async => false,
      markRemoteDeleted: () async => events.add('persist'),
      deleteRemote: () async => events.add('remote'),
      revokeProviders: () async => events.add('revoke'),
      clearLocal: () async => events.add('clear'),
      signOut: () async => events.add('logout'),
    );

    // When
    await deletion.delete();

    // Then
    expect(events, ['remote', 'persist', 'revoke', 'clear', 'logout']);
  });

  test('revocation Error still clears device and signs out', () async {
    // Given
    final events = <String>[];
    final deletion = AccountDeletion(
      markPending: () async {},
      clearPending: () async => events.add('done'),
      wasRemoteDeleted: () async => false,
      markRemoteDeleted: () async {},
      deleteRemote: () async => events.add('remote'),
      revokeProviders: () async => throw StateError('sdk bug'),
      clearLocal: () async => events.add('clear'),
      signOut: () async => events.add('logout'),
    );

    // When
    final result = deletion.delete();

    // Then
    await expectLater(result, throwsStateError);
    expect(events, ['remote', 'clear', 'logout', 'done']);
  });

  test(
    'resumed deletion revokes providers without another server call',
    () async {
      // Given
      final events = <String>[];
      final deletion = AccountDeletion(
        markPending: () async {},
        clearPending: () async {},
        wasRemoteDeleted: () async => true,
        markRemoteDeleted: () async {},
        deleteRemote: () async => events.add('remote'),
        revokeProviders: () async => events.add('revoke'),
        clearLocal: () async => events.add('clear'),
        signOut: () async => events.add('logout'),
      );

      // When
      await deletion.delete();

      // Then
      expect(events, ['revoke', 'clear', 'logout']);
    },
  );

  test(
    'new instance resumes persisted remote deletion before sign-out',
    () async {
      var deleted = false;
      var pending = false;
      var fail = true;
      var remoteCalls = 0;
      var signOutCalls = 0;
      AccountDeletion create() => AccountDeletion(
        markPending: () async => pending = true,
        clearPending: () async => pending = false,
        wasRemoteDeleted: () async => deleted,
        markRemoteDeleted: () async => deleted = true,
        deleteRemote: () async => remoteCalls++,
        revokeProviders: () async {},
        clearLocal: () async {
          if (fail) throw Exception('disk unavailable');
        },
        signOut: () async => signOutCalls++,
      );
      await expectLater(create().delete(), throwsException);
      expect(pending, isTrue);
      expect(deleted, isTrue);
      fail = false;
      await create().delete();
      expect(remoteCalls, 1);
      expect(signOutCalls, 1);
      expect(pending, isFalse);
    },
  );

  test(
    'revoked session cleans device without claiming remote deletion',
    () async {
      final events = <String>[];
      final deletion = AccountDeletion(
        markPending: () async {},
        clearPending: () async {},
        wasRemoteDeleted: () async => false,
        markRemoteDeleted: () async {},
        deleteRemote: () async => throw ServerpodClientUnauthorized(),
        revokeProviders: () async => events.add('revoke'),
        clearLocal: () async => events.add('clear'),
        signOut: () async => events.add('logout'),
      );
      await expectLater(
        deletion.delete(),
        throwsA(isA<ServerpodClientUnauthorized>()),
      );
      expect(events, ['clear', 'logout']);
    },
  );

  test(
    'uncertain remote failure preserves local data and authentication',
    () async {
      final events = <String>[];
      final deletion = AccountDeletion(
        markPending: () async {},
        clearPending: () async {},
        wasRemoteDeleted: () async => false,
        markRemoteDeleted: () async {},
        deleteRemote: () async => throw Exception('offline'),
        revokeProviders: () async => events.add('revoke'),
        clearLocal: () async => events.add('clear'),
        signOut: () async => events.add('logout'),
      );
      await expectLater(deletion.delete(), throwsException);
      expect(events, isEmpty);
    },
  );

  test(
    'cleanup retry does not delete an already deleted remote account',
    () async {
      final events = <String>[];
      var fail = true;
      final deletion = AccountDeletion(
        markPending: () async {},
        clearPending: () async {},
        wasRemoteDeleted: () async => false,
        markRemoteDeleted: () async {},
        deleteRemote: () async => events.add('remote'),
        revokeProviders: () async {},
        clearLocal: () async {
          if (fail) throw Exception('disk');
          events.add('clear');
        },
        signOut: () async => events.add('logout'),
      );
      await expectLater(deletion.delete(), throwsException);
      fail = false;
      await deletion.delete();
      expect(events, ['remote', 'clear', 'logout']);
    },
  );
}
