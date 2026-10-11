import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assist_art.dart';

/// CABAL portrait with animated atomic eyes and a speech-reactive mouth.
/// Add cabal_face.jpg to pubspec.yaml assets before selecting this skin.
///
/// The mouth is the portrait's own: a mesh over the jaw samples the photo
/// and drops its lower lip and chin with the voice, stretching the dark
/// slot between the lips into the opening.
class CabalArt extends StatefulWidget {
  const CabalArt({
    super.key,
    required this.mode,
    required this.level,
    required this.clock,
    this.box,
  });

  final ArtMode mode;
  final ValueListenable<double> level;
  final ArtClock clock;

  /// Where the face is drawn, in the widget's own coordinates: the slot the
  /// overlay keeps for it above the chat, as Jarvis's reactor does. Null
  /// fills the widget.
  final Rect? box;

  @override
  State<CabalArt> createState() => _CabalArtState();
}

class _CabalArtState extends State<CabalArt> {
  ui.Image? _face;
  ui.ImageShader? _shader;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await rootBundle.load('assets/assist/cabal_face.jpg');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() {
      _face = frame.image;
      _shader = ui.ImageShader(
        frame.image,
        TileMode.clamp,
        TileMode.clamp,
        Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        filterQuality: FilterQuality.high,
      );
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    _face?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: _CabalPainter(
        widget.mode,
        widget.level,
        widget.clock,
        _face,
        _shader,
        widget.box,
      ),
    ),
  );
}

class _CabalPainter extends CustomPainter {
  _CabalPainter(
    this.mode,
    this.level,
    this.clock,
    this.face,
    this.shader,
    this.box,
  ) : super(repaint: Listenable.merge([level, clock]));

  final ArtMode mode;
  final ValueListenable<double> level;
  final ArtClock clock;
  final ui.Image? face;
  final ui.ImageShader? shader;
  final Rect? box;

  static const _cyan = Color(0xFFB7DFFF);

  /// How large the atom is drawn against its design size.
  static const _atomScale = 0.78;

  static const _artW = 1440.0, _artH = 1080.0;

  /// The jaw mesh: the portrait's mouth sits in the slot at about
  /// (715, 807); everything from the slot's lower edge to the chin follows
  /// the jaw down, fading to nothing at the mesh's border so it never tears.
  static const _meshLeft = 500.0, _meshRight = 930.0;
  static const _meshTop = 788.0, _meshBottom = 1010.0;
  static const _cols = 36, _rows = 30;

  /// Radians a second of the syllable motion: about 4.5 syllables a second.
  static const _syllableRate = 28.0;

