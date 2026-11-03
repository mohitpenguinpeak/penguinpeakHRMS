import 'package:flutter/material.dart';

/// Uses the actual content width, including inside a desktop sidebar layout.
class AdaptiveCards extends StatelessWidget {
  const AdaptiveCards({
    super.key,
    required this.children,
    this.minWidth = 380,
    this.maxColumns = 3,
  });
  final List<Widget> children;
  final double minWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count = ((box.maxWidth + 16) / (minWidth + 16)).floor().clamp(
        1,
        maxColumns,
      );
      final width = (box.maxWidth - (count - 1) * 16) / count;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class WorkspaceHeading extends StatelessWidget {
  const WorkspaceHeading({
    super.key,
    required this.title,
    required this.action,
  });
  final String title;
  final Widget action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final heading = Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      );
      return box.maxWidth < 600
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 12), action],
            )
          : Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                action,
              ],
            );
    },
  );
}

/// Only animates entry/replacement, never on timer-driven rebuilds.
class WorkspaceReveal extends StatelessWidget {
  const WorkspaceReveal({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
  );
}
