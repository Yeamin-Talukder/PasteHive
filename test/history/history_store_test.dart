import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:synchronize_clipboard/src/history/clipboard_entry.dart';
import 'package:synchronize_clipboard/src/history/history_store.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('history_store_test');
    file = File(path.join(directory.path, 'nested', 'history.json'));
  });

  tearDown(() => directory.deleteSync(recursive: true));

  final entries = [
    ClipboardEntry(
      id: 'b-2',
      text: 'second\nline — with “quotes”',
      copiedAt: DateTime.utc(2026, 11, 26, 10),
      pinned: true,
    ),
    ClipboardEntry(
      id: 'a-1',
      text: 'first',
      copiedAt: DateTime.utc(2026, 11, 26, 9),
    ),
  ];

  test('loads nothing when no file was written yet', () async {
    expect(await JsonFileHistoryStore(file).load(), isEmpty);
  });

  test('reads back what it saved, creating the folder on the way', () async {
    await JsonFileHistoryStore(file).save(entries);
    expect(await JsonFileHistoryStore(file).load(), entries);
  });

  test(
    'a later save replaces the earlier one and leaves no temp file',
    () async {
      final store = JsonFileHistoryStore(file);
      await store.save(entries);
      await store.save([entries.last]);

      expect(await store.load(), [entries.last]);
      expect(
        [for (final item in file.parent.listSync()) path.basename(item.path)],
        ['history.json'],
      );
    },
  );

  test('treats a damaged file as an empty history', () async {
    file.parent.createSync(recursive: true);

    file.writeAsStringSync('{"entries": [{"id": "a", "tex');
    expect(await JsonFileHistoryStore(file).load(), isEmpty);

    file.writeAsStringSync('[1, 2, 3]');
    expect(await JsonFileHistoryStore(file).load(), isEmpty);

    file.writeAsStringSync('{"entries": [{"id": 7, "text": "x"}]}');
    expect(await JsonFileHistoryStore(file).load(), isEmpty);
  });
}
