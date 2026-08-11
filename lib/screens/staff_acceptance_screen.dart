import 'package:flutter/material.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/staff_service.dart';
import 'package:my_app/screens/staff_dashboard_screen.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/screens/scan_entry.dart';
import 'package:my_app/screens/organizer_main_wrapper.dart';

class StaffAcceptanceScreen extends StatefulWidget {
  final Map<String, dynamic> assignment;

  const StaffAcceptanceScreen({super.key, required this.assignment});

  @override
  State<StaffAcceptanceScreen> createState() => _StaffAcceptanceScreenState();
}

class _StaffAcceptanceScreenState extends State<StaffAcceptanceScreen> {
  final _staffService = StaffService();
  bool _isProcessing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentAssignment = widget.assignment;
    if (_currentAssignment!['club_name'] == null) {
      _fetchFullAssignment();
    }
  }

  Map<String, dynamic>? _currentAssignment;

  Future<void> _fetchFullAssignment() async {
    setState(() => _isLoading = true);
    final id = widget.assignment['id'];
    if (id != null) {
      final details = await _staffService.getAssignmentById(id.toString());
      if (details != null && mounted) {
        setState(() {
          _currentAssignment = details;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleResponse(bool accepted) async {
    if (_currentAssignment == null) return;
    setState(() => _isProcessing = true);
    final assignmentId = _currentAssignment!['id'];
    final role = (_currentAssignment!['role'] ?? '').toString().toLowerCase();
    final clubId = _currentAssignment!['organizer_id'];
    final clubName = _currentAssignment!['club_name'];

    bool success;
    if (accepted) {
      success = await _staffService.acceptAssignment(assignmentId);
    } else {
      success = await _staffService.rejectAssignment(assignmentId);
    }

    if (mounted) {
      if (success) {
        if (accepted) {
          // Automatic Role-Based Routing
          if (role == 'security' || role == 'scanner' || role == 'امن') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ScanEntryScreen()),
            );
          } else {
            // Managers/Masir go to Dashboard
            OrganizerMainWrapper.of(
              context,
            )?.selectClub(clubId, clubName, role: 'STAFF');
            Navigator.popUntil(context, (route) => route.isFirst);
          }
        } else {
          Navigator.pop(context);
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('action_failed'.tr)));
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final displayAssignment = _currentAssignment ?? widget.assignment;

    // If the assignment is already active, show the dashboard
    if (displayAssignment['status'] == 'active') {
      return StaffDashboard(organizerId: displayAssignment['organizer_id']);
    }

    final clubName = displayAssignment['club_name'] ?? 'Sivox';
    final role = displayAssignment['role'] ?? 'staff_member'.tr;
    final eventTitle = displayAssignment['event_title'] ?? 'Full Duty';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primary.withValues(alpha: 0.1),
              AppTheme.background,
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.security_outlined,
              color: AppTheme.primary,
              size: 80,
            ),
            const SizedBox(height: 48),
            Text(
              'assignment_pending'.tr,
              style: AppTheme.labelStyle.copyWith(
                color: AppTheme.secondary,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'invited_to_work_at'.tr,
              style: AppTheme.bodyStyle.copyWith(
                color: AppTheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              clubName.toUpperCase(),
              style: AppTheme.headlineStyle.copyWith(fontSize: 32, height: 1.1),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              eventTitle,
              style: AppTheme.labelStyle.copyWith(color: AppTheme.primary),
            ),
            const SizedBox(height: 48),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  _buildAssignRow(Icons.qr_code_scanner, 'role'.tr, role),
                ],
              ),
            ),
            const SizedBox(height: 64),
            ElevatedButton(
              onPressed: _isProcessing ? null : () => _handleResponse(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 64),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 20,
                shadowColor: AppTheme.primary.withValues(alpha: 0.4),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'agree_start_work'.tr,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _isProcessing ? null : () => _handleResponse(false),
              child: Text(
                'reject_assignment'.tr,
                style: AppTheme.labelStyle.copyWith(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.secondary, size: 20),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTheme.labelStyle.copyWith(fontSize: 8)),
            Text(
              value,
              style: AppTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}
