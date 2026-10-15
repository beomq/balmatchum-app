import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
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

  @override
  void initState() {
    super.initState();
    editor = PhotoEditor(
      adapter: widget.adapter,
      dogAssetPath: widget.dogAssetPath,
    );
    editor.initialize();
  }

  @override
  void dispose() {
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 편집'),
            ),
            TextButton(
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
        editor.busy ? null : () => editor.pick(PhotoSource.gallery),
      ),
      _button(
        '카메라 촬영',
        'photo_camera',
        editor.busy ? null : () => editor.pick(PhotoSource.camera),
      ),
    ],
  );

  Widget _preview() {
    final photo = editor.photo;
    if (photo == null) {
      return Container(
        height: 300,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: MeetingColors.soft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              widget.dogAssetPath,
              height: 148,
              filterQuality: FilterQuality.none,
              semanticLabel: widget.dogName,
            ),
            const SizedBox(height: 16),
            Text(
              '${widget.dogName}와 함께할 사진을 골라 주세요.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
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
              onScaleStart: editor.busy
                  ? null
                  : (details) {
                      _gestureStart = editor.sticker;
                      _focalStart = details.localFocalPoint;
                    },
              onScaleUpdate: editor.busy
                  ? null
                  : (details) {
                      final start = _gestureStart!;
                      final delta = details.localFocalPoint - _focalStart!;
                      editor.edit(
                        start.copyWith(
                          x: start.x + delta.dx / size.width,
                          y: start.y + delta.dy / size.height,
                          scale: start.scale * details.scale,
                          rotation: start.rotation + details.rotation,
                        ),
                      );
                    },
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
                color: editor.isError
                    ? const Color(0xFFA74638)
                    : MeetingColors.ink,
              ),
            ),
          ),
        ),
      if (editor.dog == null && !editor.busy)
        _button('강아지 다시 불러오기', 'photo_retry', editor.initialize),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: editor,
    builder: (context, _) => PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave(widget.onBack);
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
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
                padding: EdgeInsets.fromLTRB(padding, 16, padding, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 1100 : 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                        Text(
                          '함께 사진 찍기',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text('${widget.dogName}를 사진에 담아 보세요.'),
                        const SizedBox(height: 20),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
