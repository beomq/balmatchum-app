import 'dart:math' as math;
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

export 'photo_editor.dart'
    show PhotoAdapter, PhotoFailure, PhotoSource, PhotoShareResult;

class PhotoScreen extends StatefulWidget {
  const PhotoScreen({
    required this.dogAssetPath,
    required this.dogName,
    required this.adapter,
    required this.onBack,
    required this.onHome,
    super.key,
  });
  final String dogAssetPath;
  final String dogName;
  final PhotoAdapter adapter;
  final VoidCallback onBack;
  final VoidCallback onHome;

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

  void pick(PhotoSource value) {
    source = value;
    editor.pick(value);
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
  /// out and the bar keeps the title and save.
  Widget _editor({required bool rail}) {
    final sticker = editor.sticker;
    final message = editor.message;
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
                    FilledButton(
                      key: const ValueKey('photo_save'),
                      style: _pill,
                      onPressed: editor.canExport ? editor.save : null,
                      child: const Text('저장'),
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
            Expanded(child: _canvas()),
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
                      // Until the saved view takes it, sharing stays here.
                      Expanded(
                        child: Builder(
                          builder: (context) => OutlinedButton(
                            key: const ValueKey('photo_share'),
                            onPressed: editor.canExport
                                ? () {
                                    final box =
                                        context.findRenderObject()!
                                            as RenderBox;
                                    editor.share(
                                      box.localToGlobal(Offset.zero) & box.size,
                                    );
                                  }
                                : null,
                            child: const Text('공유'),
                          ),
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

  /// The photo as it will be saved, with the selection drawn over it. The
  /// pointer moves the companion by fractions of the drawn photo, not of
  /// the canvas around it.
  Widget _canvas() => LayoutBuilder(
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
        hint: '끌어서 옮기고 두 손가락으로 크기와 각도를 바꿔요',
        customSemanticsActions: dog == null
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
          onScaleStart: (details) {
            if (editor.busy) return;
            _gestureStart = editor.sticker;
            _focalStart = details.localFocalPoint;
          },
          onScaleUpdate: (details) {
            final start = _gestureStart;
            final focalStart = _focalStart;
            if (editor.busy || start == null || focalStart == null) return;
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
          onScaleEnd: (_) => _clearGesture(),
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
                if (selection != null)
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
                  child: ExcludeSemantics(
                    child: Center(
                      child: _Pill(
                        key: const ValueKey('photo_hint'),
                        color: ProductColors.photoHint,
                        label: '끌어서 옮기고, 두 손가락으로 크기·회전',
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
    animation: editor,
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

/// Pen `Editor Save`: a 36 pt pill at the bar's end, still a 48 pt target.
final _pill = FilledButton.styleFrom(
  minimumSize: const Size(0, 36),
  padding: const EdgeInsets.symmetric(horizontal: Space.s4),
  shape: const StadiumBorder(),
  textStyle: meetingType(14, 18, FontWeight.w800),
  tapTargetSize: MaterialTapTargetSize.padded,
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
