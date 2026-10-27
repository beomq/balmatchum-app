import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart';

import 'ads_sdk.dart';

abstract interface class AdsServer {
  Future<AdIntent> create(String purpose, String date, int revision);
  Future<AdIntent> get(String id);
  bool get isCurrent;
  void close();
}

enum AdsStatus {
  idle,
  preparing,
  creating,
  loading,
  showing,
  checking,
  missingConfiguration,
  consentRequired,
  failed,
  cancelled,
  pending,
  verified,
  consumed,
  expired,
}

/// Verification is not an entitlement. No economic mutation exists in this class.
class AdsController extends ChangeNotifier {
  AdsController({required this.server, required this.sdk});
  final AdsServer server;
  final AdsSdk sdk;
  AdsStatus status = AdsStatus.idle;
  AdIntent? intent;
  bool clientRewardObserved = false;
  bool _disposed = false;
  int _operation = 0;
  RewardedPlacement? _ad;
  bool get busy => switch (status) {
    AdsStatus.preparing ||
    AdsStatus.creating ||
    AdsStatus.loading ||
    AdsStatus.showing ||
    AdsStatus.checking => true,
    _ => false,
  };
  bool get canRefresh =>
      intent != null &&
      !busy &&
      status != AdsStatus.cancelled &&
      status != AdsStatus.expired &&
      status != AdsStatus.verified &&
      status != AdsStatus.consumed;

  void _set(AdsStatus next) {
    if (_disposed) return;
    status = next;
    notifyListeners();
  }

  bool _active(int operation) {
    if (_disposed || operation != _operation) return false;
    if (!server.isCurrent) {
      cancel();
      return false;
    }
    return true;
  }

  Future<void> start({
    required String purpose,
    required String targetDate,
    required int targetRevision,
  }) async {
    if (busy || _disposed || status == AdsStatus.cancelled) return;
    // Existing intents are reconciled, never silently replayed or replaced.
    if (intent != null) {
      await refresh();
      return;
    }
    final operation = ++_operation;
    clientRewardObserved = false;
    try {
      if (!_active(operation)) return;
      _set(AdsStatus.preparing);
      final setup = await sdk.prepare();
      if (!_active(operation)) return;
      if (setup != AdsSetup.ready) {
        _set(switch (setup) {
          AdsSetup.missingConfiguration => AdsStatus.missingConfiguration,
          AdsSetup.consentRequired => AdsStatus.consentRequired,
          _ => AdsStatus.failed,
        });
        return;
      }
      _set(AdsStatus.creating);
      final created = await server.create(purpose, targetDate, targetRevision);
      if (!_active(operation)) return;
      intent = created;
      if (created.status != 'pending') {
        _serverStatus(created);
        return;
      }
      _set(AdsStatus.loading);
      final loaded = await sdk.load(created.adUnit);
      if (!_active(operation)) {
        await loaded.dispose();
        return;
      }
      _ad = loaded;
      await loaded.setVerification(created.userId, created.customData);
      if (!_active(operation)) return;
      _set(AdsStatus.showing);
      var finished = false;
      await loaded.show(
        onReward: () {
          if (_active(operation) && !finished) {
            clientRewardObserved = true;
            // This signal never writes status, grants, or calls a completion API.
          }
        },
        onDismiss: () {
          if (!_active(operation) || finished) return;
          finished = true;
          unawaited(_dismiss(operation));
        },
        onFailure: () {
          if (!_active(operation) || finished) return;
          finished = true;
          unawaited(_release());
          _set(AdsStatus.failed);
        },
      );
    } on AdException catch (error) {
      if (_active(operation)) {
        await _release();
        if (_active(operation)) {
          _set(
            error.code == 'configurationMissing'
                ? AdsStatus.missingConfiguration
                : AdsStatus.failed,
          );
        }
      }
    } catch (_) {
      if (_active(operation)) {
        await _release();
        if (_active(operation)) _set(AdsStatus.failed);
      }
    }
  }

  Future<void> _dismiss(int operation) async {
    _set(AdsStatus.checking);
    await _release();
    if (_active(operation)) await _check(operation);
  }

  Future<void> _check(int operation) async {
    try {
      final updated = await server.get(intent!.id);
      if (!_active(operation)) return;
      intent = updated;
      _serverStatus(updated);
    } catch (_) {
      if (_active(operation)) _set(AdsStatus.failed);
    }
  }

  void _serverStatus(AdIntent value) => _set(switch (value.status) {
    'pending' => AdsStatus.pending,
    'verified' => AdsStatus.verified,
    'consumed' => AdsStatus.consumed,
    'expired' => AdsStatus.expired,
    _ => AdsStatus.failed,
  });

  Future<void> refresh() async {
    if (!canRefresh) return;
    final operation = ++_operation;
    if (!_active(operation)) return;
    _set(AdsStatus.checking);
    await _check(operation);
  }

  /// Explicit retry after a load/show failure reuses the same idempotent target.
  Future<void> retry({
    required String purpose,
    required String targetDate,
    required int targetRevision,
  }) async {
    if (busy || status == AdsStatus.cancelled || _disposed) return;
    if (intent != null) {
      await refresh();
      if (status != AdsStatus.pending) return;
      intent = null;
    }
    await start(
      purpose: purpose,
      targetDate: targetDate,
      targetRevision: targetRevision,
    );
  }

  Future<void> _release() async {
    final ad = _ad;
    _ad = null;
    await ad?.dispose();
  }

  void cancel() {
    if (_disposed) return;
    ++_operation;
    unawaited(_release());
    _set(AdsStatus.cancelled);
  }

  @override
  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    server.close();
    super.dispose();
  }
}
