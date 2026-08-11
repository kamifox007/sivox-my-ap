import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';

class HomeSearchBar extends StatelessWidget {
  final TextEditingController searchController;
  final VoidCallback onChanged;

  const HomeSearchBar({
    super.key,
    required this.searchController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 56,
        decoration: AppTheme.glassDecoration(radius: 20).copyWith(
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.05),
              blurRadius: 20,
              spreadRadius: -2,
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: TextField(
              controller: searchController,
              onChanged: (_) => onChanged(),
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'SEARCH'.tr,
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w600),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 16, right: 12),
                  child: Icon(Icons.search_rounded, color: AppTheme.primary, size: 22),
                ),
                suffixIcon: searchController.text.isNotEmpty 
                  ? GestureDetector(
                      onTap: () {
                        searchController.clear();
                        onChanged();
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.clear_rounded, color: Colors.white70, size: 14),
                        ),
                      ),
                    ) 
                  : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
