import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/booking.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/services/event_service.dart';

class OrganizerActivityScreen extends StatefulWidget {
  const OrganizerActivityScreen({super.key});

  @override
  State<OrganizerActivityScreen> createState() => _OrganizerActivityScreenState();
}

class _OrganizerActivityScreenState extends State<OrganizerActivityScreen> {
  final _bookingService = BookingService();
  final _eventService = EventService();
  bool _isLoading = true;
  List<Booking> _activities = [];

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    setState(() => _isLoading = true);
    try {
      final events = await _eventService.getOrganizerEvents();
      final eventIds = events.map((e) => e.id).toList();
      if (eventIds.isNotEmpty) {
        final bookings = await _bookingService.getBookingsForEvents(eventIds);
        // Special sorting or filtering can be done here for recent changes
        setState(() => _activities = bookings);
      }
      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('LIVE UPDATES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2)),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh, color: AppTheme.primary), onPressed: _loadActivity)],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : _activities.isEmpty
            ? _buildEmpty()
            : _buildActivityList(),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.notifications_none, size: 64, color: Colors.white10),
      const SizedBox(height: 16),
      const Text('No recent modifications or cancellations.', style: TextStyle(color: Colors.white24)),
    ]));
  }

  Widget _buildActivityList() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _activities.length,
      itemBuilder: (context, index) => _buildActivityTile(_activities[index]),
    );
  }

  Widget _buildActivityTile(Booking b) {
    // Logic to determine if it's a cancellation or modification for display
    final bool isCancelled = b.paymentStatus == 'cancelled';
    final Color accentColor = isCancelled ? Colors.redAccent : AppTheme.secondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(isCancelled ? Icons.cancel_outlined : Icons.sync_problem_outlined, color: accentColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(b.userName.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(isCancelled ? 'CANCELLED' : 'MODIFIED', style: TextStyle(color: accentColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(b.event?.title ?? 'Unknown Event', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    isCancelled 
                      ? 'The guest has released their spot.' 
                      : 'Updated requirement: ${b.numGuests} guests attending.',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
