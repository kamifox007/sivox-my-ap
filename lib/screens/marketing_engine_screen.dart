import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/services/event_service.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/services/audit_service.dart';

class MarketingEngineScreen extends StatefulWidget {
  final String? clubId;
  final String? initialEventId;
  const MarketingEngineScreen({super.key, this.clubId, this.initialEventId});

  @override
  State<MarketingEngineScreen> createState() => _MarketingEngineScreenState();
}

class _MarketingEngineScreenState extends State<MarketingEngineScreen> {
  bool _remindersEnabled = true;
  bool _welcomeAlerts = true;
  int _eventCount = 0;


  int get _level => (_eventCount >= 20) ? 3 : (_eventCount >= 10 ? 2 : 1);

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchEventCount();
  }

  Future<void> _fetchEventCount() async {
    final userId = widget.clubId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final res = await Supabase.instance.client
          .from('events')
          .select('id')
          .eq('organizer_id', userId)
          .eq('is_archived', false);
      setState(() {
        _eventCount = (res as List).length;
      });
    } catch (e) {
      // fetch failed silently
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _remindersEnabled = prefs.getBool('reminders_enabled') ?? true;
      _welcomeAlerts = prefs.getBool('welcome_alerts') ?? true;
    });
  }

  Future<void> _saveSetting(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
  }

  void _showHelp(String title, String desc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primary, size: 32),
            const SizedBox(height: 16),
            Text(title.toUpperCase(), style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showMegaphoneDeployer() async {
    final userId = widget.clubId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    if (widget.initialEventId != null) {
      // Auto-fetch the event and deploy
      final eMap = await Supabase.instance.client.from('events').select().eq('id', widget.initialEventId!).single();
      final e = Event.fromMap(eMap);
      await NotificationService().notifyFollowers(
        organizerId: userId,
        title: 'new_event_title'.trArgs([e.title]),
        body: 'new_event_body'.trArgs([e.venue ?? 'Our Club']),
        type: 'event',
        metadata: {'event_id': e.id},
      );
      await AuditService().logAction(
        actionType: 'MARKETING_BROADCAST',
        description: 'Broadcasted event "${e.title}" to all followers.',
        relatedEventId: e.id,
      );
      _showToast('BROADCAST_SUCCESS'.tr);
      return;
    }

    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF141414),
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CLUB_MEGAPHONE'.tr.toUpperCase(),
                      style: AppTheme.labelStyle.copyWith(
                        color: AppTheme.primary,
                        letterSpacing: 2,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white24),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // SEARCH BAR
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: TextField(
                    onChanged: (v) => setModalState(() => searchQuery = v),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'SEARCH_EVENT'.tr,
                      hintStyle: const TextStyle(color: Colors.white24),
                      border: InputBorder.none,
                      icon: const Icon(Icons.search, color: AppTheme.primary, size: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: FutureBuilder<List<Event>>(
                    future: EventService().getOrganizerEvents(organizerId: userId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                      final list = snapshot.data!.where((e) => e.title.toLowerCase().contains(searchQuery.toLowerCase())).toList();
                      
                      return ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final e = list[i];
                          return ListTile(
                            onTap: () async {
                                await NotificationService().notifyFollowers(
                                  organizerId: userId,
                                  title: 'new_event_title'.trArgs([e.title]),
                                  body: 'new_event_body'.trArgs([e.venue ?? 'Our Club']),
                                  type: 'event',
                                  metadata: {'event_id': e.id},
                                );
                                await AuditService().logAction(
                                  actionType: 'MARKETING_BROADCAST',
                                  description: 'Broadcasted event "${e.title}" to all followers.',
                                  relatedEventId: e.id,
                                );
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                              if (mounted) {
                                _showToast('BROADCAST_SUCCESS'.tr);
                              }
                            },
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            leading: Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                              child: e.imageUrl != null 
                                ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(e.imageUrl!, fit: BoxFit.cover))
                                : const Icon(Icons.event, color: AppTheme.primary, size: 20),
                            ),
                            title: Text(e.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(e.dateTime ?? 'TBA', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                            trailing: const Icon(Icons.send_rounded, color: AppTheme.primary, size: 18),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  void _showScarcityBooster() async {
    final userId = widget.clubId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    if (widget.initialEventId != null) {
      final eMap = await Supabase.instance.client.from('events').select().eq('id', widget.initialEventId!).single();
      final e = Event.fromMap(eMap);
      final newVal = !e.isUrgent;
      await EventService().updateEvent(e.id, {'is_urgent': newVal});
      await AuditService().logAction(
        actionType: 'MARKETING_URGENCY',
        description: '${newVal ? 'Enabled' : 'Disabled'} urgency hype for "${e.title}".',
        relatedEventId: e.id,
      );
      _showToast(newVal ? 'Hype deployed for ${e.title}!' : 'Urgency badge removed.');
      return;
    }

    String searchQuery = "";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF141414),
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'URGENCY_BOOSTER'.tr.toUpperCase(),
                      style: AppTheme.labelStyle.copyWith(
                        color: AppTheme.secondary,
                        letterSpacing: 2,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white24),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // SEARCH BAR
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: TextField(
                    onChanged: (v) => setModalState(() => searchQuery = v),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'SEARCH_EVENT'.tr,
                      hintStyle: const TextStyle(color: Colors.white24),
                      border: InputBorder.none,
                      icon: const Icon(Icons.search, color: AppTheme.secondary, size: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: FutureBuilder<List<Event>>(
                    future: EventService().getOrganizerEvents(organizerId: userId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppTheme.secondary));
                      final list = snapshot.data!.where((e) => e.title.toLowerCase().contains(searchQuery.toLowerCase())).toList();
                      
                      return ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final e = list[i];
                          return ListTile(
                            onTap: () async {
                              final newVal = !e.isUrgent;
                              await EventService().updateEvent(e.id, {'is_urgent': newVal});
                              await AuditService().logAction(
                                actionType: 'MARKETING_URGENCY',
                                description: '${newVal ? 'Enabled' : 'Disabled'} urgency hype for "${e.title}".',
                                relatedEventId: e.id,
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                              if (mounted) {
                                _showToast(newVal ? 'Hype deployed for ${e.title}!' : 'Urgency badge removed.');
                              }
                            },
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            leading: Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                              child: e.imageUrl != null 
                                ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(e.imageUrl!, fit: BoxFit.cover))
                                : const Icon(Icons.event, color: AppTheme.secondary, size: 20),
                            ),
                            title: Text(e.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(e.dateTime ?? 'TBA', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                            trailing: Icon(
                              e.isUrgent ? Icons.local_fire_department_rounded : Icons.add_circle_outline_rounded,
                              color: e.isUrgent ? Colors.redAccent : Colors.white24,
                              size: 20,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showPulseDeployer() async {
    final userId =
        widget.clubId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    if (widget.initialEventId != null) {
      final eMap = await Supabase.instance.client.from('events').select('id, title').eq('id', widget.initialEventId!).single();
      _confirmPulse(eMap['title'], eMap['id'], userId);
      return;
    }

    String searchQuery = "";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF141414),
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DEPLOY_TACTICAL_PULSE'.tr.toUpperCase(),
                      style: AppTheme.labelStyle.copyWith(
                        color: AppTheme.primary,
                        letterSpacing: 2,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white24),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // SEARCH BAR
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: TextField(
                    onChanged: (v) => setModalState(() => searchQuery = v),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'SEARCH_EVENT'.tr,
                      hintStyle: const TextStyle(color: Colors.white24),
                      border: InputBorder.none,
                      icon: const Icon(Icons.search, color: AppTheme.primary, size: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'SELECT_EVENT'.tr,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: Supabase.instance.client
                        .from('events')
                        .select('id, title, image_url, date_time')
                        .eq('organizer_id', userId)
                        .eq('is_archived', false)
                        .order('date_time', ascending: false)
                        .limit(20),
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                      }
                      
                      final allEvents = snap.data ?? [];
                      final filteredEvents = allEvents.where((e) {
                         return e['title'].toString().toLowerCase().contains(searchQuery.toLowerCase());
                      }).toList();

                      if (filteredEvents.isEmpty) {
                        return Center(
                          child: Text(
                            'NO_EVENTS_FOUND'.tr,
                            style: const TextStyle(color: Colors.white24, fontSize: 12),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: filteredEvents.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (ctx, index) {
                          final e = filteredEvents[index];
                          final hasImg = e['image_url'] != null;
                          
                          return ListTile(
                            onTap: () => _confirmPulse(e['title'], e['id'], userId),
                            contentPadding: const EdgeInsets.all(12),
                            tileColor: Colors.white.withValues(alpha: 0.02),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                              child: hasImg 
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(e['image_url'], fit: BoxFit.cover),
                                  )
                                : const Icon(Icons.event, color: AppTheme.primary, size: 20),
                            ),
                            title: Text(
                              e['title'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              e['date_time'] ?? 'TBA',
                              style: const TextStyle(color: Colors.white24, fontSize: 10),
                            ),
                            trailing: const Icon(
                              Icons.bolt_rounded,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  void _confirmPulse(String title, String id, String uId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'SET_PULSE_POWER'.tr,
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pulsePowerBtn('10%', title, id, uId),
            _pulsePowerBtn('20%', title, id, uId),
            _pulsePowerBtn('50%', title, id, uId),
          ],
        ),
      ),
    );
  }

  Widget _pulsePowerBtn(String amount, String title, String id, String uId) {
    return ListTile(
      title: Text(
        amount,
        style: const TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
      onTap: () async {
        final percentage = double.tryParse(amount.replaceAll('%', '')) ?? 0.0;
        await EventService().updateEvent(id, {'global_discount': percentage});
        
        await NotificationService().notifyDiscountFlash(
          organizerId: uId,
          eventTitle: title,
          discountAmount: amount,
        );
        await AuditService().logAction(
          actionType: 'MARKETING_FLASH_PULSE',
          description: 'Deployed $amount Flash Pulse for event "$title".',
          relatedEventId: id,
        );
        if (mounted) {
          Navigator.pop(context);
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('PULSE_DEPLOYED_SUCCESS'.tr)));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            backgroundColor: AppTheme.background,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MARKETING_CENTER'.tr.toUpperCase(),
                    style: AppTheme.headlineStyle.copyWith(
                      fontSize: 14,
                      letterSpacing: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showHelp('MARKETING_CENTER'.tr, 'HELPER_MARKETING_ENGINE_DESC'.tr),
                    child: Tooltip(
                      message: 'MORE_INFO'.tr,
                      child: const Icon(Icons.help_outline_rounded, color: Colors.white24, size: 10),
                    ),
                  ),
                ],
              ),
              centerTitle: true,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.initialEventId != null) ...[
                    _buildTargetEventHero(),
                    const SizedBox(height: 32),
                  ],
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('GROWTH_TOOLS'.tr),
                      GestureDetector(
                        onTap: () => _showHelp('GROWTH_TOOLS'.tr, 'HELPER_MARKETING_ENGINE_DESC'.tr),
                        child: Icon(Icons.help_outline_rounded, color: Colors.white.withValues(alpha: 0.05), size: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildPulseCard(),
                  const SizedBox(height: 20),
                  _buildScarcityCard(),
                  const SizedBox(height: 20),
                  _buildMegaphoneCard(),
                  
                  const SizedBox(height: 48),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('AUTOMATION'.tr),
                      GestureDetector(
                        onTap: () => _showHelp('AUTOMATION'.tr, 'HELPER_AUTOMATION_DESC'.tr),
                        child: Icon(Icons.help_outline_rounded, color: Colors.white.withValues(alpha: 0.05), size: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildToggleTile(
                    Icons.notifications_active_rounded,
                    'EVENT_PULSE'.tr,
                    'REMINDERS_DESC'.tr,
                    _remindersEnabled,
                    (v) {
                      setState(() => _remindersEnabled = v);
                      _saveSetting('reminders_enabled', v);
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildToggleTile(
                    Icons.celebration_rounded,
                    'WELCOME_ALERTS'.tr,
                    'WELCOME_DESC'.tr,
                    _welcomeAlerts,
                    (v) {
                      setState(() => _welcomeAlerts = v);
                      _saveSetting('welcome_alerts', v);
                    },
                  ),
                  
                  const SizedBox(height: 48),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('LOYALTY'.tr),
                      GestureDetector(
                        onTap: () => _showHelp('LOYALTY'.tr, 'FOLLOWER_LOYALTY_DESC'.tr),
                        child: Icon(Icons.help_outline_rounded, color: Colors.white.withValues(alpha: 0.05), size: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildLoyaltyCard(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetEventHero() {
    return FutureBuilder<Map<String, dynamic>>(
      future: Supabase.instance.client
          .from('events')
          .select('id, title, image_url, venue, date_time')
          .eq('id', widget.initialEventId!)
          .single(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final e = snap.data!;
        final hasImg = e['image_url'] != null;
        
        return Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            image: hasImg ? DecorationImage(image: NetworkImage(e['image_url']), fit: BoxFit.cover, opacity: 0.4) : null,
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
          ),
          child: Stack(
            children: [
              // Gradient Overlay
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(8)),
                      child: Text('CURRENT_TARGET'.tr.toUpperCase(), style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                    const SizedBox(height: 12),
                    Text(e['title'] ?? 'Event', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text('${e['venue']} â€¢ ${e['date_time']}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: AppTheme.labelStyle.copyWith(
        letterSpacing: 3,
        fontSize: 10,
        color: Colors.white24,
      ),
    );
  }

  Widget _buildPulseCard() {
    bool isLevelLocked = _level < 2;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isLevelLocked ? Colors.white10 : Colors.white.withValues(alpha: 0.05)),
      ),
      child: InkWell(
        onTap: () {
          if (isLevelLocked) _showTestBypassToast(2);
          _showPulseDeployer();
        },
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.bolt_rounded, color: Colors.amber, size: 28),
                  ),
                  if (isLevelLocked)
                    Positioned(bottom: 0, right: 0, child: Icon(Icons.lock_rounded, color: Colors.amber.withValues(alpha: 0.5), size: 16)),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('FLASH_PULSE'.tr.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                        if (isLevelLocked) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                            child: const Text('LVL 2', style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('FLASH_PULSE_DESC'.tr, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  void _showTestBypassToast(int req) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.primary,
        content: Text('TEST MODE: Bypassing Level $req Requirement', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      )
    );
  }

  Widget _buildScarcityCard() {
    bool isLevelLocked = _level < 2;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isLevelLocked ? Colors.white10 : Colors.white.withValues(alpha: 0.05)),
      ),
      child: InkWell(
        onTap: () {
          if (isLevelLocked) _showTestBypassToast(2);
          _showScarcityBooster();
        },
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.local_fire_department_rounded, color: Colors.redAccent, size: 28),
                  ),
                  if (isLevelLocked)
                    Positioned(bottom: 0, right: 0, child: Icon(Icons.lock_rounded, color: Colors.redAccent.withValues(alpha: 0.5), size: 16)),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('URGENCY_BOOSTER'.tr.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                        if (isLevelLocked) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                            child: const Text('LVL 2', style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('SCARCITY_HYPE_DESC'.tr, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMegaphoneCard() {
    bool isLevelLocked = _level < 3;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isLevelLocked ? Colors.white10 : Colors.white.withValues(alpha: 0.05)),
      ),
      child: InkWell(
        onTap: () {
          if (isLevelLocked) _showTestBypassToast(3);
          _showMegaphoneDeployer();
        },
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.campaign_rounded, color: AppTheme.primary, size: 28),
                  ),
                  if (isLevelLocked)
                    Positioned(bottom: 0, right: 0, child: Icon(Icons.lock_rounded, color: AppTheme.primary.withValues(alpha: 0.5), size: 16)),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('CLUB_MEGAPHONE'.tr.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                        if (isLevelLocked) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                            child: const Text('LVL 3', style: TextStyle(color: AppTheme.primary, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('MEGAPHONE_DESC'.tr, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleTile(IconData icon, String title, String subtitle, bool val, Function(bool) onChanged) {
    bool isLevelLocked = _level < 2;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isLevelLocked ? Colors.white10 : Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: isLevelLocked ? Colors.white10 : Colors.white38, size: 20),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: TextStyle(color: isLevelLocked ? Colors.white24 : Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    if (isLevelLocked) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(4)),
                        child: const Text('LVL 2', style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white24, fontSize: 10)),
              ],
            ),
          ),
          Switch(
            value: val,
            onChanged: (v) {
              if (isLevelLocked) _showTestBypassToast(2);
              onChanged(v);
            },
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildLoyaltyCard() {
    bool isLevelLocked = _level < 3;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isLevelLocked ? Colors.white.withValues(alpha: 0.02) : AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isLevelLocked ? Colors.white10 : AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stars_rounded, color: isLevelLocked ? Colors.white24 : AppTheme.primary, size: 20),
              const SizedBox(width: 12),
              Text('LOYALTY_PROGRAM'.tr.toUpperCase(), style: TextStyle(color: isLevelLocked ? Colors.white24 : AppTheme.primary, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
              const Spacer(),
              if (isLevelLocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Text('LVL 3 REQ', style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w900)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text('ACTIVE'.tr, style: const TextStyle(color: AppTheme.primary, fontSize: 8, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('FOLLOWER_LOYALTY_DESC'.tr, style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.5)),
          if (isLevelLocked) ...[
             const SizedBox(height: 16),
             Text('TEST MODE: Level 3 feature visible for preview.', style: TextStyle(color: AppTheme.primary.withValues(alpha: 0.5), fontSize: 9, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }


}
