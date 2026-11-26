import 'package:flutter/material.dart';

import '../app_shell.dart' show PanelPage;
import '../history/clipboard_entry.dart';
import '../history/clipboard_history.dart';
import '../shell/panel_controller.dart';
import '../sync/sync_service.dart';
import 'clipboard_panel.dart';
import 'sync_settings_view.dart';

/// Plays the panel's entrance and exit, and switches between its views.
///
/// One animation drives two things at once: the window sliding down from the
/// top edge (through [PanelController.setRevealProgress]) and the content
/// settling in inside it. When the exit has finished the controller is told,
/// and only then does the window leave the screen.
class PanelScene extends StatefulWidget {
  const PanelScene({
    super.key,
    required this.controller,
    required this.history,
    required this.onCopy,
    this.sync,
    this.page,
    this.clock = DateTime.now,
  });

  final PanelController controller;
  final ClipboardHistory history;
  final ValueChanged<ClipboardEntry> onCopy;

  /// Sync, when the app has it; without it the panel is the list alone.
  final SyncService? sync;

  /// Which view is showing. Needed together with [sync].
  final ValueNotifier<PanelPage>? page;

  final DateTime Function() clock;

  @override
  State<PanelScene> createState() => _PanelSceneState();
}

class _PanelSceneState extends State<PanelScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 170),
  );

  // The window overshoots its resting place by a hair and settles back, which
  // is what makes the drop feel like it has weight. Leaving is quick and plain.
  late final Animation<double> _windowProgress = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _reveal
      ..addListener(_pushProgress)
      ..addStatusListener(_onStatus);
    widget.controller.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(PanelScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _reveal.dispose();
    super.dispose();
  }

  void _sync() {
    final open = widget.controller.isOpen;
    // A new visit resets the search field and the selection.
    setState(() {});
    if (_reduceMotion) {
      // No travel and no stagger: the panel is simply there, or not.
      _reveal.value = open ? 1 : 0;
      if (!open) widget.controller.didFinishDismiss();
      return;
    }
    if (open) {
      _reveal.forward();
    } else if (_reveal.isDismissed) {
      widget.controller.didFinishDismiss();
    } else {
      _reveal.reverse();
    }
  }

  void _pushProgress() {
    widget.controller.setRevealProgress(_windowProgress.value);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      widget.controller.didFinishDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    final page = widget.page;
    if (sync == null || page == null) return _buildList(null, null);

    return ListenableBuilder(
      listenable: Listenable.merge([sync, page]),
      builder: (context, _) => AnimatedSwitcher(
        duration: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: switch (page.value) {
          PanelPage.history => KeyedSubtree(
            key: const ValueKey(PanelPage.history),
            child: _buildList(
              syncSummaryOf(sync),
              () => page.value = PanelPage.sync,
            ),
          ),
          PanelPage.sync => SyncSettingsView(
            key: const ValueKey(PanelPage.sync),
            sync: sync,
            hasMaterial: widget.controller.hasMaterial,
            onDone: () => page.value = PanelPage.history,
          ),
        },
      ),
    );
  }

  Widget _buildList(SyncSummary? summary, VoidCallback? onOpenSync) {
    return ClipboardPanel(
      history: widget.history,
      reveal: _reveal,
      visit: widget.controller.openCount,
      hasMaterial: widget.controller.hasMaterial,
      onCopy: widget.onCopy,
      onDismiss: widget.controller.dismiss,
      sync: summary,
      onOpenSync: onOpenSync,
      clock: widget.clock,
    );
  }
}

/// The state of sync in a word or two, for the panel's footer.
SyncSummary syncSummaryOf(SyncService sync) {
  if (!sync.hasKey || !sync.enabled) {
    return const SyncSummary(label: 'Sync Off');
  }
  if (sync.error != null) return const SyncSummary(label: 'Sync Problem');
  final peers = sync.peers;
  return switch (peers.length) {
    0 => const SyncSummary(label: 'Searching…'),
    1 => SyncSummary(label: peers.single.name, connected: true),
    final count => SyncSummary(label: '$count Devices', connected: true),
  };
}
