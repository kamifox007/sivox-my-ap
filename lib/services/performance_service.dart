import 'package:flutter/material.dart';

enum PerformanceTier { lite, standard, pro }

class PerformanceService {
  static final PerformanceService _instance = PerformanceService._internal();
  factory PerformanceService() => _instance;
  PerformanceService._internal();

  // Default to Standard for a beautiful mobile experience
  static PerformanceTier currentTier = PerformanceTier.lite;

  static bool get useBlur => currentTier != PerformanceTier.lite;
  static bool get useComplexShadows => currentTier == PerformanceTier.pro;
  static bool get useHeavyAnimations => currentTier == PerformanceTier.pro;
  
  static double get blurSigma => currentTier == PerformanceTier.pro ? 30.0 : (currentTier == PerformanceTier.standard ? 15.0 : 0.0);
  
  static void setTier(PerformanceTier tier) {
    currentTier = tier;
  }

  static BoxDecoration glassDecoration({
    Color? color,
    double opacity = 0.05,
    double radius = 24,
    bool showBorder = true,
  }) {
    return BoxDecoration(
      color: color ?? Colors.white.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(radius),
      border: showBorder ? Border.all(color: Colors.white.withValues(alpha: 0.05)) : null,
      boxShadow: useComplexShadows ? [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 20,
          offset: const Offset(0, 10),
        )
      ] : null,
    );
  }
}
