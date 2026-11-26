import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../platform/ports.dart';
import 'panel_palette.dart';
import 'panel_surface.dart';

/// The panel as a pane of glass that the app draws itself.
///
/// It fills a transparent window that is a little larger than the panel. As
/// [reveal] goes from 0 to 1 the glass grows out of a thin pill at the top
/// edge of the screen into the full panel: it widens first and then drops
/// down, and the content inside is scaled to fit it the whole way, so it is
/// never cut off at the sides. Shape, shadow, edge and content all follow the
/// one animation, so nothing can get out of step. The window itself never
/// moves.
class GlassShell extends StatelessWidget {
  const GlassShell({
    super.key,
    required this.reveal,
    required this.insets,
    required this.backdrop,
    required this.onTapOutside,
    required this.child,
  });

  /// The panel's corners at rest. Generous, like a sheet of glass rather
  /// than a window.
  static const double cornerRadius = 26;

  static const Size _pillSize = Size(150, 10);
  static const double _pillRadius = 5;

  /// 0 while hidden, 1 at rest. May run a little past 1 as the spring
  /// settles.
  final Animation<double> reveal;

  /// The space between the window's edges and the panel at rest.
  final EdgeInsets insets;

  /// A blurred picture of what is behind the window, the size of the window.
  /// Null when none could be taken; the glass is then opaque.
  final ui.Image? backdrop;

  /// A click on the empty margin around the panel.
  final VoidCallback onTapOutside;

  final Widget child;

