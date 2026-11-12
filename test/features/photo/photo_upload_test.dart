import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:balmatchum_app/features/photo/photo_upload.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A one-colour PNG of [width] x [height].
Future<Uint8List> pngOf(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF336699), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return data.buffer.asUint8List();
}

/// A server and bucket in memory. Each step can be made to fail once.
class FakePhotoTransport implements PhotoTransport {
  FakePhotoTransport({DateTime Function()? now}) : now = now ?? DateTime.now;
  final DateTime Function() now;
  final tickets = <PhotoUploadTicket>[];
  final puts = <(PhotoUploadTicket, Uint8List)>[];
  final bucket = <String, Uint8List>{};
  final views = <PhotoView>[];
  final downloads = <String>[];
  int lists = 0;
  bool closed = false;
  Object? putFailure;
  Object? confirmFailure;
  Object? listFailure;

  /// Holds the next PUT (only that one) until completed; [putStarted]
  /// completes when it begins.
  Completer<void>? putGate;
  Completer<void>? putStarted;

  /// What each ticket was reserved as, for confirm and assertions.
  final reserved = <UuidValue, (UploadKind, UuidValue?)>{};

  @override
  Future<PhotoUploadTicket> createUpload(
    int byteSize, {
    UploadKind kind = UploadKind.original,
    UuidValue? originalId,
  }) async {
    final ticket = PhotoUploadTicket(
      photoId: const Uuid().v7obj(),
      uploadUrl: 'https://bucket.test/put/${tickets.length}',
      method: 'PUT',
      headers: {'Content-Type': 'image/jpeg', 'Content-Length': '$byteSize'},
      expiresAt: now().toUtc().add(const Duration(minutes: 5)),
    );
    tickets.add(ticket);
    reserved[ticket.photoId] = (kind, originalId);
    return ticket;
  }

  @override
  Future<void> put(
    PhotoUploadTicket ticket,
    Uint8List bytes,
    void Function(int sent) onProgress,
  ) async {
    puts.add((ticket, bytes));
    onProgress(bytes.length ~/ 2);
    final gate = putGate;
    putGate = null;
    putStarted?.complete();
    putStarted = null;
    await gate?.future;
    if (putFailure case final failure?) {
      putFailure = null;
      throw failure;
    }
    expect(ticket.headers['Content-Length'], '${bytes.length}');
    bucket[ticket.photoId.uuid] = bytes;
    onProgress(bytes.length);
  }

  PhotoView view(UuidValue id, {int? width, int? height, DateTime? expires}) =>
      PhotoView(
        photoId: id,
        kind: (reserved[id]?.$1 ?? UploadKind.original).name,
        originalId: reserved[id]?.$2,
        contentType: 'image/jpeg',
        byteSize: bucket[id.uuid]?.length ?? 1,
        width: width,
        height: height,
        createdAt: now().toUtc(),
        url: 'https://bucket.test/get/${id.uuid}/$lists',
        urlExpiresAt: expires ?? now().toUtc().add(const Duration(minutes: 10)),
      );

  @override
  Future<PhotoView> confirm(UuidValue photoId, int width, int height) async {
    if (confirmFailure case final failure?) {
      confirmFailure = null;
      throw failure;
    }
    if (!bucket.containsKey(photoId.uuid)) {
      throw PhotoException(code: 'notUploaded');
    }
    final result = view(photoId, width: width, height: height);
    views.insert(0, result);
    return result;
  }

  @override
  Future<List<PhotoView>> list() async {
    lists++;
    if (listFailure case final failure?) {
      listFailure = null;
      throw failure;
    }
    return [for (final v in views) view(v.photoId)];
  }

  @override
  Future<void> delete(UuidValue photoId) async {
    bucket.remove(photoId.uuid);
    views.removeWhere((v) => v.photoId == photoId);
  }

