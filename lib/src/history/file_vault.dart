import 'dart:io';

import 'package:path/path.dart' as path;

/// Where files received from other devices are kept.
///
/// Each set of files that arrives together gets a folder of its own, named
/// after the transfer, so two files with the same name never collide and a
/// set can be removed in one go. The files keep their own names, which is
/// what the user sees when they paste them somewhere.
///
/// They are ordinary files on disk: anyone who can read this user's files
/// can open them.
class FileVault {
  FileVault(this.directory);

  final Directory directory;

  /// Starts taking in the files of one transfer, named [names].
  Future<IncomingFiles> begin(String transferId, List<String> names) async {
    final folder = Directory(path.join(directory.path, safeName(transferId)));
    if (await folder.exists()) await folder.delete(recursive: true);
    await folder.create(recursive: true);
    // Two files may not share a name inside one folder.
    final used = <String>{};
    final files = <File>[];
    for (final name in names) {
      var candidate = safeName(name);
      for (var copy = 2; !used.add(candidate.toLowerCase()); copy++) {
        final extension = path.extension(name);
        candidate = safeName(
          '${path.basenameWithoutExtension(name)} ($copy)$extension',
        );
      }
      files.add(File(path.join(folder.path, candidate)));
    }
    return IncomingFiles._(folder, files);
  }

  /// Whether [filePath] is one of the files kept here.
  bool holds(String filePath) => path.isWithin(directory.path, filePath);

  /// Deletes every received set none of whose files is in [keep]. Returns
  /// how many sets were deleted.
  ///
  /// Run at launch and at quit rather than when an entry is removed: a
  /// removed entry can still be brought back for a few seconds.
  Future<int> removeAllExcept(Iterable<String> keep) async {
    if (!await directory.exists()) return 0;
    final kept = {
      for (final file in keep)
        if (holds(file)) path.canonicalize(path.dirname(file)),
    };
    var removed = 0;
    await for (final entity in directory.list()) {
      if (entity is! Directory) continue;
      if (kept.contains(path.canonicalize(entity.path))) continue;
      try {
        await entity.delete(recursive: true);
        removed++;
      } on FileSystemException {
        // In use, or gone already; the next run gets it.
      }
    }
    return removed;
  }

  /// [name] made fit to be a file name on any of the systems the app runs
  /// on: no folders, no characters a file system refuses, never empty.
  static String safeName(String name) {
    var cleaned = name
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_')
        .trim();
    // Windows refuses names that end in a dot or a space.
    cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'file';
    return cleaned.length > 180
        ? cleaned.substring(cleaned.length - 180)
        : cleaned;
  }
}

/// The files of one transfer, while they are arriving.
class IncomingFiles {
  IncomingFiles._(this._folder, this._files)
    : _sinks = List.filled(_files.length, null);

  final Directory _folder;
  final List<File> _files;
  final List<IOSink?> _sinks;

  /// Adds [bytes] to the end of file number [index].
  void add(int index, List<int> bytes) {
    if (index < 0 || index >= _files.length) return;
    (_sinks[index] ??= _files[index].openWrite()).add(bytes);
  }

  /// Everything has arrived: closes the files and returns their paths.
  Future<List<String>> finish() async {
    for (final (index, file) in _files.indexed) {
      final sink = _sinks[index];
      if (sink == null) {
        // An empty file sends no bytes, but is a file all the same.
        await file.create();
      } else {
        await sink.close();
      }
    }
    return [for (final file in _files) file.path];
  }

  /// The transfer broke off: nothing of it is kept.
  Future<void> abandon() async {
    for (final sink in _sinks) {
      try {
        await sink?.close();
      } on FileSystemException {
        // Being thrown away regardless.
      }
    }
    try {
      if (await _folder.exists()) await _folder.delete(recursive: true);
    } on FileSystemException {
      // Left for the next clean-up.
    }
  }
}
