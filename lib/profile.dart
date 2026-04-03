import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        title: const Text('PROFILE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            const CircleAvatar(
              radius: 60,
              backgroundImage: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuBKBDUkaZV0ofk1w0FLNTxMpalK3D_RpE3zTE17VkGJQHoXjpiQBFjhi5V89-SK6S9jQASp-ZaxUIHSCUX83DU1tnjvlYRPZ0WedQ9ebOZejUwWS7njg1iuhkql9zplHWeUbDmKSjvIbR9KeOCDR_DpbfVg7UxfUOCuaKo6PN6DzK5QryqQjI3SOgFIjcaHNmIsvsN3PSz4wGSl-3SpgK4nmbYJxJQJeWi3FGEVqkWDp3cwMAOU1vass2wRfSTvgj2rmj-uDQDqKwPD'),
            ),
            const SizedBox(height: 16),
            const Text('ALEX MERCER', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)),
            const Text('@alex_m', style: TextStyle(color: Color(0xFFb6a0ff), fontSize: 14)),
            const SizedBox(height: 32),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1a1919),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  _buildListTile(Icons.history, 'Past Events'),
                  const Divider(color: Color(0xFF262626), height: 1),
                  _buildListTile(Icons.payment, 'Payment Methods'),
                  const Divider(color: Color(0xFF262626), height: 1),
                  _buildListTile(Icons.notifications_none, 'Notifications'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFF7C4DFF).withOpacity(0.2), const Color(0xFF00e3fd).withOpacity(0.2)]),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.stadium, color: Color(0xFF00e3fd), size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Switch to Organizer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Manage your own events', style: TextStyle(color: Color(0xFFadaaaa), fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                ],
              ),
            ),
            const SizedBox(height: 40),
            TextButton(
              onPressed: () {},
              child: const Text('SIGN OUT', style: TextStyle(color: Color(0xFFff6e84), fontWeight: FontWeight.bold, letterSpacing: 2)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFadaaaa)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF565555), size: 16),
    );
  }
}
