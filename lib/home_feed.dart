import 'package:flutter/material.dart';
import 'package:my_app/event_details.dart';
import 'package:my_app/profile.dart';
import 'package:my_app/ticket.dart';
import 'package:my_app/scan_entry.dart';

class HomeFeedScreen extends StatelessWidget {
  const HomeFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFFb6a0ff)),
          onPressed: () {},
        ),
        title: const Text(
          'AFTERDARK',
          style: TextStyle(
            color: Color(0xFFb6a0ff),
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: 2,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              backgroundColor: const Color(0xFFb6a0ff).withOpacity(0.3),
              child: const Icon(Icons.person, color: Colors.white),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Live Now', 'Tonight'),
            _buildFeaturedCard(context),
            const SizedBox(height: 24),
            _buildSectionHeader('Local Access', 'Near You'),
            _buildHorizontalList(),
            const SizedBox(height: 24),
            _buildSectionHeader('World Wide', 'Trending'),
            _buildTrendingFeed(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF2c2c2c).withOpacity(0.9),
        selectedItemColor: Colors.white,
        unselectedItemColor: const Color(0xFFadaaaa),
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 1) Navigator.push(context, MaterialPageRoute(builder: (context) => const TicketScreen()));
          if (index == 2) Navigator.push(context, MaterialPageRoute(builder: (context) => const ScanEntryScreen()));
          if (index == 3) Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.confirmation_number), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_2), label: 'Passes'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: const Color(0xFF00e3fd),
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  Widget _buildSectionHeader(String overline, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overline.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF00e3fd),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      height: 400,
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(20),
        image: const DecorationImage(
          image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuBwaGXczn-1Mfpn4hBMFcEYwZdy4SIoZrLX8WDqs5mkPzlve0lme-m7fUKW42FkAW7il0Wa_RmUXGp1zircqydvlfU4Xw3ewxe89GxnhSywzXWBy-kJOBxYOCa55B_5EUAu-RgNQGOeBVLDPutCz24R0Q55cMgSTp_6t6n1_6zJn3DTaPiBJKxuW6MEfxStOHnc7OoezTYzmgc1LTHgMaPTJ7Be99L7_zBaXe9KHLn0A4OnQxYIty50avWZWl9g7qTwGJ0m2nAxJAaq'), // Night club scene
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.8), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
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
            const SizedBox(height: 12),
            const Text('NEON VOID:\nVol. 4', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, height: 1.1)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule, color: Color(0xFF00e3fd), size: 16),
                const SizedBox(width: 4),
                const Text('22:00 - Late', style: TextStyle(color: Color(0xFFadaaaa), fontSize: 12)),
                const SizedBox(width: 16),
                const Icon(Icons.location_on, color: Color(0xFF00e3fd), size: 16),
                const SizedBox(width: 4),
                const Text('Soho, NYC', style: TextStyle(color: Color(0xFFadaaaa), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const EventDetailsScreen()));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7e51ff),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text('VIEW DETAILS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalList() {
    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        itemBuilder: (context, index) {
          return Container(
            width: 160,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(16),
                      image: const DecorationImage(
                        image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuAlQih0kKe1ziZ7eUYSSwBmfkvn8_BXrrCzRP5ohIdN-WDPrzUt8wBpdI8ZYb72YO7KehebU7ZRFTF1MBHtkJlbbYeBxHvzJe_FCYj7rJ-ElKuDSEfjLZL-dg-pZUjp93G6I2TK51Y0g9ziUgxS-A62_zywca8cYXBTy5q8iBvZaCivmZfgK2KNGm0Ip0uX6VTmxhGAp2QW0wy21DRbfIDksfd7NAsawaSp8VQh-DLTipzqh91i7OTjMCXFY8U4CvEiN03p9Ak_pzj1'),
                        fit: BoxFit.cover,
                      ),
                    ),
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.all(8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.favorite_border, color: Colors.white, size: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Synapse: Art & Bass', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Tomorrow • 20:00', style: TextStyle(color: Color(0xFFadaaaa), fontSize: 10)),
                    Text('\$25.00', style: TextStyle(color: Color(0xFF00e3fd), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrendingFeed() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1919),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFF7C4DFF), child: Icon(Icons.person, color: Colors.white)),
            title: const Text('Electric_Dreams', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('BERLIN, GERMANY', style: TextStyle(color: Color(0xFFadaaaa), fontSize: 10)),
            trailing: const Icon(Icons.more_vert, color: Color(0xFFadaaaa)),
          ),
          Container(
            height: 300,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuCDVHcEWxWKvHDS-LCFIFPX_b695h2EGOslTBsK7gMwzKC6SnjFHJhUX8OEBL6R3vuT2FZod1dbtmwx887Ec4hoxfq20vi4baY7zPookuRI3SgWRGCooTeKao_q9eTXZQtzJD0pkeJZIpAm_BcrRFfXb5vxqRFOOlotyixYw8-LvhqGWyxt5C05mvxpr38VGRZUQjCJnbsUR9oyYSOhfFGFwbWKZ6uuzCEl5oeqD7aPMTs8yIMIorPmWmXPI6hu5hkcmxmPJ3fiN8-o'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
             padding: const EdgeInsets.all(16.0),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Row(
                   children: [
                     const Icon(Icons.favorite_border, color: Color(0xFF00e3fd)),
                     const SizedBox(width: 16),
                     const Icon(Icons.chat_bubble_outline, color: Colors.white),
                     const SizedBox(width: 16),
                     const Icon(Icons.send, color: Colors.white),
                     const Spacer(),
                     const Icon(Icons.bookmark_border, color: Colors.white),
                   ],
                 ),
                 const SizedBox(height: 12),
                 const Text('TRANSCENDENCE 2024', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 4),
                 const Text(
                   'The biggest audiovisual experience of the year returns. Witness the convergence of sound and light at the Olympic Stadium.',
                   style: TextStyle(color: Color(0xFFadaaaa), fontSize: 12),
                 ),
                 const SizedBox(height: 16),
                 OutlinedButton(
                   onPressed: () {},
                   style: OutlinedButton.styleFrom(
                     side: const BorderSide(color: Color(0xFF484847)),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                   ),
                   child: const Center(child: Text('VIEW DETAILS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2))),
                 ),
               ],
             ),
          )
        ],
      ),
    );
  }
}
