import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../history/clipboard_entry.dart';
import '../history/clipboard_history.dart';
import 'panel_palette.dart';
import 'panel_surface.dart';

/// The contents of the clipboard panel: a search field and filters over the
/// list of things copied, grouped by when they were copied.
///
/// Everything can be done from the keyboard: arrows move, Enter copies,
/// Space previews, Tab changes the filter, Delete removes (and can be
/// undone). Rows settle in one after another as [reveal] goes from 0 to 1.
class ClipboardPanel extends StatefulWidget {
  const ClipboardPanel({
    super.key,
    required this.history,
    required this.reveal,
    required this.visit,
    required this.hasMaterial,
    required this.onCopy,
    required this.onDismiss,
    this.sync,
    this.onOpenSync,
    this.pastesOnSelect = false,
    this.touch = false,
    this.clock = DateTime.now,
  });

  final ClipboardHistory history;

  /// 0 while the panel is hidden, 1 when it is fully open.
  final Animation<double> reveal;

  /// Changes each time the panel opens; search, filter and selection start
  /// over.
  final int visit;

  /// Whether something translucent is behind this widget (a system material
  /// or a blurred backdrop). Without it the surface is opaque.
  final bool hasMaterial;

  final ValueChanged<ClipboardEntry> onCopy;
  final VoidCallback onDismiss;

  /// What to say about sync in the footer; null leaves sync out of it.
  final SyncSummary? sync;

  /// Opens the sync settings.
  final VoidCallback? onOpenSync;

  /// Whether choosing an entry also pastes it into the app the user was
  /// working in; only changes how the key hint reads.
  final bool pastesOnSelect;

  /// Whether this is a touch screen with no keyboard or pointer. There the
  /// key hints are left out, and a row's actions are reached by holding it
  /// (which opens its preview) instead of by hovering over it.
  final bool touch;

  /// The current time, for "5 min ago". Replaceable so tests are stable.
  final DateTime Function() clock;

  @override
  State<ClipboardPanel> createState() => _ClipboardPanelState();
}

class _ClipboardPanelState extends State<ClipboardPanel> {
  static const _listPadding = 4.0;
  static const _undoWindow = Duration(seconds: 5);

  /// The filters that are there even when they would show nothing.
  static const _alwaysOffered = {
    EntryFilter.all,
    EntryFilter.pinned,
    EntryFilter.text,
    EntryFilter.links,
    EntryFilter.images,
  };

  final _search = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _searchFocus = FocusNode(
    debugLabel: 'Clipboard search',
    onKeyEvent: _onKey,
  );

  List<ClipboardEntry> _results = const [];
  List<_ListItem> _items = const [];
  int _selected = 0;
  EntryFilter _filter = EntryFilter.all;
  bool _previewing = false;

  /// The entry just copied, so its row can show a check mark on the way out.
  String? _copiedId;

  /// The entry just deleted, while it can still be brought back.
  ClipboardEntry? _deleted;
  Timer? _undoTimer;

  double _rowExtent = 56;
  double _headerExtent = 28;

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
      _filter = EntryFilter.all;
      _previewing = false;
      _copiedId = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _searchFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _search.dispose();
    _scroll.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  ClipboardEntry? get _selectedEntry =>
      _selected < _results.length ? _results[_selected] : null;

