import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../ui/clipboard_panel.dart';
import '../ui/panel_scene.dart' show syncSummaryOf;
import '../ui/sync_settings_view.dart';
import 'mobile_ports.dart';

/// The phone app: the same list and the same sync view as on a computer,
/// filling the screen instead of dropping from its top edge.
///
/// A phone only lets an app read the clipboard while it is on screen, so
/// each time the app comes to the front it looks at the clipboard and
/// records (and sends on) whatever is new there.
class PhoneApp extends StatefulWidget {
  const PhoneApp({
    super.key,
    required this.shell,
    this.bridge,
    this.clock = DateTime.now,
  });

  final AppShell shell;

  /// The app's Android side; null where there is none, as in a test.
  final PhoneBridge? bridge;
  final DateTime Function() clock;

  @override
  State<PhoneApp> createState() => _PhoneAppState();
}

class _PhoneAppState extends State<PhoneApp> with WidgetsBindingObserver {
  bool _autoCopyOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Opening the app counts as coming to the front too.
    didChangeAppLifecycleState(AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The user may be coming back from switching the service on or off.
    widget.bridge?.autoCopyOn().then((on) {
      if (mounted && on != _autoCopyOn) setState(() => _autoCopyOn = on);
    });
    // Android hands over the clipboard only once the app's window has the
    // user's attention, which is a moment after it reports being resumed.
    // Asking again a little later costs nothing: the same text is not
    // recorded twice.
    for (final delay in const [250, 900]) {
      Future<void>.delayed(Duration(milliseconds: delay), () {
        if (mounted) widget.shell.captureNow();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    return MaterialApp(
      title: 'PasteHive',
      debugShowCheckedModeBanner: false,
      // Light or dark follows the system; there is no switch of our own.
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Builder(
        builder: (context) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return ColoredBox(
            // The same opaque surface the views paint, carried out under
            // the status bar and the gesture area.
            color: dark ? const Color(0xFF1E1E22) : const Color(0xFFF5F5F7),
            child: SafeArea(
              child: ListenableBuilder(
                listenable: Listenable.merge([shell.sync, shell.page]),
                builder: (context, _) => AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: switch (shell.page.value) {
                    PanelPage.history => ClipboardPanel(
                      key: const ValueKey(PanelPage.history),
                      history: shell.history,
                      reveal: const AlwaysStoppedAnimation(1),
                      visit: 0,
                      hasMaterial: false,
                      touch: true,
                      onCopy: shell.copy,
                      // There is nothing to close: the app is the screen.
                      onDismiss: () {},
                      sync: syncSummaryOf(shell.sync),
                      onOpenSync: () => shell.page.value = PanelPage.sync,
                      clock: widget.clock,
                    ),
                    PanelPage.sync => SyncSettingsView(
                      key: const ValueKey(PanelPage.sync),
                      sync: shell.sync,
                      hasMaterial: false,
                      onSendHistory: shell.shareHistory,
                      autoCopyOn: widget.bridge == null ? null : _autoCopyOn,
                      onOpenAutoCopy: widget.bridge?.openAutoCopySettings,
                      onDone: () => shell.page.value = PanelPage.history,
                    ),
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
    );
  }
}
