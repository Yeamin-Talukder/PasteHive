/// Putting a downloaded update in place, per kind of device.
library;

import 'dart:io';

import 'package:path/path.dart' as path;

import 'update_ports.dart';
import 'update_service.dart' show UpdateException;

/// The installer for the computer this is running on; null on anything else.
UpdateInstaller? desktopInstaller() {
  if (Platform.isWindows) return WindowsUpdateInstaller();
  if (Platform.isMacOS) return MacUpdateInstaller();
  return null;
}

Future<Directory> _freshFolder(String name) async {
  final folder = Directory(path.join(Directory.systemTemp.path, name));
  if (await folder.exists()) await folder.delete(recursive: true);
  await folder.create(recursive: true);
  return folder;
}

Future<void> _run(String command, List<String> arguments) async {
  final result = await Process.run(command, arguments);
  if (result.exitCode != 0) {
    final problem = '${result.stderr}'.trim();
    throw UpdateException(
      'The update could not be unpacked ($command: $problem).',
    );
  }
}

/// The first folder at or under [root] that holds [fileName].
Future<Directory?> _folderHolding(Directory root, String fileName) async {
  if (await File(path.join(root.path, fileName)).exists()) return root;
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    if (entry is File && path.basename(entry.path) == fileName) {
      return entry.parent;
    }
  }
  return null;
}

/// Windows: the release is a zip of the app's folder. It is unpacked beside
/// the download; then, because a running program's files cannot be replaced,
/// a small script waits for the app to close, copies the new files over the
/// old ones and starts the app again.
class WindowsUpdateInstaller implements UpdateInstaller {
  @override
  String get assetName => 'PasteHive-windows-x64.zip';

  String get _appFolder => path.dirname(Platform.resolvedExecutable);

  @override
  String? get unavailableReason {
    // Installed somewhere only an administrator may write, the app cannot
    // replace its own files.
    try {
      final probe = File(path.join(_appFolder, '.update-probe'));
      probe.writeAsStringSync('');
      probe.deleteSync();
      return null;
    } on FileSystemException {
      return 'PasteHive cannot write to the folder it is installed in. '
          'Download the new version from its page and replace the folder.';
    }
  }

  @override
  Future<Directory> downloadDirectory() => _freshFolder('pastehive-update');

  @override
  Future<bool> install(File file) async {
    final unpacked = Directory(path.join(file.parent.path, 'unpacked'));
    await unpacked.create(recursive: true);
    // Windows 10 and later ship tar, which reads zip files.
    await _run('tar', ['-xf', file.path, '-C', unpacked.path]);
    final executable = path.basename(Platform.resolvedExecutable);
    final source = await _folderHolding(unpacked, executable);
    if (source == null) {
      throw UpdateException('The update does not contain $executable.');
    }
    final script = File(path.join(file.parent.path, 'apply-update.cmd'));
    await script.writeAsString(
      windowsUpdateScript(
        processId: pid,
        source: source.path,
        target: _appFolder,
        executable: executable,
      ),
    );
    await Process.start('cmd', [
      '/c',
      script.path,
    ], mode: ProcessStartMode.detached);
    return true;
  }
}

/// The script that swaps the app's files once the app has closed.
String windowsUpdateScript({
  required int processId,
  required String source,
  required String target,
  required String executable,
}) {
  return [
    '@echo off',
    'rem Wait for PasteHive to close; its files cannot be replaced while it runs.',
    'set /a tries=0',
    ':wait',
    'tasklist /FI "PID eq $processId" 2>nul | find "$processId" >nul',
    'if errorlevel 1 goto copy',
    'set /a tries+=1',
    'if %tries% geq 60 goto copy',
    'timeout /t 1 /nobreak >nul',
    'goto wait',
    ':copy',
    'robocopy "$source" "$target" /E /R:10 /W:1 /NFL /NDL /NJH /NJS /NP >nul',
    'start "" "$target\\$executable"',
    'exit',
    '',
  ].join('\r\n');
}

