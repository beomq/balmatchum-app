import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/billing/billing_repository.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/quiz/quiz_repository.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'billing_fakes.dart';
import 'billing_http_harness.dart';
import '../daily_activity/reward_panel_test.dart' show grant;
import '../quiz/authenticated_quiz_test.dart' show question;

class _Http extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final switchAccount in [false, true]) {
    test(
      'all premium and purchase requests share account queue; stale=$switchAccount',
      () async {
        await HttpOverrides.runWithHttpOverrides(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final entered = Completer<void>();
          final release = Completer<void>();
          final methods = <String>[];
          var inFlight = 0;
          var maximum = 0;
          server.listen((request) async {
            inFlight++;
            if (inFlight > maximum) maximum = inFlight;
            final method = request.uri.path.split('/').last;
            methods.add(method);
            expect(
              request.headers.value(HttpHeaders.authorizationHeader),
              'Bearer local-billing-fixture-1',
            );
            if (method == 'verifyPurchase') {
              entered.complete();
              await release.future;
            }
            final Object result = switch (method) {
              'getTodayWithPremium' => QuizToday(
                date: '2026-10-19',
                status: 'ready',
                extraStatus: 'premiumAvailable',
                extraRevision: 1,
                premiumStatus: 'active',
                paidEntitlement: true,
              ).toJson(),
              'unlockExtraWithPremium' => question(2).toJson(),
              'claimDayWithPremium' => grant(20).toJson(),
              _ => view(active: true).toJson(),
            };
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(result));
            inFlight--;
            await request.response.close();
          });
          final client = Client('http://127.0.0.1:${server.port}/')
            ..authSessionManager = FlutterAuthSessionManager(
              storage: BillingMemoryAuth(),
            );
          addTearDown(() async {
            client.close();
            await server.close(force: true);
          });
          await client.auth.updateSignedInUser(billingTestAuth('1'));
          final account = client.auth.authInfo!.authUserId.toString();
          final queue = BillingRequestQueue();
          final billing = ServerpodBillingRepository(client, account, queue);
          final product = ProductRepository(
            client,
            accountId: account,
            billing: billing,
          );
          final quiz = QuizRepository(client, account, billing: billing);
          final verify = billing.verify(
            PurchaseInput(
              store: 'google',
              productId: 'lifetime',
              purchaseReference: 'fixture',
            ),
          );
          final verified = switchAccount
              ? expectLater(verify, throwsStateError)
              : verify;
          await entered.future.timeout(const Duration(seconds: 5));
          final operations = <Future<Object>>[
            quiz.getTodayWithPremium(),
            product.entitlement(),
            product.claimWithPremium('2026-10-19', 'claim-id', 1),
            quiz.unlockExtraWithPremium('2026-10-19', 1, 'unlock-id'),
            billing.restore(
              PurchaseInput(
                store: 'google',
                productId: 'lifetime',
                purchaseReference: 'fixture',
              ),
            ),
          ];
          final assertions = [
            for (final operation in operations)
              switchAccount
                  ? expectLater(operation, throwsStateError)
                  : operation,
          ];
          if (switchAccount) {
            await client.auth.updateSignedInUser(billingTestAuth('2'));
            // A -> B -> A must not revive a captured session, even for queued work.
            await client.auth.updateSignedInUser(billingTestAuth('1'));
          }
          release.complete();
          await verified;
          await Future.wait(assertions);
          expect(maximum, 1);
          expect(
            methods,
            switchAccount
                ? ['verifyPurchase']
                : [
                    'verifyPurchase',
                    'getTodayWithPremium',
                    'getEntitlement',
                    'claimDayWithPremium',
                    'unlockExtraWithPremium',
                    'restorePurchase',
                  ],
          );
        }, _Http());
      },
    );
  }
}
