import 'package:balmatchum_client/balmatchum_client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Usage: fvm dart run tool/check_connection.dart <URL>');
  }
  final client = Client(
    args.single,
    connectionTimeout: const Duration(seconds: 10),
  );
  try {
    final greeting = await client.greeting.hello('Balmatchum');
    if (greeting.message != 'Hello Balmatchum') {
      throw StateError('Unexpected greeting: ${greeting.message}');
    }
    print(greeting.toJson());
  } finally {
    client.close();
  }
}
