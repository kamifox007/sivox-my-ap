import 'package:flutter/material.dart';
import 'package:my_app/create_event.dart';

class OrganizerDashboardScreen extends StatelessWidget {
  const OrganizerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E0E).withOpacity(0.8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFFb6a0ff)),
          onPressed: () {},
        ),
        title: const Text(
          'NOCTURNAL',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFb6a0ff).withOpacity(0.3), width: 2),
              ),
              child: const CircleAvatar(
                backgroundColor: Colors.transparent,
                backgroundImage: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuBKBDUkaZV0ofk1w0FLNTxMpalK3D_RpE3zTE17VkGJQHoXjpiQBFjhi5V89-SK6S9jQASp-ZaxUIHSCUX83DU1tnjvlYRPZ0WedQ9ebOZejUwWS7njg1iuhkql9zplHWeUbDmKSjvIbR9KeOCDR_DpbfVg7UxfUOCuaKo6PN6DzK5QryqQjI3SOgFIjcaHNmIsvsN3PSz4wGSl-3SpgK4nmbYJxJQJeWi3FGEVqkWDp3cwMAOU1vass2wRfSTvgj2rmj-uDQDqKwPD'),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildStatsGrid(),
              const SizedBox(height: 32),
              _buildMyEventsSection(),
              const SizedBox(height: 32),
              _buildRecentBookings(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF2c2c2c).withOpacity(0.9),
        selectedItemColor: const Color(0xFF00e3fd),
        unselectedItemColor: const Color(0xFFadaaaa),
        type: BottomNavigationBarType.fixed,
        currentIndex: 4,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.style), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.confirmation_number), label: 'Events'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ORGANIZER CONSOLE',
          style: TextStyle(
            color: Color(0xFF00e3fd),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'DASHBOARD',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                color: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateEventScreen()));
              },
              icon: const Icon(Icons.add_circle, color: Colors.black),
              label: const Text('CREATE EVENT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFb6a0ff),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('Active Tickets', '1,284', const Color(0xFFb6a0ff)),
        _buildStatCard('Revenue', '\$42.1K', const Color(0xFF00e3fd)),
        _buildStatCard('Views', '18.5K', null),
        _buildStatCard('Avg. Fill', '92%', null),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color? borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1919),
        borderRadius: BorderRadius.circular(24),
        border: borderColor != null ? Border(left: BorderSide(color: borderColor, width: 4)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(color: Color(0xFFadaaaa), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildMyEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('MY EVENTS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            TextButton.icon(
              onPressed: () {},
              icon: const Text('VIEW ALL', style: TextStyle(color: Color(0xFF00e3fd), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
              label: const Icon(Icons.arrow_forward, color: Color(0xFF00e3fd), size: 16),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 350,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildEventCard('NEON JUNGLE: VOL 4', 'May 24 • Output Brooklyn', 'Live', const Color(0xFFb6a0ff), '850/1000 Sold', 'https://lh3.googleusercontent.com/aida-public/AB6AXuAnOGNCUxlAIzfXzUo3oPROo1CsKOM47k_FHjunwTwVR6_K0tj_MPAK7GsV1GncLn8gG4ppwO6EvYMVxi5hjBbTyKHViUaI_87795qGMwiqUp2BviA2m04DYvgyxCW0EiZ5C1XEjWfVpqsLC697OIisZGQStqXskNQv4EjKq3ab2nIc_oWYnfZKQ6h9czEmiBCUYm6C9SD7vLyK8eOlNPSRujTRMZAPUgIl-FEUV8ze0HHK1D64607JPw6XXJ2ULbzFjvxQR5du4Opg'),
              const SizedBox(width: 16),
              _buildEventCard('CHROME THEORY', 'June 12 • Warehouse District', 'Draft', const Color(0xFF2c2c2c), 'Pending Approval', 'https://lh3.googleusercontent.com/aida-public/AB6AXuD6uqKrj0inee6ifi5qyP9njHo9EGHsOXNxhVq41mrm9gVX8mefUtKcyOPBGxfUeVaWByf9BcyE46HG3U9DXmZ53qFRSAkej39wbZeI7xWpb6n4rRh8V3SYdhHBnffc52kWyNjzCep34txZdqhvfErJoIdM4TVAZB4BRX4MmKMh4rSU2qTyF-aFFurrydUuUk42BfDDaAOE5SHlfl-govKQpvUOOF3GXMPl77FqwSaXMEIVF3PEGclkD9PbMjCu7j3pxHHvTW2-Iey5'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventCard(String title, String subtitle, String status, Color statusColor, String stats, String imageUrl) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.2), BlendMode.darken)),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(16)),
                    child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Color(0xFFadaaaa), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(stats, style: const TextStyle(color: Color(0xFF00e3fd), fontSize: 14, fontWeight: FontWeight.bold)),
                    const Icon(Icons.more_horiz, color: Colors.white),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentBookings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('RECENT BOOKINGS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            Row(
              children: const [
                Icon(Icons.tune, color: Color(0xFF00e3fd)),
                SizedBox(width: 8),
                Icon(Icons.download, color: Color(0xFFadaaaa)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a1919),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              _buildBookingRow('Marcus Sterling', 'Neon Jungle • VIP Table', '\$450.00', 'Confirmed', 'https://lh3.googleusercontent.com/aida-public/AB6AXuCVpxeTk7_Z4DB9KnMEPZhzWAfYfd5nvHlNMFE4k9sM2dpoqRsarZjhMMPLSz81GkdmyHmEgSaQHxiLL26ctHHwZ7KNCQbInshDZTtHRREQWF_DcCqNAeJz1HQJl6u7-L2JGefJ8NryOJMy918-e5rku2gfLh81y1kWTwwUT7J3g4M2oQwm_6WpNo89EBo1AGi-7i0ykefLoAfGtnA1Yf4dCOdGrGYONjjE6EL_LfuZ1yq9eh4qCJ2Ky-HvkrhVFPnjjxSxFa3FxVbk'),
              const Divider(color: Color(0xFF262626), height: 1),
              _buildBookingRow('Elena Rodriguez', 'Neon Jungle • GA Ticket x2', '\$120.00', 'Confirmed', 'https://lh3.googleusercontent.com/aida-public/AB6AXuDyhFJsFX5MTo7t7n3tFtUAZ9CdNhQXx1oYc8Vmd84imoF7LrunA-PZ1zy9s3gTKFniGVAkhQSVaKsUwIT0L_KKOdqHlUle70bHIOz0GuLpjEUx_QQtHApLwT6IfBdAV2T1S-ZWrLIlzKCUbnIAAPFhdE6X5byxlOaigg5-TSJhCV_Y-cnzePk7-SPF335lluelEX7oOd75IOpGGkG-Nu2vTTwhVWtpFPD1T4BtDvzw4uN3U9p95g2GL8kUcDhBpWY_vGqGuanPTK4R'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBookingRow(String name, String details, String price, String status, String imageUrl) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(details.toUpperCase(), style: const TextStyle(color: Color(0xFFadaaaa), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text(status.toUpperCase(), style: const TextStyle(color: Color(0xFF00e3fd), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
        ],
      ),
    );
  }
}
