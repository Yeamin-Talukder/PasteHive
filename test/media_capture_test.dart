import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pastehive/src/app_shell.dart';
import 'package:pastehive/src/history/clipboard_entry.dart';
import 'package:pastehive/src/history/clipboard_history.dart';
import 'package:pastehive/src/history/image_vault.dart';
import 'package:pastehive/src/platform/ports.dart';
import 'package:pastehive/src/shell/panel_controller.dart';
import 'package:pastehive/src/sync/sync_ports.dart';
import 'package:pastehive/src/sync/sync_service.dart';

import 'fakes.dart';
import 'sync/memory_network.dart';

/// A real, one-pixel PNG.
final onePixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// Different bytes, standing in for a different picture.
final otherPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

ClipboardImage picture(List<int> png, {int width = 800, int height = 600}) =>
    ClipboardImage(png: Uint8List.fromList(png), width: width, height: height);

void main() {
  late Directory directory;
  late ImageVault vault;
  late ClipboardHistory history;
  late FakeClipboard clipboard;
  late FakeWindow window;
  late PanelController panel;
  late DateTime now;
  late AppShell shell;

  /// Waits until what was copied has been read and, for a picture, saved.
  Future<void> settled() async {
    await pumpEventQueue();
    await shell.captured;
  }

  AppShell buildShell({bool withVault = true}) {
    final network = MemoryNetwork();
    return AppShell(
      history: history,
      panel: panel,
      sync: SyncService(
        discovery: network.discovery('10.0.0.1'),
        transport: network.transport('10.0.0.1'),
        store: MemorySyncSettingsStore(),
        defaultDeviceName: () => 'Test PC',
      ),
      clipboard: clipboard,
      tray: FakeTray(),
      onQuit: () async {},
      images: withVault ? vault : null,
      readRetryDelay: const Duration(milliseconds: 1),
      clock: () => now,
    );
  }

  List<EntryKind> kinds() => [for (final entry in history.entries) entry.kind];

  List<String> storedImages() => directory.existsSync()
      ? [for (final file in directory.listSync()) path.basename(file.path)]
      : [];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('media_capture_test');
    vault = ImageVault(Directory(path.join(directory.path, 'images')));
    directory = vault.directory;
    history = historyWith([]);
    clipboard = FakeClipboard();
    window = FakeWindow();
    panel = PanelController(
      pointer: FakePointer(),
      window: window,
      pollInterval: const Duration(days: 1),
    );
    now = DateTime.utc(2026, 11, 27, 10);
    addTearDown(panel.dispose);
    addTearDown(() => directory.parent.deleteSync(recursive: true));
  });

  group('capturing', () {
    test('a copied picture is kept as a file and listed', () async {
      await (shell = buildShell()).start();

      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();

      final entry = history.entries.single;
      expect(entry.kind, EntryKind.image);
      expect(entry.imageWidth, 800);
      expect(entry.imageHeight, 600);
      expect(File(entry.imagePath!).readAsBytesSync(), onePixel);
      expect(storedImages(), hasLength(1));
    });

    test('the same picture copied twice is one entry and one file', () async {
      await (shell = buildShell()).start();

      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();
      clipboard.copyFromElsewhere('something in between');
      await settled();
      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();

      expect(kinds(), [EntryKind.image, EntryKind.text]);
      expect(storedImages(), hasLength(1));
    });

    test('different pictures are different entries', () async {
      await (shell = buildShell()).start();

      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();
      clipboard.copyImageFromElsewhere(picture(otherPixel));
      await settled();

      expect(kinds(), [EntryKind.image, EntryKind.image]);
      expect(storedImages(), hasLength(2));
    });

    test('copied files are listed by name', () async {
      await (shell = buildShell()).start();

      clipboard.copyFilesFromElsewhere([
        r'C:\Docs\report.pdf',
        r'C:\Docs\notes.txt',
        r'C:\Docs\photo.jpg',
      ]);
      await settled();

      final entry = history.entries.single;
      expect(entry.kind, EntryKind.files);
      expect(entry.files, hasLength(3));
      expect(entry.preview, 'report.pdf and 2 more');
    });

    test('files win over the text that comes with them', () async {
      await (shell = buildShell()).start();
      clipboard.copyFilesFromElsewhere([r'C:\Docs\report.pdf']);
      // A copied file also puts its path on the clipboard as text.
      clipboard.text = r'C:\Docs\report.pdf';
      await settled();

      expect(kinds(), [EntryKind.files]);
    });

    test('text wins over the picture that comes with it', () async {
      await (shell = buildShell()).start();
      clipboard.copyFromElsewhere('a spreadsheet cell');
      // A copied cell also puts a picture of itself on the clipboard.
      clipboard.image = picture(onePixel);
      await settled();

      expect(kinds(), [EntryKind.text]);
      expect(storedImages(), isEmpty);
    });

    test('pictures are left alone while capturing is paused', () async {
      await (shell = buildShell()).start();
      history.paused = true;

      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();

      expect(history.isEmpty, isTrue);
      expect(storedImages(), isEmpty);
    });

    test('a clipboard that is busy for a moment is read again', () async {
      await (shell = buildShell()).start();
      clipboard.busyReads = 3;

      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();

      expect(kinds(), [EntryKind.image]);
      expect(shell.lastCaptureError, isNull);
    });

    test('a clipboard that stays busy is given up on, quietly', () async {
      await (shell = buildShell()).start();
      clipboard.busyReads = 100;

      clipboard.copyFromElsewhere('never read');
      await settled();

      expect(history.isEmpty, isTrue);
      expect(shell.lastCaptureError, contains('Clipboard operation failed'));

      // The next copy is not affected.
      clipboard
        ..busyReads = 0
        ..copyFromElsewhere('read fine');
      await settled();
      expect(history.entries.single.text, 'read fine');
    });

    test('without somewhere to keep them, pictures are not recorded', () async {
      await (shell = buildShell(withVault: false)).start();
      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();
      expect(history.isEmpty, isTrue);
    });
  });

  group('picking an entry', () {
    test('a picture goes back on the clipboard as a picture', () async {
      await (shell = buildShell()).start();
      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();
      clipboard.copyFromElsewhere('newer text');
      await settled();
      final image = history.entries.last;

      shell.copy(image);
      await settled();

      expect(clipboard.writtenImages, [image.imagePath]);
      expect(kinds(), [EntryKind.image, EntryKind.text]);
    });

    test('its own picture coming back re-encoded is not a new entry', () async {
      await (shell = buildShell()).start();
      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();
      // The system hands the picture back with different bytes.
      clipboard.imageWrittenBack = picture(otherPixel);

      shell.copy(history.entries.single);
      await settled();

      expect(history.entries, hasLength(1));
      expect(storedImages(), hasLength(1));

      // Later, a picture copied somewhere else counts again.
      now = now.add(const Duration(seconds: 5));
      clipboard.copyImageFromElsewhere(picture(otherPixel));
      await settled();
      expect(history.entries, hasLength(2));
    });

    test('files go back on the clipboard as files', () async {
      await (shell = buildShell()).start();
      clipboard.copyFilesFromElsewhere([r'C:\Docs\report.pdf']);
      await settled();

      shell.copy(history.entries.single);
      await settled();

      expect(clipboard.writtenFiles, [
        [r'C:\Docs\report.pdf'],
      ]);
      expect(history.entries, hasLength(1));
    });

    test(
      'is pasted into the app the user was in, where that is possible',
      () async {
        window.canPaste = true;
        final shell = buildShell();
        await shell.start();
        clipboard.copyFromElsewhere('paste me');
        await settled();
        panel.open();

        shell.copy(history.entries.single);
        await settled();

        expect(clipboard.written, ['paste me']);
        expect(panel.isOpen, isFalse);
        expect(window.pasteCount, 1);
      },
    );

    test('is only copied where pasting is not possible', () async {
      await (shell = buildShell()).start();
      clipboard.copyFromElsewhere('copy me');
      await settled();

      shell.copy(history.entries.single);
      await settled();

      expect(clipboard.written, ['copy me']);
      expect(window.pasteCount, 0);
    });
  });

  group('stored pictures', () {
    test('are deleted once nothing refers to them', () async {
      await (shell = buildShell()).start();
      clipboard.copyImageFromElsewhere(picture(onePixel));
      await settled();
      clipboard.copyImageFromElsewhere(picture(otherPixel));
      await settled();
      expect(storedImages(), hasLength(2));

      final removed = history.entries.last;
      history.remove(removed.id);
      expect(
        File(removed.imagePath!).existsSync(),
        isTrue,
        reason: 'kept for now, so the delete can be undone',
      );

      await shell.removeUnusedImages();

      expect(File(removed.imagePath!).existsSync(), isFalse);
      expect(storedImages(), hasLength(1));
    });

    test(
      'the vault keeps what it is told to and ignores a missing folder',
      () async {
        expect(await vault.removeAllExcept(const []), 0);

        final kept = await vault.store(Uint8List.fromList(onePixel));
        await vault.store(Uint8List.fromList(otherPixel));
        expect(await vault.store(Uint8List.fromList(onePixel)), kept);

        expect(await vault.removeAllExcept([kept]), 1);
        expect(storedImages(), [path.basename(kept)]);
      },
    );
  });
}
