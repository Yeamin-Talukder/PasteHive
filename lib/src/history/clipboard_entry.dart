import 'package:flutter/foundation.dart';

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
    );
  }

  final String id;
  final String text;

  /// When this text was last copied, in UTC.
  final DateTime copiedAt;

  /// Pinned entries sort first and survive "Clear History".
  final bool pinned;

  /// The first non-empty line, with runs of whitespace collapsed: what a list
  /// row shows.
  String get preview {
    for (final line in text.split('\n')) {
      final collapsed = line.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (collapsed.isNotEmpty) return collapsed;
    }
    return '';
  }

  /// Whether the whole entry is a single web address.
  bool get isLink {
    final trimmed = text.trim();
    if (trimmed.contains(RegExp(r'\s'))) return false;
    final uri = Uri.tryParse(trimmed);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  int get lineCount => '\n'.allMatches(text.trimRight()).length + 1;

  ClipboardEntry copyWith({DateTime? copiedAt, bool? pinned}) {
    return ClipboardEntry(
      id: id,
      text: text,
      copiedAt: copiedAt ?? this.copiedAt,
      pinned: pinned ?? this.pinned,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'copiedAt': copiedAt.toUtc().millisecondsSinceEpoch,
    'pinned': pinned,
  };

  @override
  bool operator ==(Object other) =>
      other is ClipboardEntry &&
      other.id == id &&
      other.text == text &&
      other.copiedAt == copiedAt &&
      other.pinned == pinned;

  @override
  int get hashCode => Object.hash(id, text, copiedAt, pinned);

  @override
  String toString() => 'ClipboardEntry($id, pinned: $pinned, "$preview")';
}
