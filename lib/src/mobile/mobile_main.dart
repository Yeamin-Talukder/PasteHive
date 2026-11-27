import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../app_shell.dart';
import '../history/clipboard_history.dart';
import '../history/history_store.dart';
import '../history/image_vault.dart';
import '../shell/panel_controller.dart';
import '../sync/network.dart';
import '../sync/sync_service.dart';
import 'mobile_app.dart';
import 'mobile_ports.dart';

/// Starts the app on a phone.
Future<void> runPhoneApp() async {
  final supportDirectory = await getApplicationSupportDirectory();
  final history = ClipboardHistory(
    store: JsonFileHistoryStore(
      File(path.join(supportDirectory.path, 'history.json')),
    ),
  );
  await history.load();

  final bridge = PhoneBridge();
  final deviceName = await bridge.deviceName();
  final sync = SyncService(
    discovery: UdpDiscovery(),
    transport: TcpTransport(),
    store: JsonFileSyncSettingsStore(
      File(path.join(supportDirectory.path, 'sync.json')),
    ),
    defaultDeviceName: () => deviceName,
  );
  final shell = AppShell(
    history: history,
    panel: PanelController(
      pointer: const NoPointer(),
      window: const NoPanelWindow(),
      // Nothing to watch for: there is no pointer and no hot edge.
      pollInterval: const Duration(days: 1),
    ),
    sync: sync,
    clipboard: const PhoneClipboard(),
    tray: const NoTray(),
    onQuit: () async {},
    images: ImageVault(Directory(path.join(supportDirectory.path, 'images'))),
  );
  unawaited(shell.removeUnusedImages());

  // Text handed over with Share, or picked from the text-selection menu, is
  // treated as copied: the system does not let the app see a copy made in
  // another app while it is in the background, so this is the way in.
  bridge.onSharedText = shell.addCopied;

  // While sync is on, a notification keeps the app alive in the background,
  // so what is copied on the computers still arrives.
  void keepAlive() => unawaited(bridge.setKeepAlive(sync.enabled));
  sync.addListener(keepAlive);

  runApp(PhoneApp(shell: shell, bridge: bridge));
  await shell.start();
  keepAlive();

  (await bridge.takeSharedTexts()).forEach(shell.addCopied);
}
