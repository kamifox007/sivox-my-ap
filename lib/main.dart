import 'package:flutter/material.dart';
import 'package:my_app/home_feed.dart';
import 'package:my_app/organizer_dashboard.dart';

void main() {
  runApp(const NocturnalApp());
}

class NocturnalApp extends StatelessWidget {
  const NocturnalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nocturnal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E0E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C4DFF),
          surface: Color(0xFF131313),
          onSurface: Colors.white,
          onSurfaceVariant: Color(0xFFADAAAA),
        ),
        fontFamily: 'Roboto',
      ),
      home: const UnifiedSignUpScreen(),
    );
  }
}

class UnifiedSignUpScreen extends StatefulWidget {
  const UnifiedSignUpScreen({super.key});

  @override
  State<UnifiedSignUpScreen> createState() => _UnifiedSignUpScreenState();
}

class _UnifiedSignUpScreenState extends State<UnifiedSignUpScreen> {
  String selectedRole = 'attendee';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 80,
        leading: TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.arrow_back, color: Color(0xFF7C4DFF), size: 18),
          label: const Text(
            'BACK',
            style: TextStyle(fontSize: 10, color: Color(0xFFADAAAA), fontWeight: FontWeight.bold),
          ),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
        title: const Text(
          'NOCTURNAL',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18),
        ),
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color(0xFF0E0E0E),
              Color(0xCC0E0E0E),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF262626).withOpacity(0.6),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Join the Pulse.',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create an account to access exclusive nightlife events and curated club lists.',
                      style: TextStyle(color: Color(0xFFADAAAA), fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    _buildTextField('Full Name', Icons.person, 'John Doe'),
                    const SizedBox(height: 16),
                    _buildTextField('Email Address', Icons.alternate_email, 'name@domain.com'),
                    const SizedBox(height: 16),
                    const Text(
                      'I AM A...',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFADAAAA), letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildRoleCard('attendee', 'Attendee', 'I want to attend events', Icons.confirmation_number)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildRoleCard('organizer', 'Organizer', 'I want to host events', Icons.stadium)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        // Dummy Navigation
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => selectedRole == 'organizer' 
                                ? const OrganizerDashboardScreen()
                                : const HomeFeedScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C4DFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 10,
                        shadowColor: const Color(0xFF7C4DFF).withOpacity(0.5),
                      ),
                      child: const Text('ENTER WITHOUT PASSWORD', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('OR JOIN WITH', style: TextStyle(fontSize: 10, color: Color(0xFF767575), letterSpacing: 1.2)),
                        ),
                        Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.g_mobiledata, color: Colors.white),
                            label: const Text('Google', style: TextStyle(color: Colors.white)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.white.withOpacity(0.1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.apple, color: Colors.white),
                            label: const Text('Apple', style: TextStyle(color: Colors.white)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.white.withOpacity(0.1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: RichText(
                        text: const TextSpan(
                          text: 'Already a member? ',
                          style: TextStyle(color: Color(0xFFADAAAA), fontSize: 13),
                          children: [
                            TextSpan(text: 'Sign In', style: TextStyle(color: Color(0xFF7C4DFF), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, IconData icon, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
          child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFADAAAA), letterSpacing: 1.5)),
        ),
        TextField(
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF767575)),
            prefixIcon: Icon(icon, color: const Color(0xFFADAAAA)),
            filled: true,
            fillColor: const Color(0xFF262626).withOpacity(0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.05))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.05))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF7C4DFF))),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard(String value, String title, String subtitle, IconData icon) {
    bool isSelected = selectedRole == value;
    return GestureDetector(
      onTap: () => setState(() => selectedRole = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7C4DFF).withOpacity(0.1) : const Color(0xFF262626).withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF7C4DFF) : Colors.white.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF7C4DFF).withOpacity(0.3), blurRadius: 10)] : [],
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF7C4DFF), size: 24),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 9, color: Color(0xFFADAAAA)), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class DummyScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  
  const DummyScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF131313),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: const Color(0xFF7C4DFF)),
            const SizedBox(height: 20),
            Text(
              'Welcome to the\n$title!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF262626),
                foregroundColor: Colors.white,
              ),
              child: const Text('GO BACK'),
            ),
          ],
        ),
      ),
    );
  }
}
