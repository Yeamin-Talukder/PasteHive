import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// What a copied piece of text is, as far as can be told by looking at it.
enum EntryKind {
  /// Anything that is not one of the others.
  text,

  /// A single web address.
  link,

  /// A single email address.
  email,

  /// A colour written as a hex code, such as `#1E90FF`.
  color,
}

/// One thing that was copied.
///
/// Only plain text is recorded for now; [text] is the full copied value.
@immutable
class ClipboardEntry {
  const ClipboardEntry({
    required this.id,
    required this.text,
    required this.copiedAt,
    this.pinned = false,
    this.source,
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
    );
  }

  static final _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );
  static final _colorPattern = RegExp(
    r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
  );

  final String id;
  final String text;

  /// When this text was last copied, in UTC.
  final DateTime copiedAt;

  /// Pinned entries sort first and survive "Clear History".
  final bool pinned;

  /// The name of the device this was copied on, or null for this one.
  final String? source;

  /// Whether this arrived from another device.
  bool get isSynced => source != null;

  /// The first non-empty line, with runs of whitespace collapsed: what a list
  /// row shows.
  String get preview {
    for (final line in text.split('\n')) {
      final collapsed = line.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (collapsed.isNotEmpty) return collapsed;
    }
    return '';
  }

  EntryKind get kind {
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
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'copiedAt': copiedAt.toUtc().millisecondsSinceEpoch,
    'pinned': pinned,
    if (source != null) 'source': source,
  };

  @override
  bool operator ==(Object other) =>
      other is ClipboardEntry &&
      other.id == id &&
      other.text == text &&
      other.copiedAt == copiedAt &&
      other.pinned == pinned &&
      other.source == source;

  @override
  int get hashCode => Object.hash(id, text, copiedAt, pinned, source);

  @override
  String toString() => 'ClipboardEntry($id, pinned: $pinned, "$preview")';
}
