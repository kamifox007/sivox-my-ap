import 'package:flutter/material.dart';

class ScanEntryScreen extends StatelessWidget {
  const ScanEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SCAN TICKET',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 40),
          const Text(
            'Align QR code within the frame',
            style: TextStyle(color: Color(0xFFadaaaa), fontSize: 14),
          ),
          const SizedBox(height: 40),
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFb6a0ff), width: 2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Icon(Icons.qr_code_scanner, size: 100, color: const Color(0xFFb6a0ff).withValues(alpha: 0.5)),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        boxShadow: [BoxShadow(color: Color(0xFF00e3fd), blurRadius: 10, spreadRadius: 2)],
                        color: Color(0xFF00e3fd),
                      ),
                    ),
                  ), // Scanning laser simulation
                ],
              ),
            ),
          ),
          const SizedBox(height: 60),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(Icons.flash_on, 'Flash'),
                _buildActionButton(Icons.history, 'History'),
                _buildActionButton(Icons.keyboard, 'Manual'),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF131313),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('RECENT SCANS', style: TextStyle(color: Color(0xFF00e3fd), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 16),
                _buildScanResult('Alex Mercer', 'VIP Access', true),
                const Divider(color: Color(0xFF262626)),
                _buildScanResult('Jordan Lee', 'General', false),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF262626),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Color(0xFFadaaaa), fontSize: 12)),
      ],
    );
  }

  Widget _buildScanResult(String name, String type, bool success) {
    return Row(
      children: [
        Icon(
          success ? Icons.check_circle : Icons.cancel,
          color: success ? const Color(0xFF00e3fd) : const Color(0xFFff6e84),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(type, style: const TextStyle(color: Color(0xFFadaaaa), fontSize: 12)),
          ],
        ),
        const Spacer(),
        Text(
          success ? 'Admitted' : 'Invalid',
          style: TextStyle(
            color: success ? const Color(0xFF00e3fd) : const Color(0xFFff6e84),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
