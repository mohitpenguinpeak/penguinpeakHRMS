import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ToastKind { success, error, info }

/// Compact notifications above dialogs; newer feedback replaces older feedback.
class AppToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  static void show(
    BuildContext context,
    String message, {
    ToastKind kind = ToastKind.info,
  }) {
    _showContent(context, Text(message), kind: kind);
  }

  static AppToastMessenger of(BuildContext context) =>
      AppToastMessenger(context);

  static void _showContent(
    BuildContext context,
    Widget content, {
    ToastKind kind = ToastKind.info,
    SnackBarAction? action,
    Duration? displayDuration,
  }) {
    dismiss();
    final overlay = Overlay.of(context, rootOverlay: true);
    final media = MediaQuery.of(context);
    final duration =
        displayDuration ?? Duration(seconds: kind == ToastKind.error ? 8 : 5);
    _entry = OverlayEntry(
      builder: (context) => Positioned(
        top: media.padding.top + 80,
        right: 16,
        width: math.min(420, math.max(0, media.size.width - 32)),
        child: _ToastCard(
          content: content,
          action: action,
          kind: kind,
          duration: duration,
          onDismiss: dismiss,
        ),
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(duration, dismiss);
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.content,
    this.action,
    required this.kind,
    required this.duration,
    required this.onDismiss,
  });
  final Widget content;
  final SnackBarAction? action;
  final ToastKind kind;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = switch (kind) {
      ToastKind.success =>
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF6EE7B7)
            : const Color(0xFF047857),
      ToastKind.error => colors.error,
      ToastKind.info => colors.primary,
    };
    final title = switch (kind) {
      ToastKind.success => 'All set',
      ToastKind.error => 'Couldn’t complete that',
      ToastKind.info => 'Quick update',
    };
    final icon = switch (kind) {
      ToastKind.success => Icons.check_circle_outline,
      ToastKind.error => Icons.error_outline,
      ToastKind.info => Icons.info_outline,
    };
    return Semantics(
      liveRegion: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, -12 * (1 - value)),
            child: child,
          ),
        ),
        child: Material(
          color: colors.surfaceContainerHigh,
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: accent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 160),
                              child: SingleChildScrollView(
                                child: DefaultTextStyle(
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                  child: content,
                                ),
                              ),
                            ),
                            if (action != null)
                              TextButton(
                                onPressed: () {
                                  AppToast.dismiss();
                                  action!.onPressed();
                                },
                                child: Text(action!.label),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss notification',
                        visualDensity: VisualDensity.compact,
                        onPressed: onDismiss,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1, end: 0),
                  duration: duration,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 3,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Adapts existing feedback content and actions to the shared toast presentation.
class AppToastMessenger {
  AppToastMessenger(this.context);
  final BuildContext context;

  void hideCurrentSnackBar() => AppToast.dismiss();

  void showSnackBar(SnackBar notice) {
    final text = notice.content is Text
        ? (notice.content as Text).data?.toLowerCase() ?? ''
        : '';
    final kind =
        RegExp(r'error|could not|failed|failure|cannot|unable')
                .hasMatch(text) ||
            notice.backgroundColor == Colors.red
        ? ToastKind.error
        : RegExp(
                r'success|saved|submitted|accepted|updated|deleted|approved|completed',
              ).hasMatch(text) ||
              notice.backgroundColor == Colors.green
        ? ToastKind.success
        : ToastKind.info;
    AppToast._showContent(
      context,
      notice.content,
      kind: kind,
      action: notice.action,
      displayDuration: notice.duration == const Duration(milliseconds: 4000)
          ? null
          : notice.duration,
    );
  }
}
