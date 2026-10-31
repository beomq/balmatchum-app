import 'package:balmatchum_client/balmatchum_client.dart';

typedef ScopedClientFactory = Client Function(
  String host,
  Duration? connectionTimeout,
);

Client _defaultFactory(String host, Duration? connectionTimeout) =>
    Client(host, connectionTimeout: connectionTimeout);

/// Keeps one [Client] per auth header so its HTTP connection stays open
/// across requests. A new header retires the old client, which closes once
/// its in-flight requests finish.
class ScopedClientPool {
  ScopedClientPool({
    required this.host,
    this.connectionTimeout,
    this.factory = _defaultFactory,
  });

  final String host;
  final Duration? connectionTimeout;
  final ScopedClientFactory factory;
  _ScopedClient? _scoped;

  Future<T> run<T>(
    String header,
    ClientAuthKeyProvider Function(String) provider,
    Future<T> Function(Client) request,
  ) async {
    var scoped = _scoped;
    if (scoped == null || scoped.header != header) {
      scoped?.retire();
      scoped = _scoped = _ScopedClient(
        factory(host, connectionTimeout)..authKeyProvider = provider(header),
        header,
      );
    }
    scoped.active++;
    try {
      return await request(scoped.client);
    } finally {
      scoped.active--;
      if (scoped.retired) scoped.retire();
    }
  }

  void close() {
    _scoped?.retire();
    _scoped = null;
  }
}

class _ScopedClient {
  _ScopedClient(this.client, this.header);
  final Client client;
  final String header;
  int active = 0;
  bool retired = false;
  bool _closed = false;

  void retire() {
    retired = true;
    if (active > 0 || _closed) return;
    _closed = true;
    client.close();
  }
}