  void _onQueryChanged() {
    setState(() => _selected = 0);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // The search field keeps the keyboard the whole time the panel is open, so
  // the keys that drive the list are taken here, before the field sees them.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    final typing = _search.text.isNotEmpty;

    if (key == LogicalKeyboardKey.arrowDown) {
      _select(_selected + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _select(_selected - 1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final entry = _selectedEntry;
      if (entry != null) _copy(entry);
    } else if (key == LogicalKeyboardKey.escape) {
      _stepBack();
    } else if (key == LogicalKeyboardKey.tab) {
      _cycleFilter(keyboard.isShiftPressed ? -1 : 1);
    } else if (key == LogicalKeyboardKey.space && !typing) {
      // A search cannot start with a space, so the key is free for this.
      _togglePreview();
    } else if (key == LogicalKeyboardKey.delete && !typing) {
      final entry = _selectedEntry;
      if (entry != null) _delete(entry);
    } else if (command && key == LogicalKeyboardKey.keyP) {
      final entry = _selectedEntry;
      if (entry != null) widget.history.togglePin(entry.id);
    } else if (command && key == LogicalKeyboardKey.keyZ && _deleted != null) {
      _undoDelete();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Escape undoes one thing at a time: the preview, then the search, then
  /// the filter, and only then closes the panel.
  void _stepBack() {
    if (_previewing) {
      setState(() => _previewing = false);
    } else if (_search.text.isNotEmpty) {
      _search.clear();
    } else if (_filter != EntryFilter.all) {
      _setFilter(EntryFilter.all);
    } else {
      widget.onDismiss();
    }
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
    final itemIndex = _items.indexWhere(
      (item) => item is _EntryItem && item.index == _selected,
    );
    if (itemIndex < 0) return;
    var top = _listPadding;
    for (var i = 0; i < itemIndex; i++) {
      top += _extentOf(_items[i]);
    }
    final extent = _extentOf(_items[itemIndex]);
    // Scrolling up to the first row of a group brings its heading along.
    final reach = itemIndex > 0 && _items[itemIndex - 1] is _HeaderItem
        ? _headerExtent
        : 0.0;

    final position = _scroll.position;
    double? target;
    if (top - reach < position.pixels) {
      target = top - reach - _listPadding;
    } else if (top + extent > position.pixels + position.viewportDimension) {
      target = top + extent + _listPadding - position.viewportDimension;
    }
    if (target != null) {
      _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    }
  }

  void _setFilter(EntryFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _selected = 0;
      _previewing = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _cycleFilter(int step) {
    final filters = _availableFilters();
    final current = filters.indexOf(_filter);
    _setFilter(filters[(current + step) % filters.length]);
  }

  /// Filters that would show nothing at all are left out, apart from the
  /// basic ones, so the row is not cluttered with dead ends.
  List<EntryFilter> _availableFilters() {
    final entries = widget.history.entries;
    return [
      for (final filter in EntryFilter.values)
        if (_alwaysOffered.contains(filter) ||
            filter == _filter ||
            entries.any(filter.accepts))
          filter,
    ];
  }

  void _togglePreview() {
    if (_selectedEntry == null) return;
    setState(() => _previewing = !_previewing);
  }

  void _copy(ClipboardEntry entry) {
    setState(() => _copiedId = entry.id);
    widget.onCopy(entry);
  }

  void _delete(ClipboardEntry entry) {
    widget.history.remove(entry.id);
    _undoTimer?.cancel();
    _undoTimer = Timer(_undoWindow, () {
      if (mounted) setState(() => _deleted = null);
    });
    setState(() {
      _deleted = entry;
      _previewing = false;
    });
  }

  void _undoDelete() {
    final entry = _deleted;
    if (entry == null) return;
    _undoTimer?.cancel();
    widget.history.restore(entry);
    setState(() => _deleted = null);
  }

  double _extentOf(_ListItem item) =>
      item is _HeaderItem ? _headerExtent : _rowExtent;

  @override
  Widget build(BuildContext context) {
    // Rows grow with the user's text size so two lines always fit.
    final scaler = MediaQuery.textScalerOf(context);
    _rowExtent = math.max(56, scaler.scale(13) * 4.3);
    _headerExtent = math.max(28, scaler.scale(11) * 2.6);

    return PanelSurface(
      hasMaterial: widget.hasMaterial,
      builder: (context, palette) => ListenableBuilder(
        listenable: widget.history,
        builder: (context, _) {
          final now = widget.clock();
          _results = widget.history.search(_search.text, filter: _filter);
          if (_selected >= _results.length) {
            _selected = math.max(0, _results.length - 1);
          }
          _items = _group(_results, now);
          final previewed = _previewing ? _selectedEntry : null;

          return Column(
            children: [
              _SearchField(
                controller: _search,
                focusNode: _searchFocus,
                palette: palette,
              ),
              _FilterBar(
                filters: _availableFilters(),
                selected: _filter,
                palette: palette,
                onSelected: _setFilter,
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _results.isEmpty
                          ? _EmptyState(
                              palette: palette,
                              query: _search.text.trim(),
                              filter: _filter,
                            )
                          : _buildList(palette, now),
                    ),
                    Positioned.fill(
                      child: _PreviewLayer(
                        entry: previewed,
                        palette: palette,
                        now: now,
                        onClose: () => setState(() => _previewing = false),
                        onCopy: _copy,
                        onTogglePin: (entry) =>
                            widget.history.togglePin(entry.id),
                        onDelete: _delete,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 10,
                      child: _UndoToast(
                        visible: _deleted != null,
                        palette: palette,
                        onUndo: _undoDelete,
                      ),
                    ),
                  ],
                ),
              ),
              _Footer(
                palette: palette,
                count: _results.length,
                paused: widget.history.paused,
                sync: widget.sync,
                onOpenSync: widget.onOpenSync,
                selectVerb: widget.pastesOnSelect ? 'Paste' : 'Copy',
                showKeyHints: !widget.touch,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Puts a heading before each run of entries from the same period.
  static List<_ListItem> _group(List<ClipboardEntry> entries, DateTime now) {
    final items = <_ListItem>[];
    String? current;
    for (final (index, entry) in entries.indexed) {
      final section = sectionOf(entry, now);
      if (section != current) {
        items.add(_HeaderItem(section));
        current = section;
      }
      items.add(_EntryItem(entry, index));
    }
    return items;
  }

  Widget _buildList(PanelPalette palette, DateTime now) {
    return ShaderMask(
      // Rows fade out as they slide under the filters and the footer,
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
        stops: [0, 0.025, 0.97, 1],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: _listPadding),
        itemCount: _items.length,
        itemExtentBuilder: (index, _) =>
            index < _items.length ? _extentOf(_items[index]) : null,
        itemBuilder: (context, index) {
          final item = _items[index];
          return _Entrance(
            reveal: widget.reveal,
            index: index,
            child: switch (item) {
              _HeaderItem(:final title) => _SectionHeader(
                title,
                palette: palette,
              ),
              _EntryItem(:final entry, index: final entryIndex) => _EntryRow(
                key: ValueKey(entry.id),
                entry: entry,
                palette: palette,
                now: now,
                selected: entryIndex == _selected && !widget.touch,
                copied: entry.id == _copiedId,
                onHover: () {
                  if (_selected != entryIndex) {
                    setState(() => _selected = entryIndex);
                  }
                },
                onCopy: () => _copy(entry),
                onPreview: () => setState(() {
                  _selected = entryIndex;
                  _previewing = true;
                }),
                onTogglePin: () => widget.history.togglePin(entry.id),
                onDelete: () => _delete(entry),
              ),
            },
          );
        },
      ),
    );
  }
}

sealed class _ListItem {
  const _ListItem();
}

class _HeaderItem extends _ListItem {
  const _HeaderItem(this.title);

  final String title;
}

class _EntryItem extends _ListItem {
  const _EntryItem(this.entry, this.index);

  final ClipboardEntry entry;

  /// The entry's place among the results, which is what selection counts in.
  final int index;
}

/// Lets a row settle into place a little after the row above it.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.reveal,
    required this.index,
    required this.child,
  });

  static const _firstRowStart = 0.25;
  static const _stagger = 0.045;
  static const _span = 0.5;
  static const _maxStaggered = 9;
  static const _travel = 12.0;

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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 38),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: palette.controlFill,
            shape: const StadiumBorder(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                    return PanelIconButton(
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

/// The row of filters under the search field.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.palette,
    required this.onSelected,
  });

  final List<EntryFilter> filters;
  final EntryFilter selected;
  final PanelPalette palette;
  final ValueChanged<EntryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: math.max(30, MediaQuery.textScalerOf(context).scale(12) * 2.5),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final filter = filters[index];
          return _FilterChip(
            label: filter.label,
            selected: filter == selected,
            palette: palette,
            onTap: () => onSelected(filter),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final PanelPalette palette;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;

  @override
  void didUpdateWidget(_FilterChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      // Chosen from the keyboard it may be past the edge of the row.
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${widget.label} filter',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ShapeDecoration(
              color: widget.selected
                  ? palette.chipSelected
                  : _hovered
                  ? palette.rowHover
                  : const Color(0x00000000),
              shape: const StadiumBorder(),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                // The weight changes with the fill, so which filter is on
                // does not rest on colour alone.
                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                color: widget.selected ? palette.label : palette.secondaryLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {required this.palette});

  final String title;
  final PanelPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 22, bottom: 4),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Semantics(
          header: true,
          child: Text(
            title,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.tertiaryLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatefulWidget {
  const _EntryRow({
    super.key,
    required this.entry,
    required this.palette,
    required this.now,
    required this.selected,
    required this.copied,
    required this.onHover,
    required this.onCopy,
    required this.onPreview,
    required this.onTogglePin,
    required this.onDelete,
  });

  final ClipboardEntry entry;
  final PanelPalette palette;
  final DateTime now;
  final bool selected;
  final bool copied;
  final VoidCallback onHover;
  final VoidCallback onCopy;
  final VoidCallback onPreview;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final palette = widget.palette;
    final source = entry.source;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
      child: MouseRegion(
        onHover: (_) => widget.onHover(),
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: 'Copy ${entry.preview}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: widget.onCopy,
            // Holding a row opens its preview, where it can be pinned or
            // deleted: the way to those on a touch screen.
            onLongPress: widget.onPreview,
            child: AnimatedScale(
              // The row gives a little under the pointer.
              scale: _pressed ? 0.985 : 1,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? palette.rowSelected
                      : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(13),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    _KindTile(entry: entry, palette: palette),
                    const SizedBox(width: 11),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                relativeTime(entry.copiedAt, widget.now),
                                describeEntry(entry),
                                if (source != null) 'from $source',
                              ].join(' · '),
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
                    ..._trailing(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _trailing() {
    final entry = widget.entry;
    final palette = widget.palette;
    if (widget.copied) {
      return [
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            CupertinoIcons.checkmark_circle_fill,
            size: 18,
            color: palette.positive,
            semanticLabel: 'Copied',
          ),
        ),
      ];
    }
    if (widget.selected) {
      return [
        const SizedBox(width: 4),
        PanelIconButton(
          icon: CupertinoIcons.eye,
          label: 'Preview',
          palette: palette,
          onPressed: widget.onPreview,
        ),
        PanelIconButton(
          icon: entry.pinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin,
          label: entry.pinned ? 'Unpin' : 'Pin',
          palette: palette,
          onPressed: widget.onTogglePin,
        ),
        PanelIconButton(
          icon: CupertinoIcons.trash,
          label: 'Delete',
          palette: palette,
          onPressed: widget.onDelete,
        ),
      ];
    }
    if (entry.pinned) {
      return [
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Icon(
            CupertinoIcons.pin_fill,
            size: 12,
            color: palette.tertiaryLabel,
            semanticLabel: 'Pinned',
          ),
        ),
      ];
    }
    return const [];
  }
}

/// The small tile that says what kind of thing an entry is. A colour entry
/// shows the colour itself, and an image entry a thumbnail of the image.
class _KindTile extends StatelessWidget {
  const _KindTile({required this.entry, required this.palette, this.size = 34});

  final ClipboardEntry entry;
  final PanelPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final swatch = entry.color;
    final imagePath = entry.imagePath;
    final (IconData icon, Color tint) = switch (entry.kind) {
      EntryKind.link => (CupertinoIcons.link, palette.linkTint),
      EntryKind.email => (CupertinoIcons.at, palette.emailTint),
      EntryKind.color => (CupertinoIcons.drop, palette.secondaryLabel),
      EntryKind.image => (CupertinoIcons.photo, palette.secondaryLabel),
      EntryKind.files => (
        entry.files.length == 1
            ? CupertinoIcons.doc
            : CupertinoIcons.doc_on_doc,
        palette.fileTint,
      ),
      EntryKind.text => (CupertinoIcons.text_alignleft, palette.secondaryLabel),
    };
    final symbol = Icon(icon, size: size * 0.46, color: tint);
    final radius = BorderRadius.circular(size * 0.3);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: swatch ?? palette.controlFill,
        borderRadius: radius,
        border: swatch == null && imagePath == null
            ? null
            : Border.all(color: palette.separator),
      ),
      child: swatch != null
          ? null
          : imagePath == null
          ? symbol
          : Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              // Decoded small: a list of thumbnails must not hold a
              // full-size screenshot each.
              cacheWidth: (size * 3).round(),
              gaplessPlayback: true,
              excludeFromSemantics: true,
              // Until the thumbnail is read from disk, the symbol stands in.
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                  frame == null && !wasSynchronouslyLoaded ? symbol : child,
              // The file can be gone (removed by hand, say); show what kind
              // of thing it was instead.
              errorBuilder: (context, error, stackTrace) => symbol,
            ),
    );
  }
}

/// The preview of one entry in full, sliding up over the list.
class _PreviewLayer extends StatelessWidget {
  const _PreviewLayer({
    required this.entry,
    required this.palette,
    required this.now,
    required this.onClose,
    required this.onCopy,
    required this.onTogglePin,
    required this.onDelete,
  });

  /// The entry to show, or null to show nothing.
  final ClipboardEntry? entry;
  final PanelPalette palette;
  final DateTime now;
  final VoidCallback onClose;
  final ValueChanged<ClipboardEntry> onCopy;
  final ValueChanged<ClipboardEntry> onTogglePin;
  final ValueChanged<ClipboardEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    final still = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: entry == null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: AnimatedOpacity(
                opacity: entry == null ? 0 : 1,
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: ColoredBox(color: palette.scrim),
              ),
            ),
          ),
        ),
        Positioned.fill(
          top: 26,
          child: AnimatedSwitcher(
            duration: still ? Duration.zero : const Duration(milliseconds: 240),
            reverseDuration: still
                ? Duration.zero
                : const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.1),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: entry == null
                ? const SizedBox.expand()
                : _PreviewSheet(
                    // The same sheet while the selection moves under it.
                    key: const ValueKey('preview'),
                    entry: entry,
                    palette: palette,
                    now: now,
                    onClose: onClose,
                    onCopy: () => onCopy(entry),
                    onTogglePin: () => onTogglePin(entry),
                    onDelete: () => onDelete(entry),
                  ),
          ),
        ),
      ],
    );
  }
}

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({
    super.key,
    required this.entry,
    required this.palette,
    required this.now,
    required this.onClose,
    required this.onCopy,
    required this.onTogglePin,
    required this.onDelete,
  });

  final ClipboardEntry entry;
  final PanelPalette palette;
  final DateTime now;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final source = entry.source;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: 'Preview',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: palette.separator)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _KindTile(entry: entry, palette: palette, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kindLabel(entry.kind),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        [
                          'Copied ${relativeTime(entry.copiedAt, now).toLowerCase()}',
                          if (source != null) 'from $source',
                        ].join(' · '),
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
                PanelIconButton(
                  icon: CupertinoIcons.xmark,
                  label: 'Close Preview',
                  palette: palette,
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.controlFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: entry.imagePath != null
                      ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image.file(
                            File(entry.imagePath!),
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            semanticLabel: 'The copied image',
                            errorBuilder: (context, error, stackTrace) =>
                                Center(
                                  child: Text(
                                    'This image is no longer available.',
                                    style: TextStyle(
                                      color: palette.secondaryLabel,
                                    ),
                                  ),
                                ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: SelectableText(
                              entry.text,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: palette.label,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                PanelButton(
                  label: 'Copy',
                  icon: CupertinoIcons.doc_on_doc,
                  palette: palette,
                  style: PanelButtonStyle.prominent,
                  onPressed: onCopy,
                ),
                const SizedBox(width: 8),
                PanelButton(
                  label: entry.pinned ? 'Unpin' : 'Pin',
                  icon: entry.pinned
                      ? CupertinoIcons.pin_slash
                      : CupertinoIcons.pin,
                  palette: palette,
                  onPressed: onTogglePin,
                ),
                const Spacer(),
                PanelButton(
                  label: 'Delete',
                  palette: palette,
                  style: PanelButtonStyle.destructive,
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Entry deleted", with a way to take it back, for a few seconds.
class _UndoToast extends StatelessWidget {
  const _UndoToast({
    required this.visible,
    required this.palette,
    required this.onUndo,
  });

  final bool visible;
  final PanelPalette palette;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Center(
      child: AnimatedSwitcher(
        duration: still ? Duration.zero : const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: !visible
            ? const SizedBox.shrink()
            : Semantics(
                liveRegion: true,
                child: Container(
                  key: const ValueKey('undo'),
                  padding: const EdgeInsets.fromLTRB(14, 5, 5, 5),
                  decoration: ShapeDecoration(
                    color: palette.sheet,
                    shape: StadiumBorder(
                      side: BorderSide(color: palette.separator),
                    ),
                    shadows: [
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: 0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Entry deleted'),
                      const SizedBox(width: 10),
                      PanelButton(
                        label: 'Undo',
                        palette: palette,
                        compact: true,
                        onPressed: onUndo,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.palette,
    required this.query,
    required this.filter,
  });

  final PanelPalette palette;
  final String query;
  final EntryFilter filter;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title, String detail) = query.isNotEmpty
        ? (
            CupertinoIcons.search,
            'No Results',
            'Nothing you copied matches “$query”.',
          )
        : filter != EntryFilter.all
        ? (
            CupertinoIcons.line_horizontal_3_decrease,
            'Nothing Here',
            'Nothing in your history fits “${filter.label}”.',
          )
        : (
            CupertinoIcons.doc_on_clipboard,
            'Nothing Copied Yet',
            'Copy some text and it shows up here.',
          );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: palette.tertiaryLabel),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the footer says about sync, in a word or two.
@immutable
class SyncSummary {
  const SyncSummary({required this.label, this.connected = false});

  /// "Sync Off", "Searching…", the other device's name, or "3 Devices".
  final String label;

  /// Whether at least one other device is connected right now.
  final bool connected;
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.palette,
    required this.count,
    required this.paused,
    required this.sync,
    required this.onOpenSync,
    required this.selectVerb,
    required this.showKeyHints,
  });

  final PanelPalette palette;
  final int count;
  final bool paused;

  /// What Enter does to the selected entry: "Copy" or "Paste".
  final String selectVerb;

  /// Whether to say which keys do what; pointless without a keyboard.
  final bool showKeyHints;
  final SyncSummary? sync;
  final VoidCallback? onOpenSync;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: palette.secondaryLabel);
    final sync = this.sync;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.separator)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 18, 9),
        child: Row(
          children: [
            if (sync != null && onOpenSync != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Tooltip(
                  message: 'Sync Settings',
                  waitDuration: const Duration(milliseconds: 600),
                  child: PanelButton(
                    label: sync.label,
                    // A filled symbol once connected: the state is not told
                    // by the label alone.
                    icon: sync.connected
                        ? CupertinoIcons.link_circle_fill
                        : CupertinoIcons.link_circle,
                    palette: palette,
                    compact: true,
                    onPressed: onOpenSync,
                  ),
                ),
              )
            else
              const SizedBox(width: 6),
            const SizedBox(width: 10),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  // Named as the keys are labelled on each platform's
                  // keyboards.
                  !showKeyHints
                      ? ''
                      : defaultTargetPlatform == TargetPlatform.macOS
                      ? 'space Preview   return $selectVerb'
                      : 'Space Preview   Enter $selectVerb',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: style,
                ),
              ),
            ),
            const SizedBox(width: 12),
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
          ],
        ),
      ),
    );
  }
}

