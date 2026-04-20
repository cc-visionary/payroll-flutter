import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Brand-styled tooltip rendered via [OverlayPortal] — rolls our own
/// show/hide instead of wrapping Flutter's [Tooltip] so we get a clean fade
/// from opacity 0 with our own decoration from the first frame.
///
/// Two constructors:
///
/// * `BrandTooltip(message: ..., child: ...)` — single-line plain text.
/// * `BrandTooltip.richRows(rows: {...}, child: ...)` — key/value table where
///   the label uses Satoshi body and the value uses Geist Mono so numbers
///   stay tabular.
///
/// Behaviour:
/// - 150 ms hover delay before showing (matches Chart.js feel)
/// - 180 ms fade-in, 140 ms fade-out, both `Curves.easeOut`
/// - Auto-positions below the target; flips above when near the bottom edge
class BrandTooltip extends StatefulWidget {
  final Widget child;
  final String? message;
  final Map<String, String>? rows;

  const BrandTooltip({
    super.key,
    required this.message,
    required this.child,
  }) : rows = null;

  const BrandTooltip.richRows({
    super.key,
    required this.rows,
    required this.child,
  }) : message = null;

  @override
  State<BrandTooltip> createState() => _BrandTooltipState();
}

class _BrandTooltipState extends State<BrandTooltip>
    with SingleTickerProviderStateMixin {
  static const _hoverDelay = Duration(milliseconds: 150);
  static const _fadeIn = Duration(milliseconds: 180);
  static const _fadeOut = Duration(milliseconds: 140);
  static const _gap = 8.0;

  final _portalController = OverlayPortalController();
  final _link = LayerLink();
  // Eager init — `late final` with an `AnimationController(vsync: this)`
  // body is a footgun: if the widget is unmounted before any hover /
  // interaction, dispose() would be the FIRST access to `_fadeCtrl`, which
  // triggers lazy construction → `createTicker` → `TickerMode.getValuesNotifier`
  // → ancestor lookup on a deactivated element → framework assertion.
  // Initializing both in initState() sidesteps the whole lazy-init path.
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  Timer? _showTimer;
  bool _openAbove = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: _fadeIn,
      reverseDuration: _fadeOut,
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onEnter() {
    _showTimer?.cancel();
    _showTimer = Timer(_hoverDelay, _reveal);
  }

  void _onExit() {
    _showTimer?.cancel();
    if (!_portalController.isShowing) return;
    _fadeCtrl.reverse().whenCompleteOrCancel(() {
      if (!mounted) return;
      if (_fadeCtrl.status == AnimationStatus.dismissed) {
        _portalController.hide();
      }
    });
  }

  void _reveal() {
    if (!mounted) return;
    // Decide above vs below based on where the target sits within the screen.
    final box = context.findRenderObject() as RenderBox?;
    final screen = MediaQuery.of(context).size;
    if (box != null && box.hasSize) {
      final pos = box.localToGlobal(Offset.zero);
      final belowSpace = screen.height - (pos.dy + box.size.height);
      _openAbove = belowSpace < 140 && pos.dy > 140;
    } else {
      _openAbove = false;
    }
    _portalController.show();
    _fadeCtrl.forward(from: _fadeCtrl.value);
  }

  Widget _buildBubble(BuildContext ctx) {
    final isLight = Theme.of(ctx).brightness == Brightness.light;
    final bg = isLight
        ? Colors.white
        : Theme.of(ctx).colorScheme.surfaceContainerHigh;
    final decoration = BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A32325D), // rgba(50,50,93,0.10) — shadow-card
          blurRadius: 36,
          offset: Offset(0, 8),
        ),
        BoxShadow(
          color: Color(0x14000000), // rgba(0,0,0,0.08)
          blurRadius: 18,
          offset: Offset(0, 4),
        ),
      ],
    );

    final body = widget.rows != null
        ? _RichRowsBody(rows: widget.rows!)
        : Text(
            widget.message ?? '',
            style: TextStyle(
              fontFamily: 'Satoshi',
              fontSize: 13,
              color: Theme.of(ctx).colorScheme.onSurface,
            ),
          );

    return Container(
      padding: widget.rows != null
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: decoration,
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _onEnter(),
        onExit: (_) => _onExit(),
        child: OverlayPortal(
          controller: _portalController,
          overlayChildBuilder: (overlayCtx) {
            final targetAnchor =
                _openAbove ? Alignment.topCenter : Alignment.bottomCenter;
            final followerAnchor =
                _openAbove ? Alignment.bottomCenter : Alignment.topCenter;
            final offset = Offset(0, _openAbove ? -_gap : _gap);
            // `Align` absorbs the Overlay's StackFit.expand tight constraints
            // and hands loose constraints to CompositedTransformFollower, so
            // the bubble sizes to its natural content width (via the
            // ConstrainedBox + IntrinsicWidth inside `_buildBubble`) instead
            // of ballooning to the full viewport. The paint position is
            // unaffected — CompositedTransformFollower uses a layer transform
            // to place the bubble relative to the target.
            return Align(
              alignment: Alignment.topLeft,
              child: CompositedTransformFollower(
                link: _link,
                targetAnchor: targetAnchor,
                followerAnchor: followerAnchor,
                offset: offset,
                showWhenUnlinked: false,
                child: IgnorePointer(
                  child: FadeTransition(
                    opacity: _fade,
                    child: Material(
                      type: MaterialType.transparency,
                      child: _buildBubble(overlayCtx),
                    ),
                  ),
                ),
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _RichRowsBody extends StatelessWidget {
  final Map<String, String> rows;
  const _RichRowsBody({required this.rows});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.62);
    final labelStyle = TextStyle(
      fontFamily: 'Satoshi',
      fontSize: 12,
      color: muted,
      fontWeight: FontWeight.w500,
    );
    final valueStyle = AppTheme.mono(
      context,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: onSurface,
    );
    // Shrink-wrap: `IntrinsicWidth` + `mainAxisSize.min` on each row keeps the
    // bubble sized to its content instead of stretching to the overlay's
    // available width.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(entry.key, style: labelStyle),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        entry.value,
                        textAlign: TextAlign.right,
                        style: valueStyle,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
