import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/sync_service.dart';
import 'panel_palette.dart';
import 'panel_surface.dart';

/// The panel's sync view: switch sync on, see the devices nearby, ask one to
/// sync, and answer the ones that ask.
class SyncSettingsView extends StatefulWidget {
  const SyncSettingsView({
    super.key,
    required this.sync,
    required this.hasMaterial,
    required this.onDone,
    this.onSendHistory,
    this.autoCopyOn,
    this.onOpenAutoCopy,
  });

  final SyncService sync;

  /// Sends this device's history to the connected devices now.
  final VoidCallback? onSendHistory;

  /// On a phone: whether copies are picked up without the app being opened.
  /// Null where that question does not arise (a computer sees every copy).
  final bool? autoCopyOn;

  /// Opens the system setting that switches [autoCopyOn].
  final VoidCallback? onOpenAutoCopy;

  /// Whether something translucent is behind this widget.
  final bool hasMaterial;

  /// Goes back to the clipboard list.
  final VoidCallback onDone;

  @override
  State<SyncSettingsView> createState() => _SyncSettingsViewState();
}

class _SyncSettingsViewState extends State<SyncSettingsView> {
  bool _confirmingLeave = false;
  bool _historySent = false;

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
            builder: (context, _) {
              final sync = widget.sync;
              return Column(
                children: [
                  _Header(palette: palette, onDone: widget.onDone),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSwitch(palette),
                          for (final request in sync.requests) ...[
                            const SizedBox(height: 14),
                            _buildRequest(palette, request),
                          ],
                          if (sync.enabled) ...[
                            const SizedBox(height: 22),
                            _SectionLabel('Syncing With', palette: palette),
                            ..._buildPeers(palette),
                            const SizedBox(height: 22),
                            _SectionLabel('Nearby Devices', palette: palette),
                            ..._buildNearby(palette),
                          ],
                          if (sync.enabled) ...[
                            const SizedBox(height: 22),
                            _SectionLabel('History', palette: palette),
                            _buildHistory(palette),
                          ],
                          if (widget.autoCopyOn != null) ...[
                            const SizedBox(height: 22),
                            _SectionLabel('This Phone', palette: palette),
                            _buildAutoCopy(palette),
                          ],
                          if (sync.hasKey) ...[
                            const SizedBox(height: 22),
                            _buildLeave(palette),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
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
                  value: sync.enabled,
                  activeTrackColor: palette.accent,
                  onChanged: sync.setEnabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            sync.enabled
                ? 'Other devices on this network see this one as '
                      '“${sync.deviceName}”. What you copy is sent only to '
                      'devices you have connected, encrypted.'
                : 'Switch on to find your other devices on this network.',
            style: TextStyle(fontSize: 11, color: palette.secondaryLabel),
          ),
          if (sync.error != null) ...[
            const SizedBox(height: 8),
            _Notice(
              sync.error!,
              color: palette.danger,
              icon: CupertinoIcons.exclamationmark_triangle_fill,
            ),
          ],
        ],
      ),
    );
  }

  // Another device is asking to sync: the one thing here that needs an
  // answer, so it gets the one prominent button.
  Widget _buildRequest(PanelPalette palette, PairRequest request) {
    return Semantics(
      liveRegion: true,
      child: _Card(
        palette: palette,
        emphasized: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '“${request.name}” wants to sync',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Accept only if this code is also showing on that device:',
              style: TextStyle(fontSize: 11, color: palette.secondaryLabel),
            ),
            const SizedBox(height: 6),
            _Code(request.code, palette: palette),
            const SizedBox(height: 10),
            Row(
              children: [
                PanelButton(
                  label: 'Accept',
                  palette: palette,
                  style: PanelButtonStyle.prominent,
                  onPressed: () => widget.sync.accept(request),
                ),
                const SizedBox(width: 8),
                PanelButton(
                  label: 'Decline',
                  palette: palette,
                  onPressed: () => widget.sync.decline(request),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPeers(PanelPalette palette) {
    final peers = widget.sync.peers;
    if (peers.isEmpty) {
      return [
        Text(
          widget.sync.hasKey
              ? 'None of your connected devices is on this network right now.'
              : 'No devices yet. Connect to one below.',
          style: TextStyle(color: palette.secondaryLabel),
        ),
      ];
    }
    return [
      _Card(
        palette: palette,
        child: Column(
          children: [
            for (final (index, peer) in peers.indexed) ...[
              if (index > 0) _Divider(palette: palette),
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
    ];
  }

  List<Widget> _buildNearby(PanelPalette palette) {
    final sync = widget.sync;
    final outgoing = sync.outgoing;
    // Devices of this group that are merely still connecting are not
    // something to ask again.
    final devices = [
      for (final device in sync.nearby)
        if (!device.inMyGroup) device,
    ];
    return [
      if (outgoing != null) ...[
        _buildOutgoing(palette, outgoing),
        const SizedBox(height: 10),
      ],
      if (devices.isEmpty)
        Text(
          'Looking for devices… Open this app on your other device, on the '
          'same network, and switch sync on there too.',
          style: TextStyle(color: palette.secondaryLabel),
        )
      else
        _Card(
          palette: palette,
          child: Column(
            children: [
              for (final (index, device) in devices.indexed) ...[
                if (index > 0) _Divider(palette: palette),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.desktopcomputer,
                      size: 15,
                      color: palette.secondaryLabel,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PanelButton(
                      label: 'Connect',
                      palette: palette,
                      // One request at a time.
                      onPressed: outgoing?.state == OutgoingState.waiting
                          ? null
                          : () => sync.requestPairing(device.id),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _buildOutgoing(PanelPalette palette, OutgoingRequest outgoing) {
    final (String title, String? detail) = switch (outgoing.state) {
      OutgoingState.waiting => (
        'Waiting for “${outgoing.name}” to accept…',
        outgoing.code == null
            ? null
            : 'Accept on that device if it shows this code:',
      ),
      OutgoingState.accepted => ('“${outgoing.name}” accepted', null),
      OutgoingState.declined => ('“${outgoing.name}” declined', null),
      OutgoingState.failed => (
        'Could not reach “${outgoing.name}”',
        'Check that it is on, on this network, and has sync switched on.',
      ),
    };
    final waiting = outgoing.state == OutgoingState.waiting;
    return Semantics(
      liveRegion: true,
      child: _Card(
        palette: palette,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                PanelButton(
                  label: waiting ? 'Cancel' : 'OK',
                  palette: palette,
                  onPressed: widget.sync.cancelOutgoing,
                ),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(fontSize: 11, color: palette.secondaryLabel),
              ),
            ],
            if (waiting && outgoing.code != null) ...[
              const SizedBox(height: 6),
              _Code(outgoing.code!, palette: palette),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistory(PanelPalette palette) {
    final sync = widget.sync;
    final onSend = widget.onSendHistory;
    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Share History with New Devices',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Semantics(
                label: 'Share History with New Devices',
                child: CupertinoSwitch(
                  value: sync.shareHistory,
                  activeTrackColor: palette.accent,
                  onChanged: sync.setShareHistory,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'A device that connects for the first time gets the text '
            'already in this list. Deleting an entry removes it on every '
            'connected device.',
            style: TextStyle(fontSize: 11, color: palette.secondaryLabel),
          ),
          const SizedBox(height: 10),
          // Aligned rather than put in a row, so a long label at a large
          // text size is shortened instead of running off the card.
          Align(
            alignment: Alignment.centerLeft,
            child: PanelButton(
              label: _historySent ? 'History Sent' : 'Send History Now',
              icon: _historySent ? CupertinoIcons.checkmark : null,
              palette: palette,
              onPressed: onSend == null || sync.peers.isEmpty
                  ? null
                  : () {
                      onSend();
                      setState(() => _historySent = true);
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoCopy(PanelPalette palette) {
    final on = widget.autoCopyOn ?? false;
    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                on
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                size: 14,
                color: on ? palette.positive : palette.secondaryLabel,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  on
                      ? 'Copies Are Sent Automatically'
                      : 'Send Copies Automatically',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            on
                ? 'When you tap Copy or Cut in any app, the text goes to '
                      'your other devices. Switch it off in Accessibility '
                      'settings.'
                : 'Android only lets an app see a copy while that app is '
                      'open. With the PasteHive accessibility service on, '
                      'tapping Copy or Cut in any app sends the text by '
                      'itself. It only notices the tap; it does not read '
                      'your screen.',
            style: TextStyle(fontSize: 11, color: palette.secondaryLabel),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: PanelButton(
              label: 'Open Accessibility Settings',
              palette: palette,
              onPressed: widget.onOpenAutoCopy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeave(PanelPalette palette) {
    if (!_confirmingLeave) {
      return Align(
        alignment: Alignment.centerLeft,
        child: PanelButton(
          label: 'Stop Syncing with All Devices…',
          palette: palette,
          style: PanelButtonStyle.destructive,
          onPressed: () => setState(() => _confirmingLeave = true),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            'This device forgets the others. Connect again to resume.',
            style: TextStyle(color: palette.secondaryLabel),
          ),
        ),
        const SizedBox(width: 8),
        PanelButton(
          label: 'Cancel',
          palette: palette,
          onPressed: () => setState(() => _confirmingLeave = false),
        ),
        const SizedBox(width: 8),
        PanelButton(
          label: 'Stop',
          palette: palette,
          style: PanelButtonStyle.destructive,
          onPressed: () async {
            await widget.sync.leaveGroup();
            if (mounted) setState(() => _confirmingLeave = false);
          },
        ),
      ],
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
  const _Card({
    required this.palette,
    required this.child,
    this.emphasized = false,
  });

  final PanelPalette palette;
  final Widget child;

  /// Stands out from the other cards: something is waiting for an answer.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasized ? palette.rowSelected : palette.rowHover,
        borderRadius: BorderRadius.circular(12),
        border: emphasized ? Border.all(color: palette.accent) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final PanelPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(height: 1, child: ColoredBox(color: palette.separator)),
    );
  }
}

/// The six-digit code both devices show while pairing, spaced for reading.
class _Code extends StatelessWidget {
  const _Code(this.code, {required this.palette});

  final String code;
  final PanelPalette palette;

  @override
  Widget build(BuildContext context) {
    final spaced = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    return Semantics(
      label: 'Code ${code.split('').join(' ')}',
      excludeSemantics: true,
      child: Text(
        spaced,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
          color: palette.label,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A line of explanation with a symbol in front, so its meaning does not
/// rest on its colour.
class _Notice extends StatelessWidget {
  const _Notice(this.text, {required this.color, required this.icon});

  final String text;
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
