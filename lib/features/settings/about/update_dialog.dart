import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/tokens.dart';
import 'update_service.dart';

/// The one update dialog. Shown from Settings → About and from the startup
/// banner, so both entry points render identical UI and there is only one
/// implementation of download progress.
Future<void> showUpdateDialog(
  BuildContext context,
  WidgetRef ref,
  UpdateAvailable update,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _UpdateDialog(update: update),
  );
}

class _UpdateDialog extends ConsumerStatefulWidget {
  final UpdateAvailable update;
  const _UpdateDialog({required this.update});

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  bool _launching = false;
  double _progress = 0;
  String? _error;

  UpdateAvailable get _update => widget.update;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channel = _update.channel;
    final asset = _update.manifest.assetFor(channel);
    final storeLink = _update.manifest.storeLinkFor(channel);
    final canLaunch = channel.isStore
        ? (storeLink != null && storeLink.isNotEmpty)
        : (asset != null && asset.url.isNotEmpty);
    final notes = _update.manifest.releaseNotes;
    final hasNotes = notes != null && notes.trim().isNotEmpty;

    return AlertDialog(
      title: Text('Update available — v${_update.manifest.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current: v${_update.currentVersion}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: LuxiumSpacing.sm),
            if (hasNotes) ...[
              Text(
                'Release notes',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: LuxiumSpacing.xs),
              Text(notes, style: theme.textTheme.bodySmall),
              const SizedBox(height: LuxiumSpacing.md),
            ],
            Text(
              'Channel: ${channel.label}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_launching) ...[
              const SizedBox(height: LuxiumSpacing.md),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: LuxiumSpacing.xs),
              Text(
                _progress == 0
                    ? 'Starting…'
                    : 'Downloading installer… ${(_progress * 100).round()}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: LuxiumSpacing.md),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _launching ? null : () => Navigator.pop(context),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          onPressed: (!canLaunch || _launching) ? null : _launch,
          icon: Icon(
            channel.isStore
                ? Icons.open_in_new
                : channel == UpdateChannel.windowsInstaller
                ? Icons.download
                : Icons.open_in_browser,
            size: 16,
          ),
          label: Text(
            channel.isStore
                ? 'Open Store'
                : channel == UpdateChannel.windowsInstaller
                ? 'Download & Install'
                : 'Download',
          ),
        ),
      ],
    );
  }

  Future<void> _launch() async {
    setState(() {
      _launching = true;
      _progress = 0;
      _error = null;
    });
    final ok = await ref.read(updateServiceProvider).launchUpdate(
          _update,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = p.clamp(0.0, 1.0));
          },
        );
    if (!mounted) return;
    setState(() => _launching = false);
    if (!ok) {
      setState(() => _error = 'Could not launch the update.');
      return;
    }
    Navigator.pop(context);
    if (_update.channel == UpdateChannel.windowsInstaller) {
      // Installer is running detached. Prompt the user to close the app so
      // Inno Setup can replace files.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Installer started'),
          content: const Text(
            'The installer is now running. Close Payroll Flutter when prompted so the update can complete.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
    }
  }
}
