import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/theme_mode_provider.dart';
import '../../../app/tokens.dart';
import 'update_dialog.dart';
import 'update_service.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

class AboutSettingsScreen extends ConsumerWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(_packageInfoProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(LuxiumSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: LuxiumSpacing.xs),
            Text(
              'Version and appearance preferences',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: LuxiumSpacing.xl),
            _VersionCard(infoAsync: infoAsync),
            const SizedBox(height: LuxiumSpacing.lg),
            const _AppearanceCard(),
            const SizedBox(height: LuxiumSpacing.lg),
            const _FooterCard(),
          ],
        ),
      ),
    );
  }
}

class _VersionCard extends ConsumerStatefulWidget {
  final AsyncValue<PackageInfo> infoAsync;
  const _VersionCard({required this.infoAsync});

  @override
  ConsumerState<_VersionCard> createState() => _VersionCardState();
}

class _VersionCardState extends ConsumerState<_VersionCard> {
  bool _checking = false;
  String? _status;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    final result = await ref.read(updateServiceProvider).check();
    if (!mounted) return;
    setState(() => _checking = false);
    switch (result) {
      case UpdateUpToDate(:final currentVersion):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You are on the latest version (v$currentVersion).'),
          ),
        );
      case UpdateError(:final message):
        setState(() => _status = message);
      case UpdateAvailable():
        showUpdateDialog(context, ref, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channelAsync = ref.watch(updateChannelProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(LuxiumSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: _LuxiumMarkAsset(),
                ),
                const SizedBox(width: LuxiumSpacing.md),
                Text(
                  'Luxium Payroll',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuxiumSpacing.lg),
            _label(context, 'Current Version'),
            const SizedBox(height: LuxiumSpacing.xs),
            widget.infoAsync.when(
              loading: () => Text(
                '…',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              error: (e, _) => Text(
                'v—',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              data: (info) => Text(
                'v${info.version}${info.buildNumber.isNotEmpty && info.buildNumber != '1' ? '+${info.buildNumber}' : ''}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: LuxiumSpacing.lg),
            _PlatformRow(channel: channelAsync.asData?.value),
            const Divider(height: LuxiumSpacing.xxl),
            Text(
              'Updates',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: LuxiumSpacing.md),
            FilledButton.icon(
              onPressed: _checking ? null : _check,
              icon: _checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(_checking ? 'Checking…' : 'Check for Updates'),
            ),
            const SizedBox(height: LuxiumSpacing.sm),
            Text(
              _updateSubtitle(channelAsync.asData?.value),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: LuxiumSpacing.sm),
              Text(
                _status!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _updateSubtitle(UpdateChannel? channel) {
    switch (channel) {
      case UpdateChannel.windowsInstaller:
        return 'Downloads and launches the Windows installer. You will be asked to close the app.';
      case UpdateChannel.macosDirect:
        return 'Opens the download in your browser. Install the new .dmg manually.';
      case UpdateChannel.linuxDirect:
        return 'Opens the download in your browser. Replace your AppImage / .deb manually.';
      case UpdateChannel.appStore:
        return 'Routes to the App Store. Updates are installed by iOS.';
      case UpdateChannel.playStore:
        return 'Routes to Google Play. Updates are installed by Android.';
      case UpdateChannel.sideloadAndroid:
        return 'Routes to the Play Store if listed, or opens the APK download.';
      case UpdateChannel.web:
        return 'Web builds update automatically on refresh.';
      case null:
      case UpdateChannel.unknown:
        return 'Auto-updates require the desktop application.';
    }
  }
}

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(LuxiumSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Appearance',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: LuxiumSpacing.xs),
            Text(
              'Choose how Luxium Payroll looks. Matches your OS preference by default.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: LuxiumSpacing.lg),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_outlined, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined, size: 18),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).set(s.first),
              showSelectedIcon: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterCard extends StatelessWidget {
  const _FooterCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuxiumSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Luxium Payroll — Philippine Payroll System',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: LuxiumSpacing.xs),
          Text(
            'Built with Flutter and Supabase. Integrated with Lark for HR sync.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformRow extends StatelessWidget {
  final UpdateChannel? channel;
  const _PlatformRow({required this.channel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon) = _iconFor(channel);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuxiumSpacing.md,
        vertical: LuxiumSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(LuxiumRadius.lg),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: LuxiumSpacing.sm),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  (String, IconData) _iconFor(UpdateChannel? c) {
    switch (c) {
      case UpdateChannel.windowsInstaller:
        return ('Windows Desktop', Icons.laptop_windows);
      case UpdateChannel.macosDirect:
        return ('macOS Desktop', Icons.laptop_mac);
      case UpdateChannel.linuxDirect:
        return ('Linux Desktop', Icons.laptop);
      case UpdateChannel.appStore:
        return ('iOS · App Store', Icons.phone_iphone);
      case UpdateChannel.playStore:
        return ('Android · Google Play', Icons.android);
      case UpdateChannel.sideloadAndroid:
        return ('Android · Sideload', Icons.android);
      case UpdateChannel.web:
        return ('Web Application', Icons.public);
      case null:
      case UpdateChannel.unknown:
        return ('Desktop Application', Icons.laptop);
    }
  }
}

Widget _label(BuildContext context, String text) {
  final theme = Theme.of(context);
  return Text(
    text,
    style: theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    ),
  );
}

class _LuxiumMarkAsset extends StatelessWidget {
  const _LuxiumMarkAsset();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/brand/luxium-icon.svg',
      fit: BoxFit.contain,
      semanticsLabel: 'Luxium',
    );
  }
}
