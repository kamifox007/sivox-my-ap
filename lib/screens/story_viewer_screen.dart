import 'package:flutter/material.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/screens/event_details.dart';

class StoryViewerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> clubs;
  final Map<String, List<Event>> clubEvents;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.clubs,
    required this.clubEvents,
    required this.initialIndex,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
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

  void _onStoryComplete() {
    if (_pageController.page!.toInt() < widget.clubs.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context); // Close viewer when all stories are done
    }
  }

  void _onStoryPrevious() {
    if (_pageController.page!.toInt() > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context); // Close viewer if on first story and tapping back
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.clubs.length,
        itemBuilder: (context, index) {
          final club = widget.clubs[index];
          final String clubId = club['id'].toString();
          final events = widget.clubEvents[clubId] ?? [];
          
          return SingleClubStoryView(
            club: club,
            events: events,
            onComplete: _onStoryComplete,
            onPreviousClub: _onStoryPrevious,
          );
        },
      ),
    );
  }
}

class SingleClubStoryView extends StatefulWidget {
  final Map<String, dynamic> club;
  final List<Event> events;
  final VoidCallback onComplete;
  final VoidCallback onPreviousClub;

  const SingleClubStoryView({
    super.key,
    required this.club,
    required this.events,
    required this.onComplete,
    required this.onPreviousClub,
  });

  @override
  State<SingleClubStoryView> createState() => _SingleClubStoryViewState();
}

class _SingleClubStoryViewState extends State<SingleClubStoryView> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  int _currentEventIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // 5 seconds per story
    );

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _nextStory() {
    if (_currentEventIndex < widget.events.length - 1) {
      setState(() {
        _currentEventIndex++;
      });
      _animationController.forward(from: 0.0);
    } else {
      widget.onComplete();
    }
  }

  void _previousStory() {
    if (_currentEventIndex > 0) {
      setState(() {
        _currentEventIndex--;
      });
      _animationController.forward(from: 0.0);
    } else {
      widget.onPreviousClub();
    }
  }

  void _onTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;

    if (dx < screenWidth * 0.3) {
      _previousStory();
    } else {
      _nextStory();
    }
  }

  void _onLongPressDown(_) {
    _animationController.stop();
  }

  void _onLongPressEnd(_) {
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) {
      // Fallback if somehow there are no events
      return const Center(child: Text("No Stories", style: TextStyle(color: Colors.white)));
    }

    final currentEvent = widget.events[_currentEventIndex];
    final String clubName = widget.club['name'] ?? widget.club['profiles']?['full_name'] ?? 'Club';
    final String? avatarUrl = widget.club['avatar_url'] ?? widget.club['profiles']?['avatar_url'];

    return GestureDetector(
      onTapDown: _onTapDown,
      onLongPressDown: _onLongPressDown,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: () => _onLongPressEnd(null),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          currentEvent.imageUrl != null
              ? Image.network(currentEvent.imageUrl!, fit: BoxFit.cover)
              : Container(color: AppTheme.background),

          // Gradient Overlay
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.9),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),

          // Event Details Bottom
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentEvent.category != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      currentEvent.category!.toUpperCase(),
                      style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w900),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  currentEvent.title,
                  style: AppTheme.headlineStyle.copyWith(fontSize: 28, color: Colors.white),
                ),
                const SizedBox(height: 8),
                if (currentEvent.venue != null)
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: Colors.white54, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          currentEvent.venue!,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                
                // CTA Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      _animationController.stop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => EventDetailsScreen(event: currentEvent)),
                      ).then((_) => _animationController.forward());
                    },
                    child: const Text('احجز الآن', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),

          // Header (Profile info + Progress bars)
          SafeArea(
            child: Column(
              children: [
                // Progress Bars
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: List.generate(widget.events.length, (index) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              double value = 0.0;
                              if (index < _currentEventIndex) {
                                value = 1.0;
                              } else if (index == _currentEventIndex) {
                                value = _animationController.value;
                              }
                              return LinearProgressIndicator(
                                value: value,
                                backgroundColor: Colors.white.withValues(alpha: 0.3),
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                minHeight: 2.5,
                                borderRadius: BorderRadius.circular(2),
                              );
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                
                // Club Profile Info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.surface,
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null ? const Icon(Icons.nightlife, size: 16, color: AppTheme.primary) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          clubName.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
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
