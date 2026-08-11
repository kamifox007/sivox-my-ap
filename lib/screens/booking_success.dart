import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/models/booking.dart';
import 'package:my_app/screens/ticket.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:my_app/services/booking_service.dart';

class BookingSuccessScreen extends StatefulWidget {
  final Booking booking;
  const BookingSuccessScreen({super.key, required this.booking});

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0, curve: Curves.easeIn)),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _shareBooking(BuildContext context) async {
    final event = widget.booking.event;
    if (event == null) return;

    final shareLink = 'https://Sivox.app/event/${event.id}';
    final message = '${'share_event'.tr}\n\n${event.title}\n📍 ${event.venue}\n🔗 $shareLink';

    await SharePlus.instance.share(ShareParams(text: message));
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.booking.paymentStatus == 'pending_confirmation';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -150,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -200,
            right: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.secondary.withValues(alpha: 0.03),
              ),
            ),
          ),

          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Success Badge
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: isPending ? Colors.amber.withValues(alpha: 0.2) : AppTheme.primary.withValues(alpha: 0.2),
                            blurRadius: 40,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            isPending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded, 
                            color: isPending ? Colors.amber : AppTheme.primary, 
                            size: 140
                          ),
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),

                  FadeTransition(
                    opacity: _opacityAnimation,
                    child: Column(
                      children: [
                        Text(
                          (isPending ? 'request_sent'.tr : 'booking_confirmed'.tr).toUpperCase(),
                          textAlign: TextAlign.center,
                          style: AppTheme.headlineStyle.copyWith(
                            fontSize: 34,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w900,
                            color: isPending ? Colors.amber : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isPending 
                            ? 'call_to_confirm_desc'.tr
                            : '${'spot_secured_at'.tr} ${widget.booking.event?.title ?? 'the night'}.\n${'get_ready_msg'.tr}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                            height: 1.6,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 60),

                        // Action Buttons
                        if (isPending && widget.booking.event?.contactNumber != null) ...[
                          _PremiumButton(
                            onTap: () => launchUrl(Uri.parse('tel:${widget.booking.event!.contactNumber}')),
                            label: 'CALL_TO_CONFIRM'.tr.toUpperCase(),
                            isPrimary: true,
                            customColor: Colors.amber,
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        _PremiumButton(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => TicketScreen(booking: widget.booking)),
                            );
                          },
                          label: (isPending ? 'view_request_status'.tr : 'view_ticket'.tr).toUpperCase(),
                          isPrimary: !isPending,
                        ),
                        const SizedBox(height: 16),
                        if (isPending)
                          _PremiumButton(
                            onTap: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppTheme.surfaceContainer,
                                  title: Text('cancel_request_q'.tr, style: const TextStyle(color: Colors.white)),
                                  content: Text('cancel_request_desc'.tr, style: const TextStyle(color: Colors.white70)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('no'.tr)),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('yes_cancel'.tr, style: const TextStyle(color: Colors.redAccent))),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await BookingService().cancelBooking(widget.booking.id, eventId: widget.booking.eventId);
                                if (context.mounted) Navigator.pop(context);
                              }
                            },
                            label: 'CANCEL_REQUEST'.tr.toUpperCase(),
                            isPrimary: false,
                          ),
                        if (!isPending)
                          _PremiumButton(
                            onTap: () => _shareBooking(context),
                            label: 'INVITE FRIENDS'.tr.toUpperCase(),
                            isPrimary: false,
                          ),
                        const SizedBox(height: 48),

                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'back_to_home'.tr,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.2),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumButton extends StatefulWidget {
  final VoidCallback onTap;
  final String label;
  final bool isPrimary;
  final Color? customColor;

  const _PremiumButton({required this.onTap, required this.label, required this.isPrimary, this.customColor});

  @override
  State<_PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<_PremiumButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.customColor ?? (widget.isPrimary ? AppTheme.primary : Colors.white.withValues(alpha: 0.05));
    
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            border: widget.isPrimary || widget.customColor != null ? null : Border.all(color: Colors.white10),
            boxShadow: (widget.isPrimary || widget.customColor != null) ? [
              BoxShadow(
                color: bgColor.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ] : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: (widget.isPrimary || widget.customColor != null) ? Colors.black : Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
