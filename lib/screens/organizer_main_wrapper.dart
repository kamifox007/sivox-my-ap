import 'package:flutter/material.dart';
import 'package:my_app/services/notification_service.dart';
import 'package:my_app/screens/staff_dashboard_screen.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/screens/account_selector.dart';
import 'package:my_app/screens/organizer_dashboard.dart';

class OrganizerMainWrapper extends StatefulWidget {
  const OrganizerMainWrapper({super.key});

  static OrganizerMainWrapperState? of(BuildContext context) {
    return context.findAncestorStateOfType<OrganizerMainWrapperState>();
  }

  @override
  State<OrganizerMainWrapper> createState() => OrganizerMainWrapperState();
}

class OrganizerMainWrapperState extends State<OrganizerMainWrapper> {
  String? _selectedClubId;
  String? _selectedClubName;
  String _selectedBusinessType = 'club';

  @override
  void initState() {
    super.initState();
    NotificationService().startRealtimeListener();
  }

  void setIndex(int index) {
    // Keep to avoid compile errors from callers
  }

  void selectClub(String id, String name, {String role = 'OWNER', String businessType = 'club'}) {
    if (mounted) {
      setState(() {
        _selectedClubId = id;
        _selectedClubName = name;
        _selectedRole = role.toUpperCase();
        _selectedBusinessType = businessType;
      });
    }
  }

  String _selectedRole = 'OWNER';

  void openSelector() {
    if (mounted) {
      setState(() {
        _selectedClubId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedClubId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedClubId != null) {
          openSelector();
        }
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    // Staff → StaffDashboard
    if (_selectedRole == 'STAFF' && _selectedClubId != null) {
      return StaffDashboard(organizerId: _selectedClubId!);
    }

    // No club selected → show account selector
    if (_selectedClubId == null) {
      return const AccountSelectorScreen();
    }

    // Owner → go directly to OrganizerDashboardScreen to publish/manage events
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: OrganizerDashboardScreen(
        clubId: _selectedClubId!,
        clubName: _selectedClubName ?? '',
        businessType: _selectedBusinessType,
        onBack: openSelector,
      ),
    );
  }
}
