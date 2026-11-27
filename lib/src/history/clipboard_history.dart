import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

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
    this.maxUnpinnedImages = 40,
    this.maxTextLength = 1000000,
    this.saveDelay = const Duration(milliseconds: 400),
  }) : _clock = clock ?? DateTime.now;

  final HistoryStore _store;
  final DateTime Function() _clock;

  /// Unpinned entries beyond this are dropped, oldest first.
  final int maxUnpinnedEntries;

  /// Unpinned images beyond this are dropped, oldest first.
  final int maxUnpinnedImages;

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

  /// Points every picture entry at the file of the same name in [folder].
  /// For when the folder the pictures are kept in has moved.
  void relocateImages(String folder) {
    var changed = false;
    final next = [
      for (final entry in _entries)
        if (entry.imagePath == null ||
            path.equals(path.dirname(entry.imagePath!), folder))
          entry
        else
          () {
            changed = true;
            return ClipboardEntry(
              id: entry.id,
              text: entry.text,
              copiedAt: entry.copiedAt,
              pinned: entry.pinned,
              source: entry.source,
              imagePath: path.join(folder, path.basename(entry.imagePath!)),
              imageWidth: entry.imageWidth,
              imageHeight: entry.imageHeight,
            );
          }(),
    ];
    if (changed) _commit(next);
  }

  /// Records [text] as just copied, on the device named [source] or, when
  /// that is null, on this one. Returns false when it was not recorded:
  /// capturing is paused, the text is blank, or it is too long.
  bool record(String text, {String? source}) {
    if (text.trim().isEmpty || text.length > maxTextLength) return false;
    return _record(
      (id, now) =>
          ClipboardEntry(id: id, text: text, copiedAt: now, source: source),
      source: source,
    );
  }

  /// Records a copied image that has been saved as a PNG at [path].
  bool recordImage({
    required String path,
    required int width,
    required int height,
    String? source,
  }) {
    return _record(
      (id, now) => ClipboardEntry(
        id: id,
        text: '',
        copiedAt: now,
        source: source,
        imagePath: path,
        imageWidth: width,
        imageHeight: height,
      ),
      source: source,
    );
  }

  /// Records copied files and folders, by their full paths. [source] names
  /// the device they were copied on when it was not this one.
  bool recordFiles(List<String> paths, {String? source}) {
    if (paths.isEmpty) return false;
    return _record(
      (id, now) => ClipboardEntry(
        id: id,
        text: paths.join('\n'),
        copiedAt: now,
        files: List.unmodifiable(paths),
        source: source,
      ),
      source: source,
    );
  }

  // Something copied again moves to the top instead of appearing twice.
  bool _record(
    ClipboardEntry Function(String id, DateTime now) build, {
    String? source,
  }) {
    if (_paused) return false;
    final now = _clock().toUtc();
    final candidate = build(_newId(now), now);
    final existing = _entries
        .where((entry) => entry.signature == candidate.signature)
        .firstOrNull;
    final next = [
      existing?.copyWith(copiedAt: now, source: () => source) ?? candidate,
      for (final entry in _entries)
        if (!identical(entry, existing)) entry,
    ];
    _commit(_trimmed(_sorted(next)));
    return true;
  }

  /// Called with each entry the user removes here (by [remove] or
  /// [clearUnpinned]) and each one they bring back (by [restore]), so the
  /// change can be passed on to other devices. Not called for changes that
  /// came from another device.
  void Function(ClipboardEntry entry)? onRemoved;
  void Function(ClipboardEntry entry)? onRestored;

  /// Called when the user clears the history here.
  void Function()? onCleared;

  void remove(String id) {
    final removed = _entries.where((entry) => entry.id == id).firstOrNull;
    if (removed == null) return;
    _commit([
      for (final entry in _entries)
        if (entry.id != id) entry,
    ]);
    onRemoved?.call(removed);
  }

  /// Removes the text entry [text] because another device deleted it.
  /// Returns whether there was one.
  bool removeRemote(String text) {
    final next = [
      for (final entry in _entries)
        if (entry.signature != 'text:$text') entry,
    ];
    if (next.length == _entries.length) return false;
    _commit(next);
    return true;
  }

  /// Removes the picture stored under the file name [name] because another
  /// device deleted it. Returns whether there was one.
  bool removeRemoteImage(String name) {
    final next = [
      for (final entry in _entries)
        if (entry.signature != 'image:$name') entry,
    ];
    if (next.length == _entries.length) return false;
    _commit(next);
    return true;
  }

  /// Removes everything unpinned because another device cleared its
  /// history.
  void clearRemote() => _clearUnpinned();

  /// Adds [text] as copied at [copiedAt] on the device [source], because
  /// that device is sharing its history. Unlike [record] it keeps the old
  /// time, so the entry lands where it belongs in the list. Returns false
  /// when the text is already here.
  bool mergeRemote(String text, DateTime copiedAt, {required String source}) {
    if (text.trim().isEmpty || text.length > maxTextLength) return false;
    if (_entries.any((entry) => entry.signature == 'text:$text')) return false;
    final at = copiedAt.toUtc();
    _commit(
      _trimmed(
        _sorted([
          ..._entries,
          ClipboardEntry(
            id: _newId(at),
            text: text,
            copiedAt: at,
            source: source,
          ),
        ]),
      ),
    );
    return true;
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
  /// nothing if that entry, or the same thing copied again, is in the list.
  void restore(ClipboardEntry entry) {
    if (_entries.any(
      (e) => e.id == entry.id || e.signature == entry.signature,
    )) {
      return;
    }
    _commit(_trimmed(_sorted([..._entries, entry])));
    onRestored?.call(entry);
  }

  /// Removes everything that is not pinned.
  void clearUnpinned() {
    if (_clearUnpinned()) onCleared?.call();
  }

  bool _clearUnpinned() {
    final next = [
      for (final entry in _entries)
        if (entry.pinned) entry,
    ];
    if (next.length == _entries.length) return false;
    _commit(next);
    return true;
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
        if (filter.accepts(entry) && _matches(_searchable(entry), words)) entry,
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

  // A picture has no text of its own; let the words people would type for
  // one find it.
  static String _searchable(ClipboardEntry entry) =>
      entry.kind == EntryKind.image
      ? 'image picture photo screenshot'
      : entry.text.toLowerCase();

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
    var unpinnedImages = 0;
    return [
      for (final entry in sorted)
        if (entry.pinned ||
            (++unpinned <= maxUnpinnedEntries &&
                // Images take far more room on disk than text does.
                (entry.kind != EntryKind.image ||
                    ++unpinnedImages <= maxUnpinnedImages)))
          entry,
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
  images('Images'),
  files('Files'),
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
    EntryFilter.images => entry.kind == EntryKind.image,
    EntryFilter.files => entry.kind == EntryKind.files,
    EntryFilter.emails => entry.kind == EntryKind.email,
    EntryFilter.colors => entry.kind == EntryKind.color,
    EntryFilter.synced => entry.isSynced,
  };
}
