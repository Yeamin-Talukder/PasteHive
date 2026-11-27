// Writes the Android launcher icons from the app icon in design/logo.
//
//   dart run tool/generate_android_icons.dart
//
// One PNG per screen density goes into android/app/src/main/res/mipmap-*.

import 'dart:io';

import 'package:image/image.dart' as img;

const _source = 'design/logo/export/macos/app_icon_1024.png';

const _sizes = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

void main() {
  final source = img.decodePng(File(_source).readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not read $_source');
    exit(1);
  }
  for (final MapEntry(key: density, value: size) in _sizes.entries) {
    final icon = img.copyResize(
      source,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    final path = 'android/app/src/main/res/mipmap-$density/ic_launcher.png';
    File(path).writeAsBytesSync(img.encodePng(icon));
    stdout.writeln('wrote $path (${size}x$size)');
  }
}
