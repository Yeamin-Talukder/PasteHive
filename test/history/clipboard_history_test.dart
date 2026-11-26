import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/history/clipboard_entry.dart';
import 'package:synchronize_clipboard/src/history/clipboard_history.dart';
import 'package:synchronize_clipboard/src/history/history_store.dart';

import '../fakes.dart';

List<String> texts(ClipboardHistory history) => [
  for (final entry in history.entries) entry.text,
];

void main() {
  group('recording', () {
    test('puts the newest copy first', () {
      final history = historyWith(['one', 'two', 'three']);
      expect(texts(history), ['three', 'two', 'one']);
    });

    test(
      'moves text that was copied before to the top instead of repeating it',
      () {
        final history = historyWith(['one', 'two', 'three']);
        final originalId = history.entries.last.id;

        expect(history.record('one'), isTrue);

        expect(texts(history), ['one', 'three', 'two']);
        expect(history.entries.first.id, originalId);
      },
    );

    test('ignores blank text', () {
      final history = historyWith([]);
      expect(history.record(''), isFalse);
      expect(history.record('  \n\t '), isFalse);
      expect(history.isEmpty, isTrue);
    });

    test('keeps leading and trailing whitespace of what was copied', () {
      final history = historyWith(['  indented\n']);
      expect(history.entries.single.text, '  indented\n');
    });

    test('ignores text longer than the limit', () {
      final history = ClipboardHistory(
        store: MemoryHistoryStore(),
        maxTextLength: 5,
      );
      expect(history.record('123456'), isFalse);
      expect(history.record('12345'), isTrue);
      expect(texts(history), ['12345']);
    });

    test('records nothing while paused', () {
      final history = historyWith(['one'])..paused = true;
      expect(history.record('two'), isFalse);
      expect(texts(history), ['one']);

      history.paused = false;
      expect(history.record('two'), isTrue);
    });

    test('drops the oldest unpinned entries past the limit', () {
      final history = ClipboardHistory(
        store: MemoryHistoryStore(),
        clock: tickingClock(),
        maxUnpinnedEntries: 2,
      );
      history.record('one');
      history.togglePin(history.entries.single.id);
      history
        ..record('two')
        ..record('three')
        ..record('four');

      expect(texts(history), ['one', 'four', 'three']);
    });

    test('tells listeners about each change', () {
      final history = historyWith([]);
      var notifications = 0;
      history.addListener(() => notifications++);

      history.record('one');
      history.record('   ');

      expect(notifications, 1);
    });
  });

  group('pinning', () {
    test('pinned entries sort above newer unpinned ones', () {
      final history = historyWith(['one', 'two', 'three']);
      history.togglePin(history.entries.last.id);

      expect(texts(history), ['one', 'three', 'two']);
      expect(history.entries.first.pinned, isTrue);

      history.record('four');
      expect(texts(history), ['one', 'four', 'three', 'two']);
    });

    test('unpinning puts an entry back in time order', () {
      final history = historyWith(['one', 'two', 'three']);
      final id = history.entries.last.id;
      history
        ..togglePin(id)
        ..togglePin(id);

      expect(texts(history), ['three', 'two', 'one']);
    });

    test('clearing keeps pinned entries', () {
      final history = historyWith(['one', 'two', 'three']);
      history
        ..togglePin(history.entries[1].id)
        ..clearUnpinned();

      expect(texts(history), ['two']);
    });
  });

  test('remove deletes one entry and ignores unknown ids', () {
    final history = historyWith(['one', 'two']);
    history
      ..remove(history.entries.first.id)
      ..remove('no-such-id');
    expect(texts(history), ['one']);
  });

  group('search', () {
    final history = historyWith([
      'Flight BA 117 to New York',
      'https://flutter.dev/docs',
      'new password for the york office',
    ]);

    test('an empty query returns everything', () {
      expect(history.search('   '), history.entries);
    });

    test('ignores case', () {
      expect(history.search('FLUTTER').single.text, contains('flutter.dev'));
    });

    test('needs every word, in any order', () {
      expect(
        [for (final entry in history.search('york new')) entry.text],
        ['new password for the york office', 'Flight BA 117 to New York'],
      );
      expect(history.search('york flutter'), isEmpty);
    });
  });

  group('saving', () {
    test('writes changes to the store and reads them back in order', () async {
      final store = MemoryHistoryStore();
      final history = historyWith(['one', 'two'], store: store);
      history.togglePin(history.entries.last.id);
      await history.flush();

      final reloaded = ClipboardHistory(store: store);
      await reloaded.load();

      expect(texts(reloaded), ['one', 'two']);
      expect(reloaded.entries.first.pinned, isTrue);
    });

    test('a burst of copies costs one write', () async {
      final store = MemoryHistoryStore();
      final history = ClipboardHistory(
        store: store,
        clock: tickingClock(),
        saveDelay: const Duration(seconds: 5),
      );
      history
        ..record('one')
        ..record('two')
        ..record('three');
      await history.flush();

      expect(store.saveCount, 1);
      expect(store.saved, hasLength(3));
    });

    test('a store that fails does not break recording', () async {
      final history = ClipboardHistory(
        store: _FailingStore(),
        saveDelay: Duration.zero,
      );
      history.record('one');
      await history.flush();
      history.record('two');
      await history.flush();

      expect(texts(history), ['two', 'one']);
    });
  });

  group('entry', () {
    ClipboardEntry entry(String text) =>
        ClipboardEntry(id: 'a', text: text, copiedAt: DateTime.utc(2026));

    test('preview is the first line with content, whitespace collapsed', () {
      expect(entry('\n\n  hello    world \nsecond').preview, 'hello world');
    });

    test('recognises a lone web address as a link', () {
      expect(entry(' https://flutter.dev/docs ').isLink, isTrue);
      expect(entry('see https://flutter.dev').isLink, isFalse);
      expect(entry('mailto:someone@example.com').isLink, isFalse);
      expect(entry('plain words').isLink, isFalse);
    });

    test('counts lines without a trailing newline adding one', () {
      expect(entry('one').lineCount, 1);
      expect(entry('one\ntwo\n').lineCount, 2);
    });

    test('survives a trip through JSON', () {
      final original = ClipboardEntry(
        id: 'abc-1',
        text: 'héllo\n"quoted"',
        copiedAt: DateTime.utc(2026, 11, 26, 9, 30),
        pinned: true,
      );
      expect(ClipboardEntry.fromJson(original.toJson()), original);
    });
  });
}

class _FailingStore implements HistoryStore {
  @override
  Future<List<ClipboardEntry>> load() async => const [];

  @override
  Future<void> save(List<ClipboardEntry> entries) async {
    throw const FormatException('disk is full');
  }
}
