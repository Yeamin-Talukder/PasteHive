// Draws the tray icons into assets/tray/.
//
//   dart run tool/generate_tray_icons.dart
//
// SUPERSEDED: the tray icons in assets/tray/ now come from the logo, as
// copies of design/logo/export/tray/ (sources: design/logo/
// concept-3-tray-*.svg). Running this tool overwrites them with the older
// clipboard drawing described below.
//
// The icon is a clipboard: a rounded board with a clip at the top and two
// lines of "text". It is drawn large and scaled down so the edges come out
// smooth. Two versions are written:
//
//   tray_windows.png  white board on an accent-blue tile, readable on both
//                     light and dark taskbars
//   tray_macos.png    black on transparent, a template image the menu bar
//                     tints itself

import 'dart:io';

import 'package:image/image.dart' as img;

const _scale = 16;

void main() {
  Directory('assets/tray').createSync(recursive: true);
  _write('assets/tray/tray_windows.png', _windowsIcon(), 32);
  _write('assets/tray/tray_macos.png', _macosIcon(), 36);
}

void _write(String path, img.Image large, int size) {
  final small = img.copyResize(
    large,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
  File(path).writeAsBytesSync(img.encodePng(small));
  stdout.writeln('wrote $path (${size}x$size)');
}

img.Image _canvas(int units) {
  return img.Image(
    width: units * _scale,
    height: units * _scale,
    numChannels: 4,
  )..clear(img.ColorRgba8(0, 0, 0, 0));
}

void _roundRect(
  img.Image image,
  double left,
  double top,
  double right,
  double bottom,
  double radius,
  img.Color color,
) {
  img.fillRect(
    image,
    x1: (left * _scale).round(),
    y1: (top * _scale).round(),
    x2: (right * _scale).round() - 1,
    y2: (bottom * _scale).round() - 1,
    radius: radius * _scale,
    color: color,
  );
}

img.Image _windowsIcon() {
  final image = _canvas(32);
  final blue = img.ColorRgba8(10, 132, 255, 255);
  final white = img.ColorRgba8(255, 255, 255, 255);
  _roundRect(image, 1, 1, 31, 31, 8, blue);
  _roundRect(image, 9, 8, 23, 26, 2.5, white);
  _roundRect(image, 12.5, 5.5, 19.5, 10.5, 1.5, white);
  _roundRect(image, 14, 7, 18, 9, 0.8, blue);
  _roundRect(image, 12, 14, 20, 15.8, 0.9, blue);
  _roundRect(image, 12, 18.5, 20, 20.3, 0.9, blue);
  return image;
}

img.Image _macosIcon() {
  final image = _canvas(36);
  final black = img.ColorRgba8(0, 0, 0, 255);
  final clear = img.ColorRgba8(0, 0, 0, 0);
  // Outline of the board.
  _roundRect(image, 7, 6, 29, 33, 4.5, black);
  _punch(image, 9.5, 8.5, 26.5, 30.5, 2.5, clear);
  // The clip, sitting over the top edge.
  _punch(image, 11, 2, 25, 11, 3, clear);
  _roundRect(image, 12.5, 3, 23.5, 9.5, 2.5, black);
  // Two lines of text.
  _roundRect(image, 13, 15, 23, 17.5, 1.2, black);
  _roundRect(image, 13, 21.5, 23, 24, 1.2, black);
  return image;
}

// Erases a rounded rectangle: fillRect blends, so transparent pixels are set
// directly.
void _punch(
  img.Image image,
  double left,
  double top,
  double right,
  double bottom,
  double radius,
  img.Color color,
) {
  final x1 = left * _scale;
  final y1 = top * _scale;
  final x2 = right * _scale;
  final y2 = bottom * _scale;
  final r = radius * _scale;
  for (var y = y1.floor(); y < y2.ceil(); y++) {
    for (var x = x1.floor(); x < x2.ceil(); x++) {
      final dx = x < x1 + r ? x1 + r - x : (x > x2 - r ? x - (x2 - r) : 0.0);
      final dy = y < y1 + r ? y1 + r - y : (y > y2 - r ? y - (y2 - r) : 0.0);
      if (dx * dx + dy * dy <= r * r) image.setPixel(x, y, color);
    }
  }
}
