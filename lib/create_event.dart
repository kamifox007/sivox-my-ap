import 'package:flutter/material.dart';

class CreateEventScreen extends StatelessWidget {
  const CreateEventScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E0E).withOpacity(0.8),
        title: const Text('CREATE EVENT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 16)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF767575), style: BorderStyle.solid),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.add_photo_alternate, size: 48, color: Color(0xFFadaaaa)),
                  SizedBox(height: 16),
                  Text('Upload Cover Image', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('1920x1080 recommended', style: TextStyle(color: Color(0xFFadaaaa), fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildTextField('Event Name', 'e.g. Neon Void Vol. 4'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _buildTextField('Date', 'MM/DD/YYYY', icon: Icons.calendar_today)),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField('Time', 'HH:MM AM/PM', icon: Icons.schedule)),
              ],
            ),
            const SizedBox(height: 24),
            _buildTextField('Location', 'Search venues...', icon: Icons.location_on),
            const SizedBox(height: 24),
            _buildTextField('Description', 'What is this event about?', maxLines: 4),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('PUBLISH EVENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, String hint, {IconData? icon, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Color(0xFFadaaaa), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 8),
        TextField(
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF565555)),
            prefixIcon: icon != null ? Icon(icon, color: const Color(0xFFb6a0ff)) : null,
            filled: true,
            fillColor: const Color(0xFF1a1919),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF7C4DFF))),
          ),
        ),
      ],
    );
  }
}
