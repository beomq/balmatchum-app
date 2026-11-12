import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../app/duo_rail.dart';
import '../first_meeting/meeting_theme.dart';
import '../first_meeting/onboarding_widgets.dart' show wrapByWords;
import '../first_meeting/particles.dart';
import '../records/product_page.dart';
import '../wardrobe/dog_sprite.dart';
import 'photo_editor.dart';
import 'photo_upload.dart';

export 'photo_editor.dart'
    show PhotoAdapter, PhotoFailure, PhotoSource, PhotoShareResult;

class PhotoScreen extends StatefulWidget {
  const PhotoScreen({
    required this.dogAssetPath,
    required this.dogName,
    required this.adapter,
    required this.onBack,
    required this.onHome,
    this.createUploader,
    super.key,
  });
  final String dogAssetPath;
  final String dogName;
  final PhotoAdapter adapter;
  final VoidCallback onBack;
  final VoidCallback onHome;

  /// Signed-in screens back picked photos up to S3; the screen owns the
  /// uploader it makes. Without it nothing leaves the device.
  final PhotoUploader Function()? createUploader;

  @override
  State<PhotoScreen> createState() => PhotoScreenState();
}

/// What VoiceOver and TalkBack offer on the canvas in place of the removed
/// position, size and angle sliders (guide 7.4-6). Each one is one step.
abstract final class PhotoCanvasActions {
  static const left = CustomSemanticsAction(label: '왼쪽으로 옮기기');
  static const right = CustomSemanticsAction(label: '오른쪽으로 옮기기');
  static const up = CustomSemanticsAction(label: '위로 옮기기');
  static const down = CustomSemanticsAction(label: '아래로 옮기기');
  static const bigger = CustomSemanticsAction(label: '크게');
  static const smaller = CustomSemanticsAction(label: '작게');
  static const turnLeft = CustomSemanticsAction(label: '왼쪽으로 돌리기');
  static const turnRight = CustomSemanticsAction(label: '오른쪽으로 돌리기');

  /// A move is 5% of the photo, a size step 10%, a turn 15°.
  static const move = .05;
  static const grow = 1.1;
  static const turn = math.pi / 12;
}

/// Where a photo of [photo] pixels is drawn in [area]: whole, centred and
/// never stretched, so the screen and the saved PNG show the same picture.
Rect photoRect(Size photo, Rect area) => Alignment.center.inscribe(
  applyBoxFit(BoxFit.contain, photo, area.size).destination,
  area,
);

class PhotoScreenState extends State<PhotoScreen> {
  late final PhotoEditor editor;
  late final PhotoUploader? uploader;
  DogSticker? _gestureStart;
  Offset? _focalStart;
  bool leaving = false;

  /// What the last pick asked for, so its retry asks the same.
  PhotoSource source = PhotoSource.gallery;

  @override
  void initState() {
    super.initState();
    editor = PhotoEditor(
      adapter: widget.adapter,
      dogAssetPath: widget.dogAssetPath,
    );
    editor.addListener(_invalidateBusyGesture);
    editor.initialize();
    uploader = widget.createUploader?.call();
    uploader?.loadPhotos();
  }

  void _clearGesture() {
    _gestureStart = null;
    _focalStart = null;
  }

  void _invalidateBusyGesture() {
    if (editor.busy) _clearGesture();
  }

  @override
  void dispose() {
    editor.removeListener(_invalidateBusyGesture);
    editor.dispose();
    uploader?.dispose();
    super.dispose();
  }

