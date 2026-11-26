import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../history/clipboard_entry.dart';
import '../history/clipboard_history.dart';
import 'panel_palette.dart';

/// The contents of the clipboard panel: a search field over the list of
/// things copied.
///
/// The window it sits in is the system's (rounded corners, shadow and the
/// translucent material come from there). This widget lays its content over
/// that and plays the entrance: rows settle in one after another as
/// [reveal] goes from 0 to 1.
class ClipboardPanel extends StatefulWidget {
  const ClipboardPanel({
    super.key,
    required this.history,
    required this.reveal,
    required this.visit,
    required this.hasMaterial,
    required this.onCopy,
    required this.onDismiss,
    this.clock = DateTime.now,
  });

  final ClipboardHistory history;

  /// 0 while the panel is hidden, 1 when it is fully open.
  final Animation<double> reveal;

  /// Changes each time the panel opens; search and selection start over.
  final int visit;

  /// Whether the window paints a translucent material behind this widget.
  final bool hasMaterial;

  final ValueChanged<ClipboardEntry> onCopy;
  final VoidCallback onDismiss;

  /// The current time, for "5 min ago". Replaceable so tests are stable.
  final DateTime Function() clock;

  @override
  State<ClipboardPanel> createState() => _ClipboardPanelState();
}

class _ClipboardPanelState extends State<ClipboardPanel> {
  static const _listPadding = 6.0;

  final _search = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _searchFocus = FocusNode(
    debugLabel: 'Clipboard search',
    onKeyEvent: _onKey,
  );

  List<ClipboardEntry> _results = const [];
  int _selected = 0;
  double _rowExtent = 54;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQueryChanged);
  }

  @override
  void didUpdateWidget(ClipboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visit != oldWidget.visit) {
      _search.clear();
      _selected = 0;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _searchFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() => _selected = 0);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // The search field keeps the keyboard the whole time the panel is open, so
  // the keys that drive the list are taken here, before the field sees them.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _select(_selected + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _select(_selected - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_selected < _results.length) widget.onCopy(_results[_selected]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_search.text.isNotEmpty) {
        _search.clear();
      } else {
        widget.onDismiss();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _select(int index) {
    if (_results.isEmpty) return;
    final next = index.clamp(0, _results.length - 1);
    if (next == _selected) return;
    setState(() => _selected = next);
    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = _listPadding + _selected * _rowExtent;
    final bottom = top + _rowExtent;
    double? target;
    if (top < position.pixels) {
      target = top - _listPadding;
    } else if (bottom > position.pixels + position.viewportDimension) {
      target = bottom + _listPadding - position.viewportDimension;
    }
    if (target != null) {
      _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = PanelPalette.of(
      brightness: Theme.of(context).brightness,
      hasMaterial: widget.hasMaterial,
      highContrast: MediaQuery.highContrastOf(context),
    );
    // Rows grow with the user's text size so two lines always fit.
    _rowExtent = math.max(54, MediaQuery.textScalerOf(context).scale(13) * 4.2);

    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        // Built on the theme's body style so the platform's own UI font is
        // used (San Francisco on macOS, Segoe UI on Windows).
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: 13,
          height: 1.25,
          letterSpacing: 0,
          color: palette.label,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: palette.surface),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 72,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          palette.sheen,
                          palette.sheen.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: widget.history,
                builder: (context, _) {
                  _results = widget.history.search(_search.text);
                  if (_selected >= _results.length) {
                    _selected = math.max(0, _results.length - 1);
                  }
                  return Column(
                    children: [
                      _SearchField(
                        controller: _search,
                        focusNode: _searchFocus,
                        palette: palette,
                      ),
                      Expanded(
                        child: _results.isEmpty
                            ? _EmptyState(
                                palette: palette,
                                query: _search.text.trim(),
                              )
                            : _buildList(palette),
                      ),
                      _Footer(
                        palette: palette,
                        count: _results.length,
                        paused: widget.history.paused,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(PanelPalette palette) {
    final now = widget.clock();
    return ShaderMask(
      // Rows fade out as they slide under the search field and the footer,
      // instead of being cut off by a hard line.
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00000000),
          Color(0xFF000000),
          Color(0xFF000000),
          Color(0x00000000),
        ],
        stops: [0, 0.03, 0.97, 1],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: _listPadding),
        itemExtent: _rowExtent,
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final entry = _results[index];
          return _Entrance(
            reveal: widget.reveal,
            index: index,
            child: _EntryRow(
              key: ValueKey(entry.id),
              entry: entry,
              palette: palette,
              now: now,
              selected: index == _selected,
              onHover: () {
                if (_selected != index) setState(() => _selected = index);
              },
              onCopy: () => widget.onCopy(entry),
              onTogglePin: () => widget.history.togglePin(entry.id),
              onDelete: () => widget.history.remove(entry.id),
            ),
          );
        },
      ),
    );
  }
}

