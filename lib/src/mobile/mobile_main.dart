import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../app_shell.dart';
import '../history/clipboard_entry.dart';
import '../history/clipboard_history.dart';
import '../history/history_store.dart';
import '../history/file_vault.dart';
import '../history/image_vault.dart';
import '../shell/panel_controller.dart';
import '../sync/network.dart';
import '../sync/sync_service.dart';
import '../update/app_info.dart';
import '../update/github_feed.dart';
import '../update/running_version.dart';
import '../update/update_ports.dart';
import '../update/update_service.dart';
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
    clipboard: PhoneClipboard(bridge),
    tray: const NoTray(),
    onQuit: () async {},
    images: ImageVault(Directory(path.join(supportDirectory.path, 'images'))),
    receivedFiles: FileVault(
      Directory(path.join(supportDirectory.path, 'files')),
    ),
  );
  unawaited(shell.removeUnusedImages());

  shell.openLink = bridge.openUrl;
  shell.updates = UpdateService(
    currentVersion: await runningVersion(),
    feed: GitHubReleaseFeed(kRepository),
    installer: AndroidUpdateInstaller(bridge, abi: await bridge.deviceAbi()),
    store: JsonFileUpdateSettingsStore(
      File(path.join(supportDirectory.path, 'update.json')),
    ),
  );

  // Text handed over with Share, or picked from the text-selection menu, is
  // treated as copied: the system does not let the app see a copy made in
  // another app while it is in the background, so this is the way in.
  bridge.onSharedText = shell.addCopied;
  // Files handed over with Share go to the other devices as files.
  bridge.onSharedFiles = shell.addCopiedFiles;
  // Tapping a file in the list opens it: on a phone that is what one wants
  // from a PDF, far more often than pasting it.
  shell.onPicked = (entry) {
    if (entry.kind == EntryKind.files) unawaited(bridge.openFiles(entry.files));
  };
  // A copy was noticed in another app (or Send clipboard was pressed):
  // for this moment the clipboard can be read, text or picture.
  bridge.onCapture = () async {
    shell.captureNow();
    await shell.captured;
  };

  // While sync is on, a notification keeps the app alive in the background,
  // so what is copied on the computers still arrives.
  void keepAlive() => unawaited(bridge.setKeepAlive(sync.enabled));
  sync.addListener(keepAlive);

  runApp(PhoneApp(shell: shell, bridge: bridge));
  await shell.start();
  keepAlive();
  unawaited(shell.updates?.start());

  (await bridge.takeSharedTexts()).forEach(shell.addCopied);
  (await bridge.takeSharedFiles()).forEach(shell.addCopiedFiles);
}
