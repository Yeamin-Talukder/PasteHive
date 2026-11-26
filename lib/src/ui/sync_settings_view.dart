import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/sync_service.dart';
import 'panel_palette.dart';
import 'panel_surface.dart';

/// The panel's sync settings: switch sync on, create or enter the key, and
/// see which devices are connected.
class SyncSettingsView extends StatefulWidget {
  const SyncSettingsView({
    super.key,
    required this.sync,
    required this.hasMaterial,
    required this.onDone,
  });

  final SyncService sync;

  /// Whether the window paints a translucent material behind this widget.
  final bool hasMaterial;

  /// Goes back to the clipboard list.
  final VoidCallback onDone;

  @override
  State<SyncSettingsView> createState() => _SyncSettingsViewState();
}

class _SyncSettingsViewState extends State<SyncSettingsView> {
  static const _hiddenKey = '•••••-•••••-•••••-•••••';

  final _keyField = TextEditingController();
  bool _keyVisible = false;
  bool _confirmingRemoval = false;
  String? _joinError;

  @override
  void dispose() {
    _keyField.dispose();
    super.dispose();
  }

  Future<void> _createKey() async {
    await widget.sync.createKey();
    // A key that was just made is there to be typed on the other device.
    if (mounted) setState(() => _keyVisible = true);
  }

  Future<void> _join() async {
    final accepted = await widget.sync.useKey(_keyField.text);
    if (!mounted) return;
    setState(() {
      _joinError = accepted
          ? null
          : 'That is not a complete key. A key has 20 letters and digits.';
      if (accepted) _keyField.clear();
    });
  }

