import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/update/app_version.dart';
import 'package:pastehive/src/update/github_feed.dart';
import 'package:pastehive/src/update/installers.dart';
import 'package:pastehive/src/update/update_ports.dart';
import 'package:pastehive/src/update/update_service.dart';

import 'fake_updates.dart';

void main() {
  group('AppVersion', () {
    test('reads tags, plain versions and build numbers', () {
      expect(AppVersion.tryParse('v1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('1.2.3+45'), const AppVersion(1, 2, 3));
      expect(
        AppVersion.tryParse('v2.0.0-beta.1'),
        const AppVersion(2, 0, 0, 'beta.1'),
      );
      expect(AppVersion.tryParse('latest'), isNull);
      expect(AppVersion.tryParse('1.2'), isNull);
    });

    test('orders by number, not by spelling', () {
      AppVersion v(String text) => AppVersion.tryParse(text)!;
      expect(v('1.10.0') > v('1.9.9'), isTrue);
      expect(v('2.0.0') > v('1.99.99'), isTrue);
      expect(v('1.0.0') > v('1.0.0'), isFalse);
      // A pre-release comes before its release.
      expect(v('1.2.0') > v('1.2.0-beta.3'), isTrue);
      expect(v('1.2.0-beta.10') > v('1.2.0-beta.9'), isTrue);
      expect(v('1.2.0-beta.1') > v('1.1.9'), isTrue);
    });
  });

  group('reading GitHub', () {
    test('a release answer becomes a version, a page and its files', () {
      final release = parseGitHubRelease(
        jsonDecode('''
        {"tag_name": "v1.4.0", "html_url": "https://github.com/o/r/releases/tag/v1.4.0",
         "body": "Faster.",
         "assets": [
           {"name": "PasteHive-windows-x64.zip", "browser_download_url": "https://github.com/o/r/a.zip"},
           {"name": "broken"}
         ]}'''),
      )!;
      expect(release.version, const AppVersion(1, 4, 0));
      expect(release.notes, 'Faster.');
      expect(release.assets, {
        'PasteHive-windows-x64.zip': 'https://github.com/o/r/a.zip',
      });
    });

    test('an answer without a version tag is not a release', () {
      expect(parseGitHubRelease({'tag_name': 'nightly'}), isNull);
      expect(parseGitHubRelease({'message': 'Not Found'}), isNull);
      expect(parseGitHubRelease('nonsense'), isNull);
    });

    test('a checksum is found by file name', () {
      final list =
          '${'a' * 64}  PasteHive-android.apk\n'
          '${'B' * 64} *PasteHive-windows-x64.zip\n';
      expect(checksumFor(list, 'PasteHive-windows-x64.zip'), 'b' * 64);
      expect(checksumFor(list, 'PasteHive-macos.zip'), isNull);
    });
  });

  group('UpdateService', () {
    late Directory folder;
    late FakeFeed feed;
    late FakeInstaller installer;
    late MemoryUpdateSettingsStore store;
    var quits = 0;

    UpdateService service({String current = '1.0.0'}) => UpdateService(
      currentVersion: AppVersion.tryParse(current)!,
      feed: feed,
      installer: installer,
      store: store,
      quit: () async => quits++,
      clock: () => DateTime.utc(2026, 11, 27, 12),
    );

    ReleaseInfo release(String version, {Map<String, String>? assets}) =>
        ReleaseInfo(
          version: AppVersion.tryParse(version)!,
          pageUrl: 'https://github.com/o/r/releases/tag/v$version',
          assets:
              assets ??
              {
                'PasteHive-test.zip': 'https://github.com/o/r/app.zip',
                'SHA256SUMS.txt': 'https://github.com/o/r/sums.txt',
              },
        );

    Future<String> sha256Of(List<int> bytes) async =>
        (await Sha256().hash(bytes)).bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('pastehive-update-test');
      feed = FakeFeed();
      installer = FakeInstaller(folder);
      store = MemoryUpdateSettingsStore();
      quits = 0;
    });

    tearDown(() => folder.delete(recursive: true));

    test('a newer release is offered, and the check is remembered', () async {
      feed.release = release('1.1.0');
      final updates = service();
      await updates.check();
      expect(updates.status, UpdateStatus.available);
      expect(updates.hasUpdate, isTrue);
      expect(store.settings.lastChecked, DateTime.utc(2026, 11, 27, 12));
    });

    test('the same or an older release means up to date', () async {
      feed.release = release('1.0.0');
      final updates = service();
      await updates.check();
      expect(updates.status, UpdateStatus.upToDate);
      expect(updates.hasUpdate, isFalse);
    });

    test('no published release is not an error', () async {
      final updates = service();
      await updates.check();
      expect(updates.status, UpdateStatus.upToDate);
      expect(updates.latest, isNull);
      expect(updates.error, isNull);
    });

    test('a failed check says why; a quiet one says nothing', () async {
      feed.failure = const SocketException('offline');
      final updates = service();
      await updates.check(quiet: true);
      expect(updates.status, UpdateStatus.idle);
      expect(updates.error, isNull);

      await updates.check();
      expect(updates.status, UpdateStatus.failed);
      expect(updates.error, contains('Could not reach GitHub'));
    });

    test('a download that matches its checksum is installed, and the app '
        'quits when the installer needs it to', () async {
      final bytes = utf8.encode('the new version');
      feed
        ..release = release('1.1.0')
        ..files['https://github.com/o/r/app.zip'] = bytes
        ..texts['https://github.com/o/r/sums.txt'] =
            '${await sha256Of(bytes)}  PasteHive-test.zip\n';
      final updates = service();
      await updates.check();
      await updates.downloadAndInstall();

      expect(installer.installed, hasLength(1));
      expect(await installer.installed.single.readAsBytes(), bytes);
      expect(quits, 1);
    });

    test(
      'a download that does not match its checksum is thrown away',
      () async {
        feed
          ..release = release('1.1.0')
          ..files['https://github.com/o/r/app.zip'] = utf8.encode('tampered')
          ..texts['https://github.com/o/r/sums.txt'] =
              '${'0' * 64}  PasteHive-test.zip\n';
        final updates = service();
        await updates.check();
        await updates.downloadAndInstall();

        expect(installer.installed, isEmpty);
        expect(quits, 0);
        expect(updates.status, UpdateStatus.failed);
        expect(updates.error, contains('checksum'));
        expect(File('${folder.path}/PasteHive-test.zip').existsSync(), isFalse);
      },
    );

    test('a release without a file for this device says so', () async {
      feed.release = release('1.1.0', assets: {'Other.zip': 'https://x'});
      final updates = service();
      await updates.check();
      await updates.downloadAndInstall();
      expect(updates.status, UpdateStatus.failed);
      expect(updates.error, contains('no download for this device'));
    });

    test(
      'where the app cannot replace itself, nothing is downloaded',
      () async {
        installer.unavailableReason = 'Read-only folder.';
        feed.release = release('1.1.0');
        final updates = service();
        await updates.check();
        await updates.downloadAndInstall();
        expect(feed.downloads, 0);
        expect(updates.error, 'Read-only folder.');
      },
    );

    test('an install the system takes over leaves the app running', () async {
      installer.mustQuit = false;
      feed
        ..release = release(
          '1.1.0',
          assets: {'PasteHive-test.zip': 'https://github.com/o/r/app.zip'},
        )
        ..files['https://github.com/o/r/app.zip'] = [1, 2, 3];
      final updates = service();
      await updates.check();
      await updates.downloadAndInstall();
      expect(installer.installed, hasLength(1));
      expect(quits, 0);
      expect(updates.status, UpdateStatus.available);
    });

    test('automatic checks follow the switch and wait a day', () async {
      feed.release = release('1.1.0');
      store.settings = UpdateSettings(
        lastChecked: DateTime.utc(2026, 11, 27, 6),
      );
      final recent = service();
      await recent.start();
      await Future<void>.delayed(Duration.zero);
      expect(feed.checks, 0, reason: 'checked six hours ago');
      recent.dispose();

      store.settings = UpdateSettings(lastChecked: DateTime.utc(2026, 11, 25));
      final due = service();
      await due.start();
      await Future<void>.delayed(Duration.zero);
      expect(feed.checks, 1);
      expect(due.hasUpdate, isTrue);
      due.dispose();

      store.settings = const UpdateSettings(autoCheck: false);
      final off = service();
      await off.start();
      await Future<void>.delayed(Duration.zero);
      expect(feed.checks, 1, reason: 'switched off');
      off.dispose();
    });
  });

  group('swap scripts', () {
    test('Windows waits for the app, copies over it and starts it again', () {
      final script = windowsUpdateScript(
        processId: 4242,
        source: r'C:\Temp\new\PasteHive',
        target: r'C:\Apps\PasteHive',
        executable: 'pastehive.exe',
      );
      expect(script, contains('PID eq 4242'));
      expect(
        script,
        contains(r'robocopy "C:\Temp\new\PasteHive" "C:\Apps\PasteHive" /E'),
      );
      expect(script, contains(r'start "" "C:\Apps\PasteHive\pastehive.exe"'));
      expect(script.indexOf('robocopy'), greaterThan(script.indexOf(':wait')));
    });

    test('macOS keeps the old app until the new one is in place', () {
      final script = macUpdateScript(
        processId: 77,
        source: "/tmp/new/it's.app",
        target: '/Applications/pastehive.app',
      );
      expect(script, contains('kill -0 77'));
      expect(script, contains(r"'/tmp/new/it'\''s.app'"));
      expect(
        script.indexOf("mv '/Applications/pastehive.app'"),
        lessThan(script.indexOf('ditto')),
      );
      expect(script, contains("open '/Applications/pastehive.app'"));
    });
  });
}
