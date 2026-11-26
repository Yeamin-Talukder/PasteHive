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
import 'src/history/image_vault.dart';
import 'src/platform/native_ports.dart';
import 'src/shell/panel_controller.dart';
import 'src/sync/network.dart';
import 'src/sync/sync_ports.dart';
import 'src/sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    await history.load();
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
    captureAtLaunch: !checking,
  );
  shell.trace = trace;
  // Pictures whose entries are gone (deleted, or pushed out by newer ones).
  unawaited(shell.removeUnusedImages());

  final captureKey = checking ? GlobalKey() : null;
  runApp(ClipboardApp(shell: shell, captureKey: captureKey));
  trace('app running');
  await shell.start();
  trace('shell started: panel=${shell.panelReady} tray=${shell.trayReady}');

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
