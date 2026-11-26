import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// The secret that devices share in order to sync with each other.
///
/// It is 20 characters from a 32-character alphabet, so 100 bits: long enough
/// that it cannot be guessed, short enough to type once on the other device.
/// Every device holding the same key is in the same group; nothing else is
/// needed to pair. The key itself never travels over the network.
class SyncKey {
  const SyncKey._(this.canonical);

  /// Digits and capitals, without the letters that are easy to misread
  /// (I, L, O, U).
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const length = 20;
  static const _groupSize = 5;

  /// The 20 characters, upper case, no separators.
  final String canonical;

  static SyncKey generate([Random? random]) {
    final source = random ?? Random.secure();
    return SyncKey._(
      String.fromCharCodes([
        for (var i = 0; i < length; i++)
          alphabet.codeUnitAt(source.nextInt(alphabet.length)),
      ]),
    );
  }

  /// Reads a key the way a person types it: any case, with or without dashes
  /// and spaces, and with the look-alike letters accepted for the digits they
  /// resemble. Returns null when it is not a complete key.
  static SyncKey? tryParse(String input) {
    final cleaned = input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (cleaned.length != length) return null;
    for (final unit in cleaned.codeUnits) {
      if (!alphabet.codeUnits.contains(unit)) return null;
    }
    return SyncKey._(cleaned);
  }

  /// The key in groups of five, as shown to the user: `ABCDE-FGHJK-…`.
  String get formatted => [
    for (var i = 0; i < length; i += _groupSize)
      canonical.substring(i, i + _groupSize),
  ].join('-');

  /// The bytes mixed into every session's encryption keys.
  List<int> get secretBytes => utf8.encode('syncclip/1 key:$canonical');

  /// What a device announces on the network next to its [deviceId].
  ///
  /// Another device holding the same key can recompute it and so recognise a
  /// member of its group; a device without the key learns nothing from it.
  Future<String> discoveryTag(String deviceId) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode('syncclip/1 discovery:$deviceId'),
      secretKey: SecretKey(secretBytes),
    );
    return [
      for (final byte in mac.bytes.take(8))
        byte.toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  @override
  bool operator ==(Object other) =>
      other is SyncKey && other.canonical == canonical;

  @override
  int get hashCode => canonical.hashCode;

  // Never print the secret by accident.
  @override
  String toString() => 'SyncKey(…)';
}
