import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Set-complete effects driven by assets/wardrobe/effects/presets.json, the
/// same settings the art preview engine (season-sets/effects/effect.py) uses:
/// falling, rising, burst and sparkle layers on a 768x512 canvas, 48 frames
/// at 12 fps, every motion closing its loop at frame 48. Particle placement
/// uses Dart's seeded Random, so positions differ from the preview GIFs but
/// follow the same rules.
class EffectPresets {
  EffectPresets(this.json);

  final Map<String, dynamic> json;

  static const asset = 'assets/wardrobe/effects/presets.json';
  static Future<EffectPresets>? _loaded;

  static Future<EffectPresets> load([AssetBundle? bundle]) =>
      _loaded ??= (bundle ?? rootBundle)
          .loadString(asset)
          .then(
            (text) => EffectPresets(jsonDecode(text) as Map<String, dynamic>),
          );

  Map<String, dynamic> get _canvas => json['canvas'] as Map<String, dynamic>;
  int get width => _canvas['w'] as int;
  int get height => _canvas['h'] as int;
  int get frames => _canvas['frames'] as int;
  int get fps => _canvas['fps'] as int;

  EffectEngine? engine(String name) {
    final preset = (json['presets'] as Map<String, dynamic>)[name];
    if (preset == null) return null;
    return EffectEngine(this, preset as Map<String, dynamic>);
  }
}

/// One filled square of a frame, in canvas pixels.
class EffectPixel {
  const EffectPixel(this.rect, this.color);
  final Rect rect;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is EffectPixel && other.rect == rect && other.color == color;

  @override
  int get hashCode => Object.hash(rect, color);
}

class _Particle {
  _Particle(this.x, this.y, this.size, this.laps, this.drift, this.phase);
  final int x;
  final int y;
  final int size;
  final int laps;
  final int drift;
  final double phase;
  int colour = 0;
  int off = 0;
}

Color _hex(String s) =>
    Color(0xFF000000 | int.parse(s.replaceFirst('#', ''), radix: 16));

class EffectEngine {
  EffectEngine(this.presets, Map<String, dynamic> preset)
    : layers = [
        for (final layer in preset['layers'] as List)
          layer as Map<String, dynamic>,
      ] {
    for (final layer in layers) {
      _particles.add(
        layer['type'] == 'falling' || layer['type'] == 'rising'
            ? _draw(layer)
            : const [],
      );
    }
  }

  final EffectPresets presets;
  final List<Map<String, dynamic>> layers;
  final List<List<_Particle>> _particles = [];

  int get w => presets.width;
  int get h => presets.height;
  int get n => presets.frames;

  List<_Particle> _draw(Map<String, dynamic> layer) {
    final rng = math.Random(layer['seed'] as int);
    final sizes = [for (final s in layer['sizes'] as List) s as Map];
    final drift = [for (final d in layer['drift'] as List) d as int];
    final colours = (layer['colours'] as List).length;
    final flicker = layer['flicker'] as Map?;
    return [
      for (var i = 0; i < (layer['count'] as int); i++)
        () {
          final r = rng.nextDouble();
          var acc = 0.0;
          var pick = sizes.last;
          for (final s in sizes) {
            acc += (s['p'] as num).toDouble();
            if (r < acc) {
              pick = s;
              break;
            }
          }
          final p = _Particle(
            rng.nextInt(w),
            rng.nextInt(h),
            pick['px'] as int,
            pick['laps'] as int,
            drift[0] + rng.nextInt(math.max(1, drift[1] - drift[0])),
            rng.nextDouble(),
          );
          if (colours > 1) p.colour = rng.nextInt(colours);
          if (flicker != null) p.off = rng.nextInt(flicker['period'] as int);
          return p;
        }(),
    ];
  }

