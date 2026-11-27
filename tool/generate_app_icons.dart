// Writes every app icon from the logo drawing in design/logo.
//
//   dart run tool/generate_app_icons.dart
//
// The drawing is a glass tile carrying the mark, set in a wide dark border of
// rings. An icon made from the whole drawing shows the mark at a third of the
// icon's width, and smaller again once a system adds its own margin or shape,
// so the icons are made from the tile alone:
//
//   Windows   windows/runner/resources/app_icon.ico   the tile, edge to edge
//   macOS     macos/.../AppIcon.appiconset/*.png      the tile on Apple's
//                                                     grid (824 of 1024)
//   Android   mipmap-*/ic_launcher_background.png     the tile's glass,
//             mipmap-*/ic_launcher_foreground.png     edge to edge, and the
//             + mipmap-anydpi-v26/ic_launcher.xml     mark alone, well inside
//             mipmap-*/ic_launcher.png                the tile, for Android 7
//
// An Android launcher cuts the icon to a shape of its own (a circle, a
// squircle, ...). A tile drawn inside that shape shows as a square within a
// circle, with a different colour in the corners. So there the glass fills
// the whole icon, whatever it is cut to, and only the mark is drawn on it,
// with room to spare on every side.
//   In-app    assets/app_icon.png                     the tile
//
// The tray icons are separate: see generate_tray_icons.dart.

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _source = 'design/logo/concept-3-icon.png';

// Where the tile is in the 1024-wide drawing (concept-3-icon.svg).
const _tileOrigin = 152;
const _tileSize = 720;
const _tileRadius = 164;

// The square of the tile that holds the mark and none of the tile's bright
// edge, in the tile's own coordinates.
const _markOrigin = 56;
const _markSize = 608;

const _androidDensities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

void main() {
  var drawing = img.decodePng(File(_source).readAsBytesSync());
  if (drawing == null) {
    stderr.writeln('Could not read $_source');
    exit(1);
  }
  if (drawing.width != 1024 || drawing.height != 1024) {
    drawing = img.copyResize(
      drawing,
      width: 1024,
      height: 1024,
      interpolation: img.Interpolation.cubic,
    );
  }
  final tile = _cutTile(drawing.convert(numChannels: 4));

  // In-app.
  _write('assets/app_icon.png', _scaled(tile, 256));

  // Windows: one file holding every size the shell asks for.
  final ico = img.IcoEncoder().encodeImages([
    for (final size in const [16, 24, 32, 48, 64, 128, 256])
      _scaled(tile, size),
  ]);
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico);
  stdout.writeln('wrote windows/runner/resources/app_icon.ico');

  // macOS: the body takes 824 of 1024, the margin Apple's own icons keep.
  for (final size in const [16, 32, 64, 128, 256, 512, 1024]) {
    final body = (size * 824 / 1024).round();
    _write(
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png',
      _centred(_scaled(tile, body), size),
    );
    _write(
      'design/logo/export/macos/app_icon_$size.png',
      _centred(_scaled(tile, body), size),
    );
  }

  // Android. An adaptive icon is 108 units wide; a launcher shows a shape
  // cut from the middle 72 and promises only a circle 66 across. The mark is
  // sized to sit well inside that circle.
  final corners = _glassCorners(tile);
  final mark = _cutMark(tile, corners);
  for (final MapEntry(key: density, value: scale)
      in _androidDensities.entries) {
    final folder = 'android/app/src/main/res/mipmap-$density';
    final canvas = (108 * scale).round();
    _write('$folder/ic_launcher_background.png', _glass(canvas, corners));
    _write(
      '$folder/ic_launcher_foreground.png',
      _centred(_scaled(mark, (canvas * 0.46).round()), canvas),
    );
    _write('$folder/ic_launcher.png', _scaled(tile, (48 * scale).round()));
  }
  final adaptive = File(
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
  )..parent.createSync(recursive: true);
  adaptive.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<!-- Written by tool/generate_app_icons.dart. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <!-- The mark alone, for launchers that tint icons to match a theme. -->
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');
  final oldColour = File(
    'android/app/src/main/res/values/ic_launcher_background.xml',
  );
  if (oldColour.existsSync()) oldColour.deleteSync();
  stdout.writeln('wrote the Android adaptive icon');
}