  @override
  Future<Uint8List> download(String url) async {
    downloads.add(url);
    final id = url.split('/')[4];
    return bucket[id] ?? (throw const PhotoHttpException(404));
  }

  @override
  void close() => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the upload copy is a JPEG at most 1600 px on its longest side',
    () async {
      for (final (w, h, ew, eh) in [
        (3200, 2000, 1600, 1000),
        (900, 2400, 600, 1600),
        (800, 600, 800, 600),
      ]) {
        final copy = await compressForUpload(await pngOf(w, h));
        expect((copy.width, copy.height), (ew, eh), reason: '$w x $h');
        final decoded = img.decodeJpg(copy.bytes)!;
        expect((decoded.width, decoded.height), (ew, eh));
        // JPEG SOI marker.
        expect(copy.bytes.sublist(0, 2), [0xFF, 0xD8]);
      }
    },
  );

  test('ticket, signed PUT with progress, then confirm', () async {
    final transport = FakePhotoTransport();
    final cache = PhotoCache();
    final uploader = PhotoUploader(transport: transport, cache: cache);
    final progress = <double>[];
    uploader.addListener(() {
      if (uploader.phase == UploadPhase.uploading) {
        progress.add(uploader.progress);
      }
    });
    await uploader.upload(await pngOf(2000, 1000));
    expect(uploader.phase, UploadPhase.done);
    final ticket = transport.tickets.single;
    final (sentTicket, bytes) = transport.puts.single;
    expect(sentTicket, same(ticket));
    expect(ticket.headers['Content-Length'], '${bytes.length}');
    expect(progress.last, 1.0);
    expect(progress, contains(lessThan(1.0)));
    final view = uploader.photos!.single;
    expect((view.width, view.height), (1600, 800));
    // The strip shows the bytes just sent, without a GET.
    expect(await uploader.bytesOf(view), bytes);
    expect(transport.downloads, isEmpty);
  });

  test('a failed PUT keeps the photo and retries on the same ticket', () async {
    final transport = FakePhotoTransport()
      ..putFailure = const SocketException('offline');
    final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
    await uploader.upload(await pngOf(10, 10));
    expect(uploader.phase, UploadPhase.failed);
    expect(uploader.error, isNotNull);
    expect(uploader.photos, isNull);
    await uploader.retry();
    expect(uploader.phase, UploadPhase.done);
    expect(transport.tickets, hasLength(1));
    expect(transport.puts, hasLength(2));
    expect(uploader.photos, hasLength(1));
  });

  test(
    'confirm failures are retryable; an expired ticket is replaced',
    () async {
      var clock = DateTime.utc(2026, 11, 12, 9);
      final transport = FakePhotoTransport(now: () => clock)
        ..confirmFailure = PhotoException(code: 'storageUnavailable');
      final uploader = PhotoUploader(
        transport: transport,
        cache: PhotoCache(),
        now: () => clock,
      );
      await uploader.upload(await pngOf(10, 10));
      expect(uploader.phase, UploadPhase.failed);
      // Past the ticket's expiry (minus the one-minute margin).
      clock = clock.add(const Duration(minutes: 4, seconds: 30));
      await uploader.retry();
      expect(uploader.phase, UploadPhase.done);
      expect(transport.tickets, hasLength(2));
      expect(transport.puts.last.$1, same(transport.tickets.last));
    },
  );

  test('notUploaded from confirm shows a failure with retry', () async {
    final transport = FakePhotoTransport()
      ..confirmFailure = PhotoException(code: 'notUploaded');
    final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
    await uploader.upload(await pngOf(10, 10));
    expect(uploader.phase, UploadPhase.failed);
    await uploader.retry();
    expect(uploader.phase, UploadPhase.done);
  });

  test('a newer pick supersedes an upload still in flight', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final transport = FakePhotoTransport()
      ..putGate = gate
      ..putStarted = started;
    final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
    final firstPhoto = await pngOf(10, 10);
    final secondPhoto = await pngOf(20, 20);
    final first = uploader.upload(firstPhoto);
    await started.future.timeout(const Duration(seconds: 10));
    await uploader.upload(secondPhoto);
    expect(uploader.phase, UploadPhase.done);
    // Release the first PUT; its late result must change nothing.
    gate.complete();
    await first;
    expect(uploader.phase, UploadPhase.done);
    expect(uploader.photos!.map((p) => p.photoId), [
      transport.tickets.last.photoId,
    ]);
    expect(transport.views, hasLength(1), reason: 'first never confirmed');
  });

  test('photos load by id from cache; expired URLs are listed again', () async {
    var clock = DateTime.utc(2026, 11, 12, 9);
    final transport = FakePhotoTransport(now: () => clock);
    final seeded = PhotoUploader(transport: transport, cache: PhotoCache());
    await seeded.upload(await pngOf(10, 10));
    final id = seeded.photos!.single.photoId;

    final uploader = PhotoUploader(
      transport: transport,
      cache: PhotoCache(),
      now: () => clock,
    );
    await uploader.loadPhotos();
    final listed = uploader.photos!.single;
    final first = await uploader.bytesOf(listed);
    expect(first, transport.bucket[id.uuid]);
    expect(await uploader.bytesOf(listed), first);
    expect(transport.downloads, hasLength(1), reason: 'second read is cached');

    final cold = PhotoUploader(
      transport: transport,
      cache: PhotoCache(),
      now: () => clock,
    );
    await cold.loadPhotos();
    final stale = cold.photos!.single;
    clock = clock.add(const Duration(minutes: 11));
    final lists = transport.lists;
    await cold.bytesOf(stale);
    expect(transport.lists, lists + 1);
    expect(transport.downloads.last, isNot(stale.url));
  });

  test('a failed listing says so and can be retried', () async {
    final transport = FakePhotoTransport()
      ..listFailure = const SocketException('offline');
    final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
    await uploader.loadPhotos();
    expect(uploader.photos, isNull);
    expect(uploader.photosError, isNotNull);
    await uploader.loadPhotos();
    expect(uploader.photos, isEmpty);
    expect(uploader.photosError, isNull);
  });

  test('delete removes the photo and evicts its cached bytes', () async {
    final dir = await Directory.systemTemp.createTemp('photo-cache-');
    addTearDown(() => dir.delete(recursive: true));
    final transport = FakePhotoTransport();
    final cache = PhotoCache(directory: () async => dir);
    final uploader = PhotoUploader(transport: transport, cache: cache);
    await uploader.upload(await pngOf(10, 10));
    final id = uploader.photos!.single.photoId;
    expect(File('${dir.path}/${id.uuid}.jpg').existsSync(), isTrue);
    // A fresh cache over the same directory reads it from disk.
    expect(await PhotoCache(directory: () async => dir).read(id), isNotNull);
    await uploader.delete(id);
    expect(uploader.photos, isEmpty);
    expect(await cache.read(id), isNull);
    expect(File('${dir.path}/${id.uuid}.jpg').existsSync(), isFalse);
    expect(transport.bucket, isEmpty);
  });

  group('composite', () {
    PhotoView photo(String id, String kind, [String? original]) => PhotoView(
      photoId: UuidValue.fromString(id),
      kind: kind,
      originalId: original == null ? null : UuidValue.fromString(original),
      contentType: 'image/jpeg',
      byteSize: 1,
      createdAt: DateTime.utc(2026),
      url: 'https://bucket.test/get/$id/0',
      urlExpiresAt: DateTime.utc(2100),
    );
    const o1 = '00000000-0000-7000-8000-000000000001';
    const c1 = '00000000-0000-7000-8000-000000000002';
    const o2 = '00000000-0000-7000-8000-000000000003';
    const c3 = '00000000-0000-7000-8000-000000000004';
    const gone = '00000000-0000-7000-8000-000000000009';

    test(
      'the strip pairs a composite with its original and shows it first',
      () {
        final groups = groupPhotos([
          photo(c3, 'composite', gone),
          photo(o2, 'original'),
          photo(c1, 'composite', o1),
          photo(o1, 'original'),
        ]);
        expect(groups.map((g) => (g.main.photoId.uuid, g.members.length)), [
          (c3, 1),
          (o2, 1),
          (c1, 2),
        ]);
        expect(groups.last.original!.photoId.uuid, o1);
        // A composite whose original is not listed stands alone.
        expect(groups.first.original, isNull);
      },
    );

    test('a saved picture uploads linked to its finished original', () async {
      final transport = FakePhotoTransport();
      final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
      await uploader.upload(await pngOf(40, 30));
      final original = uploader.photos!.single.photoId;
      await uploader.uploadComposite(await pngOf(40, 30));
      expect(uploader.kind, UploadKind.composite);
      expect(uploader.phase, UploadPhase.done);
      final (kind, link) = transport.reserved[transport.tickets.last.photoId]!;
      expect((kind, link), (UploadKind.composite, original));
      expect(uploader.groups.single.main.kind, 'composite');
      expect(uploader.groups.single.members, hasLength(2));
    });

    test('a saved picture waits for an original still uploading', () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final transport = FakePhotoTransport()
        ..putGate = gate
        ..putStarted = started;
      final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
      final original = uploader.upload(await pngOf(40, 30));
      await started.future.timeout(const Duration(seconds: 10));
      final composite = uploader.uploadComposite(await pngOf(40, 30));
      gate.complete();
      await original;
      await composite;
      final link = transport.reserved[transport.tickets.last.photoId]!.$2;
      expect(link, transport.tickets.first.photoId);
    });

    test('a failed original leaves the saved picture unlinked', () async {
      final transport = FakePhotoTransport()
        ..putFailure = const SocketException('offline');
      final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
      await uploader.upload(await pngOf(40, 30));
      await uploader.uploadComposite(await pngOf(40, 30));
      expect(uploader.phase, UploadPhase.done);
      expect(transport.reserved[transport.tickets.last.photoId]!.$2, isNull);
    });

    test('a reopened uploaded photo links without uploading again', () async {
      final transport = FakePhotoTransport();
      final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
      final id = UuidValue.fromString(o1);
      uploader.adoptOriginal(id);
      await uploader.uploadComposite(await pngOf(40, 30));
      expect(transport.tickets, hasLength(1));
      expect(transport.reserved[transport.tickets.single.photoId], (
        UploadKind.composite,
        id,
      ));
    });

    test('a failed saved picture retries on its own ticket', () async {
      final transport = FakePhotoTransport();
      final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
      await uploader.upload(await pngOf(40, 30));
      transport.putFailure = const SocketException('offline');
      await uploader.uploadComposite(await pngOf(40, 30));
      expect(
        (uploader.kind, uploader.phase),
        (UploadKind.composite, UploadPhase.failed),
      );
      await uploader.retry();
      expect(uploader.phase, UploadPhase.done);
      expect(transport.tickets, hasLength(2), reason: 'one per photo');
    });

    test(
      'deleting an entry removes the saved picture and its original',
      () async {
        final transport = FakePhotoTransport();
        final uploader = PhotoUploader(
          transport: transport,
          cache: PhotoCache(),
        );
        await uploader.upload(await pngOf(40, 30));
        await uploader.uploadComposite(await pngOf(40, 30));
        await uploader.deleteGroup(uploader.groups.single);
        expect(uploader.photos, isEmpty);
        expect(transport.bucket, isEmpty);
      },
    );
  });

  test('disposing closes the transport', () {
    final transport = FakePhotoTransport();
    PhotoUploader(transport: transport, cache: PhotoCache()).dispose();
    expect(transport.closed, isTrue);
  });
}
