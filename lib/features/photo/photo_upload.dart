import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// The upload copy: longest side at most [uploadMaxSide] px, JPEG [quality].
const uploadMaxSide = 1600;
const uploadJpegQuality = 80;

typedef CompressedPhoto = ({Uint8List bytes, int width, int height});

/// Decodes on the engine at the target size, then encodes the JPEG on a
/// background isolate so the editor keeps its frame rate.
Future<CompressedPhoto> compressForUpload(Uint8List source) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(source);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      final ratio = math.min(1.0, uploadMaxSide / math.max(width, height));
      return ui.TargetImageSize(
        width: math.max(1, (width * ratio).round()),
        height: math.max(1, (height * ratio).round()),
      );
    },
  );
  final ui.Image image;
  try {
    image = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
  try {
    final width = image.width;
    final height = image.height;
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    final jpeg = await Isolate.run(
      () => img.encodeJpg(
        img.Image.fromBytes(
          width: width,
          height: height,
          bytes: rgba.buffer,
          numChannels: 4,
        ),
        quality: uploadJpegQuality,
      ),
    );
    return (bytes: jpeg, width: width, height: height);
  } finally {
    image.dispose();
  }
}

/// Everything the photo upload needs from the network, injectable for tests.
abstract interface class PhotoTransport {
  Future<PhotoUploadTicket> createUpload(int byteSize);

  /// PUTs [bytes] with exactly the ticket's signed headers, reporting the
  /// bytes written so far.
  Future<void> put(
    PhotoUploadTicket ticket,
    Uint8List bytes,
    void Function(int sent) onProgress,
  );

  Future<PhotoView> confirm(UuidValue photoId, int width, int height);
  Future<List<PhotoView>> list();
  Future<void> delete(UuidValue photoId);
  Future<Uint8List> download(String url);
  void close();
}

/// The signed-in photo screen's uploader: the account's client and a disk
/// cache under Application Support, one directory per account.
PhotoUploader accountPhotoUploader(Client client, String accountId) =>
    PhotoUploader(
      transport: ServerpodPhotoTransport(client),
      cache: PhotoCache(
        directory: () async => Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '/photo-cache/$accountId',
        ),
      ),
    );

/// Thrown when S3 answers a PUT or GET with something other than success.
class PhotoHttpException implements Exception {
  const PhotoHttpException(this.status);
  final int status;
  @override
  String toString() => 'S3 HTTP $status';
}

/// The generated client for the endpoint and dart:io for the signed URLs.
class ServerpodPhotoTransport implements PhotoTransport {
  ServerpodPhotoTransport(this.client, {HttpClient? http})
    : _http = http ?? HttpClient();
  final Client client;
  final HttpClient _http;

  /// Bytes per write, so progress moves while a slow link sends.
  static const _chunk = 64 * 1024;

  @override
  Future<PhotoUploadTicket> createUpload(int byteSize) =>
      client.photo.createUpload('image/jpeg', byteSize);

  @override
  Future<void> put(
    PhotoUploadTicket ticket,
    Uint8List bytes,
    void Function(int sent) onProgress,
  ) async {
    // The URL is used exactly as signed; Uri.parse keeps its encoding.
    final request = await _http.openUrl(
      ticket.method,
      Uri.parse(ticket.uploadUrl),
    );
    for (final MapEntry(:key, :value) in ticket.headers.entries) {
      if (key.toLowerCase() == 'content-length') {
        request.contentLength = int.parse(value);
      } else {
        request.headers.set(key, value, preserveHeaderCase: true);
      }
    }
    var sent = 0;
    for (var start = 0; start < bytes.length; start += _chunk) {
      final end = math.min(start + _chunk, bytes.length);
      request.add(Uint8List.sublistView(bytes, start, end));
      await request.flush();
      sent = end;
      onProgress(sent);
    }
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != 200) {
      throw PhotoHttpException(response.statusCode);
    }
  }

  @override
  Future<PhotoView> confirm(UuidValue photoId, int width, int height) =>
      client.photo.confirmUpload(photoId, width, height);

  @override
  Future<List<PhotoView>> list() => client.photo.listMine();

  @override
  Future<void> delete(UuidValue photoId) => client.photo.deletePhoto(photoId);

  @override
  Future<Uint8List> download(String url) async {
    final request = await _http.getUrl(Uri.parse(url));
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    if (response.statusCode != 200) {
      throw PhotoHttpException(response.statusCode);
    }
    return builder.takeBytes();
  }

  @override
  void close() => _http.close(force: true);
}

/// Photo bytes by photo id, in memory and, when [directory] is given, on
/// disk. Presigned URLs change on every listing, so they are never a key.
class PhotoCache {
  PhotoCache({this.directory});
  final Future<Directory> Function()? directory;
  final _memory = <String, Uint8List>{};

  Future<File?> _file(UuidValue id) async {
    final dir = await directory?.call();
    return dir == null ? null : File('${dir.path}/${id.uuid}.jpg');
  }

  Future<Uint8List?> read(UuidValue id) async {
    final hit = _memory[id.uuid];
    if (hit != null) return hit;
    final file = await _file(id);
    if (file == null || !await file.exists()) return null;
    return _memory[id.uuid] = await file.readAsBytes();
  }

