import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'dev_test_session.dart';
import '../billing/billing_repository.dart';
import 'scoped_client.dart';

/// The generated client is the only transport contract.
class ProductRepository {
  ProductRepository(this.client, {this.accountId, this.billing});
  final Client client;
  final String? accountId;
  final ServerpodBillingRepository? billing;

  Future<EntitlementView> entitlement() => billing!.entitlement();

  Future<RewardGrant> claimWithPremium(
    String date,
    String requestId,
    int revision,
  ) => billing!.request(
    (c) => c.product.claimDayWithPremium(date, requestId, revision),
  );

  late final ScopedClientPool pool = ScopedClientPool(
    host: client.host,
    connectionTimeout: client.connectionTimeout,
  );

  Future<T> _records<T>(Future<T> Function(Client) request) async {
    if (accountId == null) return request(client);
    final authentication = client.auth.authInfo;
    if (authentication?.authUserId.toString() != accountId) {
      throw StateError('Record account changed');
    }
    final header = await client.auth.authHeaderValue;
    if (!identical(authentication, client.auth.authInfo) || header == null) {
      throw StateError('Record authentication changed');
    }
    // One pooled client per auth header; see [ScopedClientPool].
    return pool.run(header, _RecordAuthHeader.new, (scoped) async {
      final result = await request(scoped);
      if (!identical(authentication, client.auth.authInfo)) {
        throw StateError('Record authentication changed');
      }
      return result;
    });
  }

  void close() {
    pool.close();
  }

  Future<void> connectDevelopmentUser() async {
    if (await importDevTestSession(client)) return;
    await client.auth.restore();
    if (!client.auth.isAuthenticated ||
        !await client.modules.serverpod_auth_core.status.isSignedIn()) {
      throw const FormatException('Development test session required');
    }
  }

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime get today =>
      DateTime.now().toUtc().add(const Duration(hours: 9));

  Future<DailyRecord> day(DateTime date) =>
      _records((client) => client.product.getDay(dateKey(date)));

  Future<List<DailyRecord>> month(DateTime month) => _records(
    (client) => client.product.listDays(
      dateKey(DateTime(month.year, month.month)),
      dateKey(DateTime(month.year, month.month + 1, 0)),
    ),
  );

  /// Days [from] through [to], KST, in one request (the server allows 93).
  Future<List<DailyRecord>> days(DateTime from, DateTime to) =>
      _records((client) => client.product.listDays(dateKey(from), dateKey(to)));

  Future<WalletView> wallet() =>
      _records((client) => client.product.getWallet());

  Future<DailyRecord> deleteDay(DateTime date, String requestId) =>
      _records((client) => client.product.deleteDay(dateKey(date), requestId));

  Future<RewardGrant> claim(String date, String requestId, int revision) =>
      _records((client) => client.product.claimDay(date, requestId, revision));

  Future<RewardGrant> claimWithAd(
    String date,
    String requestId,
    int revision,
    String intentId,
  ) => _records(
    (client) =>
        client.product.claimDayWithAd(date, requestId, revision, intentId),
  );

  Future<DailyQuiz> quiz(DateTime date) =>
      client.product.getQuiz(dateKey(date));

  Future<DailyQuiz> answer(String date, int answerIndex, String requestId) =>
      client.product.answerQuiz(date, answerIndex, requestId);

  Future<ThemeStore> themes() =>
      _records((client) => client.product.listThemes());

  Future<ThemeStore> purchase(String themeId, String requestId) =>
      _records((client) => client.product.purchaseTheme(themeId, requestId));

  Future<ThemeStore> equip(String themeId, String requestId) =>
      _records((client) => client.product.equipTheme(themeId, requestId));

  Future<OutfitStore> outfits() =>
      _records((client) => client.product.listOutfits());

  Future<OutfitStore> purchaseOutfit(String outfitId, String requestId) =>
      _records((client) => client.product.purchaseOutfit(outfitId, requestId));

  Future<OutfitStore> equipOutfit(String outfitId, String requestId) =>
      _records((client) => client.product.equipOutfit(outfitId, requestId));

  Future<OutfitStore> unequipOutfit(String requestId) =>
      _records((client) => client.product.unequipOutfit(requestId));
}

class _RecordAuthHeader implements ClientAuthKeyProvider {
  _RecordAuthHeader(this.header);
  final String header;
  @override
  Future<String?> get authHeaderValue async => header;
}