/// The heading an entry is listed under.
String sectionOf(ClipboardEntry entry, DateTime now) {
  if (entry.pinned) return 'Pinned';
  final day = DateUtils.dateOnly(entry.copiedAt.toLocal());
  final today = DateUtils.dateOnly(now.toLocal());
  final daysAgo = today.difference(day).inDays;
  if (daysAgo <= 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo < 7) return 'This Week';
  return 'Earlier';
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

/// The name of a kind of entry, as shown above its preview.
String kindLabel(EntryKind kind) => switch (kind) {
  EntryKind.text => 'Text',
  EntryKind.link => 'Link',
  EntryKind.email => 'Email Address',
  EntryKind.color => 'Color',
  EntryKind.image => 'Image',
  EntryKind.files => 'Files',
};

/// A short note on what an entry is: where a link goes, how big an image is,
/// where a file lives, or how much text there is.
String describeEntry(ClipboardEntry entry) {
  switch (entry.kind) {
    case EntryKind.link:
      return Uri.parse(entry.text.trim()).host;
    case EntryKind.email:
      return 'Email address';
    case EntryKind.color:
      return 'Color';
    case EntryKind.image:
      final width = entry.imageWidth ?? 0;
      final height = entry.imageHeight ?? 0;
      return width > 0 && height > 0 ? '$width × $height' : 'Picture';
    case EntryKind.files:
      if (entry.files.length > 1) return '${entry.files.length} items';
      // The folder a single file is in, which tells files of one name apart.
      final folder = path.basename(path.dirname(entry.files.single));
      return folder.isEmpty ? 'File' : 'in $folder';
    case EntryKind.text:
      final lines = entry.lineCount;
      if (lines > 1) return '$lines lines';
      final characters = entry.text.trim().length;
      return characters == 1 ? '1 character' : '$characters characters';
  }
}