  /// Every square lit in frame [t]. The motions themselves are periodic, so
  /// frame [n] equals frame 0 only when the preset closes its loop. [bursts]
  /// false leaves out the flashing fireworks, for reduced motion.
  List<EffectPixel> frame(int t, {bool bursts = true}) {
    final out = <EffectPixel>[];
    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      switch (layer['type']) {
        case 'falling':
          _moving(out, layer, _particles[i], t, 1);
        case 'rising':
          _moving(out, layer, _particles[i], t, -1);
        case 'sparkle':
          _sparkle(out, layer, t);
        case 'burst':
          if (bursts) _burst(out, layer, t);
      }
    }
    return out;
  }

  void _put(List<EffectPixel> out, num x, num y, num size, Color c) {
    if (x >= w || y >= h || x + size <= 0 || y + size <= 0) return;
    out.add(
      EffectPixel(
        Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          size.toDouble(),
          size.toDouble(),
        ),
        c,
      ),
    );
  }

  void _moving(
    List<EffectPixel> out,
    Map<String, dynamic> layer,
    List<_Particle> particles,
    int t,
    int direction,
  ) {
    final fills = [for (final c in layer['colours'] as List) _hex(c as String)];
    final shade = layer['shade'] == null
        ? null
        : _hex(layer['shade'] as String);
    final flicker = layer['flicker'] as Map?;
    final shapeName = layer['shape'] as String;
    for (final p in particles) {
      if (flicker != null &&
          (t + p.off) % (flicker['period'] as int) >= (flicker['on'] as int)) {
        continue;
      }
      final angle = 2 * math.pi * (t / n + p.phase);
      final y = (p.y + direction * p.laps * h * t / n).floor() % h;
      final x = (p.x + p.drift * math.sin(angle)).floor() % w;
      final fill = fills[p.colour];
      if (shapeName == 'square') {
        final e = (layer['edge_px'] as int?) ?? 0;
        if (e > 0) {
          _put(
            out,
            x - e,
            y - e,
            p.size + 2 * e,
            _hex(layer['edge'] as String),
          );
        }
        _put(out, x, y, p.size, fill);
      } else {
        final shape =
            (presets.json['shapes'] as Map<String, dynamic>)[shapeName] as Map;
        final mirror = layer['flip'] == true && math.cos(angle) < 0;
        _shape(out, x, y, shape, p.size, fill, shade ?? fill, mirror);
      }
    }
  }

  void _shape(
    List<EffectPixel> out,
    int x,
    int y,
    Map shape,
    int scale,
    Color fill,
    Color shade,
    bool mirror,
  ) {
    final u = (shape['unit'] as int) * scale;
    final rows = [for (final r in shape['rows'] as List) r as String];
    for (var j = 0; j < rows.length; j++) {
      final row = mirror ? rows[j].split('').reversed.join() : rows[j];
      for (var i = 0; i < row.length; i++) {
        if (row[i] == '.') continue;
        _put(out, x + i * u, y + j * u, u, row[i] == '1' ? fill : shade);
      }
    }
  }

  void _sparkle(List<EffectPixel> out, Map<String, dynamic> layer, int t) {
    final u = layer['unit'] as int;
    final colours = [
      for (final c in layer['colours'] as List) _hex(c as String),
    ];
    final points = layer['points'] as List;
    const arms = [0, 1, 2, 3, 2, 1];
    for (var i = 0; i < points.length; i++) {
      final k = (t + i * (layer['offset'] as int)) % (layer['period'] as int);
      if (k >= 6 || arms[k] == 0) continue;
      final [cx as int, cy as int] = points[i] as List;
      final c = colours[i % colours.length];
      _put(out, cx, cy, u, c);
      for (var d = 1; d <= arms[k]; d++) {
        for (final (x, y) in [
          (cx + u * d, cy),
          (cx - u * d, cy),
          (cx, cy + u * d),
          (cx, cy - u * d),
        ]) {
          if (x >= 0 && x < w - u && y >= 0 && y < h - u) _put(out, x, y, u, c);
        }
      }
    }
  }

  void _burst(List<EffectPixel> out, Map<String, dynamic> layer, int t) {
    final u = layer['unit'] as int;
    final count = layer['particles'] as int;
    final life = layer['life'] as int;
    final bursts = layer['bursts'] as List;
    for (var bi = 0; bi < bursts.length; bi++) {
      final b = bursts[bi] as Map;
      final k = (t - (b['start'] as int)) % (layer['period'] as int);
      if (k >= life) continue;
      final colours = [for (final c in b['colours'] as List) _hex(c as String)];
      final bx = b['x'] as int;
      final by = b['y'] as int;
      if (k == 0) {
        _put(out, bx - u, by - u, 2 * u, colours.first);
        continue;
      }
      for (final (step, dim) in [(k - 1, true), (k, false)]) {
        final q = (step + 1) / life;
        final r = (layer['radius'] as int) * (1 - math.pow(1 - q, 2));
        final ci = math.min(
          colours.length - 1,
          (q * colours.length).floor() + (dim ? 1 : 0),
        );
        for (var i = 0; i < count; i++) {
          final th = 2 * math.pi * i / count + bi * 0.4;
          final x = (bx + r * math.cos(th)).floor() ~/ u * u;
          final y =
              (by + r * math.sin(th) + (layer['droop'] as int) * q * q)
                  .floor() ~/
              u *
              u;
          if (x >= 0 && x < w - u && y >= 0 && y < h - u) {
            _put(out, x, y, u, colours[ci]);
          }
        }
      }
    }
  }
}

