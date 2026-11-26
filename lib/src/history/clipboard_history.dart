import 'dart:async';

import 'package:flutter/foundation.dart';

import 'clipboard_entry.dart';
import 'history_store.dart';

/// The list of things copied, newest first, with pinned entries on top.
///
/// Copying text that is already in the list moves that entry to the top
/// instead of adding a second one. Changes are written to the [HistoryStore]
/// a moment later, so a burst of copies costs one write.
class ClipboardHistory extends ChangeNotifier {
  ClipboardHistory({
    required this._store,
    DateTime Function()? clock,
    this.maxUnpinnedEntries = 200,
    this.maxTextLength = 1000000,
    this.saveDelay = const Duration(milliseconds: 400),
  }) : _clock = clock ?? DateTime.now;

  final HistoryStore _store;
  final DateTime Function() _clock;

  /// Unpinned entries beyond this are dropped, oldest first.
  final int maxUnpinnedEntries;

  /// Copies longer than this many characters are not recorded.
  final int maxTextLength;

  final Duration saveDelay;

  List<ClipboardEntry> _entries = const [];
  bool _paused = false;
  int _idCounter = 0;
  Timer? _saveTimer;
  Future<void> _lastSave = Future.value();

  /// Pinned entries first, then the rest; each group newest first.
  List<ClipboardEntry> get entries => _entries;

  bool get isEmpty => _entries.isEmpty;

  /// While paused, [record] does nothing.
  bool get paused => _paused;

  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    notifyListeners();
  }

  Future<void> load() async {
    _entries = _sorted(await _store.load());
    notifyListeners();
  }

  /// Records [text] as just copied, on the device named [source] or, when
  /// that is null, on this one. Returns false when it was not recorded:
  /// capturing is paused, the text is blank, or it is too long.
  bool record(String text, {String? source}) {
    if (_paused) return false;
    if (text.trim().isEmpty || text.length > maxTextLength) return false;

    final now = _clock().toUtc();
    final existing = _entries.where((entry) => entry.text == text).firstOrNull;
    final next = [
      existing?.copyWith(copiedAt: now, source: () => source) ??
          ClipboardEntry(
            id: _newId(now),
            text: text,
            copiedAt: now,
            source: source,
          ),
      for (final entry in _entries)
        if (!identical(entry, existing)) entry,
    ];
    _commit(_trimmed(_sorted(next)));
    return true;
  }

  void remove(String id) {
    final next = [
      for (final entry in _entries)
        if (entry.id != id) entry,
    ];
    if (next.length != _entries.length) _commit(next);
  }

  void togglePin(String id) {
    if (!_entries.any((entry) => entry.id == id)) return;
    _commit(
      _trimmed(
        _sorted([
          for (final entry in _entries)
            entry.id == id ? entry.copyWith(pinned: !entry.pinned) : entry,
        ]),
      ),
    );
  }

  /// Puts back an entry that [remove] took out, exactly as it was. Does
  /// nothing if an entry with that id or that text is in the list again.
  void restore(ClipboardEntry entry) {
    if (_entries.any((e) => e.id == entry.id || e.text == entry.text)) return;
    _commit(_trimmed(_sorted([..._entries, entry])));
  }

  /// Removes everything that is not pinned.
  void clearUnpinned() {
    final next = [
      for (final entry in _entries)
        if (entry.pinned) entry,
    ];
    if (next.length != _entries.length) _commit(next);
  }

  /// Entries that pass [filter] and whose text contains every word of
  /// [query], ignoring case.
  List<ClipboardEntry> search(
    String query, {
    EntryFilter filter = EntryFilter.all,
  }) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty && filter == EntryFilter.all) return _entries;
    return [
      for (final entry in _entries)
        if (filter.accepts(entry) && _matches(entry.text.toLowerCase(), words))
          entry,
    ];
  }

  /// Writes any pending change now and waits for it to reach the store.
  Future<void> flush() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _save();
    }
    return _lastSave;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  static bool _matches(String haystack, List<String> words) {
    for (final word in words) {
      if (!haystack.contains(word)) return false;
    }
    return true;
  }

  void _commit(List<ClipboardEntry> next) {
    _entries = List.unmodifiable(next);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, _save);
  }

  void _save() {
    final snapshot = _entries;
    _lastSave = _lastSave.then((_) => _store.save(snapshot)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      // Losing a save must not take the app down; the next change retries.
      debugPrint('Could not save clipboard history: $error');
    });
  }

  List<ClipboardEntry> _sorted(List<ClipboardEntry> entries) {
    return List.of(entries)..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.copiedAt.compareTo(a.copiedAt);
    });
  }

  List<ClipboardEntry> _trimmed(List<ClipboardEntry> sorted) {
    var unpinned = 0;
    return [
      for (final entry in sorted)
        if (entry.pinned || ++unpinned <= maxUnpinnedEntries) entry,
    ];
  }

  String _newId(DateTime now) {
    _idCounter++;
    return '${now.microsecondsSinceEpoch.toRadixString(36)}-$_idCounter';
  }
}

/// The ways the list can be narrowed down, besides searching.
enum EntryFilter {
  all('All'),
  pinned('Pinned'),
  text('Text'),
  links('Links'),
  emails('Emails'),
  colors('Colors'),

  /// Copied on another device.
  synced('Synced');

  const EntryFilter(this.label);

  /// The name shown on the filter's chip.
  final String label;

  bool accepts(ClipboardEntry entry) => switch (this) {
    EntryFilter.all => true,
    EntryFilter.pinned => entry.pinned,
    EntryFilter.text => entry.kind == EntryKind.text,
    EntryFilter.links => entry.kind == EntryKind.link,
    EntryFilter.emails => entry.kind == EntryKind.email,
    EntryFilter.colors => entry.kind == EntryKind.color,
    EntryFilter.synced => entry.isSynced,
  };
}