  Future<void> write(UuidValue id, Uint8List bytes) async {
    _memory[id.uuid] = bytes;
    final file = await _file(id);
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> evict(UuidValue id) async {
    _memory.remove(id.uuid);
    final file = await _file(id);
    if (file != null && await file.exists()) await file.delete();
  }
}

enum UploadPhase { idle, preparing, uploading, confirming, done, failed }

/// The latest picked photo's trip to S3 and the account's uploaded photos.
class PhotoUploader extends ChangeNotifier {
  PhotoUploader({
    required this.transport,
    required this.cache,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PhotoTransport transport;
  final PhotoCache cache;
  final DateTime Function() _now;

  UploadPhase phase = UploadPhase.idle;

  /// 0..1 while [UploadPhase.uploading].
  double progress = 0;
  String? error;

  CompressedPhoto? _photo;
  PhotoUploadTicket? _ticket;
  int _generation = 0;
  bool _disposed = false;

  /// Uploaded photos, newest first; null until loaded.
  List<PhotoView>? photos;
  bool loadingPhotos = false;
  String? photosError;

  bool get busy =>
      phase == UploadPhase.preparing ||
      phase == UploadPhase.uploading ||
      phase == UploadPhase.confirming;

  /// Starts uploading a newly picked photo; a later pick supersedes it.
  Future<void> upload(Uint8List picked) async {
    final generation = ++_generation;
    _photo = null;
    _ticket = null;
    _set(UploadPhase.preparing);
    try {
      final photo = await compressForUpload(picked);
      if (generation != _generation) return;
      _photo = photo;
    } catch (_) {
      if (generation != _generation) return;
      _fail('사진을 올릴 준비를 하지 못했어요. 다시 시도해 주세요.');
      return;
    }
    await _send(generation);
  }

  /// Sends the same compressed photo again, reusing a ticket that has not
  /// expired yet.
  Future<void> retry() async {
    if (phase != UploadPhase.failed || _photo == null) return;
    await _send(++_generation);
  }

  Future<void> _send(int generation) async {
    final photo = _photo!;
    try {
      var ticket = _ticket;
      // A minute of margin so the PUT never starts on a dying URL.
      if (ticket == null ||
          !ticket.expiresAt.isAfter(
            _now().toUtc().add(const Duration(minutes: 1)),
          )) {
        _set(UploadPhase.preparing);
        ticket = await transport.createUpload(photo.bytes.length);
        if (generation != _generation) return;
        _ticket = ticket;
      }
      progress = 0;
      _set(UploadPhase.uploading);
      await transport.put(ticket, photo.bytes, (sent) {
        if (generation != _generation) return;
        progress = sent / photo.bytes.length;
        _notify();
      });
      if (generation != _generation) return;
      _set(UploadPhase.confirming);
      final view = await transport.confirm(
        ticket.photoId,
        photo.width,
        photo.height,
      );
      if (generation != _generation) return;
      // The bytes are already here; the strip shows them without a GET.
      await cache.write(view.photoId, photo.bytes);
      photos = [view, ...?photos?.where((p) => p.photoId != view.photoId)];
      _photo = null;
      _ticket = null;
      _set(UploadPhase.done);
    } catch (e) {
      if (generation != _generation) return;
      if (e is PhotoException && e.code == 'invalidUpload') _ticket = null;
      _fail(_message(e));
    }
  }

  String _message(Object e) => switch (e) {
    PhotoException(code: 'notConfigured') => '지금은 사진을 올릴 수 없어요.',
    PhotoException(code: 'quotaExceeded') =>
      '올릴 수 있는 사진 수를 넘었어요. 올린 사진을 지운 뒤 다시 시도해 주세요.',
    PhotoException(code: 'tooManyPending') => '잠시 후 다시 시도해 주세요.',
    _ => '사진을 올리지 못했어요. 다시 시도해 주세요.',
  };

  /// Lists the uploaded photos; URLs are short-lived, so a listing older
  /// than its first URL is refreshed.
  Future<void> loadPhotos() async {
    if (loadingPhotos) return;
    loadingPhotos = true;
    photosError = null;
    _notify();
    try {
      photos = await transport.list();
    } catch (_) {
      photosError = '올린 사진을 불러오지 못했어요.';
    } finally {
      loadingPhotos = false;
      _notify();
    }
  }

  /// Cached bytes, else a GET through the photo's signed URL (relisting
  /// first when it has expired).
  Future<Uint8List> bytesOf(PhotoView photo) async {
    final cached = await cache.read(photo.photoId);
    if (cached != null) return cached;
    var current = photo;
    if (!current.urlExpiresAt.isAfter(_now().toUtc())) {
      await loadPhotos();
      current =
          photos?.firstWhere(
            (p) => p.photoId == photo.photoId,
            orElse: () => photo,
          ) ??
          photo;
    }
    final bytes = await transport.download(current.url);
    await cache.write(photo.photoId, bytes);
    return bytes;
  }

  /// Deletes on the server first; the photo leaves the list only after.
  Future<void> delete(UuidValue photoId) async {
    await transport.delete(photoId);
    await cache.evict(photoId);
    photos = photos?.where((p) => p.photoId != photoId).toList();
    _notify();
  }

  void _set(UploadPhase value) {
    phase = value;
    if (value != UploadPhase.failed) error = null;
    _notify();
  }

  void _fail(String message) {
    error = message;
    phase = UploadPhase.failed;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    transport.close();
    super.dispose();
  }
}
