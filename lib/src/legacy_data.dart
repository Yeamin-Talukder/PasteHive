import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// The names the app's data folder went by before the app was renamed to
/// PasteHive.
const _formerNames = ['synchronize_clipboard', 'synchronizeClipboard'];

/// Brings the history, pictures and sync pairing along from where the app
/// kept them under its old name, the first time it runs under the new one.
///
/// The old folder is copied, not moved: nothing is lost if this goes wrong,
/// and an older copy of the app that is still around keeps working. It does
/// nothing once [support] has a history of its own. Returns whether anything
/// was brought over.
Future<bool> adoptDataFromFormerName(Directory support) async {
  try {
    if (await File(path.join(support.path, 'history.json')).exists()) {
      return false;
    }
    for (final former in _formerNames) {
      final old = Directory(support.path.replaceAll('pastehive', former));
      if (old.path == support.path || !await old.exists()) continue;
      await _copy(old, support);
      return true;
    }
  } on FileSystemException catch (error) {
    // Starting with an empty list is better than not starting.
    debugPrint('Could not bring over the data from the old name: $error');
  }
  return false;
}

Future<void> _copy(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entity in from.list()) {
    final target = path.join(to.path, path.basename(entity.path));
    if (entity is File) {
      await entity.copy(target);
    } else if (entity is Directory) {
      await _copy(entity, Directory(target));
    }
  }
}
