import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/platform/native_ports.dart';

void main() {
  final bytes = [for (var i = 0; i < 200; i++) (i * 7) % 256];
  final plain = base64Encode(bytes);

  test('reads a data URI', () {
    expect(decodeDataUri('data:image/png;base64,$plain'), bytes);
  });

  test('reads bare base64', () {
    expect(decodeDataUri(plain), bytes);
  });

  test('reads base64 that was wrapped into lines', () {
    final wrapped = [
      for (var i = 0; i < plain.length; i += 64)
        plain.substring(i, (i + 64).clamp(0, plain.length)),
    ].join('\r\n');
    expect(decodeDataUri('data:image/png;base64,$wrapped\r\n'), bytes);
  });

  test('reads base64 whose padding was left off', () {
    final unpadded = base64Encode([1, 2, 3, 4]).replaceAll('=', '');
    expect(decodeDataUri(unpadded), [1, 2, 3, 4]);
  });

  test('ignores stray characters around the data', () {
    expect(decodeDataUri('data:image/png;base64,$plain\u0000'), bytes);
    expect(decodeDataUri(' $plain== \n'), bytes);
  });

  test('refuses a length no encoding produces', () {
    expect(
      () => decodeDataUri('data:image/png;base64,ABCDE'),
      throwsFormatException,
    );
  });
}
