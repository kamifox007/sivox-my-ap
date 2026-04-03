import 'package:flutter/material.dart';

class EventDetailsScreen extends StatelessWidget {
  const EventDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400.0,
            pinned: true,
            backgroundColor: const Color(0xFF0E0E0E),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuBwaGXczn-1Mfpn4hBMFcEYwZdy4SIoZrLX8WDqs5mkPzlve0lme-m7fUKW42FkAW7il0Wa_RmUXGp1zircqydvlfU4Xw3ewxe89GxnhSywzXWBy-kJOBxYOCa55B_5EUAu-RgNQGOeBVLDPutCz24R0Q55cMgSTp_6t6n1_6zJn3DTaPiBJKxuW6MEfxStOHnc7OoezTYzmgc1LTHgMaPTJ7Be99L7_zBaXe9KHLn0A4OnQxYIty50avWZWl9g7qTwGJ0m2nAxJAaq',
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [const Color(0xFF0E0E0E), Colors.transparent],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFb6a0ff).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFb6a0ff).withOpacity(0.5)),
                    ),
                    child: const Text('SECRET WAREHOUSE', style: TextStyle(color: Color(0xFFb6a0ff), fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  const Text('NEON VOID: Vol. 4', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1.1)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Color(0xFF00e3fd), size: 16),
                      const SizedBox(width: 8),
                      const Text('May 24, 2024', style: TextStyle(color: Colors.white, fontSize: 14)),
                      const SizedBox(width: 24),
                      const Icon(Icons.schedule, color: Color(0xFF00e3fd), size: 16),
                      const SizedBox(width: 8),
                      const Text('22:00 - Late', style: TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFF00e3fd), size: 16),
                      const SizedBox(width: 8),
                      const Text('Output Brooklyn, Soho, NYC', style: TextStyle(color: Color(0xFFadaaaa), fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text('ABOUT THE EVENT', style: TextStyle(color: Color(0xFF00e3fd), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 12),
                  const Text(
                    'Experience the fourth volume of Neon Void, where experimental bass meets cutting-edge visual arts. An immersive warehouse journey that redefines underground nightlife. Strict dress code applies. No cameras allowed.',
                    style: TextStyle(color: Color(0xFFadaaaa), fontSize: 14, height: 1.6),
                  ),
                  const SizedBox(height: 32),
                  const Text('LINEUP', style: TextStyle(color: Color(0xFF00e3fd), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 12),
                  _buildLineupItem('DJ Midnight', '22:00'),
                  _buildLineupItem('Synthwave Phantom', '00:00'),
                  _buildLineupItem('The Labyrinth', '02:00'),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF131313).withOpacity(0.95),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('TOTAL', style: TextStyle(color: Color(0xFFadaaaa), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                Text('\$45.00', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              ],
            ),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('BOOK TICKET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineupItem(String artist, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(artist, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(time, style: const TextStyle(color: Color(0xFFadaaaa), fontSize: 14)),
        ],
      ),
    );
  }
}
