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
import 'src/platform/native_ports.dart';
import 'src/shell/panel_controller.dart';
import 'src/sync/network.dart';
import 'src/sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supportDirectory = await getApplicationSupportDirectory();
  final history = ClipboardHistory(
    store: JsonFileHistoryStore(
      File(path.join(supportDirectory.path, 'history.json')),
    ),
  );
  await history.load();

  final window = NativePanelWindow();
  final shell = AppShell(
    history: history,
    panel: PanelController(pointer: const NativePointer(), window: window),
    sync: SyncService(
      discovery: UdpDiscovery(),
      transport: TcpTransport(),
      store: JsonFileSyncSettingsStore(
        File(path.join(supportDirectory.path, 'sync.json')),
      ),
      defaultDeviceName: () => Platform.localHostname,
    ),
    clipboard: const NativeClipboard(),
    tray: NativeTray(),
    onQuit: () async => exit(0),
  );

  runApp(ClipboardApp(shell: shell));
  await shell.start();

  final smokePath = SmokeRun.requestedPath;
  if (smokePath != null) {
    unawaited(
      SmokeRun(outputPath: smokePath, shell: shell, window: window).run(),
    );
  }
}
