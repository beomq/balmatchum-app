import 'dart:async';

import 'package:flutter/services.dart';

import '../auth/kakao_auth_service.dart';
import 'watch_bridge.dart';
import 'watch_contract.dart';
import 'watch_sync_server.dart';

/// One queue orders native changes, session writes, enumeration and uploads.
/// Epoch invalidation happens synchronously, before a queued logout can run.
class WatchSyncService {
  WatchSyncService({required this.bridge, required this.server});

  final WatchBridge bridge;
  final WatchSyncServer server;
  Future<void> _tail = Future<void>.value();
  StreamSubscription<void>? _events;
  int _epoch = 0;
  String? _account;
  WatchContext? _context;
  JsonObject? _steps;
  bool _changingAuthentication = false;
  bool _disposed = false;
  String? lastError;

  void _recordError(Object error) {
    lastError = switch (error) {
      FormatException() => 'invalidData',
      MissingPluginException() => 'capabilityUnavailable',
      PlatformException() => 'nativeError',
      StateError() => 'authenticationRequired',
      _ => 'syncFailed',
    };
  }

  bool get isActive => _context != null && _account == server.accountId;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _tail.then((_) {
      if (_disposed) throw StateError('Watch sync disposed');
      return action();
    });
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _recordError(error);
      },
    );
    return result;
  }

  void _invalidate() {
    _epoch++;
    _account = null;
    _context = null;
    _steps = null;
  }

  bool _current(int epoch, String account) =>
      !_disposed && epoch == _epoch && account == server.accountId;

  /// Local-only startup reconciliation. Never validates or uploads on restore.
  Future<void> initialize() async {
    await clearContext();
    _events ??= bridge.inboxChanges.listen(
      (_) {
        final epoch = _epoch;
        _background(
          _enqueue(() async {
            final account = _account;
            if (account != null && _current(epoch, account)) {
              await _sync(epoch, account);
            }
          }),
        );
      },
      onError: (Object error) {
        _recordError(error);
      },
    );
  }

  void _background(Future<void> operation) {
    unawaited(
      operation.catchError((Object error) {
        _recordError(error);
      }),
    );
  }

  /// Called by the auth adapter on identity changes outside our session writes.
  void authenticationChanged() {
    if (!_changingAuthentication) _background(clearContext());
  }

  /// Explicit user action: persisted credentials are not proof of a session.
  Future<void> resumeAndSync() {
    final epoch = _epoch;
    return _enqueue(() async {
      final account = server.accountId;
      if (account == null) {
        _invalidate();
        await bridge.clearContext();
        throw StateError('Watch sync requires authentication');
      }
      if (!_current(epoch, account)) throw StateError('Watch account changed');
      try {
        final valid = await server.validateAuthentication();
        if (!_current(epoch, account)) {
          throw StateError('Watch account changed');
        }
        if (!valid) throw StateError('Watch session validation failed');
        await _activate(epoch, account);
        await _sync(epoch, account);
        if (!_current(epoch, account)) {
          throw StateError('Watch account changed');
        }
        lastError = null;
      } catch (_) {
        if (_current(epoch, account)) {
          _invalidate();
          await bridge.clearContext();
        }
        rethrow;
      }
    });
  }

  Future<void> _activate(int epoch, String account) async {
    final context = await bridge.activateContext(account);
    if (!_current(epoch, account)) return;
    _account = account;
    _context = context;
    await _publish(epoch, account);
  }

  Future<void> _publish(int epoch, String account) async {
    final context = _context;
    if (context == null || !_current(epoch, account)) return;
    final revision = context.displayRevision + 1;
    await bridge.publishDisplaySnapshot(
      DisplaySnapshot.fromJson({
        'schemaVersion': 1,
        'contextId': context.contextId,
        'revision': revision,
        'authState': 'authenticated',
        'selectedDog': null,
        'dailySteps': _steps,
      }),
    );
    if (_current(epoch, account)) {
      _context = WatchContext(
        context.contextId,
        context.boundaryRevision,
        revision,
      );
    }
  }

  Future<void> _sync(int epoch, String account) async {
    final context = _context;
    if (context == null || !_current(epoch, account)) return;
    final records = await bridge.listPendingRecords();
    for (final record in records) {
      if (!_current(epoch, account)) return;
      if (record.contextId != context.contextId) {
        throw const FormatException('Native inbox returned another context');
      }
      final input = watchRecordInput(record);
      final receipt = await server.saveConfirmed(account, input);
      validateWatchReceipt(input, receipt);
      // A stale receipt remains safely retryable under its original account.
      // Never ACK it through the newly active account or advance its display.
      if (!_current(epoch, account)) return;
      await bridge.acknowledgeServerReceipt(context.contextId, receipt);
    }
  }

  /// Clears Watch eligibility, not the server session. Retains native queues.
  Future<void> clearContext() {
    _invalidate();
    return _enqueue(bridge.clearContext);
  }

  /// User initiated only. Failure statuses stay null in the display snapshot.
  Future<DailyStepsResult> requestDailySteps() {
    final epoch = _epoch;
    return _enqueue(() async {
      final result = await bridge.requestDailySteps();
      final account = _account;
      if (account != null && _current(epoch, account)) {
        _steps = result.dailySteps;
        await _publish(epoch, account);
      }
      return result;
    });
  }

  /// Only the real login adapter calls this after obtaining AuthSuccess.
  Future<void> saveAuthenticatedSession(Future<void> Function() save) {
    _invalidate();
    final epoch = _epoch;
    return _enqueue(() async {
      // Native failure must not masquerade as failed credential persistence.
      var cleared = false;
      try {
        await bridge.clearContext();
        cleared = true;
      } catch (error) {
        _recordError(error);
      }
      _changingAuthentication = true;
      try {
        await save();
      } finally {
        _changingAuthentication = false;
      }
      final account = server.accountId;
      if (cleared && account != null && _current(epoch, account)) {
        try {
          await _activate(epoch, account);
        } catch (error) {
          _invalidate();
          _recordError(error);
          try {
            await bridge.clearContext();
          } catch (clearError) {
            _recordError(clearError);
          }
        }
      }
    });
  }

  /// Logout clears Watch even if server revocation or local persistence fails.
  Future<SessionLogoutOutcome> logoutSession(
    Future<SessionLogoutOutcome> Function() logout,
  ) {
    _invalidate();
    return _enqueue(() async {
      try {
        await bridge.clearContext();
      } catch (error) {
        _recordError(error);
      }
      _changingAuthentication = true;
      try {
        return await logout();
      } finally {
        _changingAuthentication = false;
      }
    });
  }

  Future<void> dispose() async {
    _invalidate();
    _disposed = true;
    await _events?.cancel();
  }
}