/// Paints the [preset] effect over the box it fills, scaled like a cover-fit
/// background. Plays at 12 fps; reduced motion shows one still frame without
/// fireworks, and the ticker stops whenever TickerMode mutes it (another tab,
/// a covered route).
class SetEffect extends StatefulWidget {
  const SetEffect({required this.preset, this.still = false, super.key});

  final String preset;

  /// One frame and no ticker: shop cards show what a set brings without
  /// every card animating at once.
  final bool still;

  @override
  State<SetEffect> createState() => _SetEffectState();
}

class _SetEffectState extends State<SetEffect>
    with SingleTickerProviderStateMixin {
  EffectEngine? engine;
  late final Ticker _ticker = createTicker(_onTick);
  int frame = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SetEffect old) {
    super.didUpdateWidget(old);
    if (old.preset != widget.preset) _load();
  }

  Future<void> _load() async {
    final presets = await EffectPresets.load(DefaultAssetBundle.of(context));
    if (!mounted) return;
    setState(() => engine = presets.engine(widget.preset));
    _sync();
  }

  bool get _still =>
      widget.still || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync() {
    if (engine == null || _still) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _onTick(Duration elapsed) {
    final e = engine;
    if (e == null) return;
    final next = (elapsed.inMilliseconds * e.presets.fps ~/ 1000) % e.n;
    if (next != frame) setState(() => frame = next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = engine;
    if (e == null) return const SizedBox.expand();
    final still = _still;
    return IgnorePointer(
      child: CustomPaint(
        key: ValueKey('set_effect_${widget.preset}'),
        size: Size.infinite,
        painter: _EffectPainter(e, e.frame(still ? 0 : frame, bursts: !still)),
      ),
    );
  }
}

class _EffectPainter extends CustomPainter {
  _EffectPainter(this.engine, this.pixels);
  final EffectEngine engine;
  final List<EffectPixel> pixels;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(size.width / engine.w, size.height / engine.h);
    final dx = (size.width - engine.w * scale) / 2;
    final dy = (size.height - engine.h * scale) / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(dx, dy);
    canvas.scale(scale);
    final paint = Paint()..isAntiAlias = false;
    for (final p in pixels) {
      canvas.drawRect(p.rect, paint..color = p.color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EffectPainter old) => old.pixels != pixels;
}
