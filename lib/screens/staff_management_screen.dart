import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/screens/vetting_hub_screen.dart';

class StaffMember {
  final String id; // Assignment ID
  final String userId; // Actual User ID
  final String name;
  final String? phoneNumber;
  final String role;
  final String status;
  final Map<String, dynamic> permissions;

  StaffMember(
    this.id,
    this.userId,
    this.name,
    this.role,
    this.status, {
    this.phoneNumber,
    this.permissions = const {},
  });
}

class StaffManagementScreen extends StatefulWidget {
  final String? clubId;
  final String? clubName;
  const StaffManagementScreen({super.key, this.clubId, this.clubName});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final _searchController = TextEditingController();
  final _dutyController = TextEditingController();

  final supabase = Supabase.instance.client;
  List<StaffMember> _currentStaff = [];
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedUser;
  bool _isLoading = true;
  bool _isSearching = false;

  // New Authority State
  String _activeRole = 'role_security'; // 'role_manager' or 'role_security'
  final Map<String, bool> _activePerms = {
    'can_scan': true,
    'can_cancel': false,
    'can_generate': false,
    'can_view_stats': false,
    'can_manage_guests': false,
    'can_send_notifs': false,
    'can_view_logs': false,
    'can_block_guest': false,
    'can_eject_guest': false,
    'can_mark_late': false,
    'can_view_team_logs': false,
    'can_confirm_payment': false,
    'can_confirm_booking': false,
  };

