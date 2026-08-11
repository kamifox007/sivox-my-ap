import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/screens/profile.dart';
import 'package:my_app/screens/notifications_screen.dart';

class HomeSliverAppBar extends StatelessWidget {
  final String selectedCountryCode;
  final Function(String) onCountryChanged;

  const HomeSliverAppBar({
    super.key,
    required this.selectedCountryCode,
    required this.onCountryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: AppTheme.background.withValues(alpha: 0.8),
      floating: true,
      pinned: false,
      elevation: 0,
      centerTitle: false,
      title: Builder(
        builder: (context) {
          final user = Supabase.instance.client.auth.currentUser;
          final name = user?.userMetadata?['full_name'] ?? '';
          final firstName = name.toString().split(' ').first;
          return Row(
            children: [
              const Icon(Icons.menu_rounded, color: AppTheme.primary, size: 28),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (firstName.isNotEmpty)
                    Text(
                      '${'welcome_back'.tr}, $firstName',
                      style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.normal),
                    ),
                  Text(
                    'AFTERDARK',
                    style: AppTheme.headlineStyle.copyWith(
                      fontSize: firstName.isNotEmpty ? 20 : 24,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.primary,
                      letterSpacing: -1,
                      shadows: [
                        Shadow(color: AppTheme.primary.withValues(alpha: 0.8), blurRadius: 15),
                        Shadow(color: AppTheme.secondary.withValues(alpha: 0.5), blurRadius: 30),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        }
      ),
      actions: [
        _buildNotificationBell(context),
        const SizedBox(width: 16),
        _buildAvatar(context),
        const SizedBox(width: 24),
      ],
    );
  }


  Widget _buildAvatar(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final avatar = user?.userMetadata?['avatar_url'];
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: avatar != null 
            ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
            : const Icon(Icons.person_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.unreadCount,
      builder: (context, count, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 26),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
            if (count > 0)
              Positioned(
                top: 12,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
                ),
              ),
          ],
        );
      },
    );
  }
}
