import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/history/clipboard_entry.dart';
import 'package:pastehive/src/history/clipboard_history.dart';
import 'package:pastehive/src/history/history_store.dart';

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

  group('pictures and files', () {
    test('a picture is an entry of its own kind', () {
      final history = historyWith(['some text'])
        ..recordImage(path: r'C:\images\abc.png', width: 1920, height: 1080);

      final entry = history.entries.first;
      expect(entry.kind, EntryKind.image);
      expect(entry.preview, 'Image');
      expect(entry.text, isEmpty);
      expect(entry.imageWidth, 1920);
    });

    test('the same picture file is recognised when copied again', () {
      final history = historyWith([])
        ..recordImage(path: r'C:\images\abc.png', width: 10, height: 10)
        ..record('text in between')
        ..recordImage(path: r'C:\images\abc.png', width: 10, height: 10)
        ..recordImage(path: r'C:\images\def.png', width: 10, height: 10);

      expect(
        [for (final entry in history.entries) entry.kind],
        [EntryKind.image, EntryKind.image, EntryKind.text],
      );
    });

    test('files are named after the first of them', () {
      final history = historyWith([]);
      history.recordFiles([r'C:\Docs\report.pdf']);
      expect(history.entries.first.preview, 'report.pdf');
      expect(history.entries.first.kind, EntryKind.files);

      history.recordFiles([r'C:\Docs\a.txt', r'C:\Docs\b.txt']);
      expect(history.entries.first.preview, 'a.txt and 1 more');

      history.recordFiles(['/home/sam/a', '/home/sam/b', '/home/sam/c']);
      expect(history.entries.first.preview, 'a and 2 more');

      expect(history.recordFiles(const []), isFalse);
      expect(history.entries, hasLength(3));
    });

    test('the same files copied again move up instead of repeating', () {
      final history = historyWith([])
        ..recordFiles([r'C:\Docs\report.pdf'])
        ..record('text')
        ..recordFiles([r'C:\Docs\report.pdf']);
      expect(history.entries, hasLength(2));
      expect(history.entries.first.kind, EntryKind.files);
    });

    test('have filters of their own, and can be searched for', () {
      final history = historyWith(['plain text'])
        ..recordImage(path: r'C:\images\abc.png', width: 10, height: 10)
        ..recordFiles([r'C:\Docs\Quarterly Report.pdf']);

      expect(history.search('', filter: EntryFilter.images), hasLength(1));
      expect(history.search('', filter: EntryFilter.files), hasLength(1));
      expect(
        history.search('', filter: EntryFilter.text).single.text,
        'plain text',
      );
      expect(history.search('quarterly').single.kind, EntryKind.files);
      expect(history.search('screenshot').single.kind, EntryKind.image);
      expect(history.search('image').single.kind, EntryKind.image);
    });

    test('only so many unpinned pictures are kept', () {
      final history = ClipboardHistory(
        store: MemoryHistoryStore(),
        clock: tickingClock(),
        maxUnpinnedImages: 2,
      );
      history.recordImage(path: 'one.png', width: 1, height: 1);
      history.togglePin(history.entries.single.id);
      for (final name in ['two', 'three', 'four']) {
        history.recordImage(path: '$name.png', width: 1, height: 1);
      }
      history.record('text is not counted');

      expect(
        [for (final entry in history.entries) entry.preview],
        ['Image', 'text is not counted', 'Image', 'Image'],
      );
      expect(
        [
          for (final entry in history.entries)
            if (entry.imagePath != null) entry.imagePath,
        ],
        ['one.png', 'four.png', 'three.png'],
      );
    });

    test('survive a trip through JSON', () {
      final history = historyWith([])
        ..recordImage(
          path: r'C:\images\abc.png',
          width: 640,
          height: 480,
          source: 'Mac',
        )
        ..recordFiles([r'C:\Docs\a.txt', r'C:\Docs\b.txt']);

      for (final entry in history.entries) {
        expect(ClipboardEntry.fromJson(entry.toJson()), entry);
      }
    });

    test('text saved before pictures existed still loads', () {
      final old = ClipboardEntry.fromJson(const {
        'id': 'a',
        'text': 'hello',
        'copiedAt': 0,
        'pinned': false,
      });
      expect(old.kind, EntryKind.text);
      expect(old.files, isEmpty);
      expect(old.imagePath, isNull);
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
