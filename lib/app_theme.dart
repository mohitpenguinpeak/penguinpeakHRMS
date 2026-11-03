import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(
  ThemeMode.dark,
);

class AppThemes {
  static const orange = Color(0xFFF59E0B);

  static ThemeData get dark => _workspace(
    ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: orange,
        brightness: Brightness.dark,
        primary: orange,
      ),
      scaffoldBackgroundColor: const Color(0xFF101010),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF101010)),
      cardTheme: CardThemeData(
        color: const Color(0xFF1A1A1A),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF303030)),
        ),
      ),
    ),
  );

  static ThemeData get light => _workspace(
    ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: orange,
        brightness: Brightness.light,
        primary: const Color(0xFFB85C00),
      ),
      scaffoldBackgroundColor: const Color(0xFFBDBDBD),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFBDBDBD),
        foregroundColor: Color(0xFF171717),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E5E5)),
        ),
      ),
    ),
  );

  static ThemeData _workspace(ThemeData theme) {
    final colors = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return theme.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: theme.cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.primary,
        unselectedLabelColor: colors.onSurfaceVariant,
        indicatorColor: colors.primary,
        dividerColor: colors.outlineVariant,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(
          colors.onSurface.withValues(alpha: 0.04),
        ),
        headingTextStyle: TextStyle(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        horizontalMargin: 20,
        columnSpacing: 28,
        dividerThickness: 0.5,
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 0.5,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    );
  }
}