  /// The outline of the glass at [progress] along its entrance, for a panel
  /// resting at [rest].
  static RRect shapeAt(Rect rest, double progress) {
    if (progress <= 0) return RRect.zero;
    final settled = progress.clamp(0.0, 1.0);
    // Anything past 1 is the spring overshooting; it is added back on so
    // the glass swells a touch before it settles.
    final overshoot = progress - settled;
    // The width runs ahead of the height: the pill stretches sideways and
    // then the sheet drops.
    final across = 1 - math.pow(1 - settled, 2.4) + overshoot;
    final down = settled + overshoot;

    final width = ui.lerpDouble(_pillSize.width, rest.width, across)!;
    final top = ui.lerpDouble(rest.top - _pillSize.height, rest.top, settled)!;
    final bottom = ui.lerpDouble(rest.top, rest.bottom, down)!;
    return RRect.fromRectAndRadius(
      Rect.fromLTRB(
        rest.center.dx - width / 2,
        top,
        rest.center.dx + width / 2,
        bottom,
      ),
      Radius.circular(
        ui.lerpDouble(
          _pillRadius,
          cornerRadius,
          Curves.easeOut.transform(settled),
        )!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = PanelPalette.of(
      brightness: Theme.of(context).brightness,
      hasMaterial: backdrop != null,
      highContrast: MediaQuery.highContrastOf(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final rest = insets.deflateRect(Offset.zero & constraints.biggest);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTapOutside,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ShadowPainter(reveal, rest, palette),
                ),
              ),
            ),
            Positioned.fill(
              child: ClipRRect(
                clipper: _ShapeClipper(reveal, rest),
                child: Stack(
                  children: [
                    if (backdrop != null)
                      Positioned.fill(
                        child: RawImage(image: backdrop, fit: BoxFit.fill),
                      ),
                    // The tint that turns the blurred picture into glass,
                    // there from the first frame.
                    Positioned.fill(child: ColoredBox(color: palette.surface)),
                    Positioned.fromRect(
                      rect: rest,
                      child: _Content(
                        reveal: reveal,
                        rest: rest,
                        // Swallows clicks on the glass itself, so only the
                        // margin around it counts as outside.
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: GlassScope(child: child),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _RimPainter(reveal, rest, palette)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Keeps the content fitted to the glass while it opens, and fades it in
/// once there is room for it.
class _Content extends StatelessWidget {
  const _Content({
    required this.reveal,
    required this.rest,
    required this.child,
  });

  final Animation<double> reveal;
  final Rect rest;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reveal,
      child: child,
      builder: (context, child) {
        final progress = reveal.value;
        if (progress == 1) return child!;
        final shape = GlassShell.shapeAt(rest, progress).outerRect;
        final opacity = ((progress - 0.22) / 0.5).clamp(0.0, 1.0);
        return IgnorePointer(
          // Half-open glass is not something to click on.
          ignoring: progress < 0.8,
          child: Opacity(
            opacity: Curves.easeOut.transform(opacity),
            child: Transform(
              // As wide as the glass is right now, hanging from its top
              // edge.
              transform: Matrix4.identity()
                ..translateByDouble(0, shape.top - rest.top, 0, 1)
                ..scaleByDouble(
                  shape.width / rest.width,
                  shape.width / rest.width,
                  1,
                  1,
                ),
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _ShapeClipper extends CustomClipper<RRect> {
  _ShapeClipper(this.reveal, this.rest) : super(reclip: reveal);

  final Animation<double> reveal;
  final Rect rest;

  @override
  RRect getClip(Size size) => GlassShell.shapeAt(rest, reveal.value);

  @override
  bool shouldReclip(_ShapeClipper oldClipper) =>
      oldClipper.rest != rest || oldClipper.reveal != reveal;
}

/// The shadow under the glass: a wide soft one for height and a tight one
/// where it meets what is below.
class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.reveal, this.rest, this.palette) : super(repaint: reveal);

  final Animation<double> reveal;
  final Rect rest;
  final PanelPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = reveal.value;
    if (progress <= 0) return;
    final shape = GlassShell.shapeAt(rest, progress);
    final strength = progress.clamp(0.0, 1.0);
    final dark = palette.brightness == Brightness.dark;

    canvas
      ..drawRRect(
        shape.shift(Offset(0, 20 * strength)),
        Paint()
          ..color = palette.shadow.withValues(
            alpha: (dark ? 0.50 : 0.24) * strength,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 28 * strength + 1),
      )
      ..drawRRect(
        shape.shift(Offset(0, 3 * strength)),
        Paint()
          ..color = palette.shadow.withValues(
            alpha: (dark ? 0.30 : 0.12) * strength,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
  }

  @override
  bool shouldRepaint(_ShadowPainter oldDelegate) =>
      oldDelegate.rest != rest || oldDelegate.palette != palette;
}

/// The edge of the glass: a soft glow of light falling in from the top, a
/// hairline outside it, and a line of light just inside that is brightest
/// along the top.
class _RimPainter extends CustomPainter {
  _RimPainter(this.reveal, this.rest, this.palette) : super(repaint: reveal);

  final Animation<double> reveal;
  final Rect rest;
  final PanelPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = reveal.value;
    if (progress <= 0) return;
    final shape = GlassShell.shapeAt(rest, progress);
    final bounds = shape.outerRect;

    canvas
      ..save()
      ..clipRRect(shape)
      ..drawRect(
        Rect.fromLTWH(bounds.left, bounds.top, bounds.width, 90),
        Paint()
          ..shader = ui.Gradient.linear(
            bounds.topCenter,
            bounds.topCenter + const Offset(0, 90),
            [palette.sheen, palette.sheen.withValues(alpha: 0)],
          ),
      )
      ..restore()
      ..drawRRect(
        shape.inflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.outline,
      )
      ..drawRRect(
        shape.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = ui.Gradient.linear(
            bounds.topCenter,
            bounds.bottomCenter,
            [palette.rimHighlight, palette.rimShade, palette.rimShade],
            const [0, 0.35, 1],
          ),
      );
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      oldDelegate.rest != rest || oldDelegate.palette != palette;
}

/// Turns a picture of the screen into the frosted backdrop of the glass:
/// blurred until nothing in it can be read, with its colours lifted a little
/// so the glass does not look grey.
Future<ui.Image> blurBackdrop(
  BackdropCapture capture, {
  required double devicePixelRatio,
}) async {
  final decoded = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    capture.bgra,
    capture.width,
    capture.height,
    ui.PixelFormat.bgra8888,
    decoded.complete,
  );
  final sharp = await decoded.future;

  final recorder = ui.PictureRecorder();
  final sigma = 30 * devicePixelRatio;
  Canvas(recorder).drawImage(
    sharp,
    Offset.zero,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      )
      ..colorFilter = const ColorFilter.matrix(_saturate),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(capture.width, capture.height);
  } finally {
    picture.dispose();
    sharp.dispose();
  }
}

// Saturation of 1.5, from the usual luminance weights.
const List<double> _saturate = [
  1.3935, -0.3575, -0.0360, 0, 0, //
  -0.1065, 1.1425, -0.0360, 0, 0, //
  -0.1065, -0.3575, 1.4640, 0, 0, //
  0, 0, 0, 1, 0,
];
