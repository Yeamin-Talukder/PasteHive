import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/sync/sync_key.dart';

void main() {
  test('a generated key is 20 characters from the unambiguous alphabet', () {
    final key = SyncKey.generate(Random(1));

    expect(key.canonical, hasLength(20));
    expect(key.canonical, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{20}$')));
    expect(
      key.formatted,
      matches(RegExp(r'^[0-9A-Z]{5}-[0-9A-Z]{5}-[0-9A-Z]{5}-[0-9A-Z]{5}$')),
    );
  });

  test('two generated keys differ', () {
    expect(SyncKey.generate(), isNot(SyncKey.generate()));
  });

  test('reads a key the way people type it', () {
    final key = SyncKey.generate(Random(7));

    expect(SyncKey.tryParse(key.formatted), key);
    expect(SyncKey.tryParse(key.canonical.toLowerCase()), key);
    expect(SyncKey.tryParse('  ${key.formatted.replaceAll('-', ' ')}\n'), key);
  });

  test('takes look-alike letters for the digits they resemble', () {
    expect(
      SyncKey.tryParse('OOOOO-IIIII-LLLLL-ooooo')!.canonical,
      '00000111111111100000',
    );
  });

  test('rejects anything that is not a complete key', () {
    expect(SyncKey.tryParse(''), isNull);
    expect(SyncKey.tryParse('ABCDE-FGHJK'), isNull);
    expect(SyncKey.tryParse('ABCDE-FGHJK-MNPQR-STVWX-YZ'), isNull);
    expect(SyncKey.tryParse('ABCDE-FGHJK-MNPQR-STVW!'), isNull);
    expect(SyncKey.tryParse('UUUUU-UUUUU-UUUUU-UUUUU'), isNull);
  });

  group('discovery tag', () {
    final key = SyncKey.tryParse('ABCDE-FGHJK-MNPQR-STVWX')!;
    final other = SyncKey.tryParse('ABCDE-FGHJK-MNPQR-STVWY')!;

    test('is the same every time for the same key and device', () async {
      expect(
        await key.discoveryTag('device-1'),
        await key.discoveryTag('device-1'),
      );
      expect(await key.discoveryTag('device-1'), matches(r'^[0-9a-f]{16}$'));
    });

    test('differs between devices and between keys', () async {
      final tag = await key.discoveryTag('device-1');
      expect(await key.discoveryTag('device-2'), isNot(tag));
      expect(await other.discoveryTag('device-1'), isNot(tag));
    });
  });

  test('does not print the secret', () {
    final key = SyncKey.generate(Random(3));
    expect('$key', isNot(contains(key.canonical)));
    expect('$key', isNot(contains(key.formatted)));
  });
}
