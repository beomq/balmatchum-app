import 'package:balmatchum_app/features/daily_activity/dev_test_session.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remote server cannot import a local development credential', () async {
    final client = Client('https://example.com/');
    addTearDown(client.close);
    expect(await importDevTestSession(client), isFalse);
  });
}