/// macOS: the release is a zip of the app bundle. The same idea as on
/// Windows: unpack, then a script replaces the bundle once the app has
/// closed and opens it again.
///
/// The app is not signed by a registered developer, so macOS treats the new
/// copy as a different program: the Accessibility permission that pasting
/// needs has to be given again after an update.
class MacUpdateInstaller implements UpdateInstaller {
  @override
  String get assetName => 'PasteHive-macos.zip';

  /// The `.app` folder this program is running from; null when it is not
  /// in one (a development run).
  String? get _bundle {
    var folder = path.dirname(Platform.resolvedExecutable);
    for (var i = 0; i < 3; i++) {
      if (folder.endsWith('.app')) return folder;
      folder = path.dirname(folder);
    }
    return null;
  }

  @override
  String? get unavailableReason {
    final bundle = _bundle;
    if (bundle == null) {
      return 'This copy of PasteHive is not an app bundle, so it cannot '
          'replace itself. Download the new version from its page.';
    }
    try {
      final probe = File(path.join(path.dirname(bundle), '.update-probe'));
      probe.writeAsStringSync('');
      probe.deleteSync();
      return null;
    } on FileSystemException {
      return 'PasteHive cannot write to the folder it is in. Download the '
          'new version from its page and replace the app.';
    }
  }

  @override
  Future<Directory> downloadDirectory() => _freshFolder('pastehive-update');

  @override
  Future<bool> install(File file) async {
    final bundle = _bundle;
    if (bundle == null) throw UpdateException(unavailableReason!);
    final unpacked = Directory(path.join(file.parent.path, 'unpacked'));
    await unpacked.create(recursive: true);
    await _run('ditto', ['-x', '-k', file.path, unpacked.path]);
    Directory? source;
    await for (final entry in unpacked.list(recursive: true)) {
      if (entry is Directory && entry.path.endsWith('.app')) {
        source = entry;
        break;
      }
    }
    if (source == null) {
      throw const UpdateException('The update does not contain the app.');
    }
    final script = File(path.join(file.parent.path, 'apply-update.sh'));
    await script.writeAsString(
      macUpdateScript(processId: pid, source: source.path, target: bundle),
    );
    await Process.start('/bin/sh', [
      script.path,
    ], mode: ProcessStartMode.detached);
    return true;
  }
}

String _quoted(String text) => "'${text.replaceAll("'", r"'\''")}'";

/// The script that swaps the app bundle once the app has closed.
String macUpdateScript({
  required int processId,
  required String source,
  required String target,
}) {
  return [
    '#!/bin/sh',
    '# Wait for PasteHive to close, replace the app, and open it again.',
    'tries=0',
    'while kill -0 $processId 2>/dev/null && [ \$tries -lt 60 ]; do',
    '  sleep 1',
    '  tries=\$((tries + 1))',
    'done',
    'rm -rf ${_quoted('$target.old')}',
    'mv ${_quoted(target)} ${_quoted('$target.old')} || exit 1',
    'if ditto ${_quoted(source)} ${_quoted(target)}; then',
    '  rm -rf ${_quoted('$target.old')}',
    'else',
    '  # Put the old one back rather than leave nothing.',
    '  rm -rf ${_quoted(target)}',
    '  mv ${_quoted('$target.old')} ${_quoted(target)}',
    'fi',
    'xattr -dr com.apple.quarantine ${_quoted(target)} 2>/dev/null',
    'open ${_quoted(target)}',
    '',
  ].join('\n');
}

/// A device the app has no way of updating itself on.
class NoUpdateInstaller implements UpdateInstaller {
  const NoUpdateInstaller();

  @override
  String get assetName => '';

  @override
  String? get unavailableReason =>
      'PasteHive cannot update itself on this device. Download the new '
      'version from its page.';

  @override
  Future<Directory> downloadDirectory() async => Directory.systemTemp;

  @override
  Future<bool> install(File file) async => false;
}

/// Opens [url] in the computer's browser.
Future<void> openLinkOnDesktop(String url) async {
  final uri = Uri.tryParse(url);
  // Only ever a web address: this goes to the system's "open" command.
  if (uri == null || uri.scheme != 'https') return;
  try {
    if (Platform.isWindows) {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else {
      await Process.start('xdg-open', [url]);
    }
  } on ProcessException {
    // No browser to hand it to; nothing more to do.
  }
}
