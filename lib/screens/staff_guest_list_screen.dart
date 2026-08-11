import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/models/booking.dart';

class StaffGuestListScreen extends StatefulWidget {
  final String? organizerId;
  final String? eventId;
  const StaffGuestListScreen({super.key, this.organizerId, this.eventId});

  @override
  State<StaffGuestListScreen> createState() => _StaffGuestListScreenState();
}

class _StaffGuestListScreenState extends State<StaffGuestListScreen> {
  final _eventService = EventService();
  final _bookingService = BookingService();
  final _searchController = TextEditingController();
  
  List<Event> _events = [];
  Event? _selectedEvent;
  List<Booking> _bookings = [];
  List<Booking> _filteredBookings = [];
  bool _isLoading = true;
  bool _showGenerated = false; // NEW TRACKING

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    
    if (widget.eventId != null) {
      final event = await _eventService.getEventById(widget.eventId!);
      if (mounted) {
        setState(() {
          _selectedEvent = event;
          _events = event != null ? [event] : [];
          if (_selectedEvent != null) {
            _loadBookings();
          } else {
            _isLoading = false;
          }
        });
      }
      return;
    }

    final events = await _eventService.getOrganizerEvents(organizerId: widget.organizerId);
    if (mounted) {
      setState(() {
        _events = events;
        if (_events.isNotEmpty) {
          _selectedEvent = _events.first;
          _loadBookings();
        } else {
          _isLoading = false;
        }
      });
    }
  }

  Future<void> _loadBookings() async {
    if (_selectedEvent == null) return;
    setState(() => _isLoading = true);
    final bookings = await _bookingService.getBookingsForEvents([_selectedEvent!.id]);
    if (mounted) {
      setState(() {
        _bookings = bookings;
        _filteredBookings = bookings;
        _isLoading = false;
      });
    }
  }

  void _filterBookings() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredBookings = _bookings.where((b) {
        // FILTER BY TRACK FIRST
        if (_showGenerated && !b.isWalkin) return false;
        if (!_showGenerated && b.isWalkin) return false;

        final name = b.userName.toLowerCase();
        final phone = (b.guestPhone ?? '').toLowerCase();
        final serial = (b.walkinSerial ?? '').toLowerCase();
        return name.contains(query) || phone.contains(query) || serial.contains(query);
      }).toList();
    });
  }

  Future<void> _manualCheckIn(Booking booking) async {
    final success = await _bookingService.updateBookingStatus(booking.id, 'used');
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('checked_in_success'.tr), backgroundColor: AppTheme.primary),
      );
      _loadBookings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned(top: -50, right: -50, child: _aura(AppTheme.primary.withValues(alpha: 0.1))),
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              _buildFilterSection(),
              if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
              else if (_filteredBookings.isEmpty)
                _buildEmptyState()
              else
                _buildGuestList(),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aura(Color c) => Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: c, blurRadius: 100)]));

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      backgroundColor: Colors.transparent,
      pinned: true,
      title: Text('guest_list'.tr.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18, letterSpacing: 2)),
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18), onPressed: () => Navigator.pop(context)),
    );
  }

  Widget _buildFilterSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildEventSelector(),
            const SizedBox(height: 20),
            _buildTrackSelector(),
            const SizedBox(height: 20),
            _buildSearchBox(),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackSelector() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          _trackTab('RESERVED_TICKETS', !_showGenerated),
          _trackTab('GENERATED_PASSES', _showGenerated),
        ],
      ),
    );
  }

  Widget _trackTab(String label, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _showGenerated = label == 'GENERATED_PASSES');
          _filterBookings();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            label.tr.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(color: active ? AppTheme.primary : Colors.white24, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => _filterBookings(),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'search_guests'.tr,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildEventSelector() {
    if (_events.length <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Event>(
          value: _selectedEvent,
          dropdownColor: const Color(0xFF141414),
          isExpanded: true,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          items: _events.map((e) => DropdownMenuItem(value: e, child: Text(e.title))).toList(),
          onChanged: (v) {
            setState(() => _selectedEvent = v);
            _loadBookings();
          },
        ),
      ),
    );
  }

  Widget _buildGuestList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final booking = _filteredBookings[index];
          final used = booking.paymentStatus == 'used';
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: used ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white10)),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: used ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05), child: Icon(Icons.person_outline, color: used ? AppTheme.primary : Colors.white38)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(booking.userName.isEmpty ? 'Anonymous'.tr : booking.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      _buildTacticalSerial(booking),
                    ],
                  ),
                ),
                if (!used)
                  GestureDetector(
                    onTap: () => _manualCheckIn(booking),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(12)),
                      child: Text('check_in_manual'.tr, style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('already_used'.tr, style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          );
        }, childCount: _filteredBookings.length),
      ),
    );
  }


  Widget _buildTacticalSerial(Booking booking) {
    final serial = booking.qrCode.toUpperCase();
    Color prefixColor = Colors.white24;
    
    if (serial.startsWith('RES-')) prefixColor = AppTheme.primary;
    if (serial.startsWith('GEN-')) prefixColor = Colors.amber;
    if (serial.startsWith('TEST-')) prefixColor = Colors.purpleAccent;

    return Row(
      children: [
        Text(serial.split('-')[0], style: TextStyle(color: prefixColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
        Text(serial.substring(serial.indexOf('-')), style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_off_outlined, size: 48, color: Colors.white10),
            const SizedBox(height: 16),
            Text('no_bookings_found'.tr, style: const TextStyle(color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}