/// Lets a row settle into place a little after the row above it.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.reveal,
    required this.index,
    required this.child,
  });

  static const _firstRowStart = 0.1;
  static const _stagger = 0.05;
  static const _span = 0.45;
  static const _maxStaggered = 9;
  static const _travel = 10.0;

  final Animation<double> reveal;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reveal,
      child: child,
      builder: (context, child) {
        if (reveal.value >= 1) return child!;
        final start =
            _firstRowStart + math.min(index, _maxStaggered) * _stagger;
        final local = ((reveal.value - start) / _span).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(local);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, (eased - 1) * _travel),
            child: child,
          ),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.palette,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PanelPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: palette.controlFill,
            shape: const StadiumBorder(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.search,
                  size: 15,
                  color: palette.secondaryLabel,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: palette.label,
                    ),
                    cursorColor: palette.accent,
                    cursorWidth: 1.5,
                    decoration: InputDecoration.collapsed(
                      hintText: 'Search Clipboard',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: palette.secondaryLabel,
                      ),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    if (controller.text.isEmpty) return const SizedBox.shrink();
                    return _IconAction(
                      icon: CupertinoIcons.clear_circled_solid,
                      label: 'Clear Search',
                      palette: palette,
                      size: 20,
                      onPressed: controller.clear,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.entry,
    required this.palette,
    required this.now,
    required this.selected,
    required this.onHover,
    required this.onCopy,
    required this.onTogglePin,
    required this.onDelete,
  });

  final ClipboardEntry entry;
  final PanelPalette palette;
  final DateTime now;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onCopy;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        onHover: (_) => onHover(),
        child: Semantics(
          button: true,
          selected: selected,
          label: 'Copy ${entry.preview}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCopy,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              decoration: BoxDecoration(
                color: selected ? palette.rowSelected : const Color(0x00000000),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _KindTile(entry: entry, palette: palette),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${relativeTime(entry.copiedAt, now)} · '
                            '${describeEntry(entry)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.secondaryLabel,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    _IconAction(
                      icon: entry.pinned
                          ? CupertinoIcons.pin_slash
                          : CupertinoIcons.pin,
                      label: entry.pinned ? 'Unpin' : 'Pin',
                      palette: palette,
                      onPressed: onTogglePin,
                    ),
                    _IconAction(
                      icon: CupertinoIcons.trash,
                      label: 'Delete',
                      palette: palette,
                      onPressed: onDelete,
                    ),
                  ] else if (entry.pinned) ...[
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        CupertinoIcons.pin_fill,
                        size: 12,
                        color: palette.accent,
                        semanticLabel: 'Pinned',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small tile that says what kind of thing a row holds.
class _KindTile extends StatelessWidget {
  const _KindTile({required this.entry, required this.palette});

  final ClipboardEntry entry;
  final PanelPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: palette.controlFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        entry.isLink ? CupertinoIcons.link : CupertinoIcons.doc_text,
        size: 15,
        color: palette.secondaryLabel,
      ),
    );
  }
}

/// An icon-only button with a tooltip and a screen-reader label.
class _IconAction extends StatefulWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onPressed,
    this.size = 28,
  });

  final IconData icon;
  final String label;
  final PanelPalette palette;
  final VoidCallback onPressed;
  final double size;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 600),
      child: Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: _hovered
                    ? widget.palette.controlFill
                    : const Color(0x00000000),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.icon,
                size: widget.size * 0.5,
                color: _hovered
                    ? widget.palette.label
                    : widget.palette.secondaryLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.query});

  final PanelPalette palette;
  final String query;

  @override
  Widget build(BuildContext context) {
    final searching = query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? CupertinoIcons.search
                  : CupertinoIcons.doc_on_clipboard,
              size: 34,
              color: palette.tertiaryLabel,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'No Results' : 'Nothing Copied Yet',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              searching
                  ? 'Nothing you copied matches “$query”.'
                  : 'Copy some text and it shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.palette,
    required this.count,
    required this.paused,
  });

  final PanelPalette palette;
  final int count;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: palette.secondaryLabel);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.separator)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 9),
        child: Row(
          children: [
            if (paused) ...[
              Icon(
                CupertinoIcons.pause_circle_fill,
                size: 13,
                color: palette.secondaryLabel,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              paused
                  ? 'Capturing Paused'
                  : count == 1
                  ? '1 item'
                  : '$count items',
              style: style,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  // Named as the keys are labelled on each platform's
                  // keyboards.
                  defaultTargetPlatform == TargetPlatform.macOS
                      ? '↑↓ Select   return Copy   esc Close'
                      : '↑↓ Select   Enter Copy   Esc Close',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: style,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How long ago [time] was, in the fewest words that are still clear.
String relativeTime(DateTime time, DateTime now) {
  final elapsed = now.difference(time);
  if (elapsed.inSeconds < 45) return 'Just now';
  if (elapsed.inMinutes < 60) {
    return '${math.max(1, elapsed.inMinutes)} min ago';
  }
  if (elapsed.inHours < 24) return '${elapsed.inHours} hr ago';
  if (elapsed.inDays < 2) return 'Yesterday';
  if (elapsed.inDays < 7) return '${elapsed.inDays} days ago';
  final local = time.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A short note on what an entry is: where a link goes, or how much text.
String describeEntry(ClipboardEntry entry) {
  if (entry.isLink) return Uri.parse(entry.text.trim()).host;
  final lines = entry.lineCount;
  if (lines > 1) return '$lines lines';
  final characters = entry.text.trim().length;
  return characters == 1 ? '1 character' : '$characters characters';
}
