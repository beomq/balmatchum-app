import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart'
    hide Protocol;

import 'billing_fakes.dart';

class BillingMemoryAuth implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async => value = data;
}

AuthSuccess billingTestAuth(String suffix) => AuthSuccess(
  authStrategy: 'session',
  token: 'local-billing-fixture-$suffix',
  authUserId: UuidValue.fromString(
    '00000000-0000-4000-8000-00000000000$suffix',
  ),
  scopeNames: {},
);

/// Real loopback HTTP and generated serialization, not a production verifier.
/// Fixture credentials are recognized only here; no external request is made.
class BillingHttpHarness {
  BillingHttpHarness._(this.server);
  final HttpServer server;
  final requests = <(String, String?, Map<String, dynamic>)>[];
  final arrivals = StreamController<String>.broadcast(sync: true);
  EntitlementView result = view();
  String? failure;
  Completer<void>? verificationGate;
  int inFlight = 0;
  int maximumInFlight = 0;

  static Future<BillingHttpHarness> start() async {
    final harness = BillingHttpHarness._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    harness.server.listen(harness._handle);
    return harness;
  }

  Future<void> _handle(HttpRequest request) async {
    final method = request.uri.path.split('/').last;
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    final payload = jsonDecode(
      await utf8.decoder.bind(request).join(),
    ) as Map<String, dynamic>;
    requests.add((method, header, payload));
    inFlight++;
    if (inFlight > maximumInFlight) maximumInFlight = inFlight;
    final gate = verificationGate;
    arrivals.add(method);
    try {
      if (method == 'verifyPurchase' || method == 'restorePurchase') {
        if (gate != null) await gate.future;
      }
      request.response.headers.contentType = ContentType.json;
      if (header != 'Bearer local-billing-fixture-1' &&
          header != 'Bearer local-billing-fixture-2') {
        request.response.statusCode = 401;
      } else if (failure != null) {
        // Use the generated protocol wrapper, not a hand-written exception DTO.
        request.response.statusCode = 400;
        request.response.write(
          Protocol().encodeWithType(BillingException(code: failure!)),
        );
      } else {
        request.response.write(
          jsonEncode(
            method == 'getPurchaseConfiguration'
                ? config(
                    store: payload['store'] as String,
                    binding: header!.endsWith('-1') ? bindingA : bindingB,
                  ).toJson()
                : result.toJson(),
          ),
        );
      }
    } finally {
      inFlight--;
      await request.response.close();
    }
  }

  Client client() => Client('http://127.0.0.1:${server.port}/')
    ..authSessionManager = FlutterAuthSessionManager(
      storage: BillingMemoryAuth(),
    );

  Future<void> close() async {
    await server.close(force: true);
    await arrivals.close();
  }
}
