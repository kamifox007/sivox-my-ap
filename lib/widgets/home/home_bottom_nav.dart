import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';

class HomeBottomNav extends StatelessWidget {
  final bool isHeaderVisible;
  final int currentIndex;
  final Function(int) onTabSelected;

  const HomeBottomNav({
    super.key,
    required this.isHeaderVisible,
    required this.currentIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      offset: isHeaderVisible ? Offset.zero : const Offset(0, 1.5),
      curve: Curves.easeOutCubic,
      child: Container(
        height: 70, 
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 30),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 5)
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround, 
              children: [
                _navItem(0, Icons.explore_rounded, 'home'.tr), 
                _navItem(1, Icons.map_rounded, 'map'.tr), 
                _navItem(2, Icons.confirmation_num_rounded, 'passes'.tr), 
                _navItem(3, Icons.person_rounded, 'profile'.tr)
              ]
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final active = currentIndex == index;
    return GestureDetector(
      onTap: () => onTabSelected(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: active ? BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)) : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: active ? AppTheme.primary : Colors.white24, size: 26),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: active ? AppTheme.primary : Colors.white24, fontSize: 10, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
        ]),
      ),
    );
  }
}
