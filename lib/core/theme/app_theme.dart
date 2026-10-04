import 'package:flutter/material.dart';

/// "Aurora": night-blue with soft cyan and blue glows behind frosted cards.
/// The light version is the same idea on a pale sky background.
class AppTheme {
  static const font = 'Outfit';

  static const _cyan = Color(0xFF38BDF8);
  static const _glow = Color(0xFF2F80ED);
  static const _blue = Color(0xFF2563EB);

  /// The gradient behind the main "left to spend" card and similar heroes.
  static LinearGradient heroGradient(Brightness b) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: b == Brightness.dark
            ? const [Color(0x557DB0FF), Color(0x402F80ED)]
            : const [Color(0xFF3B82E6), Color(0xFF1F5FBF)],
      );

  /// Thin light edge that makes hero cards read as glass.
  static const heroBorder = Border.fromBorderSide(
      BorderSide(color: Color(0x40FFFFFF), width: 1));

  static const heroShadowColor = Color(0xFF2F80ED);

  /// Text and icon colour on top of [heroGradient].
  static const onHero = Colors.white;

  /// Colour for money owed, readable on both backgrounds.
  static Color owed(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFFF8FA3) : const Color(0xFFD63E55);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: _blue,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFF8DB8FF) : const Color(0xFF2F5FD0),
      onPrimary: dark ? const Color(0xFF04102A) : Colors.white,
      primaryContainer: dark ? const Color(0xFF26356F) : const Color(0xFFD9E5FF),
      onPrimaryContainer: dark ? const Color(0xFFE3ECFF) : const Color(0xFF0C2160),
      surface: dark ? const Color(0xFF0A0F24) : const Color(0xFFEAF3FF),
      onSurface: dark ? const Color(0xFFEAF0FF) : const Color(0xFF0E1A3A),
      onSurfaceVariant: dark ? const Color(0xFF98A6CF) : const Color(0xFF55618A),
      outlineVariant: dark ? const Color(0x33FFFFFF) : const Color(0x330E1A3A),
      surfaceContainerLowest: dark ? const Color(0xFF080C1D) : Colors.white,
      surfaceContainerLow: dark ? const Color(0xFF121936) : const Color(0xFFF7FAFF),
      surfaceContainer: dark ? const Color(0xFF182042) : const Color(0xFFE3EDFB),
      surfaceContainerHigh: dark ? const Color(0xFF1E2751) : const Color(0xFFD9E6F8),
      surfaceContainerHighest: dark ? const Color(0xFF262F5E) : const Color(0xFFCEDDF3),
    );

    final cardColor = dark ? const Color(0x14FFFFFF) : const Color(0xB3FFFFFF);
    final cardEdge = dark ? const Color(0x1FFFFFFF) : const Color(0xCCFFFFFF);
    final navColor = dark ? const Color(0xC00A0F24) : const Color(0xCCFFFFFF);

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: font);
    final text = base.textTheme.apply(fontFamily: font).copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        );

    return base.copyWith(
      textTheme: text,
      // Transparent so the glow behind the whole app (see AuroraBackground) shows.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: scheme.surfaceContainerLow,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        clipBehavior: Clip.antiAlias,
        color: cardColor,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: cardEdge),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w800),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorShape: const StadiumBorder(),
        indicatorColor: dark ? const Color(0x667DB0FF) : const Color(0x332F5FD0),
        labelTextStyle: WidgetStatePropertyAll(
            text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: const StadiumBorder(),
        backgroundColor: dark ? const Color(0xFF7DB0FF) : const Color(0xFF2F5FD0),
        foregroundColor: dark ? const Color(0xFF04102A) : Colors.white,
        elevation: 6,
        extendedTextStyle: text.labelLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: const StadiumBorder()),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: const StadiumBorder()),
      ),
      chipTheme: const ChipThemeData(shape: StadiumBorder(), side: BorderSide.none),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0x14FFFFFF) : const Color(0x99FFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cardEdge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cardEdge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      listTileTheme: ListTileThemeData(
        titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }

  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);
}

/// The soft cyan and blue glow behind every screen.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF0A0F24) : const Color(0xFFEAF3FF);
    return DecoratedBox(
      decoration: BoxDecoration(color: base),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-1.1, -1.05),
            radius: 1.25,
            colors: [
              AppTheme._cyan.withValues(alpha: dark ? 0.38 : 0.30),
              Colors.transparent,
            ],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.1, -0.6),
              radius: 1.1,
              colors: [
                AppTheme._glow.withValues(alpha: dark ? 0.40 : 0.24),
                Colors.transparent,
              ],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.3, 1.15),
                radius: 1.0,
                colors: [
                  AppTheme._blue.withValues(alpha: dark ? 0.34 : 0.18),
                  Colors.transparent,
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
