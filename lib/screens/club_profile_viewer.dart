import 'package:flutter/material.dart';
import 'package:my_app/screens/club_profile.dart';

class ClubProfileViewer extends StatefulWidget {
  final List<dynamic> followedClubs;
  final int initialIndex;

  const ClubProfileViewer({
    super.key,
    required this.followedClubs,
    required this.initialIndex,
  });

  @override
  State<ClubProfileViewer> createState() => _ClubProfileViewerState();
}

class _ClubProfileViewerState extends State<ClubProfileViewer> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.followedClubs.length,
        itemBuilder: (context, index) {
          final club = widget.followedClubs[index];
          final String name = club['name'] ?? club['profiles']?['full_name'] ?? 'Club';
          final String clubId = club['id'].toString();

          return ClubProfileScreen(
            organizerId: clubId, 
            organizerName: name
          );
        },
      ),
    );
  }
}
