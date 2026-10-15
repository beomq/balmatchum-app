import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'dev_test_session.dart';

/// The generated client is the only transport contract.
class ProductRepository {
  ProductRepository(this.client);
  final Client client;

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
      client.product.getDay(dateKey(date));

  Future<List<DailyRecord>> month(DateTime month) => client.product.listDays(
    dateKey(DateTime(month.year, month.month)),
    dateKey(DateTime(month.year, month.month + 1, 0)),
  );

  Future<WalletView> wallet() => client.product.getWallet();

  Future<DailyRecord> deleteDay(DateTime date, String requestId) =>
      client.product.deleteDay(dateKey(date), requestId);

  Future<RewardGrant> claim(DailyRecord day, String requestId) =>
      client.product.claimDay(day.date, requestId, day.revision);

  Future<DailyQuiz> quiz(DateTime date) =>
      client.product.getQuiz(dateKey(date));

  Future<DailyQuiz> answer(String date, int answerIndex, String requestId) =>
      client.product.answerQuiz(date, answerIndex, requestId);

  Future<ThemeStore> themes() => client.product.listThemes();

  Future<ThemeStore> purchase(String themeId, String requestId) =>
      client.product.purchaseTheme(themeId, requestId);

  Future<ThemeStore> equip(String themeId, String requestId) =>
      client.product.equipTheme(themeId, requestId);
}
