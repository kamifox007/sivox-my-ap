import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/staff_service.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = NotificationService();
    
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Background Glows
          _buildAura(AppTheme.primary, top: -100, right: -100),
          _buildAura(AppTheme.secondary, bottom: -100, left: -100),
          
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(context, service),
              StreamBuilder<List<AppNotification>>(
                stream: service.getNotificationsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                    );
                  }

                  final notifications = snapshot.data ?? [];
                  if (notifications.isEmpty) {
                    return _buildEmptyState();
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _NotificationTile(notification: notifications[index]),
                      childCount: notifications.length,
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, NotificationService service) {
    return SliverAppBar(
      expandedHeight: 120,
      backgroundColor: Colors.transparent,
      pinned: true,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
        title: Text(
          'notifications'.tr.toUpperCase(),
          style: AppTheme.headlineStyle.copyWith(fontSize: 16, letterSpacing: 2),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => service.markAllAsRead(),
          child: Text('mark_all_read'.tr, style: const TextStyle(color: AppTheme.primary, fontSize: 11)),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, color: Colors.white.withValues(alpha: 0.05), size: 100),
            const SizedBox(height: 24),
            Text('no_notifications'.tr, style: const TextStyle(color: Colors.white24, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildAura(Color c, {double? top, double? right, double? bottom, double? left}) {
    return Positioned(
      top: top, right: right, bottom: bottom, left: left,
      child: Container(
        width: 300, height: 300,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.1), blurRadius: 150)],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatefulWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> {
  bool _isProcessing = false;

  Future<void> _handleInvitation(bool accept) async {
    final assignmentId = widget.notification.metadata?['assignment_id'];
    if (assignmentId == null) return;
    
    setState(() => _isProcessing = true);
    try {
      final staffService = StaffService();
      bool success = false;
      if (accept) {
        success = await staffService.acceptAssignment(assignmentId);
      } else {
        success = await staffService.rejectAssignment(assignmentId);
      }
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accept ? 'Invitation accepted!'.tr : 'Invitation declined'.tr),
          backgroundColor: accept ? Colors.green : Colors.redAccent,
        ));
        NotificationService().markAsRead(widget.notification.id);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = NotificationService();
    final notif = widget.notification;
    final isInvite = notif.type == 'staff_invitation';
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          service.markAsRead(notif.id);
          // Handle navigation based on type if needed
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: notif.isRead 
                    ? Colors.white.withValues(alpha: 0.01) 
                    : (_getHighlightColor(notif.type).withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: notif.isRead 
                      ? Colors.white.withValues(alpha: 0.03) 
                      : (_getHighlightColor(notif.type).withValues(alpha: 0.6)),
                  width: (!notif.isRead) ? 2 : 1,
                ),
                boxShadow: [
                   if (!notif.isRead)
                      BoxShadow(
                        color: _getHighlightColor(notif.type).withValues(alpha: 0.05), 
                        blurRadius: 20, 
                        spreadRadius: -5
                      )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _getIconForType(notif.type),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  notif.title.toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w900,
                                    fontSize: 10,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  DateFormat('HH:mm').format(notif.createdAt),
                                  style: const TextStyle(color: Colors.white12, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              notif.body,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isInvite && !notif.isRead) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_isProcessing)
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                        else ...[
                          TextButton(
                            onPressed: () => _handleInvitation(false),
                            child: Text('decline'.tr.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => _handleInvitation(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                            ),
                            child: Text('accept'.tr.toUpperCase(), style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getHighlightColor(String? type) {
    if (type == 'alert') return Colors.redAccent;
    if (type == 'presence' || type == 'booking') return AppTheme.secondary;
    if (type == 'staff_invitation') return AppTheme.primary;
    return Colors.white24;
  }

  Widget _getIconForType(String? type) {
    IconData iconData;
    Color color;

    switch (type) {
      case 'booking':
        iconData = Icons.confirmation_number_outlined;
        color = AppTheme.secondary;
        break;
      case 'event':
        iconData = Icons.celebration_outlined;
        color = AppTheme.primary;
        break;
      case 'presence':
        iconData = Icons.sensors_rounded;
        color = AppTheme.secondary;
        break;
      case 'alert':
        iconData = Icons.warning_amber_rounded;
        color = Colors.redAccent;
        break;
      case 'staff_invitation':
        iconData = Icons.work_outline_rounded;
        color = AppTheme.primary;
        break;
      default:
        iconData = Icons.notifications_none_rounded;
        color = Colors.white54;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: color, size: 18),
    );
  }
}

