import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/screens/create_event.dart';
import 'package:my_app/screens/event_manage_details.dart';
import 'package:my_app/services/translation_service.dart';

class MyEventsScreen extends StatefulWidget {
  final String organizerId;

  const MyEventsScreen({super.key, required this.organizerId});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen> {
  final _eventService = EventService();
  bool _isLoading = true;
  List<Event> _events = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final events = await _eventService.getOrganizerEvents(organizerId: widget.organizerId);
      setState(() {
        _events = events;
      });
    } catch (e) {
      debugPrint('Error loading events: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'MY_EVENTS'.tr,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Create Event Button at the top
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreateEventScreen(clubId: widget.organizerId, businessType: 'club'),
                        ),
                      ).then((_) => _loadEvents());
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.7)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline_rounded, color: Colors.black, size: 24),
                          SizedBox(width: 12),
                          Text(
                            'إنشاء فعالية جديدة',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Events List
                  Expanded(
                    child: _events.isEmpty
                        ? Center(
                            child: Text(
                              'لا توجد فعاليات منشأة بعد',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _events.length,
                            itemBuilder: (context, index) {
                              final event = _events[index];
                              return _buildEventCard(event);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEventCard(Event event) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventManageDetailsScreen(event: event),
          ),
        ).then((_) => _loadEvents());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            // Event Image Placeholder or Actual Image
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.event, color: AppTheme.primary, size: 30),
            ),
            const SizedBox(width: 16),
            
            // Event Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.dateTime != null ? event.dateTime!.substring(0, 10) : 'No Date',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                  ),
                ],
              ),
            ),
            
            // Arrow Icon
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}
