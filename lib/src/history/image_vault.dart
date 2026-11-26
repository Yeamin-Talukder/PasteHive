import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;

/// Where copied images are kept, as PNG files in one folder.
///
/// A file is named after a hash of its contents, so the same picture copied
/// twice is stored once and is recognised as the same entry.
///
/// The files are plain images on disk: anyone who can read this user's files
/// can open them.
class ImageVault {
  ImageVault(this.directory);

  final Directory directory;

  /// Saves [png] and returns the file's path. Saving the same bytes again
  /// returns the same path without writing anything.
  Future<String> store(Uint8List png) async {
    final digest = await Sha256().hash(png);
    final name = [
      for (final byte in digest.bytes.take(16))
        byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    final file = File(path.join(directory.path, '$name.png'));
    if (!await file.exists()) {
      await directory.create(recursive: true);
      // Written beside it and renamed, so a half-written file is never
      // mistaken for a picture.
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(png, flush: true);
      await temporary.rename(file.path);
    }
    return file.path;
  }

  /// Deletes every stored image that is not in [keep]. Returns how many
  /// were deleted.
  ///
  /// Run at launch and at quit rather than when an entry is removed: a
  /// removed entry can still be brought back for a few seconds, and needs
  /// its picture.
  Future<int> removeAllExcept(Iterable<String> keep) async {
    if (!await directory.exists()) return 0;
    final kept = {for (final file in keep) path.canonicalize(file)};
    var removed = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (kept.contains(path.canonicalize(entity.path))) continue;
      try {
        await entity.delete();
        removed++;
      } on FileSystemException {
        // In use, or gone already; the next run gets it.
      }
    }
    return removed;
  }
}
