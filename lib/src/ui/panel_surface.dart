import 'package:flutter/material.dart';

import 'panel_palette.dart';

/// What every view in the panel stands on: the tint over the window's
/// material, the highlight along the top edge, and the panel's text style.
class PanelSurface extends StatelessWidget {
  const PanelSurface({
    super.key,
    required this.hasMaterial,
    required this.builder,
  });

  /// Whether the window paints a translucent material behind this widget.
  final bool hasMaterial;

  final Widget Function(BuildContext context, PanelPalette palette) builder;

  @override
  Widget build(BuildContext context) {
    final palette = PanelPalette.of(
      brightness: Theme.of(context).brightness,
      hasMaterial: hasMaterial,
      highContrast: MediaQuery.highContrastOf(context),
    );
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
              Positioned.fill(child: builder(context, palette)),
            ],
          ),
        ),
      ),
    );
  }
}

/// An icon-only button with a tooltip and a screen-reader label.
class PanelIconButton extends StatefulWidget {
  const PanelIconButton({
    super.key,
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
  State<PanelIconButton> createState() => _PanelIconButtonState();
}

class _PanelIconButtonState extends State<PanelIconButton> {
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

/// How much a [PanelButton] stands out.
enum PanelButtonStyle {
  /// A quiet capsule; most buttons.
  plain,

  /// Filled with the accent colour; at most one per view.
  prominent,

  /// For actions that take something away.
  destructive,
}

/// A capsule button with a text label, and optionally an icon before it.
class PanelButton extends StatefulWidget {
  const PanelButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onPressed,
    this.icon,
    this.style = PanelButtonStyle.plain,
    this.compact = false,
  });

  final String label;
  final PanelPalette palette;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final IconData? icon;
  final PanelButtonStyle style;

  /// A smaller capsule, for the footer.
  final bool compact;

  @override
  State<PanelButton> createState() => _PanelButtonState();
}

class _PanelButtonState extends State<PanelButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.onPressed != null;
    final (Color fill, Color text) = switch (widget.style) {
      PanelButtonStyle.prominent => (palette.accent, const Color(0xFFFFFFFF)),
      PanelButtonStyle.destructive => (palette.controlFill, palette.danger),
      PanelButtonStyle.plain => (palette.controlFill, palette.label),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Container(
              constraints: BoxConstraints(minHeight: widget.compact ? 22 : 30),
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 9 : 14,
                vertical: widget.compact ? 3 : 6,
              ),
              decoration: ShapeDecoration(
                color: fill,
                shape: const StadiumBorder(),
              ),
              foregroundDecoration: ShapeDecoration(
                // A light wash on hover, over whatever the fill is.
                color: _hovered && enabled
                    ? palette.rowHover
                    : const Color(0x00000000),
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: widget.compact ? 12 : 14,
                      color: text,
                    ),
                    SizedBox(width: widget.compact ? 5 : 6),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: widget.compact ? 11 : 13,
                        fontWeight: widget.compact
                            ? FontWeight.w400
                            : FontWeight.w500,
                        color: text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
