import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/quiz/quiz_repository.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../ads/ads_session_test.dart' show auth;
import 'authenticated_quiz_test.dart' show question;

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async {
    value = data;
  }
}

class _Http extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final method in [
    'getToday',
    'answer',
    'unlockExtra',
    'listHistory',
    'review',
  ]) {
    for (final switchAccount in [false, true]) {
      test(
        '$method captures auth and rejects late success: $switchAccount',
        () async {
          await HttpOverrides.runWithHttpOverrides(() async {
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            addTearDown(() => server.close(force: true));
            final arrived = Completer<HttpRequest>();
            server.listen(arrived.complete);
            final client = Client('http://127.0.0.1:${server.port}/')
              ..authSessionManager = FlutterAuthSessionManager(
                storage: _Storage(),
              );
            addTearDown(client.close);
            await client.auth.updateSignedInUser(auth('1'));
            final repository = QuizRepository(
              client,
              client.auth.authInfo!.authUserId.toString(),
            );
            final Future<Object> operation = switch (method) {
              'getToday' => repository.getToday(),
              'answer' => repository.answer(question(1), 1, 'same-request'),
              'unlockExtra' => repository.unlockExtra(
                '2026-10-19',
                1,
                'intent',
                'same-request',
              ),
              'listHistory' => repository.history(31),
              _ => repository.review(1),
            };
            final assertion = switchAccount
                ? expectLater(operation, throwsStateError)
                : null;
            final request = await arrived.future.timeout(
              const Duration(seconds: 5),
            );
            expect(
              request.headers.value(HttpHeaders.authorizationHeader),
              'Bearer test-token-1',
            );
            expect(request.uri.path, '/quiz/$method');
            final body = jsonDecode(
              await utf8.decoder.bind(request).join(),
            ) as Map<String, dynamic>;
            if (method == 'listHistory') expect(body['beforeAssignmentId'], 31);
            if (method == 'answer' || method == 'unlockExtra') {
              expect(body['requestId'], 'same-request');
            }
            if (switchAccount) await client.auth.updateSignedInUser(auth('2'));
            final result = switch (method) {
              'getToday' => QuizToday(
                premiumStatus: 'notChecked',
                date: '2026-10-19',
                status: 'ready',
                free: question(1),
                extraStatus: 'freeRequired',
              ).toJson(),
              'listHistory' => [question(1, answered: true).toJson()],
              _ => question(1, answered: true).toJson(),
            };
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(result));
            await request.response.close();
            if (assertion != null) {
              await assertion;
            } else {
              expect(await operation, isNotNull);
            }
            if (switchAccount) {
              await expectLater(repository.getToday(), throwsStateError);
            }
          }, _Http());
        },
      );
    }
  }
}
