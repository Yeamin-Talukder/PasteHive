import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../app_shell.dart' show PanelPage;
import '../history/clipboard_entry.dart';
import '../history/clipboard_history.dart';
import '../platform/ports.dart';
import '../shell/panel_controller.dart';
import '../sync/sync_service.dart';
import 'clipboard_panel.dart';
import 'glass_shell.dart';
import 'sync_settings_view.dart';

/// Makes the picture of the screen behind the panel into frosted glass.
typedef BackdropPreparer = Future<ui.Image?> Function(
  BackdropCapture capture,
  double pixelRatio,
);

/// Plays the panel's entrance and exit, and switches between its views.
///
/// One spring drives everything that moves when the panel opens: the glass
/// growing out of the top edge (or, where the system draws the panel, the
/// window sliding down) and the content settling in inside it. When the exit
/// has finished the controller is told, and only then does the window leave
/// the screen.
class PanelScene extends StatefulWidget {
  const PanelScene({
    super.key,
    required this.controller,
    required this.history,
    required this.onCopy,
    this.sync,
    this.page,
    this.prepareBackdrop = _blur,
    this.clock = DateTime.now,
  });

  final PanelController controller;
  final ClipboardHistory history;
  final ValueChanged<ClipboardEntry> onCopy;

  /// Sync, when the app has it; without it the panel is the list alone.
  final SyncService? sync;

  /// Which view is showing. Needed together with [sync].
  final ValueNotifier<PanelPage>? page;

  /// Replaceable so tests need not wait for real image work.
  final BackdropPreparer prepareBackdrop;

  final DateTime Function() clock;

  static Future<ui.Image?> _blur(BackdropCapture capture, double pixelRatio) {
    return blurBackdrop(capture, devicePixelRatio: pixelRatio);
  }

  @override
  State<PanelScene> createState() => _PanelSceneState();
}

class _PanelSceneState extends State<PanelScene>
    with SingleTickerProviderStateMixin {
  // Lively but controlled: it overshoots its resting place by a couple of
  // percent and settles in about a third of a second.
  static const _openSpring = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 30,
  );
  static const _closeDuration = Duration(milliseconds: 190);

  // Unbounded, so the spring's overshoot past 1 is not cut off.
  late final AnimationController _reveal = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  bool _reduceMotion = false;
  ui.Image? _backdrop;
  BackdropCapture? _preparedFrom;
  int _visit = 0;

  /// Whether this app draws the panel's glass (as opposed to the system).
  bool get _drawsChrome => widget.controller.chromeInsets != EdgeInsets.zero;

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
    _backdrop?.dispose();
    super.dispose();
  }

  void _sync() {
    final controller = widget.controller;
    // A new visit resets the search field and the selection.
    setState(() {});

    if (!controller.isOpen) {
      _close();
      return;
    }
    if (controller.openCount == _visit) {
      // Reopened before it had finished closing: turn around.
      _open();
      return;
    }
    _visit = controller.openCount;
    final capture = _drawsChrome ? controller.backdrop : null;
    if (capture == null) {
      _preparedFrom = null;
      _setBackdrop(null);
      _open();
    } else if (identical(capture, _preparedFrom) && _backdrop != null) {
      // The same picture as last time (a reopen mid-close): already glass.
      _open();
    } else {
      _preparedFrom = capture;
      unawaited(_openOver(capture, _visit));
    }
  }

  // The glass is drawn over a blurred picture of the screen. Preparing it
  // takes a few milliseconds, during which the window is up but empty; the
  // entrance starts once it is ready, so the first frame is already glass.
  Future<void> _openOver(BackdropCapture capture, int visit) async {
    ui.Image? image;
    try {
      image = await widget.prepareBackdrop(
        capture,
        MediaQuery.devicePixelRatioOf(context),
      );
    } on Object catch (error) {
      debugPrint('Could not prepare the backdrop: $error');
    }
    if (!mounted || visit != _visit) {
      image?.dispose();
      return;
    }
    _setBackdrop(image);
    if (widget.controller.isOpen) _open();
  }

  void _setBackdrop(ui.Image? image) {
    final previous = _backdrop;
    if (identical(previous, image)) return;
    setState(() => _backdrop = image);
    previous?.dispose();
  }

  void _open() {
    if (_reduceMotion) {
      // No travel and no stagger: the panel is simply there.
      _reveal.value = 1;
      return;
    }
    _reveal.animateWith(SpringSimulation(_openSpring, _reveal.value, 1, 0));
  }

  void _close() {
    if (_reduceMotion || _reveal.value <= 0) {
      _reveal.value = 0;
      widget.controller.didFinishDismiss();
      return;
    }
    _reveal.animateBack(0, duration: _closeDuration, curve: Curves.easeInCubic);
  }

  void _pushProgress() {
    widget.controller.setRevealProgress(_reveal.value);
  }

  void _onStatus(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.completed:
        // A spring stops within a hair of its target; land exactly on it.
        _reveal.value = 1;
      case AnimationStatus.dismissed:
        widget.controller.didFinishDismiss();
      case AnimationStatus.forward || AnimationStatus.reverse:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildPages();
    if (!_drawsChrome) return content;
    return GlassShell(
      reveal: _reveal,
      insets: widget.controller.chromeInsets,
      backdrop: _backdrop,
      onTapOutside: widget.controller.dismiss,
      child: content,
    );
  }

  /// Whether something translucent is behind the content: the system's
  /// material, or the blurred picture this app draws.
  bool get _hasMaterial =>
      _drawsChrome ? _backdrop != null : widget.controller.hasMaterial;

  Widget _buildPages() {
    final sync = widget.sync;
    final page = widget.page;
    if (sync == null || page == null) return _buildList(null, null);

    return ListenableBuilder(
      listenable: Listenable.merge([sync, page]),
      builder: (context, _) => AnimatedSwitcher(
        duration: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
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
            hasMaterial: _hasMaterial,
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
      hasMaterial: _hasMaterial,
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
