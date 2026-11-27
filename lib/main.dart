import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/app_shell.dart';
import 'src/diagnostics/smoke_run.dart';
import 'src/history/clipboard_history.dart';
import 'src/history/history_store.dart';
import 'src/legacy_data.dart';
import 'src/mobile/mobile_main.dart';
import 'src/history/file_vault.dart';
import 'src/history/image_vault.dart';
import 'src/platform/native_ports.dart';
import 'src/shell/panel_controller.dart';
import 'src/sync/network.dart';
import 'src/sync/sync_ports.dart';
import 'src/sync/sync_service.dart';
import 'src/update/app_info.dart';
import 'src/update/github_feed.dart';
import 'src/update/installers.dart';
import 'src/update/running_version.dart';
import 'src/update/update_ports.dart';
import 'src/update/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A phone gets a different app around the same core: no panel, no tray,
  // and a clipboard it may only look at while on screen.
  if (Platform.isAndroid || Platform.isIOS) return runPhoneApp();

  // A self-check run shows made-up entries and leaves the real history and
  // the real clipboard alone.
  final smokePath = SmokeRun.requestedPath;
  final checking = smokePath != null;
  // A self-check says how far it got, so a launch that stalls can be traced.
  void trace(String step) {
    if (checking) stderr.writeln('[check] $step');
  }

  trace('started');

  final supportDirectory = await getApplicationSupportDirectory();
  trace('support folder: ${supportDirectory.path}');
  // Copied pictures are kept as files; a self-check keeps its made-up one
  // out of the real folder.
  final images = ImageVault(
    checking
        ? Directory(path.join(Directory.systemTemp.path, 'syncclip-check'))
        : Directory(path.join(supportDirectory.path, 'images')),
  );
  final ClipboardHistory history;
  if (checking) {
    history = await SmokeRun.demoHistory(images);
    trace('demo history ready');
  } else {
    history = ClipboardHistory(
      store: JsonFileHistoryStore(
        File(path.join(supportDirectory.path, 'history.json')),
      ),
    );
    // The app used to keep its data under another name.
    await adoptDataFromFormerName(supportDirectory);
    await history.load();
    // Pictures are remembered by full path; point them at this folder.
    history.relocateImages(images.directory.path);
  }

  final window = NativePanelWindow();
  final shell = AppShell(
    history: history,
    panel: PanelController(pointer: const NativePointer(), window: window),
    sync: SyncService(
      discovery: UdpDiscovery(),
      transport: TcpTransport(),
      // A self-check never goes on the network: it gets blank settings.
      store: checking
          ? MemorySyncSettingsStore()
          : JsonFileSyncSettingsStore(
              File(path.join(supportDirectory.path, 'sync.json')),
            ),
      defaultDeviceName: () => Platform.localHostname,
    ),
    clipboard: const NativeClipboard(),
    tray: NativeTray(),
    onQuit: () async => exit(0),
    images: images,
    // A self-check neither sends nor keeps files.
    receivedFiles: checking
        ? null
        : FileVault(Directory(path.join(supportDirectory.path, 'files'))),
    captureAtLaunch: !checking,
  );
  shell.trace = trace;
  shell.openLink = openLinkOnDesktop;
  shell.updates = UpdateService(
    currentVersion: await runningVersion(),
    feed: GitHubReleaseFeed(kRepository),
    installer: desktopInstaller() ?? const NoUpdateInstaller(),
    // A self-check keeps nothing and never goes on the network.
    store: checking
        ? MemoryUpdateSettingsStore()
        : JsonFileUpdateSettingsStore(
            File(path.join(supportDirectory.path, 'update.json')),
          ),
    quit: shell.quit,
  );
  // Pictures whose entries are gone (deleted, or pushed out by newer ones).
  unawaited(shell.removeUnusedImages());

  final captureKey = checking ? GlobalKey() : null;
  runApp(ClipboardApp(shell: shell, captureKey: captureKey));
  trace('app running');
  await shell.start();
  trace('shell started: panel=${shell.panelReady} tray=${shell.trayReady}');
  if (!checking) unawaited(shell.updates?.start());

  if (smokePath != null) {
    unawaited(
      SmokeRun(
        outputPath: smokePath,
        shell: shell,
        window: window,
        captureKey: captureKey!,
      ).run(),
    );
  }
}
