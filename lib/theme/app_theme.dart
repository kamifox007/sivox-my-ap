import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_app/services/performance_service.dart';

class AppTheme {
  // الألوان الأساسية
  static const Color background = Color(0xFF0E0E0E);
  static const Color surface = Color(0xFF0E0E0E);
  static const Color surfaceContainer = Color(0xFF1A1919);
  static const Color surfaceContainerHighest = Color(0xFF262626);
  static const Color primary = Color(0xFFD3BFFF); // Nocturnal Purple Brighter
  static const Color secondary = Color(0xFF26F0FF); // Vibrant Cyan
  static const Color tertiary = Color(0xFFFF96BB); // Pink
  static const Color onSurface = Colors.white;
  static const Color onSurfaceVariant = Color(0xFFE0E0E0);
  static const Color outline = Color(0xFF484847);

  // التدرجات اللونية (Gradients)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF7A45E5)],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x40FFFFFF), Color(0x10FFFFFF)],
  );

  // أنماط الخطوط
  static TextStyle get headlineStyle => GoogleFonts.epilogue(
        fontSize: 32,
        fontWeight: FontWeight.w900,
        color: onSurface,
        height: 1.1,
        letterSpacing: -1,
      );

  static TextStyle get bodyStyle => GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: onSurface,
      );

  static TextStyle get labelStyle => GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: onSurfaceVariant,
        letterSpacing: 1.5,
      );

  // ثيم التطبيق الكامل
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        tertiary: tertiary,
        surface: surface,
        onSurface: onSurface,
      ),
      textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          elevation: 0,
          textStyle: GoogleFonts.epilogue(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E1E1E),
        contentTextStyle: GoogleFonts.cairo(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 10,
      ),
    );
  }

  // مكوّن اللوحة الزجاجية (Glass Card Decoration)
  static BoxDecoration glassDecoration({double opacity = 0.05, double radius = 32, bool showBorder = true}) {
    return PerformanceService.glassDecoration(
      opacity: opacity,
      radius: radius,
      showBorder: showBorder,
    );
  }
  static const String mapDarkStyle = '[{"elementType":"geometry","stylers":[{"color":"#212121"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},{"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#757575"}]},{"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#181818"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"poi.park","elementType":"labels.text.stroke","stylers":[{"color":"#1b1b1b"}]},{"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2c2c2c"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},{"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373737"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c3c3c"}]},{"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#4e4e4e"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d3d"}]}]';
}
