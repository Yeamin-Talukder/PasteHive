import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// What a copied thing is.
enum EntryKind {
  /// Text that is not one of the more specific kinds below.
  text,

  /// A single web address.
  link,

  /// A single email address.
  email,

  /// A colour written as a hex code, such as `#1E90FF`.
  color,

  /// A picture: a screenshot, or an image copied from a page or an editor.
  image,

  /// One or more files or folders, as copied in a file manager.
  files,
}

/// One thing that was copied: some text, an image, or a set of files.
@immutable
class ClipboardEntry {
  const ClipboardEntry({
    required this.id,
    required this.text,
    required this.copiedAt,
    this.pinned = false,
    this.source,
    this.imagePath,
    this.imageWidth,
    this.imageHeight,
    this.files = const [],
  });

  factory ClipboardEntry.fromJson(Map<String, Object?> json) {
    return ClipboardEntry(
      id: json['id']! as String,
      text: json['text']! as String,
      copiedAt: DateTime.fromMillisecondsSinceEpoch(
        json['copiedAt']! as int,
        isUtc: true,
      ),
      pinned: json['pinned'] as bool? ?? false,
      source: json['source'] as String?,
      imagePath: json['imagePath'] as String?,
      imageWidth: json['imageWidth'] as int?,
      imageHeight: json['imageHeight'] as int?,
      files: [
        for (final file in json['files'] as List? ?? const []) file as String,
      ],
    );
  }

  static final _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );
  static final _colorPattern = RegExp(
    r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
  );

  final String id;

  /// The copied text. For files it is their paths, one per line, so a search
  /// finds them by name; for an image it is empty.
  final String text;

  /// When this was last copied, in UTC.
  final DateTime copiedAt;

  /// Pinned entries sort first and survive "Clear History".
  final bool pinned;

  /// The name of the device this was copied on, or null for this one.
  final String? source;

  /// Where the copied image is kept, as a PNG file; null unless this is an
  /// image.
  final String? imagePath;

  /// The image's size in pixels.
  final int? imageWidth;
  final int? imageHeight;

  /// The full paths of the copied files and folders; empty unless this is a
  /// set of files.
  final List<String> files;

  /// Whether this arrived from another device.
  bool get isSynced => source != null;

  /// What makes two copies "the same thing", so that copying it again moves
  /// the entry up instead of adding a second one.
  String get signature {
    if (imagePath != null) return 'image:${path.basename(imagePath!)}';
    if (files.isNotEmpty) return 'files:${files.join('\n')}';
    return 'text:$text';
  }

  /// One line that stands for the entry in a list row.
  String get preview {
    switch (kind) {
      case EntryKind.image:
        return 'Image';
      case EntryKind.files:
        final first = path.basename(files.first);
        return switch (files.length) {
          1 => first,
          2 => '$first and 1 more',
          final count => '$first and ${count - 1} more',
        };
      case EntryKind.text ||
          EntryKind.link ||
          EntryKind.email ||
          EntryKind.color:
        // The first non-empty line, with runs of whitespace collapsed.
        for (final line in text.split('\n')) {
          final collapsed = line.trim().replaceAll(RegExp(r'\s+'), ' ');
          if (collapsed.isNotEmpty) return collapsed;
        }
        return '';
    }
  }

  EntryKind get kind {
    if (imagePath != null) return EntryKind.image;
    if (files.isNotEmpty) return EntryKind.files;
    final trimmed = text.trim();
    if (trimmed.contains(RegExp(r'\s'))) return EntryKind.text;
    if (_colorPattern.hasMatch(trimmed)) return EntryKind.color;
    if (_emailPattern.hasMatch(trimmed)) return EntryKind.email;
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      return EntryKind.link;
    }
    return EntryKind.text;
  }

  /// Whether the whole entry is a single web address.
  bool get isLink => kind == EntryKind.link;

  /// The colour this entry spells out, or null when it is not a colour.
  Color? get color {
    if (kind != EntryKind.color) return null;
    var hex = text.trim().substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((digit) => '$digit$digit').join();
    }
    // Written as RRGGBB or RRGGBBAA; Color wants the alpha first.
    final value = int.parse(hex, radix: 16);
    return hex.length == 8
        ? Color(((value & 0xFF) << 24) | (value >> 8))
        : Color(0xFF000000 | value);
  }

  int get lineCount => '\n'.allMatches(text.trimRight()).length + 1;

  ClipboardEntry copyWith({
    DateTime? copiedAt,
    bool? pinned,
    String? Function()? source,
  }) {
    return ClipboardEntry(
      id: id,
      text: text,
      copiedAt: copiedAt ?? this.copiedAt,
      pinned: pinned ?? this.pinned,
      source: source == null ? this.source : source(),
      imagePath: imagePath,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      files: files,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'copiedAt': copiedAt.toUtc().millisecondsSinceEpoch,
    'pinned': pinned,
    if (source != null) 'source': source,
    if (imagePath != null) 'imagePath': imagePath,
    if (imageWidth != null) 'imageWidth': imageWidth,
    if (imageHeight != null) 'imageHeight': imageHeight,
    if (files.isNotEmpty) 'files': files,
  };

  @override
  bool operator ==(Object other) =>
      other is ClipboardEntry &&
      other.id == id &&
      other.text == text &&
      other.copiedAt == copiedAt &&
      other.pinned == pinned &&
      other.source == source &&
      other.imagePath == imagePath &&
      other.imageWidth == imageWidth &&
      other.imageHeight == imageHeight &&
      listEquals(other.files, files);

  @override
  int get hashCode => Object.hash(
    id,
    text,
    copiedAt,
    pinned,
    source,
    imagePath,
    Object.hashAll(files),
  );

  @override
  String toString() => 'ClipboardEntry($id, pinned: $pinned, "$preview")';
}
