import 'dart:ui' show Color;

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

  group('kinds', () {
    ClipboardEntry entry(String text) =>
        ClipboardEntry(id: 'a', text: text, copiedAt: DateTime.utc(2026));

    test('tells links, emails, colours and plain text apart', () {
      expect(entry('https://flutter.dev').kind, EntryKind.link);
      expect(entry(' someone@example.com\n').kind, EntryKind.email);
      expect(entry('#1E90FF').kind, EntryKind.color);
      expect(entry('#fff').kind, EntryKind.color);
      expect(entry('#12345').kind, EntryKind.text);
      expect(entry('#hashtag').kind, EntryKind.text);
      expect(entry('mail someone@example.com').kind, EntryKind.text);
      expect(entry('ftp://files.example.com').kind, EntryKind.text);
    });

    test('reads a colour in its three spellings', () {
      expect(entry('#1E90FF').color, const Color(0xFF1E90FF));
      expect(entry('#f80').color, const Color(0xFFFF8800));
      expect(entry('#1E90FF80').color, const Color(0x801E90FF));
      expect(entry('plain').color, isNull);
    });
  });

  group('filters', () {
    late ClipboardHistory history;

    setUp(() {
      history = historyWith([
        'a note',
        'https://flutter.dev',
        'someone@example.com',
        '#1E90FF',
      ]);
      history
        ..record('from the mac', source: 'Mac')
        ..togglePin(history.entries.last.id);
    });

    List<String> shown(EntryFilter filter, [String query = '']) => [
      for (final entry in history.search(query, filter: filter)) entry.text,
    ];

    test('each filter keeps only its own kind', () {
      expect(shown(EntryFilter.all), hasLength(5));
      expect(shown(EntryFilter.pinned), ['a note']);
      expect(shown(EntryFilter.text), ['a note', 'from the mac']);
      expect(shown(EntryFilter.links), ['https://flutter.dev']);
      expect(shown(EntryFilter.emails), ['someone@example.com']);
      expect(shown(EntryFilter.colors), ['#1E90FF']);
      expect(shown(EntryFilter.synced), ['from the mac']);
    });

    test('a filter and a search both have to match', () {
      expect(shown(EntryFilter.text, 'mac'), ['from the mac']);
      expect(shown(EntryFilter.links, 'mac'), isEmpty);
    });
  });

  group('where an entry came from', () {
    test('is remembered, and saved', () async {
      final store = MemoryHistoryStore();
      final history = historyWith([], store: store)
        ..record('local')
        ..record('remote', source: 'Mac');
      await history.flush();

      expect(history.entries.first.source, 'Mac');
      expect(history.entries.first.isSynced, isTrue);
      expect(history.entries.last.isSynced, isFalse);
      expect(ClipboardEntry.fromJson(store.saved.first.toJson()).source, 'Mac');
    });

    test('follows the latest copy of the same text', () {
      final history = historyWith(['same'])..record('same', source: 'Mac');
      expect(history.entries.single.source, 'Mac');

      history.record('same');
      expect(history.entries.single.source, isNull);
    });
  });

  group('restore', () {
    test('puts a removed entry back where it was', () {
      final history = historyWith(['one', 'two', 'three']);
      final removed = history.entries[1];
      history
        ..remove(removed.id)
        ..restore(removed);

      expect(texts(history), ['three', 'two', 'one']);
      expect(history.entries[1], removed);
    });

    test('does nothing if the text was copied again meanwhile', () {
      final history = historyWith(['one', 'two']);
      final removed = history.entries.last;
      history
        ..remove(removed.id)
        ..record('one')
        ..restore(removed);

      expect(texts(history), ['one', 'two']);
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
