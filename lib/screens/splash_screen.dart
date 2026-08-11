import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/screens/home_feed.dart';
import 'package:my_app/screens/auth_screen.dart';
import 'package:my_app/services/config_service.dart';
import 'package:my_app/screens/maintenance_screen.dart';
import 'dart:ui';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.8, curve: Curves.elasticOut)),
    );

    _controller.forward();
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    // 1. Minimum Animation Duration
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    // 2. Remote Config Check (Maintenance / Version)
    final config = await ConfigService().getAppConfig();
    if (mounted && config != null) {
      if (config['is_maintenance'] == true) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MaintenanceScreen(message: config['alert_message']))
        );
        return;
      }
    }

    // 3. Normal Flow
    final session = Supabase.instance.client.auth.currentSession;
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => 
            session != null ? const HomeFeedScreen() : const AuthScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Glows
          _buildAura(AppTheme.primary, top: -100, right: -100),
          _buildAura(AppTheme.secondary, bottom: -100, left: -100),
          
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLogo(),
                        const SizedBox(height: 40),
                        _buildLoader(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                   Text(
                    'sivox_slogan'.tr.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'PRODUCTION READY V1.0',
                    style: TextStyle(
                      color: Colors.white10,
                      fontSize: 8,
                      letterSpacing: 2,
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

  Widget _buildLogo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            children: [
              Text(
                'Sivox',
                style: AppTheme.headlineStyle.copyWith(
                  fontSize: 72,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w900,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.secondary],
                    ).createShader(const Rect.fromLTWH(0.0, 0.0, 300.0, 70.0)),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 2,
                width: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.primary, Colors.transparent]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoader() {
    return Column(
      children: [
        SizedBox(
          width: 140,
          child: LinearProgressIndicator(
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            color: AppTheme.primary,
            minHeight: 1,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'SECURE SESSION INITIALIZING...',
          style: TextStyle(
            color: AppTheme.primary,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildAura(Color c, {double? top, double? right, double? bottom, double? left}) {
    return Positioned(
      top: top, right: right, bottom: bottom, left: left,
      child: Container(
        width: 400, height: 400,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.12), blurRadius: 200, spreadRadius: 50)],
        ),
      ),
    );
  }
}
