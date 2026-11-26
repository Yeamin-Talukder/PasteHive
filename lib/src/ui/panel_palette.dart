import 'package:flutter/widgets.dart';

/// The colours of the clipboard panel.
///
/// The panel sits on a system material (vibrancy on macOS, acrylic on
/// Windows), so text and symbols are monochrome and colour is kept for the
/// keyboard focus ring and the pinned mark. Without a material, or when the
/// user asks for more contrast, the surface is opaque.
@immutable
class PanelPalette {
  const PanelPalette._({
    required this.surface,
    required this.sheen,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.controlFill,
    required this.rowHover,
    required this.rowSelected,
    required this.separator,
    required this.accent,
  });

  factory PanelPalette.of({
    required Brightness brightness,
    required bool hasMaterial,
    required bool highContrast,
  }) {
    final translucent = hasMaterial && !highContrast;
    if (brightness == Brightness.dark) {
      return PanelPalette._(
        surface: translucent
            ? const Color(0x52000000)
            : const Color(0xFF1E1E21),
        sheen: const Color(0x14FFFFFF),
        label: const Color(0xF0FFFFFF),
        secondaryLabel: highContrast
            ? const Color(0xD9FFFFFF)
            : const Color(0xA6FFFFFF),
        tertiaryLabel: highContrast
            ? const Color(0xBFFFFFFF)
            : const Color(0x8CFFFFFF),
        controlFill: const Color(0x1FFFFFFF),
        rowHover: const Color(0x14FFFFFF),
        rowSelected: const Color(0x29FFFFFF),
        separator: highContrast
            ? const Color(0x66FFFFFF)
            : const Color(0x1FFFFFFF),
        accent: const Color(0xFF0A84FF),
      );
    }
    return PanelPalette._(
      surface: translucent ? const Color(0x85FFFFFF) : const Color(0xFFF5F5F7),
      sheen: const Color(0x66FFFFFF),
      label: const Color(0xE6000000),
      secondaryLabel: highContrast
          ? const Color(0xCC000000)
          : const Color(0x99000000),
      tertiaryLabel: highContrast
          ? const Color(0xB3000000)
          : const Color(0x80000000),
      controlFill: const Color(0x12000000),
      rowHover: const Color(0x0F000000),
      rowSelected: const Color(0x1F000000),
      separator: highContrast
          ? const Color(0x66000000)
          : const Color(0x1A000000),
      accent: const Color(0xFF007AFF),
    );
  }

  /// Painted over the system material, or instead of it when there is none.
  final Color surface;

  /// A soft highlight along the top edge, where glass catches the light.
  final Color sheen;

  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;

  /// The search field and the icon tiles.
  final Color controlFill;

  final Color rowHover;
  final Color rowSelected;
  final Color separator;
  final Color accent;
}
