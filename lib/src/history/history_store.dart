import 'dart:convert';
import 'dart:io';

import 'clipboard_entry.dart';

/// Where the clipboard history lives between launches.
abstract interface class HistoryStore {
  /// The saved entries, or an empty list when nothing was saved yet or the
  /// saved data cannot be read.
  Future<List<ClipboardEntry>> load();

  Future<void> save(List<ClipboardEntry> entries);
}

/// Keeps nothing; for tests and for running without a writable disk.
class MemoryHistoryStore implements HistoryStore {
  MemoryHistoryStore([List<ClipboardEntry> initial = const []])
    : saved = List.of(initial);

  List<ClipboardEntry> saved;
  int saveCount = 0;

  @override
  Future<List<ClipboardEntry>> load() async => List.of(saved);

  @override
  Future<void> save(List<ClipboardEntry> entries) async {
    saved = List.of(entries);
    saveCount++;
  }
}

/// One JSON file. Written to a sibling file first and then renamed over the
/// old one, so a crash mid-write cannot leave a half-written history.
///
/// The file is plain text on disk: anything copied, including secrets, is
/// readable by whoever can read the user's files.
class JsonFileHistoryStore implements HistoryStore {
  JsonFileHistoryStore(this.file);

  static const _version = 1;

  final File file;

  @override
  Future<List<ClipboardEntry>> load() async {
    try {
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return const [];
      final entries = decoded['entries'];
      if (entries is! List) return const [];
      return [
        for (final entry in entries)
          if (entry is Map<String, Object?>) ClipboardEntry.fromJson(entry),
      ];
    } on FormatException {
      return const [];
    } on TypeError {
      // A file from a different shape of this app; start over rather than
      // refuse to launch.
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  @override
  Future<void> save(List<ClipboardEntry> entries) async {
    final payload = jsonEncode({
      'version': _version,
      'entries': [for (final entry in entries) entry.toJson()],
    });
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    await temporary.rename(file.path);
  }
}
