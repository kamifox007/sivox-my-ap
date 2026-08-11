import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/models/booking.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:my_app/screens/ticket.dart';
import 'package:my_app/models/event.dart';
import 'package:url_launcher/url_launcher.dart';

class TicketsListScreen extends StatefulWidget {
  const TicketsListScreen({super.key});

  @override
  State<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends State<TicketsListScreen> {
  final _bookingService = BookingService();
  List<Booking>? _bookings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      final res = await _bookingService.getUserBookings();
      if (mounted) {
        setState(() {
          _bookings = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('passes'.tr.toUpperCase(), style: AppTheme.labelStyle.copyWith(letterSpacing: 2)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: TabBar(
                  indicator: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    Tab(text: 'active'.tr.toUpperCase()),
                    Tab(text: 'history'.tr.toUpperCase()),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _fetch,
          color: AppTheme.primary,
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _bookings == null || _bookings!.isEmpty
              ? _buildEmpty()
              : TabBarView(
                  children: [
                    _buildFilteredList('active'),
                    _buildFilteredList('history'),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.confirmation_num_outlined, color: Colors.white10, size: 80),
              const SizedBox(height: 24),
              Text('no_tickets_found'.tr, style: const TextStyle(color: Colors.white24)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilteredList(String type) {
    if (_bookings == null) {
      return const SizedBox.shrink();
    }
    
    final list = _bookings!.where((b) {
      final isUsed = b.paymentStatus == 'used';
      final isLive = _isEventLive(b);
      
      if (type == 'active') {
        return b.paymentStatus == 'confirmed' || b.paymentStatus == 'pending_confirmation' || (isUsed && isLive);
      } else {
        return b.paymentStatus == 'archived' || (isUsed && !isLive) || b.paymentStatus == 'cancelled';
      }
    }).toList();

    if (list.isEmpty) {
      return Center(child: Text(type == 'active' ? 'no_active_tickets'.tr : 'no_archived_tickets'.tr, style: const TextStyle(color: Colors.white10, fontSize: 12)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final b = list[index];
        final event = b.event;
        final isCancelled = b.paymentStatus == 'cancelled';
        final isUsed = b.paymentStatus == 'used';
        
        final opacity = (isCancelled || (isUsed && !_isEventLive(b))) ? 0.5 : 1.0;
        
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 400 + (index * 60)),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, val, child) {
            return Transform.translate(
              offset: Offset(0, 30 * (1 - val)),
              child: Opacity(opacity: val * opacity, child: child),
            );
          },
          child: GestureDetector(
            onTap: isCancelled ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => TicketScreen(booking: b))).then((_) => _fetch()),
            child: Hero(
              tag: 'hero_pass_${b.id}',
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: isUsed ? Colors.white12 : Colors.white.withValues(alpha: 0.08)),
                  boxShadow: [
                    if (!isUsed) BoxShadow(color: AppTheme.primary.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 110,
                          decoration: BoxDecoration(
                            image: event?.imageUrl != null 
                              ? DecorationImage(
                                  image: NetworkImage(event!.imageUrl!), 
                                  fit: BoxFit.cover,
                                  colorFilter: isUsed ? const ColorFilter.mode(Colors.grey, BlendMode.saturation) : null,
                                )
                              : null,
                            color: Colors.white10,
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.4)],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _buildItemDetails(b, isUsed, event)),
                        Container(
                          width: 40,
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1, style: BorderStyle.solid)),
                          ),
                          child: RotatedBox(
                            quarterTurns: 1,
                            child: Center(
                              child: Text(
                                'PASS #${b.id.substring(0, 4).toUpperCase()}',
                                style: TextStyle(color: Colors.white10, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2),
                              ),
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
      },
    );
  }

  Widget _buildItemDetails(Booking b, bool isUsed, Event? event) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(event?.title ?? 'Event', style: TextStyle(color: isUsed ? Colors.white38 : Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (b.paymentStatus == 'pending_confirmation')
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.call, color: AppTheme.secondary, size: 18),
                  onPressed: () => launchUrl(Uri.parse('tel:${event?.contactNumber ?? ""}'))
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(event?.dateTime ?? '', style: const TextStyle(color: Colors.white10, fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statusChip(b.paymentStatus),
              if (event != null) 
                Text(
                  LocalizationService.formatPrice(event.price - b.discountAmount, event.countryCode),
                  style: TextStyle(color: isUsed ? Colors.white10 : AppTheme.secondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isEventLive(Booking b) {
    if (b.event?.dateTime == null) return true;
    try {
      final timeMatch = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(b.event!.dateTime!);
      if (timeMatch == null) return true;
      final hour = int.parse(timeMatch.group(1)!);
      final minute = int.parse(timeMatch.group(2)!);
      final now = DateTime.now();
      final eventTime = DateTime(now.year, now.month, now.day, hour, minute);
      final expiryTime = eventTime.add(const Duration(hours: 8));
      return now.isBefore(expiryTime);
    } catch (e) {
      return true;
    }
  }

  Widget _statusChip(String status) {
    Color color = Colors.amber;
    if (status == 'confirmed') color = AppTheme.primary;
    if (status == 'pending_confirmation') color = Colors.orangeAccent;
    if (status == 'used') color = Colors.blueAccent;
    if (status == 'cancelled') color = Colors.redAccent;
    if (status == 'archived') color = Colors.white24;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15), 
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        status.tr.toUpperCase(), 
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)
      ),
    );
  }
}
