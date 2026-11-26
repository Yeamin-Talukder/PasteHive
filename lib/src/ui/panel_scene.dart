import 'package:flutter/material.dart';

import '../history/clipboard_entry.dart';
import '../history/clipboard_history.dart';
import '../shell/panel_controller.dart';
import 'clipboard_panel.dart';

/// Plays the panel's entrance and exit.
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
    this.clock = DateTime.now,
  });

  final PanelController controller;
  final ClipboardHistory history;
  final ValueChanged<ClipboardEntry> onCopy;
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
    return ClipboardPanel(
      history: widget.history,
      reveal: _reveal,
      visit: widget.controller.openCount,
      hasMaterial: widget.controller.hasMaterial,
      onCopy: widget.onCopy,
      onDismiss: widget.controller.dismiss,
      clock: widget.clock,
    );
  }
}
