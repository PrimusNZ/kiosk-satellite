import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'assist_art.dart';

/// The KITT skin's indicator: the voice box from Knight Rider's dash. Three
/// columns of red blocks light outward from their middle with the voice,
/// the outer two always a block shorter than the centre, brightest at the
/// middle and fading toward the tips. At rest only the middle of each
/// column glows; while the assistant thinks the columns swell and ease.
class KittArt extends StatelessWidget {
  const KittArt({
    super.key,
    required this.mode,
    required this.level,
    required this.clock,
    this.box,
  });

  final ArtMode mode;
  final ValueListenable<double> level;
  final ArtClock clock;

  /// Where the voice box goes, in the widget's own coordinates. Null fills
  /// the widget.
  final Rect? box;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: _KittPainter(mode, level, clock, box),
    ),
  );
}

class _KittPainter extends CustomPainter {
  _KittPainter(this.mode, this.level, this.clock, this.box)
    : super(repaint: Listenable.merge([level, clock]));

  final ArtMode mode;
  final ValueListenable<double> level;
  final ArtClock clock;
  final Rect? box;

  static const _columns = 3;

  /// Segments in each column: the centre one is the longest.
  static const _rows = [19, 21, 19];
  static const _red = Color(0xFFFF0A00);

  /// The artboard, in design units: three columns of blocks, the centre
  /// one reaching furthest.
  static const _columnWidth = 90.0, _columnGap = 67.0;
  static const _segment = 34.0, _pitch = 41.0;
  static const _artW = _columnWidth * 3 + _columnGap * 2;
  static const _artH = 21 * _pitch - (_pitch - _segment);

  /// A steady pseudo-random 0 to 1 for one tick, so the bars jump from
  /// beat to beat like the dash's, rather than gliding.
  static double _jitter(int tick) {
    final x = math.sin(tick * 12.9898 + 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  /// 0 to 1: how far from the middle row the centre column lights. The
  /// outer two always stand one block short of it at each end.
  double _reach(double t) {
    final raw = level.value.clamp(0.0, 1.0);
    switch (mode) {
      case ArtMode.speaking:
        final beat = _jitter((t * 16).floor());
        return (raw * (0.45 + 0.55 * beat)).clamp(0.0, 1.0);
      case ArtMode.listening:
        final beat = _jitter((t * 12).floor());
        return (raw * 0.8 * (0.5 + 0.5 * beat)).clamp(0.0, 1.0);
      case ArtMode.thinking:
        return 0.12 + 0.3 * (0.5 + 0.5 * math.sin(t * 3.2));
      case ArtMode.idle:
        return 0;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final area = box ?? Offset.zero & size;
    final scale = math.min(area.width / _artW, area.height / _artH) * 0.96;
    final t = clock.seconds;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(area.left, 0, area.right, size.height));
    canvas.translate(area.center.dx, area.center.dy);
    canvas.scale(scale);
    canvas.translate(-_artW / 2, -_artH / 2);
    final radius = Radius.circular(_segment * 0.06);
    for (var c = 0; c < _columns; c++) {
      final rows = _rows[c];
      final middle = (rows - 1) / 2;
      final left = c * (_columnWidth + _columnGap);
      final top = (_artH - (rows * _pitch - (_pitch - _segment))) / 2;
      // How many rows each side of the middle light, fractionally: the
      // centre column's, and one less for the outer two.
      final centre = _reach(t) * ((_rows[1] - 1) / 2 + 0.5);
      final span = c == 1 ? centre : math.max(0.0, centre - 1);
      for (var r = 0; r < rows; r++) {
        final distance = (r - middle).abs();
        var on = (span - distance + 0.5).clamp(0.0, 1.0);
        // The brightest at the middle, fading toward the tips.
        var tone = 1 - 0.9 * (distance / (span + 1)).clamp(0.0, 1.0);
        if (mode == ArtMode.idle) {
          // Only the middle of each column glows, slowly breathing.
          on = distance < 0.5 ? 1 : 0;
          tone = 0.2 + 0.1 * math.sin(t * 1.6);
        }
        if (on <= 0.01) continue;
        final level = tone * on;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top + r * _pitch, _columnWidth, _segment),
          radius,
        );
        canvas.drawRRect(
          rect.inflate(_segment * 0.15),
          Paint()
            ..color = _red.withValues(alpha: 0.28 * level)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        // Each block runs a shade darker at its top than its bottom.
        final bottom = Color.lerp(Colors.black, _red, level)!;
        final topColor = Color.lerp(Colors.black, _red, level * 0.82)!;
        canvas.drawRRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [topColor, bottom],
            ).createShader(rect.outerRect),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KittPainter old) =>
      old.mode != mode ||
      old.level != level ||
      old.clock != clock ||
      old.box != box;
}