  Future<void> leave(VoidCallback action) async {
    if (editor.busy) return;
    if (editor.photo != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('사진 편집을 나갈까요?'),
          content: const Text('저장하지 않은 편집 내용은 사라져요. 원본 사진은 그대로예요.'),
          actionsOverflowButtonSpacing: 8,
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 편집'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('나가기'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  /// A newly picked photo also starts its upload; editing never waits.
  Future<void> pick(PhotoSource value) async {
    source = value;
    final before = editor.photo;
    await editor.pick(value);
    final bytes = editor.pickedBytes;
    if (!mounted || bytes == null || identical(editor.photo, before)) return;
    uploader?.upload(bytes);
  }

  /// Saves to the gallery, then backs the saved picture up as a composite
  /// of the photo being edited.
  Future<void> _save() async {
    await editor.save();
    final png = editor.savedPng;
    if (!mounted || png == null) return;
    uploader?.uploadComposite(png);
  }

  /// Opens an uploaded entry to arrange again: its original when there is
  /// one, so a new save links to it; nothing is uploaded again.
  Future<void> _openUploaded(PhotoGroup group) async {
    final source = uploader;
    if (source == null || editor.busy) return;
    try {
      await editor.open(await source.bytesOf(group.original ?? group.main));
      source.adoptOriginal(group.original?.photoId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진을 불러오지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _deleteUploaded(PhotoGroup group) async {
    final source = uploader;
    if (source == null) return;
    final pair = group.members.length > 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('올린 사진을 지울까요?'),
        content: Text(
          pair
              ? '고른 사진과 꾸민 사진이 함께 지워져요. 기기 앨범의 사진은 그대로예요.'
              : '서버에 보관한 사진이 지워져요. 기기 앨범의 사진은 그대로예요.',
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('photo_upload_delete_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await source.deleteGroup(group);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진을 지우지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  /// The uploaded photos on the start screen: loading, empty, failure with
  /// a retry, or a row of thumbnails (tap to arrange, long-press to delete).
  Widget _uploads(PhotoUploader source) {
    final photos = source.photos;
    final groups = source.groups;
    final Widget content;
    if (photos == null && source.photosError != null) {
      content = Row(
        children: [
          Expanded(
            child: Text(
              source.photosError!,
              key: const ValueKey('photo_uploads_error'),
              style: meetingType(13, 18, FontWeight.w600, MeetingColors.error),
            ),
          ),
          TextButton(
            key: const ValueKey('photo_uploads_retry'),
            onPressed: source.loadingPhotos ? null : source.loadPhotos,
            child: const Text('다시 불러오기'),
          ),
        ],
      );
    } else if (photos == null) {
      content = const SizedBox(
        height: _Thumb.size,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              key: ValueKey('photo_uploads_loading'),
              strokeWidth: 2,
            ),
          ),
        ),
      );
    } else if (photos.isEmpty) {
      content = Text(
        '사진을 고르면 여기에 보관돼요.',
        key: const ValueKey('photo_uploads_empty'),
        style: meetingType(13, 18, FontWeight.w500, MeetingColors.muted),
      );
    } else {
      content = SizedBox(
        height: _Thumb.size,
        child: ListView.separated(
          key: const ValueKey('photo_uploads_list'),
          scrollDirection: Axis.horizontal,
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.s2),
          itemBuilder: (context, index) {
            // The saved picture is the entry's face when there is one.
            final group = groups[index];
            return _Thumb(
              key: ValueKey('photo_upload_${group.main.photoId.uuid}'),
              load: () => source.bytesOf(group.main),
              onTap: editor.busy ? null : () => _openUploaded(group),
              onLongPress: () => _deleteUploaded(group),
            );
          },
        ),
      );
    }
    return Column(
      key: const ValueKey('photo_uploads'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s2,
      children: [
        Text(
          groups.isEmpty ? '올린 사진' : '올린 사진 ${groups.length}',
          style: meetingType(15, 20, FontWeight.w800),
        ),
        content,
      ],
    );
  }

  /// Under the canvas: the picked photo's upload, then the saved picture's.
  /// Editing never waits on either; a failure keeps the photo and offers
  /// the same upload again.
  Widget? _uploadStatus(PhotoUploader source) {
    final what = source.kind == UploadKind.composite ? '꾸민 사진' : '사진';
    final (String label, Color color) = switch (source.phase) {
      UploadPhase.idle => ('', MeetingColors.muted),
      UploadPhase.preparing => (
        '${withEul(what)} 보관할 준비 중이에요',
        MeetingColors.muted,
      ),
      UploadPhase.uploading => (
        '$what 보관 중 ${(source.progress * 100).round()}%',
        MeetingColors.muted,
      ),
      UploadPhase.confirming => ('거의 다 됐어요', MeetingColors.muted),
      UploadPhase.done => (
        source.kind == UploadKind.composite ? '꾸민 사진도 보관했어요' : '사진을 안전하게 보관했어요',
        MeetingColors.primaryStrong,
      ),
      UploadPhase.failed => (source.error ?? '', MeetingColors.error),
    };
    if (source.phase == UploadPhase.idle) return null;
    return Semantics(
      liveRegion:
          source.phase == UploadPhase.done ||
          source.phase == UploadPhase.failed,
      child: Column(
        key: const ValueKey('photo_upload_status'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s2,
        children: [
          Row(
            spacing: Space.s2,
            children: [
              Expanded(
                child: Text(
                  label,
                  key: const ValueKey('photo_upload_label'),
                  style: meetingType(13, 18, FontWeight.w700, color),
                ),
              ),
              if (source.phase == UploadPhase.failed)
                TextButton(
                  key: const ValueKey('photo_upload_retry'),
                  onPressed: source.retry,
                  child: const Text('다시 올리기'),
                ),
            ],
          ),
          if (source.busy)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                key: const ValueKey('photo_upload_progress'),
                minHeight: 4,
                value: source.phase == UploadPhase.uploading
                    ? source.progress
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  /// One accessibility step; the new place is read back at once.
  void _step(DogSticker Function(DogSticker) change) {
    if (editor.busy || editor.photo == null) return;
    editor.edit(change(editor.sticker));
    SemanticsService.sendAnnouncement(
      View.of(context),
      _stickerValue(editor.sticker),
      Directionality.of(context),
    );
  }

  /// PHOTO-01 (Pen `opawe`): a worked example of the result, one pick and
  /// nothing to save or edit yet. A cancelled pick stays here; only a
  /// picked photo moves on.
  Widget _start({required bool rail}) {
    final name = widget.dogName;
    final failed = editor.isError && editor.message != null;
    final headline = '사진 위에 ${withEul(name)} 올려 한 장 남겨요';
    final body = '앨범에서 사진을 고르면 ${withEul(name)} 옮기고 크기를 바꿀 수 있어요.';
    final title = ProductTitle(
      '${withWa(name)} 한 장',
      textAlign: rail ? TextAlign.start : TextAlign.center,
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        final gutter = math.max(
          pageGutter(bounds.maxWidth),
          (bounds.maxWidth - 600) / 2,
        );
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(gutter, Space.s2, gutter, Space.s6),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, bounds.maxHeight - Space.s2 - Space.s6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 48,
                      child: rail
                          ? Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: title,
                            )
                          : Row(
                              children: [
                                IconButton(
                                  key: const ValueKey('photo_back'),
                                  tooltip: '뒤로',
                                  onPressed: editor.busy
                                      ? null
                                      : () => leave(widget.onBack),
                                  icon: const PixelIcon('back'),
                                ),
                                Expanded(child: title),
                                IconButton(
                                  key: const ValueKey('photo_home'),
                                  tooltip: '홈',
                                  onPressed: editor.busy
                                      ? null
                                      : () => leave(widget.onHome),
                                  icon: const PixelIcon('home'),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 14),
                    // Short or wide screens shrink the example so the
                    // pick stays in view; it never stretches.
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.max(220, bounds.maxHeight - 310),
                        ),
                        child: _Example(dogAssetPath: widget.dogAssetPath),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      wrapByWords(headline),
                      key: const ValueKey('photo_start_title'),
                      semanticsLabel: headline,
                      textAlign: TextAlign.center,
                      style: meetingType(19, 26, FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      wrapByWords(body),
                      semanticsLabel: body,
                      textAlign: TextAlign.center,
                      style: meetingType(
                        14,
                        21,
                        FontWeight.w500,
                        MeetingColors.muted,
                      ),
                    ),
                    // Permission and read failures stay on this screen with
                    // the adapter's own guidance and a retry (guide 7.3-4).
                    if (failed) ...[
                      const SizedBox(height: Space.s4),
                      ProductPanel(
                        key: const ValueKey('photo_pick_error'),
                        color: ProductColors.warningSoft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: Space.s3,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                editor.message!,
                                key: const ValueKey('photo_status'),
                                style: const TextStyle(
                                  color: MeetingColors.error,
                                ),
                              ),
                            ),
                            OutlinedButton(
                              key: const ValueKey('photo_pick_retry'),
                              onPressed: editor.busy
                                  ? null
                                  : () => pick(source),
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (editor.dog == null && !editor.busy) ...[
                      const SizedBox(height: Space.s3),
                      _retryDog(),
                    ],
                    if (uploader case final source?) ...[
                      const SizedBox(height: Space.s5),
                      _uploads(source),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: Space.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.s1,
                    children: [
                      FilledButton(
                        key: const ValueKey('photo_gallery'),
                        // Pen `Photo Pick`: the one primary action, 52 pt.
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: editor.busy
                            ? null
                            : () => pick(PhotoSource.gallery),
                        child: const Text('앨범에서 사진 고르기'),
                      ),
                      // Not in Pen: the existing camera pick stays as text.
                      TextButton(
                        key: const ValueKey('photo_camera'),
                        onPressed: editor.busy
                            ? null
                            : () => pick(PhotoSource.camera),
                        child: const Text('카메라로 찍기'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _retryDog() => OutlinedButton(
    key: const ValueKey('photo_retry'),
    onPressed: editor.initialize,
    child: const Text('강아지 다시 불러오기'),
  );

  /// PHOTO-02 (Pen `rov6I`): actions on top, the canvas in all the height
  /// left and the tools below. With the Duo rail the rail takes the way
  /// out and the bar keeps the title and save. PHOTO-03 (Pen `PGjdt`) is
  /// the same frame once the save succeeded: no selection, no edits, and
  /// the share there.
  Widget _editor({required bool rail}) {
    final sticker = editor.sticker;
    final message = editor.message;
    final savedView = editor.phase == PhotoPhase.saved;
    return LayoutBuilder(
      builder: (context, bounds) {
        final gutter = math.max(
          pageGutter(bounds.maxWidth),
          (bounds.maxWidth - 600) / 2,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: rail ? gutter : Space.s2,
                  end: gutter,
                ),
                child: Row(
                  spacing: Space.s2,
                  children: [
                    if (!rail)
                      IconButton(
                        key: const ValueKey('photo_back'),
                        tooltip: '닫기',
                        onPressed: editor.busy
                            ? null
                            : () => leave(widget.onBack),
                        icon: const PixelIcon('close-x', size: 24),
                      ),
                    Expanded(
                      child: ProductTitle(
                        '사진 꾸미기',
                        textAlign: rail ? TextAlign.start : TextAlign.center,
                      ),
                    ),
                    // A saved arrangement is not saved again; a change
                    // since then makes it savable.
                    FilledButton(
                      key: const ValueKey('photo_save'),
                      style: editor.saved ? _savedPill : _pill,
                      onPressed: editor.canExport && !editor.saved
                          ? _save
                          : null,
                      child: Text(editor.saved ? '저장됨' : '저장'),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 2,
              child: editor.busy
                  ? const LinearProgressIndicator(
                      key: ValueKey('photo_busy'),
                      minHeight: 2,
                    )
                  : null,
            ),
            Expanded(child: _canvas(editable: !savedView)),
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, Space.s3, gutter, Space.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s3,
                children: [
                  if (message != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        key: const ValueKey('photo_status'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: editor.isError
                              ? MeetingColors.error
                              : MeetingColors.ink,
                        ),
                      ),
                    ),
                  if (editor.dog == null && !editor.busy) _retryDog(),
                  if (uploader case final source?) ?_uploadStatus(source),
                  if (savedView)
                    Row(
                      spacing: 10,
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const ValueKey('photo_reedit'),
                            onPressed: editor.busy ? null : editor.reedit,
                            child: const Text('다시 꾸미기'),
                          ),
                        ),
                        // The share sheet anchors to this button.
                        Expanded(
                          child: Builder(
                            builder: (context) => FilledButton(
                              key: const ValueKey('photo_share'),
                              onPressed: editor.busy
                                  ? null
                                  : () {
                                      final box =
                                          context.findRenderObject()!
                                              as RenderBox;
                                      editor.share(
                                        box.localToGlobal(Offset.zero) &
                                            box.size,
                                      );
                                    },
                              child: const Text('공유하기'),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      spacing: 10,
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const ValueKey('photo_flip'),
                            onPressed: editor.busy
                                ? null
                                : () => editor.edit(
                                    sticker.copyWith(flipped: !sticker.flipped),
                                  ),
                            child: Text(sticker.flipped ? '좌우 반전 해제' : '좌우 반전'),
                          ),
                        ),
                        Expanded(
                          child: OutlinedButton(
                            key: const ValueKey('photo_reset'),
                            onPressed: editor.busy
                                ? null
                                : () => editor.edit(const DogSticker()),
                            child: const Text('처음으로'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// The photo as it will be saved, with the selection drawn over it while
  /// [editable]. The pointer moves the companion by fractions of the drawn
  /// photo, not of the canvas around it. The saved view shows the same
  /// composite with nothing over it but its notice.
  Widget _canvas({required bool editable}) => LayoutBuilder(
    builder: (context, bounds) {
      final photo = editor.photo!;
      final dog = editor.dog;
      final sticker = editor.sticker;
      final rect = photoRect(
        Size(photo.width.toDouble(), photo.height.toDouble()),
        Offset.zero & bounds.biggest,
      );
      final selection = dog == null
          ? null
          : sticker
                .rect(
                  rect.size,
                  Size(dog.width.toDouble(), dog.height.toDouble()),
                )
                .shift(rect.topLeft);
      void step(DogSticker Function(DogSticker) change) => _step(change);
      return Semantics(
        label: '${widget.dogName} 사진 편집',
        value: _stickerValue(sticker),
        hint: editable ? '끌어서 옮기고 두 손가락으로 크기와 각도를 바꿔요' : null,
        customSemanticsActions: dog == null || !editable
            ? null
            : {
                PhotoCanvasActions.left: () =>
                    step((s) => s.copyWith(x: s.x - PhotoCanvasActions.move)),
                PhotoCanvasActions.right: () =>
                    step((s) => s.copyWith(x: s.x + PhotoCanvasActions.move)),
                PhotoCanvasActions.up: () =>
                    step((s) => s.copyWith(y: s.y - PhotoCanvasActions.move)),
                PhotoCanvasActions.down: () =>
                    step((s) => s.copyWith(y: s.y + PhotoCanvasActions.move)),
                PhotoCanvasActions.bigger: () => step(
                  (s) => s.copyWith(scale: s.scale * PhotoCanvasActions.grow),
                ),
                PhotoCanvasActions.smaller: () => step(
                  (s) => s.copyWith(scale: s.scale / PhotoCanvasActions.grow),
                ),
                PhotoCanvasActions.turnLeft: () => step(
                  (s) => s.copyWith(
                    rotation: s.rotation - PhotoCanvasActions.turn,
                  ),
                ),
                PhotoCanvasActions.turnRight: () => step(
                  (s) => s.copyWith(
                    rotation: s.rotation + PhotoCanvasActions.turn,
                  ),
                ),
              },
        child: GestureDetector(
          key: const ValueKey('photo_canvas'),
          behavior: HitTestBehavior.opaque,
          onScaleStart: !editable
              ? null
              : (details) {
                  if (editor.busy) return;
                  _gestureStart = editor.sticker;
                  _focalStart = details.localFocalPoint;
                },
          onScaleUpdate: !editable
              ? null
              : (details) {
                  final start = _gestureStart;
                  final focalStart = _focalStart;
                  if (editor.busy || start == null || focalStart == null) {
                    return;
                  }
                  final delta = details.localFocalPoint - focalStart;
                  editor.edit(
                    start.copyWith(
                      x: start.x + delta.dx / rect.width,
                      y: start.y + delta.dy / rect.height,
                      scale: start.scale * details.scale,
                      rotation: start.rotation + details.rotation,
                    ),
                  );
                },
          onScaleEnd: !editable ? null : (_) => _clearGesture(),
          child: ColoredBox(
            color: MeetingColors.pressed,
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRect(
                    child: CustomPaint(
                      key: const ValueKey('photo_preview'),
                      painter: _PhotoPainter(photo, dog, sticker),
                      size: rect.size,
                    ),
                  ),
                ),
                if (editable && selection != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: PhotoSelectionOverlay(
                        rect: selection,
                        rotation: sticker.rotation,
                      ),
                    ),
                  ),
                Positioned(
                  top: Space.s4,
                  left: Space.s4,
                  right: Space.s4,
                  child: Center(
                    child: editable
                        ? const ExcludeSemantics(
                            child: _Pill(
                              key: ValueKey('photo_hint'),
                              color: ProductColors.photoHint,
                              label: '끌어서 옮기고, 두 손가락으로 크기·회전',
                            ),
                          )
                        // Announced as it appears (guide 7.5-2).
                        : Semantics(
                            liveRegion: true,
                            child: const _Pill(
                              key: ValueKey('photo_saved_notice'),
                              color: ProductColors.photoSaved,
                              label: '✓ 갤러리에 저장했어요',
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([editor, ?uploader]),
    builder: (context, _) {
      // Same guards as the top bar, so leaving still asks while editing.
      final spec = DuoRailSpec(
        tools: duoBackHome(
          onBack: editor.busy ? null : () => leave(widget.onBack),
          onHome: editor.busy ? null : () => leave(widget.onHome),
        ),
      );
      final mode = duoRailMode(MediaQuery.of(context), spec);
      return PopScope(
        canPop: leaving,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) leave(widget.onBack);
        },
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: editor.photo == null
                    ? _start(rail: mode != null)
                    : _editor(rail: mode != null),
              ),
              if (mode != null) DuoRail(spec: spec, mode: mode),
            ],
          ),
        ),
      );
    },
  );
}

/// One uploaded photo, square-cropped. The bytes load once per thumbnail;
/// the uploader serves them from its cache by photo id.
class _Thumb extends StatefulWidget {
  const _Thumb({
    required this.load,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });
  final Future<Uint8List> Function() load;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  static const size = 72.0;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late Future<Uint8List> bytes = widget.load();

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '올린 사진',
    hint: '누르면 다시 꾸미고, 길게 누르면 지워요',
    child: GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox.square(
          dimension: _Thumb.size,
          child: ColoredBox(
            color: MeetingColors.pressed,
            child: FutureBuilder<Uint8List>(
              future: bytes,
              builder: (context, snapshot) => switch (snapshot) {
                AsyncSnapshot(hasData: true, :final data?) => Image.memory(
                  data,
                  fit: BoxFit.cover,
                  cacheWidth: (_Thumb.size * 3).round(),
                  gaplessPlayback: true,
                ),
                AsyncSnapshot(hasError: true) => IconButton(
                  tooltip: '다시 불러오기',
                  onPressed: () => setState(() => bytes = widget.load()),
                  icon: const Icon(Icons.refresh, color: MeetingColors.muted),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pen `Editor Save`: a 36 pt pill at the bar's end, still a 48 pt target.
final _pill = FilledButton.styleFrom(
  minimumSize: const Size(0, 36),
  padding: const EdgeInsets.symmetric(horizontal: Space.s4),
  shape: const StadiumBorder(),
  textStyle: meetingType(14, 18, FontWeight.w800),
  tapTargetSize: MaterialTapTargetSize.padded,
);

/// Pen's saved state of the same pill: primary-soft, not pressable.
final _savedPill = _pill.merge(
  FilledButton.styleFrom(
    disabledBackgroundColor: MeetingColors.soft,
    disabledForegroundColor: MeetingColors.primaryStrong,
  ),
);

/// Where the companion is, for assistive technology.
String _stickerValue(DogSticker s) {
  final turn = (s.rotation * 180 / math.pi).round() % 360;
  return [
    '가로 ${(s.x * 100).round()}%',
    '세로 ${(s.y * 100).round()}%',
    '크기 ${(s.scale * 100).round()}%',
    '회전 $turn도',
    if (s.flipped) '좌우 반전',
  ].join(', ');
}

/// Pen `Editor Hint`: one short line on a dark pill over the canvas.
class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.label, super.key});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.all(Radius.circular(999)),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: meetingType(12.5, 16, FontWeight.w700, MeetingColors.raised),
    ),
  );
}

/// The selected companion's border and corner marks (Pen `Editor
/// Selection`), turned with it. Drawn over the canvas only: [paintPhoto]
/// and the saved PNG never include it. The marks show the selection; size
/// and angle change with two fingers, not by dragging them.
class PhotoSelectionOverlay extends StatelessWidget {
  const PhotoSelectionOverlay({
    required this.rect,
    required this.rotation,
    super.key,
  });

  /// The companion's box in the canvas, before [rotation] about its centre.
  final Rect rect;
  final double rotation;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SelectionPainter(rect, rotation));
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.rect, this.rotation);
  final Rect rect;
  final double rotation;

  /// Pen's 14 pt corner circles.
  static const _mark = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(rotation);
    final box = Rect.fromCenter(
      center: Offset.zero,
      width: rect.width,
      height: rect.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = MeetingColors.raised,
    );
    final fill = Paint()..color = MeetingColors.raised;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = MeetingColors.primaryStrong;
    for (final corner in [
      box.topLeft,
      box.topRight,
      box.bottomLeft,
      box.bottomRight,
    ]) {
      canvas.drawCircle(corner, _mark, fill);
      canvas.drawCircle(corner, _mark, ring);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      rect != oldDelegate.rect || rotation != oldDelegate.rotation;
}

/// Pen `Photo Example`: the app's sunny background with the user's own
/// companion on it, tagged so it is never taken for their photo or a saved
/// result. The base sprite only, as the editor composites.
class _Example extends StatelessWidget {
  const _Example({required this.dogAssetPath});
  final String dogAssetPath;

  /// Pen frame and dog box, in its 358 × 400 points.
  static const _frame = Size(358, 400);
  static const _dog = Rect.fromLTWH(120, 170, 220, 220);

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: _frame.width / _frame.height,
    child: Semantics(
      key: const ValueKey('photo_example'),
      image: true,
      label: '완성 예시',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final scale = bounds.maxWidth / _frame.width;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/first_meeting/sunny.png',
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.none,
                  ),
                  Positioned.fromRect(
                    rect: Rect.fromLTWH(
                      _dog.left * scale,
                      _dog.top * scale,
                      _dog.width * scale,
                      _dog.height * scale,
                    ),
                    child: DogSprite(asset: dogAssetPath),
                  ),
                  Positioned(
                    left: Space.s3,
                    top: Space.s3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: const BoxDecoration(
                        color: ProductColors.photoTag,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text(
                        '완성 예시',
                        style: meetingType(12.5, 16, FontWeight.w700),
                      ),
                    ),
                  ),
                  // Pen draws the line stroke over the picture's edge.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: MeetingColors.line),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter(this.photo, this.dog, this.sticker);
  final ui.Image photo;
  final ui.Image? dog;
  final DogSticker sticker;
  @override
  void paint(Canvas canvas, Size size) {
    if (dog != null) {
      paintPhoto(canvas, size, photo, dog!, sticker);
    } else {
      canvas.drawImageRect(
        photo,
        Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
        Offset.zero & size,
        Paint(),
      );
    }
  }

  @override
  bool shouldRepaint(_PhotoPainter oldDelegate) =>
      photo != oldDelegate.photo ||
      dog != oldDelegate.dog ||
      sticker != oldDelegate.sticker;
}