  /// The furthest the lower lip travels, in design pixels.
  static const _drop = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Design coordinates match the supplied 4:3 portrait; scale uniformly
    // and letterbox rather than distorting the face on widescreen kiosks.
    // With a box the portrait fills it edge to edge (its black margins make
    // the crop invisible); without one it is letterboxed in the widget.
    final area = box ?? Offset.zero & size;
    final fit = box == null ? math.min : math.max;
    final scale = fit(area.width / _artW, area.height / _artH).toDouble();
    final ox = area.left + (area.width - _artW * scale) / 2;
    final oy = area.top + (area.height - _artH * scale) / 2;
    canvas.save();
    if (box != null) {
      canvas.clipRect(Rect.fromLTRB(area.left, 0, area.right, area.bottom));
    }
    canvas.translate(ox, oy);
    canvas.scale(scale);
    final img = face;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        const Rect.fromLTWH(0, 0, _artW, _artH),
        Paint()..filterQuality = FilterQuality.high,
      );
      _drawJaw(canvas, img);
      _drawGlow(canvas, img, clock.seconds);
    }
    final t = clock.seconds;
    _drawAtomicEye(canvas, const Offset(568, 545), t, 0.0);
    _drawAtomicEye(canvas, const Offset(865, 545), t, 1.37);
    canvas.restore();
  }

  /// 0 to 1: how open the mouth is. The portrait's closed mouth is the
  /// idle state.
  double _open(double t) {
    if (mode != ArtMode.speaking) return 0;
    final raw = level.value.clamp(0.0, 1.0);
    // A syllabic motion rides on the measured level, at the pace of speech.
    final syllable = 0.5 + 0.5 * math.sin(t * _syllableRate);
    return (0.04 + raw * 0.62 + syllable * raw * 0.34).clamp(0.0, 1.0);
  }

  /// The head's halo, alive: a blurred, slightly swelling copy of the
  /// portrait is added back over its own glow, masked so only the edge
  /// halo (not the face) brightens. It breathes while idle, ripples while
  /// thinking, and swells with the voice when listening or speaking.
  void _drawGlow(Canvas canvas, ui.Image img, double t) {
    final lv = level.value.clamp(0.0, 1.0);
    final double a;
    switch (mode) {
      case ArtMode.speaking:
        a = 0.30 + lv * 0.55 + 0.10 * math.sin(t * 28) * lv;
      case ArtMode.listening:
        a = 0.26 + lv * 0.30 + 0.05 * math.sin(t * 2.4);
      case ArtMode.thinking:
        a = 0.28 + 0.16 * math.sin(t * 3.6);
      case ArtMode.idle:
        a = 0.20 + 0.08 * math.sin(t * 1.3);
    }
    final swell = 1.0 + 0.012 * math.sin(t * 1.3) + 0.03 * a;
    const c = Offset(720, 530);
    final bounds = Offset.zero & const Size(_artW, _artH);
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.plus);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(swell);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26)
        ..color = const Color(0xFFFFFFFF).withValues(alpha: a.clamp(0.0, 1.0))
        ..filterQuality = FilterQuality.low,
    );
    canvas.restore();
    // Keep the face itself untouched: clear the inner ellipse softly.
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          c,
          560,
          const [Color(0x00000000), Color(0x00000000), Color(0xFFFFFFFF)],
          const [0.0, 0.55, 0.86],
          TileMode.clamp,
          Float64List.fromList([
            0.78,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0.22 * c.dx,
            0,
            0,
            1,
          ]),
        ),
    );
    canvas.restore();
  }

  static double _smooth(double a, double b, double x) {
    final u = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return u * u * (3 - 2 * u);
  }

  /// How far down a point of the jaw follows the opening, 0 to 1.
  static double _follow(double x, double y) {
    // Zero over the upper lip and the slot's top edge, full just under the
    // slot so the slot's dark pixels stretch into the opening, then easing
    // out toward the chin's end and the sides of the jaw.
    final vertical = _smooth(809, 819, y) * (1 - _smooth(950, 1008, y));
    final across = 1 - _smooth(70, 200, (x - 715).abs());
    return vertical * across;
  }

  void _drawJaw(Canvas canvas, ui.Image img) {
    final open = _open(clock.seconds);
    final s = shader;
    if (open < 0.015 || s == null) return;
    final dy = _drop * open;
    final sx = img.width / _artW, sy = img.height / _artH;
    final n = (_cols + 1) * (_rows + 1);
    final pos = Float32List(n * 2);
    final tex = Float32List(n * 2);
    var k = 0;
    for (var r = 0; r <= _rows; r++) {
      final y = _meshTop + (_meshBottom - _meshTop) * r / _rows;
      for (var c = 0; c <= _cols; c++) {
        final x = _meshLeft + (_meshRight - _meshLeft) * c / _cols;
        pos[k] = x;
        pos[k + 1] = y + dy * _follow(x, y);
        tex[k] = x * sx;
        tex[k + 1] = y * sy;
        k += 2;
      }
    }
    final idx = Uint16List(_cols * _rows * 6);
    var i = 0;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final a = r * (_cols + 1) + c;
        final b = a + 1;
        final d = a + _cols + 1;
        final e = d + 1;
        idx
          ..[i++] = a
          ..[i++] = b
          ..[i++] = d
          ..[i++] = b
          ..[i++] = e
          ..[i++] = d;
      }
    }
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        pos,
        textureCoordinates: tex,
        indices: idx,
      ),
      BlendMode.src,
      Paint()..shader = s,
    );
  }

  void _drawAtomicEye(Canvas canvas, Offset c, double t, double phase) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    // Black out the portrait's own sigil (radius about 18) so it never
    // shows through the animation: solid to 21, feathered to 27.
    canvas.drawCircle(
      Offset.zero,
      27,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0.0, 0.78, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 27)),
    );
    // The atom is drawn smaller than the sigil's disc so it reads as an
    // iris. Orbital ellipses stay inside the eye socket.
    canvas.scale(_atomScale);
    final glow = Paint()
      ..color = _cyan.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset.zero, 17, glow);

    for (var i = 0; i < 3; i++) {
      final angle = phase + t * (i.isEven ? 0.95 : -0.72) + i * math.pi / 3;
      canvas.save();
      canvas.rotate(angle);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: 42,
        height: i == 1 ? 17 : 23,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = _cyan.withValues(alpha: 0.36)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.7),
      );
      final a = t * (i.isEven ? 2.25 : -1.8) + phase + i * 2.1;
      final electron = Offset(
        math.cos(a) * 21,
        math.sin(a) * (i == 1 ? 8.5 : 11.5),
      );
      canvas.drawCircle(
        electron,
        3.2,
        Paint()
          ..color = _cyan.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
      canvas.drawCircle(
        electron,
        1.5,
        Paint()
          ..color = const Color(0xFFD2E8FA).withValues(alpha: 0.82)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
      );
      canvas.restore();
    }
    // With the portrait's sigil covered, the nucleus carries its own glow.
    canvas.drawCircle(
      Offset.zero,
      7,
      Paint()
        ..color = _cyan.withValues(alpha: 0.34)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      Offset.zero,
      2.8,
      Paint()
        ..color = const Color(0xFFDCEEFF).withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.9),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CabalPainter old) =>
      old.mode != mode ||
      old.level != level ||
      old.clock != clock ||
      old.face != face ||
      old.box != box;
}
