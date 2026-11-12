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
Future<CompressedPhoto> compressForUpload(
  Uint8List source, {
  int quality = uploadJpegQuality,
}) async {
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
        quality: quality,
      ),
    );
    return (bytes: jpeg, width: width, height: height);
  } finally {
    image.dispose();
  }
}

/// Everything the photo upload needs from the network, injectable for tests.
abstract interface class PhotoTransport {
  Future<PhotoUploadTicket> createUpload(
    int byteSize, {
    UploadKind kind = UploadKind.original,
    UuidValue? originalId,
  });

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
  Future<PhotoUploadTicket> createUpload(
    int byteSize, {
    UploadKind kind = UploadKind.original,
    UuidValue? originalId,
  }) => client.photo.createUpload(
    'image/jpeg',
    byteSize,
    kind: kind.name,
    originalId: originalId,
  );

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

/// What was uploaded: the picked photo, or the saved picture with the
/// companion on it. Matches the server's `kind`.
enum UploadKind { original, composite }

/// The saved picture keeps more of its detail than the picked photo's copy.
const compositeJpegQuality = 90;

/// One upload's state. The picked photo and the saved composite each have
/// one, so starting the composite never cancels the original.
class _Job {
  _Job(this.kind);
  final UploadKind kind;
  UploadPhase phase = UploadPhase.idle;
  double progress = 0;
  String? error;
  CompressedPhoto? photo;
  PhotoUploadTicket? ticket;
  UuidValue? originalId;
  int generation = 0;
}

/// One entry of the uploaded strip: the composite in front when there is
/// one, together with the original it was made from.
typedef PhotoGroup = ({
  PhotoView main,
  PhotoView? original,
  List<PhotoView> members,
});

/// Groups [photos] (newest first) by original: a composite joins the
/// original it links to when that original is listed; anything else stands
/// alone. Groups keep the order of their newest member.
List<PhotoGroup> groupPhotos(List<PhotoView> photos) {
  final listed = {
    for (final p in photos)
      if (p.kind == UploadKind.original.name) p.photoId,
  };
  final groups = <UuidValue, List<PhotoView>>{};
  for (final photo in photos) {
    final link = photo.originalId;
    final key =
        photo.kind == UploadKind.composite.name &&
            link != null &&
            listed.contains(link)
        ? link
        : photo.photoId;
    (groups[key] ??= []).add(photo);
  }
  return [
    for (final members in groups.values)
      (
        main: members.firstWhere(
          (p) => p.kind == UploadKind.composite.name,
          orElse: () => members.first,
        ),
        original: members
            .where((p) => p.kind == UploadKind.original.name)
            .firstOrNull,
        members: members,
      ),
  ];
}

/// The picked photo's and the saved composite's trips to S3, and the
/// account's uploaded photos.
class PhotoUploader extends ChangeNotifier {
  PhotoUploader({
    required this.transport,
    required this.cache,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PhotoTransport transport;
  final PhotoCache cache;
  final DateTime Function() _now;

  final _original = _Job(UploadKind.original);
  final _composite = _Job(UploadKind.composite);

  /// The job the status line shows: the one started last.
  late _Job _current = _original;

  /// The current photo's original photoId once known: set when its upload
  /// is confirmed, null when it failed or was superseded.
  Completer<UuidValue?> _originalOutcome = Completer()..complete(null);
  bool _disposed = false;

  UploadPhase get phase => _current.phase;

  /// 0..1 while [UploadPhase.uploading].
  double get progress => _current.progress;
  String? get error => _current.error;
  UploadKind get kind => _current.kind;

  /// Uploaded photos, newest first; null until loaded.
  List<PhotoView>? photos;
  bool loadingPhotos = false;
  String? photosError;

  List<PhotoGroup> get groups => groupPhotos(photos ?? const []);

  bool get busy =>
      phase == UploadPhase.preparing ||
      phase == UploadPhase.uploading ||
      phase == UploadPhase.confirming;

  /// Starts uploading a newly picked photo; a later pick supersedes it and
  /// any composite of the previous photo.
  Future<void> upload(Uint8List picked) {
    _composite.generation++;
    _composite.phase = UploadPhase.idle;
    _resetOutcome();
    return _start(_original, picked, uploadJpegQuality);
  }

  /// Uploads the saved picture, linked to its original once that upload has
  /// finished (unlinked when it failed).
  Future<void> uploadComposite(Uint8List png) =>
      _start(_composite, png, compositeJpegQuality, waitForOriginal: true);

  /// The photo being edited is one already uploaded: its composite links to
  /// [photoId] (unlinked when null) and nothing is uploaded again.
  void adoptOriginal(UuidValue? photoId) {
    _original
      ..generation += 1
      ..phase = UploadPhase.idle
      ..photo = null
      ..ticket = null;
    _composite
      ..generation += 1
      ..phase = UploadPhase.idle;
    _current = _original;
    _resetOutcome();
    _originalOutcome.complete(photoId);
    _notify();
  }

  void _resetOutcome() {
    if (!_originalOutcome.isCompleted) _originalOutcome.complete(null);
    _originalOutcome = Completer();
  }

  Future<void> _start(
    _Job job,
    Uint8List source,
    int quality, {
    bool waitForOriginal = false,
  }) async {
    final generation = ++job.generation;
    job
      ..photo = null
      ..ticket = null
      ..originalId = null;
    _current = job;
    _set(job, UploadPhase.preparing);
    try {
      final photo = await compressForUpload(source, quality: quality);
      if (generation != job.generation) return;
      job.photo = photo;
      if (waitForOriginal) {
        job.originalId = await _originalOutcome.future;
        if (generation != job.generation) return;
      }
    } catch (_) {
      if (generation != job.generation) return;
      _fail(job, '사진을 올릴 준비를 하지 못했어요. 다시 시도해 주세요.');
      return;
    }
    await _send(job, generation);
  }

  /// Sends the failed upload's compressed photo again, reusing a ticket
  /// that has not expired yet.
  Future<void> retry() async {
    final job = _current;
    if (job.phase != UploadPhase.failed || job.photo == null) return;
    if (job == _original && _originalOutcome.isCompleted) {
      _originalOutcome = Completer();
    }
    await _send(job, ++job.generation);
  }

  Future<void> _send(_Job job, int generation) async {
    final photo = job.photo!;
    try {
      var ticket = job.ticket;
      // A minute of margin so the PUT never starts on a dying URL.
      if (ticket == null ||
          !ticket.expiresAt.isAfter(
            _now().toUtc().add(const Duration(minutes: 1)),
          )) {
        _set(job, UploadPhase.preparing);
        ticket = await transport.createUpload(
          photo.bytes.length,
          kind: job.kind,
          originalId: job.originalId,
        );
        if (generation != job.generation) return;
        job.ticket = ticket;
      }
      job.progress = 0;
      _set(job, UploadPhase.uploading);
      await transport.put(ticket, photo.bytes, (sent) {
        if (generation != job.generation) return;
        job.progress = sent / photo.bytes.length;
        _notify();
      });
      if (generation != job.generation) return;
      _set(job, UploadPhase.confirming);
      final view = await transport.confirm(
        ticket.photoId,
        photo.width,
        photo.height,
      );
      if (generation != job.generation) return;
      // The bytes are already here; the strip shows them without a GET.
      await cache.write(view.photoId, photo.bytes);
      photos = [view, ...?photos?.where((p) => p.photoId != view.photoId)];
      job
        ..photo = null
        ..ticket = null;
      if (job == _original && !_originalOutcome.isCompleted) {
        _originalOutcome.complete(view.photoId);
      }
      _set(job, UploadPhase.done);
    } catch (e) {
      if (generation != job.generation) return;
      if (e is PhotoException && e.code == 'invalidUpload') job.ticket = null;
      if (job == _original && !_originalOutcome.isCompleted) {
        _originalOutcome.complete(null);
      }
      _fail(job, _message(e));
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

  /// Deletes a strip entry: its composites first, then its original.
  Future<void> deleteGroup(PhotoGroup group) async {
    for (final photo in [
      ...group.members.where((p) => p.kind != UploadKind.original.name),
      ?group.original,
    ]) {
      await delete(photo.photoId);
    }
  }

  void _set(_Job job, UploadPhase value) {
    job.phase = value;
    if (value != UploadPhase.failed) job.error = null;
    _notify();
  }

  void _fail(_Job job, String message) {
    job
      ..error = message
      ..phase = UploadPhase.failed;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _original.generation++;
    _composite.generation++;
    if (!_originalOutcome.isCompleted) _originalOutcome.complete(null);
    transport.close();
    super.dispose();
  }
}
