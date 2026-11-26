import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'ui/panel_scene.dart';

/// The app's one window: the clipboard panel.
class ClipboardApp extends StatelessWidget {
  const ClipboardApp({super.key, required this.shell});

  final AppShell shell;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synchronize Clipboard',
      debugShowCheckedModeBanner: false,
      // Light or dark follows the system; there is no switch of our own.
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: PanelScene(
        controller: shell.panel,
        history: shell.history,
        onCopy: shell.copy,
        sync: shell.sync,
        page: shell.page,
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      // Nothing paints behind the panel, so the window's material shows.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      tooltipTheme: const TooltipThemeData(
        textStyle: TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }
}