/// The colour of the tile's glass near each corner (top left, top right,
/// bottom left, bottom right): it is lighter where the light falls on it.
List<List<double>> _glassCorners(img.Image tile) {
  List<double> sample(int x, int y) {
    var r = 0.0, g = 0.0, b = 0.0;
    const side = 24;
    for (var dy = 0; dy < side; dy++) {
      for (var dx = 0; dx < side; dx++) {
        final pixel = tile.getPixel(x + dx, y + dy);
        r += pixel.r;
        g += pixel.g;
        b += pixel.b;
      }
    }
    return [r / (side * side), g / (side * side), b / (side * side)];
  }

  const near = 64;
  const far = _tileSize - 64 - 24;
  return [
    sample(near, near),
    sample(far, near),
    sample(near, far),
    sample(far, far),
  ];
}

/// The glass colour at a point, [u] across and [v] down, each 0 to 1.
List<double> _glassAt(List<List<double>> corners, double u, double v) => [
  for (var channel = 0; channel < 3; channel++)
    (corners[0][channel] * (1 - u) + corners[1][channel] * u) * (1 - v) +
        (corners[2][channel] * (1 - u) + corners[3][channel] * u) * v,
];

/// A square of the tile's glass with nothing on it, [size] wide.
img.Image _glass(int size, List<List<double>> corners) {
  final glass = img.Image(width: size, height: size, numChannels: 4);
  for (final pixel in glass) {
    final colour = _glassAt(
      corners,
      pixel.x / (size - 1),
      pixel.y / (size - 1),
    );
    pixel
      ..r = colour[0]
      ..g = colour[1]
      ..b = colour[2]
      ..a = 255;
  }
  return glass;
}

/// The mark alone, white on nothing, lifted off the tile: a pixel is part
/// of the mark as far as it is brighter than the glass around it.
img.Image _cutMark(img.Image tile, List<List<double>> corners) {
  final mark = img.Image(width: _markSize, height: _markSize, numChannels: 4);
  for (final pixel in mark) {
    final source = tile.getPixel(pixel.x + _markOrigin, pixel.y + _markOrigin);
    final glass = _glassAt(
      corners,
      (pixel.x + _markOrigin) / (_tileSize - 1),
      (pixel.y + _markOrigin) / (_tileSize - 1),
    );
    final brightness = (source.r + source.g + source.b) / 3;
    // The glass has a grain; a margin keeps its speckles out of the mark.
    final floor = (glass[0] + glass[1] + glass[2]) / 3 + 45;
    final coverage = ((brightness - floor) / (240 - floor)).clamp(0.0, 1.0);
    pixel
      ..r = 255
      ..g = 255
      ..b = 255
      ..a = 255 * coverage;
  }
  return mark;
}

/// The tile cut out of the drawing, its corners rounded and smooth.
img.Image _cutTile(img.Image drawing) {
  final tile = img.copyCrop(
    drawing,
    x: _tileOrigin,
    y: _tileOrigin,
    width: _tileSize,
    height: _tileSize,
  );
  const radius = _tileRadius * 1.0;
  for (final pixel in tile) {
    // How far inside the rounded square this pixel's centre is; the edge
    // fades over one pixel instead of stepping.
    final dx = math.max(
      0,
      (pixel.x + 0.5 - _tileSize / 2).abs() - (_tileSize / 2 - radius),
    );
    final dy = math.max(
      0,
      (pixel.y + 0.5 - _tileSize / 2).abs() - (_tileSize / 2 - radius),
    );
    final inside = radius - math.sqrt(dx * dx + dy * dy);
    final coverage = (inside + 0.5).clamp(0.0, 1.0);
    pixel.a = pixel.a * coverage;
  }
  return tile;
}

img.Image _scaled(img.Image image, int size) => img.copyResize(
  image,
  width: size,
  height: size,
  // Averaging keeps the thin strokes of the mark when shrinking a lot.
  interpolation: img.Interpolation.average,
);

/// [image] in the middle of a transparent square [size] wide.
img.Image _centred(img.Image image, int size) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.compositeImage(
    canvas,
    image,
    dstX: (size - image.width) ~/ 2,
    dstY: (size - image.height) ~/ 2,
  );
  return canvas;
}

void _write(String path, img.Image image) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $path (${image.width}x${image.height})');
}
