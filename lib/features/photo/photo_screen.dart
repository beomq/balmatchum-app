import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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

  Widget _button(
    String label,
    String key,
    VoidCallback? action, {
    bool primary = false,
  }) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(44, 48)),
    );
    return primary
        ? FilledButton(
            key: ValueKey(key),
            onPressed: action,
            style: style,
            child: Text(label),
          )
        : OutlinedButton(
            key: ValueKey(key),
            onPressed: action,
            style: style,
            child: Text(label),
          );
  }

  Widget _sources() => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      _button(
        '사진 선택',
        'photo_gallery',
        editor.busy ? null : () => pick(PhotoSource.gallery),
      ),
      _button(
        '카메라 촬영',
        'photo_camera',
        editor.busy ? null : () => pick(PhotoSource.camera),
      ),
    ],
  );

  Widget _preview() {
    final photo = editor.photo!;
    return AspectRatio(
      aspectRatio: photo.width / photo.height,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final size = bounds.biggest;
          return Semantics(
            label: '${widget.dogName} 사진 편집. 끌어서 이동하고 두 손가락으로 크기와 각도를 조절해요.',
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
                    x: start.x + delta.dx / size.width,
                    y: start.y + delta.dy / size.height,
                    scale: start.scale * details.scale,
                    rotation: start.rotation + details.rotation,
                  ),
                );
              },
              onScaleEnd: (_) => _clearGesture(),
              child: ClipRect(
                child: CustomPaint(
                  painter: _PhotoPainter(photo, editor.dog, editor.sticker),
                  size: size,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _slider(
    String label,
    String key,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      Slider(
        key: ValueKey(key),
        value: value,
        min: min,
        max: max,
        onChanged: editor.busy ? null : change,
        semanticFormatterCallback: (value) => value.toStringAsFixed(1),
      ),
    ],
  );

  Widget _controls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sources(),
      const SizedBox(height: 20),
      if (editor.photo != null) ...[
        const Text('끌어서 이동 · 두 손가락으로 크기와 각도 조절'),
        const SizedBox(height: 16),
        _slider(
          '가로 위치',
          'photo_x',
          editor.sticker.x,
          0,
          1,
          (v) => editor.edit(editor.sticker.copyWith(x: v)),
        ),
        _slider(
          '세로 위치',
          'photo_y',
          editor.sticker.y,
          0,
          1,
          (v) => editor.edit(editor.sticker.copyWith(y: v)),
        ),
        _slider(
          '크기',
          'photo_scale',
          editor.sticker.scale,
          .3,
          3,
          (v) => editor.edit(editor.sticker.copyWith(scale: v)),
        ),
        _slider(
          '회전',
          'photo_rotation',
          math.atan2(
            math.sin(editor.sticker.rotation),
            math.cos(editor.sticker.rotation),
          ),
          -math.pi,
          math.pi,
          (v) => editor.edit(editor.sticker.copyWith(rotation: v)),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _button(
              editor.sticker.flipped ? '좌우 반전 해제' : '좌우 반전',
              'photo_flip',
              editor.busy
                  ? null
                  : () => editor.edit(
                      editor.sticker.copyWith(flipped: !editor.sticker.flipped),
                    ),
            ),
            _button(
              '위치 초기화',
              'photo_reset',
              editor.busy ? null : () => editor.edit(const DogSticker()),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
      _button(
        '갤러리에 저장',
        'photo_save',
        editor.canExport ? editor.save : null,
        primary: true,
      ),
      const SizedBox(height: 12),
      Builder(
        builder: (context) => _button(
          '사진 공유',
          'photo_share',
          editor.canExport
              ? () {
                  final box = context.findRenderObject()! as RenderBox;
                  editor.share(box.localToGlobal(Offset.zero) & box.size);
                }
              : null,
        ),
      ),
      const SizedBox(height: 16),
      const Text('원본 사진은 그대로 두고, 합성한 사진만 저장해요. 사진은 서버로 보내지 않아요.'),
      if (editor.busy)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: LinearProgressIndicator(),
        ),
      if (editor.message != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Semantics(
            liveRegion: true,
            child: Text(
              editor.message!,
              key: const ValueKey('photo_status'),
              style: TextStyle(
                color: editor.isError ? MeetingColors.error : MeetingColors.ink,
              ),
            ),
          ),
        ),
      if (editor.dog == null && !editor.busy)
        _button('강아지 다시 불러오기', 'photo_retry', editor.initialize),
    ],
  );

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
                      _button('강아지 다시 불러오기', 'photo_retry', editor.initialize),
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
                    : LayoutBuilder(
                        builder: (context, bounds) {
                          final padding = bounds.maxWidth < 360
                              ? 12.0
                              : bounds.maxWidth < 600
                              ? 16.0
                              : bounds.maxWidth < 840
                              ? 24.0
                              : 32.0;
                          final wide = bounds.maxWidth >= 840;
                          return SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              padding,
                              16,
                              padding,
                              24,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: wide ? 1100 : 600,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (mode == null) ...[
                                      Row(
                                        children: [
                                          IconButton(
                                            key: const ValueKey('photo_back'),
                                            tooltip: '뒤로',
                                            onPressed: editor.busy
                                                ? null
                                                : () => leave(widget.onBack),
                                            icon: Image.asset(
                                              'assets/first_meeting/icons/back.png',
                                              width: 32,
                                              height: 32,
                                              filterQuality: FilterQuality.none,
                                            ),
                                          ),
                                          const Spacer(),
                                          TextButton(
                                            key: const ValueKey('photo_home'),
                                            onPressed: editor.busy
                                                ? null
                                                : () => leave(widget.onHome),
                                            child: const Text('홈'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 18),
                                    ],
                                    Text(
                                      '함께 사진 찍기',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall,
                                    ),
                                    const SizedBox(height: 8),
                                    Text('${widget.dogName}를 사진에 담아 보세요.'),
                                    const SizedBox(height: 20),
                                    if (wide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(flex: 6, child: _preview()),
                                          const SizedBox(width: 24),
                                          Expanded(flex: 4, child: _controls()),
                                        ],
                                      )
                                    else ...[
                                      _preview(),
                                      const SizedBox(height: 20),
                                      _controls(),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (mode != null) DuoRail(spec: spec, mode: mode),
            ],
          ),
        ),
      );
    },
  );
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
