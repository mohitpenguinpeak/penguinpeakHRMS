import 'package:flutter/material.dart';

class AppColors {
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF090A0F) // Deep graphite charcoal
          : const Color(0xFFF4F5F7); // Pristine light SaaS workspace background

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF13151A)
          : Colors.white;

  static Color surfaceElevated(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1A1D24)
          : const Color(0xFFFFFFFF);

  static Color surfaceMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E222B)
          : const Color(0xFFEDF2F7);

  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFF1F3F5)
          : const Color(0xFF0F172A);

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF9CA3AF)
          : const Color(0xFF475569);

  static Color textTertiary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF6B7280)
          : const Color(0xFF94A3B8);

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF262B35)
          : const Color(0xFFE2E8F0);

  // Professional SaaS Accent: Electric Indigo / Slate Violet
  static const Color accent = Color(0xFF6366F1); // Indigo
  static const Color accentSoft = Color(0xFFEEF2FF);

  static const Color success = Color(0xFF10B981); // Emerald
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color error = Color(0xFFEF4444); // Rose Red
  static const Color info = Color(0xFF3B82F6); // Blue
}

class AppSpacing {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double full = 999.0;
}

class AppShadows {
  static List<BoxShadow> subtle(BuildContext context) => [
        BoxShadow(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> elevated(BuildContext context) => [
        BoxShadow(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withValues(alpha: 0.4)
              : Colors.black.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.lg);

    return Container(
      decoration: BoxDecoration(
        color:
            backgroundColor ?? (isDark ? const Color(0xFF13151A) : Colors.white),
        borderRadius: radius,
        border: Border.all(
          color: isDark ? const Color(0xFF262B35) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: AppShadows.subtle(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
            child: child,
          ),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final String? trend;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.accentColor,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    trend!,
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 16),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
