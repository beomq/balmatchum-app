import 'package:flutter/material.dart';

/// Pen sizes of the companion outside home (guide 3.6): beside a result or a
/// record, under an open quiz question, and over an empty state.
abstract final class DogSpriteSize {
  static const companion = 72.0;
  static const hint = 96.0;
  static const emptyState = 140.0;
}

/// The companion's approved sprite with an optional worn layer.
///
/// A layer shares its sprite's exact canvas, so it is pinned to the box the
/// sprite was laid out in and painted with the same contain fit and centre
/// alignment. Without a layer this is the sprite image alone, as before.
class DogSprite extends StatelessWidget {
  const DogSprite({
    required this.asset,
    this.layer,
    this.spriteKey,
    this.layerKey,
    super.key,
  });

  final String asset;
  final String? layer;
  final Key? spriteKey;
  final Key? layerKey;

  @override
  Widget build(BuildContext context) {
    final sprite = Image.asset(
      asset,
      key: spriteKey,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
    );
    final worn = layer;
    if (worn == null) return sprite;
    return Stack(
      // The sprite gets the parent's constraints unchanged and sizes the
      // stack, so its own layout is identical with or without the layer.
      fit: StackFit.passthrough,
      children: [
        sprite,
        Positioned.fill(
          child: Image.asset(
            worn,
            key: layerKey,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          ),
        ),
      ],
    );
  }
}
