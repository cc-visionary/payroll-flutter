import 'package:flutter/material.dart';

/// Wraps a wide widget (typically a [DataTable]) so it caps at [maxWidth]
/// on wide screens, aligns to the start, and falls back to horizontal
/// scrolling when the content exceeds the available width.
///
/// Use this for every table in the app to keep layouts consistent and avoid
/// columns stretching across ultrawide windows.
///
/// Pass [fullWidth] = true when the table should expand to fill its parent
/// (Settings tables want this — columns spread across the whole pane).
/// The horizontal-scroll fallback still kicks in on narrow viewports.
class ResponsiveTable extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool fullWidth;

  const ResponsiveTable({
    super.key,
    required this.child,
    this.maxWidth = 1100,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    if (fullWidth) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: child,
          ),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: child,
        ),
      ),
    );
  }
}
