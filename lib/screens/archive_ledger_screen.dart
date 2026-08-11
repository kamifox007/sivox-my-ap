import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/models/booking.dart';
import 'package:my_app/services/reporting_service.dart';
import 'package:printing/printing.dart';

class ArchiveLedgerScreen extends StatefulWidget {
  const ArchiveLedgerScreen({super.key});

  @override
  State<ArchiveLedgerScreen> createState() => _ArchiveLedgerScreenState();
}

class _ArchiveLedgerScreenState extends State<ArchiveLedgerScreen> {
  final _bookingService = BookingService();
  final _reporting = ReportingService();
  bool _isLoading = true;
  List<Booking> _archivedBookings = [];

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  Future<void> _loadArchive() async {
    setState(() => _isLoading = true);
    try {
      final bookings = await _bookingService.getUserBookings();
      if (mounted) {
        setState(() {
          // Filter: Past events or Used/Cancelled tickets
          _archivedBookings = bookings.where((b) {
            final isUsed = b.paymentStatus == 'used' || b.paymentStatus == 'cancelled';
            final eventDate = b.event?.dateTime;
            
            bool isPast = false;
            if (eventDate != null) {
              try {
                // Try parsing standard formats
                isPast = DateTime.parse(eventDate).isBefore(DateTime.now());
              } catch (_) {
                // If parsing fails (e.g. "Tonight • 22:00"), 
                // we'll check if it's been used or cancelled at least
              }
            }
            return isUsed || isPast;
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadReceipt(Booking b) async {
    if (b.event == null) return;
    setState(() => _isLoading = true);
    try {
      final pdfBytes = await _reporting.generateEventReport(
        eventId: b.eventId,
        userRole: 'attendee',
        eventTitle: b.event!.title,
        clubName: 'Sivox Archive',
      );
      await Printing.sharePdf(bytes: pdfBytes, filename: 'Sivox_Receipt_${b.event!.title}.pdf');
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('ARCHIVE'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 16, letterSpacing: 2)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : _archivedBookings.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _archivedBookings.length,
              itemBuilder: (context, index) => _archiveCard(_archivedBookings[index]),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text('no_history'.tr, style: const TextStyle(color: Colors.white24)),
        ],
      ),
    );
  }

  Widget _archiveCard(Booking b) {
    final e = b.event;
    if (e == null) return const SizedBox.shrink();
    
    final isCancelled = b.paymentStatus == 'cancelled';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isCancelled ? Colors.red.withValues(alpha: 0.1) : Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: e.imageUrl != null ? DecorationImage(image: NetworkImage(e.imageUrl!), fit: BoxFit.cover) : null,
              color: Colors.white10,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(e.dateTime ?? 'TBA', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                const SizedBox(height: 4),
                _statusChip(b.paymentStatus),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: AppTheme.primary, size: 20),
            onPressed: () => _downloadReceipt(b),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color c = Colors.white24;
    if (status == 'used') c = Colors.tealAccent;
    if (status == 'cancelled') c = Colors.redAccent;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(status.toUpperCase(), style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }
}
