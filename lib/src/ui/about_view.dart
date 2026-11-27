import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../update/app_info.dart';
import '../update/update_service.dart';
import 'panel_palette.dart';
import 'panel_surface.dart';

/// The About view: what the app is, who makes it, where its source and
/// website are, and its updates.
class AboutView extends StatelessWidget {
  const AboutView({
    super.key,
    required this.updates,
    required this.hasMaterial,
    required this.onDone,
    required this.onOpenLink,
  });

  final UpdateService updates;

  /// Whether something translucent is behind this widget.
  final bool hasMaterial;

  /// Goes back to the clipboard list.
  final VoidCallback onDone;

  /// Opens a web address in the browser.
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onDone},
      child: Focus(
        autofocus: true,
        child: PanelSurface(
          hasMaterial: hasMaterial,
          builder: (context, palette) => Column(
            children: [
              _Header(palette: palette, onDone: onDone),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildIdentity(palette),
                      const SizedBox(height: 22),
                      _SectionLabel('Updates', palette: palette),
                      ListenableBuilder(
                        listenable: updates,
                        builder: (context, _) => _buildUpdates(palette),
                      ),
                      const SizedBox(height: 22),
                      _SectionLabel('About', palette: palette),
                      _buildDetails(palette),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentity(PanelPalette palette) {
    return _Card(
      palette: palette,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/app_icon.png',
              width: 52,
              height: 52,
              filterQuality: FilterQuality.medium,
              // The name stands by itself if the picture is missing.
              errorBuilder: (context, _, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  kAppName,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  'Version ${updates.currentVersion}',
                  style: TextStyle(color: palette.secondaryLabel),
                ),
                const SizedBox(height: 6),
                Text(
                  kAppTagline,
                  style: TextStyle(fontSize: 11, color: palette.secondaryLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdates(PanelPalette palette) {
    final latest = updates.latest;
    final status = updates.status;
    final available = updates.hasUpdate && latest != null;
    final cannotInstall = updates.installUnavailableReason;

    final (IconData icon, Color color, String title) = switch (status) {
      UpdateStatus.checking => (
        CupertinoIcons.arrow_2_circlepath,
        palette.secondaryLabel,
        'Checking for Updates…',
      ),
      UpdateStatus.downloading => (
        CupertinoIcons.arrow_down_circle,
        palette.accent,
        'Downloading Version ${latest?.version ?? ''}…',
      ),
      UpdateStatus.installing => (
        CupertinoIcons.arrow_down_circle_fill,
        palette.accent,
        'Installing…',
      ),
      UpdateStatus.failed => (
        CupertinoIcons.exclamationmark_triangle_fill,
        palette.danger,
        available
            ? 'Version ${latest.version} Is Available'
            : 'Could Not Check for Updates',
      ),
      _ when available => (
        CupertinoIcons.arrow_down_circle_fill,
        palette.accent,
        'Version ${latest.version} Is Available',
      ),
      UpdateStatus.upToDate => (
        CupertinoIcons.checkmark_circle_fill,
        palette.positive,
        latest == null ? 'No Release Published Yet' : 'PasteHive Is Up to Date',
      ),
      _ => (CupertinoIcons.circle, palette.secondaryLabel, 'Not Checked Yet'),
    };

    final String detail;
    if (updates.error != null) {
      detail = updates.error!;
    } else if (status == UpdateStatus.installing) {
      detail = 'PasteHive closes and opens again by itself.';
    } else if (available) {
      detail = cannotInstall ?? 'You have ${updates.currentVersion}.';
    } else if (status == UpdateStatus.upToDate && latest == null) {
      detail =
          'This copy was built from source. When a release is '
          'published, it will show here.';
    } else if (updates.lastChecked != null) {
      detail = 'Last checked ${_ago(updates.lastChecked!)}.';
    } else {
      detail = 'PasteHive asks GitHub for the newest version.';
    }

    return _Card(
      palette: palette,
      emphasized: available && !updates.busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(
              fontSize: 11,
              color: updates.error != null
                  ? palette.danger
                  : palette.secondaryLabel,
            ),
          ),
          if (status == UpdateStatus.downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: updates.progress,
                minHeight: 4,
                color: palette.accent,
                backgroundColor: palette.controlFill,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (available && cannotInstall == null)
                PanelButton(
                  label: 'Download and Install',
                  palette: palette,
                  style: PanelButtonStyle.prominent,
                  onPressed: updates.busy ? null : updates.downloadAndInstall,
                ),
              if (available && latest.pageUrl.isNotEmpty)
                PanelButton(
                  label: cannotInstall == null
                      ? 'What’s New'
                      : 'Open Download Page',
                  palette: palette,
                  style: cannotInstall == null
                      ? PanelButtonStyle.plain
                      : PanelButtonStyle.prominent,
                  onPressed: () => onOpenLink(latest.pageUrl),
                ),
              PanelButton(
                label: 'Check Now',
                palette: palette,
                onPressed: updates.busy ? null : updates.check,
              ),
            ],
          ),
          _Divider(palette: palette),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Check Automatically'),
                    Text(
                      'Once a day. Nothing is installed without your say-so.',
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: 'Check for updates automatically',
                child: CupertinoSwitch(
                  value: updates.autoCheck,
                  activeTrackColor: palette.accent,
                  onChanged: updates.setAutoCheck,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(PanelPalette palette) {
    return _Card(
      palette: palette,
      child: Column(
        children: [
          _DetailRow(
            label: 'Developer',
            value: kDeveloperName,
            palette: palette,
            onOpen: () => onOpenLink(kDeveloperUrl),
          ),
          _Divider(palette: palette),
          _DetailRow(
            label: 'Website',
            value: 'yeamin-talukder.github.io/PasteHive',
            palette: palette,
            onOpen: () => onOpenLink(kWebsiteUrl),
          ),
          _Divider(palette: palette),
          _DetailRow(
            label: 'Source Code',
            value: 'github.com/$kRepository',
            palette: palette,
            onOpen: () => onOpenLink(kRepositoryUrl),
          ),
          _Divider(palette: palette),
          _DetailRow(
            label: 'Report a Problem',
            value: 'GitHub Issues',
            palette: palette,
            onOpen: () => onOpenLink(kIssuesUrl),
          ),
          _Divider(palette: palette),
          _DetailRow(
            label: 'License',
            value: kLicenseName,
            palette: palette,
            onOpen: () => onOpenLink(kLicenseUrl),
          ),
        ],
      ),
    );
  }

  String _ago(DateTime then) {
    final passed = DateTime.now().difference(then);
    if (passed.inMinutes < 1) return 'just now';
    if (passed.inHours < 1) return '${passed.inMinutes} min ago';
    if (passed.inDays < 1) return '${passed.inHours} hr ago';
    return passed.inDays == 1 ? 'yesterday' : '${passed.inDays} days ago';
  }
}

/// One line of the details: what it is, its value, and a way to open it.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.palette,
    required this.onOpen,
  });

  final String label;
  final String value;
  final PanelPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value. Opens in the browser.',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Row(
            children: [
              // Side by side at ordinary text sizes; with large text there is
              // no room for both on a line, so the value goes underneath.
              if (MediaQuery.textScalerOf(context).scale(1) > 1.3)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label),
                      Text(
                        value,
                        style: TextStyle(color: palette.secondaryLabel),
                      ),
                    ],
                  ),
                )
              else ...[
                Text(label),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.secondaryLabel),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.arrow_up_right,
                size: 12,
                color: palette.secondaryLabel,
              ),
            ],
          ),
        ),
      ),
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
            'About',
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

class _Card extends StatelessWidget {
  const _Card({
    required this.palette,
    required this.child,
    this.emphasized = false,
  });

  final PanelPalette palette;
  final Widget child;

  /// Stands out: there is something here to act on.
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
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: SizedBox(height: 1, child: ColoredBox(color: palette.separator)),
    );
  }
}
