import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/screens/staff_dashboard_screen.dart';
import 'package:my_app/services/reporting_service.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StaffEventSelector extends StatefulWidget {
  final String organizerId;
  final String organizerName;

  const StaffEventSelector({
    super.key, 
    required this.organizerId, 
    required this.organizerName
  });

  @override
  State<StaffEventSelector> createState() => _StaffEventSelectorState();
}

class _StaffEventSelectorState extends State<StaffEventSelector> {
  final _eventService = EventService();
  final _reporting = ReportingService();
  bool _isLoading = true;
  List<Event> _events = [];

  Future<void> _downloadReport(Event e) async {
    setState(() => _isLoading = true);
    try {
      final role = Supabase.instance.client.auth.currentUser?.userMetadata?['role'] ?? 'role_security';
      final pdfBytes = await _reporting.generateEventReport(
        eventId: e.id,
        userRole: role,
        eventTitle: e.title,
        clubName: widget.organizerName,
      );
      await Printing.sharePdf(bytes: pdfBytes, filename: 'Sivox_Record_${e.title}.pdf');
    } catch (_) {}
    setState(() => _isLoading = false);
  }

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
        _isLoading = false;
      });
    } catch (e) {
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
        title: Text(widget.organizerName.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CHOOSE EVENT'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(color: AppTheme.primary, letterSpacing: 4)),
                const SizedBox(height: 8),
                Text('select_event_to_manage'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 24)),
                const SizedBox(height: 32),
                Expanded(
                  child: _events.isEmpty
                    ? Center(child: Text('no_active_events'.tr, style: const TextStyle(color: Colors.white24)))
                    : ListView.builder(
                        itemCount: _events.length,
                        itemBuilder: (context, index) => _eventCard(_events[index]),
                      ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _eventCard(Event e) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StaffDashboard(
        organizerId: widget.organizerId,
        currentEventId: e.id,
      ))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10),
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
                  Text(e.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(e.dateTime ?? '', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white38, size: 20),
              onPressed: () => _downloadReport(e),
              tooltip: 'download_record'.tr,
            ),
          ],
        ),
      ),
    );
  }
}
