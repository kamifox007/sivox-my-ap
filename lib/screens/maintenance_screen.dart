import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';

class MaintenanceScreen extends StatelessWidget {
  final String? message;
  const MaintenanceScreen({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.settings_suggest_rounded, color: AppTheme.primary, size: 80),
              ),
              const SizedBox(height: 48),
              Text(
                'MAINTENANCE_MODE'.tr.toUpperCase(),
                style: AppTheme.headlineStyle.copyWith(fontSize: 24, letterSpacing: 2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                message ?? 'MAINTENANCE_DESC'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 60),
              // Non-clickable decorative button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 16),
                    Text('CHECKING_FOR_UPDATES'.tr, style: const TextStyle(color: Colors.white30, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
