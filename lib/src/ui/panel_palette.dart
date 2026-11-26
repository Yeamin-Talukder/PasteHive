import 'package:flutter/widgets.dart';

/// The colours of the clipboard panel.
///
/// The panel is glass: it sits on a blurred picture of whatever is behind
/// it, tinted just enough to keep text readable. Text and symbols are
/// monochrome; colour is kept for the one prominent button, the kind of an
/// entry, and status. Without anything to blur, or when the user asks for
/// more contrast, the surface is opaque.
@immutable
class PanelPalette {
  const PanelPalette._({
    required this.brightness,
    required this.surface,
    required this.sheen,
    required this.sheet,
    required this.scrim,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.controlFill,
    required this.chipSelected,
    required this.rowHover,
    required this.rowSelected,
    required this.separator,
    required this.rimHighlight,
    required this.rimShade,
    required this.outline,
    required this.shadow,
    required this.accent,
    required this.linkTint,
    required this.emailTint,
    required this.danger,
    required this.positive,
  });

  factory PanelPalette.of({
    required Brightness brightness,
    required bool hasMaterial,
    required bool highContrast,
  }) {
    final translucent = hasMaterial && !highContrast;
    if (brightness == Brightness.dark) {
      return PanelPalette._(
        brightness: brightness,
        surface: translucent
            ? const Color(0x8C14141A)
            : const Color(0xFF1E1E22),
        sheen: const Color(0x1AFFFFFF),
        sheet: const Color(0xFF2A2A31),
        scrim: const Color(0x66000000),
        label: const Color(0xF2FFFFFF),
        secondaryLabel: highContrast
            ? const Color(0xD9FFFFFF)
            : const Color(0xA8FFFFFF),
        tertiaryLabel: highContrast
            ? const Color(0xBFFFFFFF)
            : const Color(0x8CFFFFFF),
        controlFill: const Color(0x1CFFFFFF),
        chipSelected: const Color(0x38FFFFFF),
        rowHover: const Color(0x12FFFFFF),
        rowSelected: const Color(0x24FFFFFF),
        separator: highContrast
            ? const Color(0x66FFFFFF)
            : const Color(0x1AFFFFFF),
        rimHighlight: const Color(0x80FFFFFF),
        rimShade: const Color(0x14FFFFFF),
        outline: const Color(0x66000000),
        shadow: const Color(0xFF000000),
        accent: const Color(0xFF0A84FF),
        linkTint: const Color(0xFF64B5FF),
        emailTint: const Color(0xFF63E6BE),
        danger: const Color(0xFFFF6961),
        positive: const Color(0xFF30D158),
      );
    }
    return PanelPalette._(
      brightness: brightness,
      surface: translucent ? const Color(0x99FFFFFF) : const Color(0xFFF5F5F7),
      sheen: const Color(0x73FFFFFF),
      sheet: const Color(0xFFFBFBFD),
      scrim: const Color(0x29000000),
      label: const Color(0xE6000000),
      secondaryLabel: highContrast
          ? const Color(0xCC000000)
          : const Color(0x99000000),
      tertiaryLabel: highContrast
          ? const Color(0xB3000000)
          : const Color(0x80000000),
      controlFill: const Color(0x12000000),
      chipSelected: const Color(0xD9FFFFFF),
      rowHover: const Color(0x0D000000),
      rowSelected: const Color(0x1C000000),
      separator: highContrast
          ? const Color(0x66000000)
          : const Color(0x17000000),
      rimHighlight: const Color(0xE6FFFFFF),
      rimShade: const Color(0x59FFFFFF),
      outline: const Color(0x1F000000),
      shadow: const Color(0xFF1A2433),
      accent: const Color(0xFF007AFF),
      linkTint: const Color(0xFF0A6CDB),
      emailTint: const Color(0xFF0B8A6A),
      danger: const Color(0xFFC4281C),
      positive: const Color(0xFF1E8E3E),
    );
  }

  final Brightness brightness;

  /// The tint over the blurred backdrop, or the whole surface without one.
  final Color surface;

  /// A soft highlight along the top edge, where glass catches the light.
  final Color sheen;

  /// A layer that slides over the list, such as the preview. Opaque: glass
  /// on glass would blur the two together.
  final Color sheet;

  /// Dims the list behind a [sheet].
  final Color scrim;

  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;

  /// The search field, the icon tiles and quiet buttons.
  final Color controlFill;

  /// The filter that is switched on.
  final Color chipSelected;

  final Color rowHover;
  final Color rowSelected;
  final Color separator;

  /// The bright line along the panel's top edge, fading to [rimShade] at the
  /// bottom: light catching the edge of the glass.
  final Color rimHighlight;
  final Color rimShade;

  /// A hairline just outside the glass that keeps its edge crisp against a
  /// background of the same brightness.
  final Color outline;

  /// The colour of the panel's drop shadow, before its opacity is applied.
  final Color shadow;

  final Color accent;

  /// The symbol of an entry that is a web address.
  final Color linkTint;

  /// The symbol of an entry that is an email address.
  final Color emailTint;

  /// Text of an action that takes something away.
  final Color danger;

  /// A check mark: connected, or copied.
  final Color positive;
}