  Future<void> _removeKey() async {
    await widget.sync.removeKey();
    if (!mounted) return;
    setState(() {
      _confirmingRemoval = false;
      _keyVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDone,
      },
      child: Focus(
        autofocus: true,
        child: PanelSurface(
          hasMaterial: widget.hasMaterial,
          builder: (context, palette) => ListenableBuilder(
            listenable: widget.sync,
            builder: (context, _) => Column(
              children: [
                _Header(palette: palette, onDone: widget.onDone),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSwitch(palette),
                        const SizedBox(height: 22),
                        _SectionLabel('Sync Key', palette: palette),
                        if (widget.sync.hasKey)
                          ..._buildKey(palette)
                        else
                          ..._buildNoKey(palette),
                        const SizedBox(height: 22),
                        _SectionLabel('Devices', palette: palette),
                        ..._buildDevices(palette),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitch(PanelPalette palette) {
    final sync = widget.sync;
    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Sync over Local Network',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Semantics(
                label: 'Sync over Local Network',
                child: CupertinoSwitch(
                  value: sync.enabled && sync.hasKey,
                  activeTrackColor: palette.accent,
                  // There is nothing to switch on until a key exists.
                  onChanged: sync.hasKey ? sync.setEnabled : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            sync.hasKey
                ? 'Text you copy goes to your other devices on this network, '
                      'encrypted. This one appears as “${sync.deviceName}”.'
                : 'Add a sync key below to switch this on.',
            style: TextStyle(fontSize: 11, color: palette.secondaryLabel),
          ),
          if (sync.error != null) ...[
            const SizedBox(height: 8),
            _Notice(
              sync.error!,
              palette: palette,
              color: palette.danger,
              icon: CupertinoIcons.exclamationmark_triangle_fill,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildNoKey(PanelPalette palette) {
    return [
      Text(
        'Devices that share a key sync with each other. Create one here, or '
        'enter the key shown on your other device.',
        style: TextStyle(color: palette.secondaryLabel),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: PanelButton(
          label: 'Create a Key',
          palette: palette,
          style: PanelButtonStyle.prominent,
          onPressed: _createKey,
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: palette.controlFill,
                shape: const StadiumBorder(),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _keyField,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  style: _keyStyle(palette, size: 13),
                  cursorColor: palette.accent,
                  cursorWidth: 1.5,
                  onSubmitted: (_) => _join(),
                  decoration: InputDecoration.collapsed(
                    hintText: 'Key from your other device',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: palette.secondaryLabel,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PanelButton(label: 'Join', palette: palette, onPressed: _join),
        ],
      ),
      if (_joinError != null) ...[
        const SizedBox(height: 8),
        _Notice(
          _joinError!,
          palette: palette,
          color: palette.danger,
          icon: CupertinoIcons.exclamationmark_circle_fill,
        ),
      ],
    ];
  }

  List<Widget> _buildKey(PanelPalette palette) {
    final key = widget.sync.formattedKey!;
    return [
      _Card(
        palette: palette,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: _keyVisible ? 'Sync key $key' : 'Sync key, hidden',
                excludeSemantics: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    _keyVisible ? key : _hiddenKey,
                    maxLines: 1,
                    style: _keyStyle(palette, size: 15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PanelButton(
              label: _keyVisible ? 'Hide' : 'Show',
              palette: palette,
              onPressed: () => setState(() => _keyVisible = !_keyVisible),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Enter this key on your other device. Anyone on your network who '
        'has it can read what you copy, so keep it to yourself.',
        style: TextStyle(fontSize: 11, color: palette.secondaryLabel),
      ),
      const SizedBox(height: 12),
      if (_confirmingRemoval)
        Row(
          children: [
            Expanded(
              child: Text(
                'Sync stops on this device.',
                style: TextStyle(color: palette.secondaryLabel),
              ),
            ),
            PanelButton(
              label: 'Cancel',
              palette: palette,
              onPressed: () => setState(() => _confirmingRemoval = false),
            ),
            const SizedBox(width: 8),
            PanelButton(
              label: 'Remove',
              palette: palette,
              style: PanelButtonStyle.destructive,
              onPressed: _removeKey,
            ),
          ],
        )
      else
        Align(
          alignment: Alignment.centerLeft,
          child: PanelButton(
            label: 'Remove Key…',
            palette: palette,
            style: PanelButtonStyle.destructive,
            onPressed: () => setState(() => _confirmingRemoval = true),
          ),
        ),
    ];
  }

  List<Widget> _buildDevices(PanelPalette palette) {
    final sync = widget.sync;
    final peers = sync.peers;
    final String? status = !sync.hasKey
        ? 'Add a sync key to connect your devices.'
        : !sync.enabled
        ? 'Sync is off.'
        : peers.isEmpty
        ? 'Looking for your other devices on this network…'
        : null;
    return [
      if (status != null)
        Text(status, style: TextStyle(color: palette.secondaryLabel)),
      if (peers.isNotEmpty)
        _Card(
          palette: palette,
          child: Column(
            children: [
              for (final (index, peer) in peers.indexed) ...[
                if (index > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      height: 1,
                      child: ColoredBox(color: palette.separator),
                    ),
                  ),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      size: 14,
                      color: palette.positive,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        peer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      'Connected',
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      if (sync.differentKeyNearby) ...[
        const SizedBox(height: 10),
        _Notice(
          'A device nearby is using a different key. Check that the key is '
          'the same on both.',
          palette: palette,
          color: palette.secondaryLabel,
          icon: CupertinoIcons.info_circle_fill,
        ),
      ],
    ];
  }

  static TextStyle _keyStyle(PanelPalette palette, {required double size}) {
    return TextStyle(
      fontSize: size,
      height: 1.25,
      letterSpacing: 0.5,
      color: palette.label,
      // Every character the same width, so the groups line up and 0 and 8
      // are easy to tell apart.
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['SF Mono', 'Consolas', 'Courier New'],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.palette, required this.onDone});

  final PanelPalette palette;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PanelButton(
              label: 'Clipboard',
              icon: CupertinoIcons.chevron_left,
              palette: palette,
              onPressed: onDone,
            ),
          ),
          const Text(
            'Sync',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.palette});

  final String text;
  final PanelPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: palette.secondaryLabel,
          ),
        ),
      ),
    );
  }
}

/// A rounded group of related controls.
class _Card extends StatelessWidget {
  const _Card({required this.palette, required this.child});

  final PanelPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.rowHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    );
  }
}

/// A line of explanation with a symbol in front, so its meaning does not
/// rest on its colour.
class _Notice extends StatelessWidget {
  const _Notice(
    this.text, {
    required this.palette,
    required this.color,
    required this.icon,
  });

  final String text;
  final PanelPalette palette;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    );
  }
}