  @override
  void initState() {
    super.initState();
    _fetchStaff();
    _setupRealtime();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      if (_searchResults.isNotEmpty) setState(() => _searchResults = []);
      return;
    }
    _performSearch(query);
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    
    setState(() => _isSearching = true);
    try {
      final response = await supabase
          .from('profiles')
          .select('id, full_name, phone_number, avatar_url')
          .or('phone_number.ilike.%$query%,full_name.ilike.%$query%')
          .limit(5);

      if (mounted) {
        setState(() {
          _searchResults = (response as List).cast<Map<String, dynamic>>();
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  RealtimeChannel? _staffChannel;

  void _setupRealtime() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _staffChannel = supabase
        .channel('staff_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'staff_assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organizer_id',
            value: userId,
          ),
          callback: (payload) {
            _fetchStaff(); // Reload on any change
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dutyController.dispose();
    _staffChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchStaff() async {
    setState(() => _isLoading = true);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final query = supabase
          .from('staff_assignments')
          .select('*, profiles:staff_id(full_name, phone_number)');

      if (widget.clubId != null) {
        query.eq('club_id', widget.clubId!);
      } else {
        query.eq('organizer_id', userId);
      }

      final response = await query;

      setState(() {
        final List<StaffMember> fetched = (response as List).map((s) {
          final profile = s['profiles'] as Map<String, dynamic>?;
          final fullName = profile?['full_name'] ?? profile?['phone_number'] ?? 'Assistant';
          final phone = profile?['phone_number'];
          
          return StaffMember(
            s['id'],
            s['staff_id'],
            fullName,
            s['role'] ?? 'Scanner',
            s['status'] ?? 'pending',
            phoneNumber: phone,
            permissions: (s['permissions'] as Map<String, dynamic>?) ?? {},
          );
        }).toList();

        // Filter duplicates by staff_id if needed, or just keep them unique
        final seen = <String>{};
        _currentStaff = fetched.where((s) => seen.add(s.userId)).toList();
      });
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addStaff() async {
    if (_selectedUser == null) {
      _showMsg('please_select_staff_from_list'.tr, isError: true);
      return;
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);
    try {
      final staffId = _selectedUser!['id'];

      if (staffId == userId) {
        _showMsg('error_self_invite'.tr, isError: true);
        return;
      }

      final res = await supabase
          .from('staff_assignments')
          .insert({
            'organizer_id': userId,
            'club_id': widget.clubId,
            'club_name': widget.clubName ?? 'Sivox',
            'role': _activeRole,
            'status': 'pending',
            'staff_id': staffId,
            'permissions': _activePerms,
          })
          .select('id')
          .single();

      final assignmentId = res['id'];

      await NotificationService().sendNotificationToUser(
        userId: staffId,
        title: 'job_invitation_title'.tr,
        body: 'job_invitation_body'.trArgs([_activeRole.tr]),
        type: 'staff_invitation',
        metadata: {'assignment_id': assignmentId},
      );

      await AuditService().logAction(
        actionType: 'STAFF_INVITE',
        description: 'Invited ${_selectedUser!['full_name']} as ${_activeRole.tr}.',
      );
      
      setState(() {
        _selectedUser = null;
        _searchResults = [];
        _searchController.clear();
      });
      _fetchStaff();

      _showMsg('staff_added_success'.tr, isError: false);
    } catch (e) {
      _showMsg('action_failed'.tr, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMsg(String m, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: isError ? Colors.redAccent : AppTheme.primary,
      ),
    );
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

  Future<void> _removeStaff(String id) async {
    try {
      await supabase.from('staff_assignments').delete().eq('id', id);
      await AuditService().logAction(
        actionType: 'STAFF_REMOVED',
        description: 'Removed a staff member from the roster.',
      );
      _fetchStaff();
    } catch (e) {
      _showMsg('action_failed'.tr, isError: true);
    }
  }

  Future<void> _updateStaffRole(StaffMember staff, String newRole, Map<String, bool> newPerms) async {
    setState(() => _isLoading = true);
    try {
      await supabase.from('staff_assignments').update({
        'role': newRole,
        'permissions': newPerms,
      }).eq('id', staff.id);

      await NotificationService().sendStaffNotification(
        staffId: staff.userId,
        organizerId: widget.clubId ?? supabase.auth.currentUser!.id,
        title: 'ROLE_UPDATED_TITLE'.tr,
        body: 'ROLE_UPDATED_BODY'.trArgs([newRole.tr]),
        type: 'staff_guidance',
      );

      await AuditService().logAction(
        actionType: 'STAFF_ROLE_UPDATED',
        description: 'Updated ${staff.name} to $newRole with new permissions.',
      );

      _fetchStaff();
      _showMsg('staff_updated_success'.tr);
    } catch (e) {
      _showMsg('action_failed'.tr, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEditStaffDialog(StaffMember staff) {
    String localRole = staff.role;
    Map<String, bool> localPerms = Map<String, bool>.from(staff.permissions);
    
    // Ensure all possible perms are present in local map
    for (var key in _activePerms.keys) {
      localPerms.putIfAbsent(key, () => false);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setInternalState) => AlertDialog(
          backgroundColor: AppTheme.background,
          title: Text('edit_staff_permissions'.tr, style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: localRole,
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(labelText: 'role'.tr, labelStyle: const TextStyle(color: Colors.white70)),
                  items: ['role_manager', 'role_security', 'Scanner'].map((r) => DropdownMenuItem(value: r, child: Text(r.tr))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setInternalState(() => localRole = val);
                    }
                  },
                ),
                const SizedBox(height: 20),
                _buildSpecialPermissionSection(localPerms, setInternalState),
                const SizedBox(height: 20),
                ...localPerms.keys.where((k) => !['can_confirm_payment', 'can_confirm_booking'].contains(k)).map((perm) => CheckboxListTile(
                  title: Text(perm.tr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  value: localPerms[perm],
                  activeColor: AppTheme.primary,
                  onChanged: (val) => setInternalState(() => localPerms[perm] = val ?? false),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr)),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateStaffRole(staff, localRole, localPerms);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: Text('save'.tr, style: const TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  void _generateInviteLink() {
    final userId = supabase.auth.currentUser?.id;
    final link = 'https://Sivox.app/invite/$userId';
    Clipboard.setData(ClipboardData(text: link));
    _showMsg('invite_link_copied'.tr);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withValues(alpha: 0.8),
        elevation: 0,
        title: Text(
          'manage_staff'.tr,
          style: AppTheme.headlineStyle.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.link_rounded, color: AppTheme.secondary),
            tooltip: 'copy_invite_link'.tr,
            onPressed: _generateInviteLink,
          ),
          IconButton(
            icon: const Icon(Icons.verified_user_rounded, color: AppTheme.primary),
            tooltip: 'TACTICAL_VETTING'.tr,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VettingHubScreen(clubId: widget.clubId ?? supabase.auth.currentUser!.id))),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'add_new_staff'.tr,
                        style: AppTheme.headlineStyle.copyWith(fontSize: 20),
                      ),
                      GestureDetector(
                        onTap: () => _showHelp('add_new_staff'.tr, 'HELPER_STAFF_DESC'.tr),
                        child: Icon(Icons.help_outline_rounded, color: Colors.white.withValues(alpha: 0.05), size: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'search_staff_hint'.tr,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  
                  // SEARCH AREA WITH FLOATING RESULTS LOGIC
                  _buildSearchSection(),
                  
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Authority Level'.tr,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      GestureDetector(
                        onTap: () => _showHelp('Authority Level'.tr, 'HELPER_INFRASTRUCTURE_DESC'.tr),
                        child: Icon(Icons.help_outline_rounded, color: Colors.white.withValues(alpha: 0.05), size: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildRoleSelector(),
                  const SizedBox(height: 24),
                  Text(
                    'Permissions'.tr,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildPermissionCheckboxes(),
                  const SizedBox(height: 32),
                  _buildActionButton(),
                  const SizedBox(height: 48),
                  _buildComplementarySummons(),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'current_staff'.tr,
                        style: AppTheme.headlineStyle.copyWith(fontSize: 20),
                      ),
                      GestureDetector(
                        onTap: () => _showHelp('current_staff'.tr, 'HELPER_STAFF_DESC'.tr),
                        child: Icon(Icons.help_outline_rounded, color: Colors.white.withValues(alpha: 0.05), size: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: _isLoading && _currentStaff.isEmpty
                ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
                : _currentStaff.isEmpty
                    ? SliverToBoxAdapter(child: _buildEmptyState())
                    : _buildStaffListSliver(),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: _selectedUser != null ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10))] : null,
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _addStaff,
        style: ElevatedButton.styleFrom(
          backgroundColor: _selectedUser != null ? AppTheme.primary : Colors.white.withValues(alpha: 0.05),
          minimumSize: const Size(double.infinity, 64),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: _isLoading 
          ? const CircularProgressIndicator(color: Colors.black)
          : Text(
              'assign_as_staff'.tr.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _selectedUser != null ? Colors.black : Colors.white24,
                letterSpacing: 2,
              ),
            ),
      ),
    );
  }

  Widget _buildSearchSection() {
    return Column(
      children: [
        _buildSearchField(),
        if (_searchResults.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildSearchResults(),
          )
        else if (_searchController.text.isNotEmpty && !_isSearching)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'no_users_found'.tr,
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ),
        if (_selectedUser != null) _buildSelectedUserCard(),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _selectedUser != null ? AppTheme.primary : Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: (v) => _performSearch(v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'phone_or_name_hint'.tr,
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: _isSearching 
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)))
                  : const Icon(Icons.search, color: AppTheme.primary, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white24),
              onPressed: () {
                _searchController.clear();
                setState(() { _searchResults = []; _selectedUser = null; });
              },
            ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => _performSearch(_searchController.text),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'SEARCH'.tr,
                  style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 40, offset: const Offset(0, 20)),
          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 20),
        ],
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.person_search_rounded, color: AppTheme.primary, size: 16),
                const SizedBox(width: 8),
                Text('SEARCH_RESULTS'.tr.toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const Spacer(),
                Text('${_searchResults.length} ${'FOUND'.tr}', style: const TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Flexible(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _searchResults.length,
                separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                itemBuilder: (context, index) {
                  final user = _searchResults[index];
                  return ListTile(
                    onTap: () {
                      setState(() {
                        _selectedUser = user;
                        _searchResults = [];
                        _searchController.text = user['full_name'] ?? '';
                      });
                      FocusScope.of(context).unfocus();
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2))),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                        child: user['avatar_url'] == null ? const Icon(Icons.person_rounded, size: 20, color: AppTheme.primary) : null,
                      ),
                    ),
                    title: Text(user['full_name'] ?? 'User', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    subtitle: Text(user['phone_number'] ?? '', style: TextStyle(color: AppTheme.primary.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600)),
                    trailing: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.add_rounded, color: AppTheme.primary, size: 20),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedUserCard() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withValues(alpha: 0.1), AppTheme.primary.withValues(alpha: 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: _selectedUser!['avatar_url'] != null ? NetworkImage(_selectedUser!['avatar_url']) : null,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
            child: _selectedUser!['avatar_url'] == null ? const Icon(Icons.person_rounded, color: AppTheme.primary) : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_selectedUser!['full_name'] ?? 'User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(_selectedUser!['phone_number'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white24),
            onPressed: () => setState(() => _selectedUser = null),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Row(
      children: [
        Expanded(
          child: _roleOption('role_manager', Icons.admin_panel_settings),
        ),
        const SizedBox(width: 12),
        Expanded(child: _roleOption('role_security', Icons.security)),
      ],
    );
  }

  Widget _roleOption(String role, IconData icon) {
    final active = _activeRole == role;
    return GestureDetector(
      onTap: () {
        setState(() => _activeRole = role);
        _applyPreset(role);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primary.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppTheme.primary : Colors.white12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: active ? AppTheme.primary : Colors.white24,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              role.tr,
              style: TextStyle(
                color: active ? AppTheme.primary : Colors.white54,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyPreset(String role) {
    setState(() {
      // Reset all to false first
      _activePerms.updateAll((key, value) => false);

      if (role == 'role_manager') {
        _activePerms.updateAll((key, value) => true);
      } else if (role == 'role_security') {
        _activePerms['can_scan'] = true;
        _activePerms['can_view_logs'] = true;
        _activePerms['can_block_guest'] = true;
        _activePerms['can_eject_guest'] = true;
        _activePerms['can_confirm_payment'] = true;
        _activePerms['can_confirm_booking'] = true;
        _activePerms['can_view_team_logs'] = false;
      }
    });
  }

  Widget _buildPermissionCheckboxes() {
    return Column(
      children: [
        _buildSpecialPermissionSection(_activePerms, setState),
        const SizedBox(height: 16),
        ..._activePerms.keys.where((k) => !['can_confirm_payment', 'can_confirm_booking'].contains(k)).map((perm) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.01),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CheckboxListTile(
              title: Text(
                perm.tr,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              value: _activePerms[perm],
              activeColor: AppTheme.primary,
              checkColor: Colors.black,
              onChanged: (val) =>
                  setState(() => _activePerms[perm] = val ?? false),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, color: Colors.white10, size: 64),
          const SizedBox(height: 16),
          Text(
            'no_staff_added'.tr,
            style: const TextStyle(color: Colors.white24),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffListSliver() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final staff = _currentStaff[index];
          final isPending = staff.status == 'pending';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isPending ? Colors.amber.withValues(alpha: 0.1) : Colors.white10,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: isPending ? Colors.amber.withValues(alpha: 0.1) : AppTheme.primary.withValues(alpha: 0.1),
                child: Icon(
                  isPending ? Icons.hourglass_empty : Icons.person_rounded,
                  color: isPending ? Colors.amber : AppTheme.primary,
                  size: 20,
                ),
              ),
              title: Text(staff.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(staff.role.tr.toUpperCase(), style: const TextStyle(color: AppTheme.secondary, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900)),
                  if (staff.phoneNumber != null) ...[
                    const SizedBox(height: 2),
                    Text(staff.phoneNumber!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isPending)
                    IconButton(
                      icon: const Icon(Icons.campaign_rounded, color: AppTheme.primary, size: 20),
                      tooltip: 'summon'.tr,
                      onPressed: () => _showIndividualSummonDialog(staff),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.white38, size: 20),
                    onPressed: () => _showEditStaffDialog(staff),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white10, size: 20),
                    onPressed: () => _removeStaff(staff.id),
                  ),
                ],
              ),
            ),
          );
        },
        childCount: _currentStaff.length,
      ),
    );
  }


  Widget _buildComplementarySummons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded, color: AppTheme.primary, size: 16),
            const SizedBox(width: 8),
            Text(
              'TACTICAL_NOTIFICATIONS'.tr.toUpperCase(),
              style: AppTheme.labelStyle.copyWith(
                color: AppTheme.primary,
                fontSize: 10,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _summonChip(
                '🚨 ${'URGENT'.tr}',
                'urgent_mission'.tr,
                Colors.redAccent,
              ),
              const SizedBox(width: 8),
              _summonChip(
                '🎫 ${'GATE'.tr}',
                'gate_support'.tr,
                AppTheme.primary,
              ),
              const SizedBox(width: 8),
              _summonChip(
                '💎 ${'VIP'.tr}',
                'vip_support'.tr,
                Colors.purpleAccent,
              ),
              const SizedBox(width: 8),
              _summonChip(
                '🍹 ${'BAR'.tr}',
                'bar_support'.tr,
                Colors.blueAccent,
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showCustomMissionDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '✏️ ${'CUSTOM'.tr}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.add_rounded, color: Colors.white70, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summonChip(String label, String mission, Color color) {
    return GestureDetector(
      onTap: () => _sendCollectiveSummon(mission),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.send_rounded, color: Colors.white10, size: 12),
          ],
        ),
      ),
    );
  }

  void _showCustomMissionDialog() {
    final TextEditingController missionController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('custom_mission'.tr, style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
        content: TextField(
          controller: missionController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'type_mission_details'.tr,
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr, style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final text = missionController.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx);
                _sendCollectiveSummon(text);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black),
            child: Text('send'.tr),
          ),
        ],
      ),
    );
  }

  void _showIndividualSummonDialog(StaffMember staff) {
    final TextEditingController missionController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${'summon'.tr} ${staff.name}', style: AppTheme.headlineStyle.copyWith(fontSize: 18)),
        content: TextField(
          controller: missionController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'type_mission_details'.tr,
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr, style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = missionController.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                try {
                  await NotificationService().sendStaffMission(
                    staffId: staff.userId,
                    organizerId: widget.clubId ?? supabase.auth.currentUser!.id,
                    clubName: widget.clubName ?? 'Club',
                    missionText: text,
                  );
                  await AuditService().logAction(
                    actionType: 'STAFF_INDIVIDUAL_SUMMON',
                    description: 'Sent individual summon: "$text" to ${staff.name}.',
                  );
                  _showMsg('notification_sent'.tr);
                } catch (e) {
                  _showMsg('action_failed'.tr, isError: true);
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black),
            child: Text('send'.tr),
          ),
        ],
      ),
    );
  }


  Future<void> _sendCollectiveSummon(String text) async {
    setState(() => _isLoading = true);
    try {
      final staffQuery = await supabase
          .from('staff_assignments')
          .select('staff_id')
          .eq('club_id', widget.clubId ?? '')
          .eq('status', 'active');

      final List<dynamic> staffList = staffQuery as List;
      if (staffList.isEmpty) {
        _showMsg('No active staff to notify.'.tr, isError: true);
        return;
      }

      final notifService = NotificationService();
      int successCount = 0;

      for (final s in staffList) {
        final String sId = s['staff_id'];
        await notifService.sendStaffMission(
          staffId: sId,
          organizerId: widget.clubId ?? supabase.auth.currentUser!.id,
          clubName: widget.clubName ?? 'Club',
          missionText: text,
        );
        successCount++;
      }

      await AuditService().logAction(
        actionType: 'STAFF_COLLECTIVE_SUMMON',
        description: 'Sent collective summon: "$text" to $successCount staff.',
      );

      _showMsg('Notification sent to $successCount staff member(s).'.tr);
    } catch (e) {
      _showMsg('Failed to send notification.'.tr, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSpecialPermissionSection(Map<String, bool> perms, Function updater) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars_rounded, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'CRITICAL_OPERATIONS'.tr.toUpperCase(),
                style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _permCheckRow('can_confirm_payment', perms, updater),
          _permCheckRow('can_confirm_booking', perms, updater),
        ],
      ),
    );
  }

  Widget _permCheckRow(String key, Map<String, bool> perms, Function updater) {
    return CheckboxListTile(
      title: Text(key.tr, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      value: perms[key] ?? false,
      activeColor: AppTheme.primary,
      checkColor: Colors.black,
      contentPadding: EdgeInsets.zero,
      dense: true,
      onChanged: (val) => updater(() => perms[key] = val ?? false),
    );
  }
}
