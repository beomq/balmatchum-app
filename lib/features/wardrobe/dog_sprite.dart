import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'wardrobe_art.dart';

/// Pen sizes of the companion outside home (guide 3.6): beside a result or a
/// record, under an open quiz question, and over an empty state.
abstract final class DogSpriteSize {
  static const companion = 72.0;
  static const hint = 96.0;
  static const emptyState = 140.0;
}

/// The companion's approved sprite, optionally wearing a [look].
///
/// Every layer shares its sprite's exact canvas, so the stack is painted into
/// the box the base sprite was laid out in, with the same contain fit and
/// centre alignment and no smoothing. Without a look (or until its pictures
/// are decoded) this is the plain sprite image, as before.
class DogSprite extends StatelessWidget {
  const DogSprite({
    required this.asset,
    this.look,
    this.spriteKey,
    this.layerKey,
    super.key,
  });

  final String asset;
  final DogLook? look;
  final Key? spriteKey;
  final Key? layerKey;

  @override
  Widget build(BuildContext context) {
    final worn = look;
    if (worn == null || (worn.plain && worn.base == asset)) {
      return _image(asset, spriteKey);
    }
    return _LayeredSprite(look: worn, spriteKey: spriteKey, layerKey: layerKey);
  }
}

Image _image(String asset, Key? key) => Image.asset(
  asset,
  key: key,
  fit: BoxFit.contain,
  filterQuality: FilterQuality.none,
);

class _LayeredSprite extends StatefulWidget {
  const _LayeredSprite({required this.look, this.spriteKey, this.layerKey});

  final DogLook look;
  final Key? spriteKey;
  final Key? layerKey;

  @override
  State<_LayeredSprite> createState() => _LayeredSpriteState();
}

class _LayeredSpriteState extends State<_LayeredSprite> {
  _Stack? stack;
  var _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(_LayeredSprite old) {
    super.didUpdateWidget(old);
    if (old.look.key != widget.look.key) unawaited(_resolve());
  }

  Future<ui.Image> _decode(String asset) {
    final done = Completer<ui.Image>();
    final stream = AssetImage(asset)
        .resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete(info.image);
      },
      onError: (error, trace) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.completeError(error, trace);
      },
    );
    stream.addListener(listener);
    return done.future;
  }

  Future<void> _resolve() async {
    final generation = ++_generation;
    final look = widget.look;
    try {
      final images = await Future.wait([
        _decode(look.base),
        for (final cut in look.cuts) _decode(cut),
        for (final layer in look.layers) _decode(layer),
      ]);
      if (!mounted || generation != _generation) return;
      setState(
        () => stack = _Stack(
          look.key,
          images.first,
          images.sublist(1, 1 + look.cuts.length),
          images.sublist(1 + look.cuts.length),
        ),
      );
    } on Object {
      // A missing picture leaves the plain sprite; nothing is borrowed.
      if (!mounted || generation != _generation) return;
      setState(() => stack = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = stack != null && stack!.key == widget.look.key;
    final base = _image(widget.look.base, widget.spriteKey);
    return Stack(
      // The base image sizes the stack exactly as the plain sprite would.
      fit: StackFit.passthrough,
      children: [
        Opacity(opacity: ready ? 0 : 1, child: base),
        if (ready)
          Positioned.fill(
            child: CustomPaint(
              key: widget.layerKey,
              painter: _StackPainter(stack!),
            ),
          ),
      ],
    );
  }
}

class _Stack {
  const _Stack(this.key, this.base, this.cuts, this.layers);
  final String key;
  final ui.Image base;
  final List<ui.Image> cuts;
  final List<ui.Image> layers;
}

class _StackPainter extends CustomPainter {
  _StackPainter(this.stack);
  final _Stack stack;

  @override
  void paint(Canvas canvas, Size size) {
    final source = Size(
      stack.base.width.toDouble(),
      stack.base.height.toDouble(),
    );
    final fitted = applyBoxFit(BoxFit.contain, source, size);
    final dest = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final from = Offset.zero & source;
    final paint = Paint()..filterQuality = FilterQuality.none;
    canvas.saveLayer(dest, Paint());
    canvas.drawImageRect(stack.base, from, dest, paint);
    final erase = Paint()
      ..filterQuality = FilterQuality.none
      ..blendMode = BlendMode.dstOut;
    for (final cut in stack.cuts) {
      canvas.drawImageRect(cut, from, dest, erase);
    }
    for (final layer in stack.layers) {
      canvas.drawImageRect(layer, from, dest, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StackPainter old) => old.stack.key != stack.key;
}
