import 'package:flutter/material.dart';
import 'package:my_app/models/event.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BentoGridWidget extends StatelessWidget {
  final List<Event> events;
  final Function(Event) onEventTap;

  const BentoGridWidget({
    super.key,
    required this.events,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return _buildEmptyBento();
    
    final topEvents = events.take(3).toList();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          if (topEvents.isNotEmpty)
            _buildBentoItem(topEvents[0], height: 280, isLarge: true),
          const SizedBox(height: 16),
          if (topEvents.length > 1)
            Row(
              children: [
                Expanded(child: _buildBentoItem(topEvents[1], height: 200)),
                const SizedBox(width: 16),
                if (topEvents.length > 2)
                  Expanded(child: _buildBentoItem(topEvents[2], height: 200))
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBentoItem(Event e, {required double height, bool isLarge = false}) {
    final hasImg = e.imageUrl != null && e.imageUrl!.isNotEmpty;
    return GestureDetector(
      onTap: () => onEventTap(e),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned.fill(
                child: hasImg
                    ? CachedNetworkImage(
                        imageUrl: e.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (ctx, url) => Container(color: const Color(0xFF1A1A1A)),
                        errorWidget: (ctx, url, err) => Container(
                          color: const Color(0xFF1A1A1A),
                          child: const Icon(Icons.image_not_supported_rounded, color: Colors.white12, size: 40),
                        ),
                      )
                    : Container(color: const Color(0xFF1A1A1A)),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.35, 1.0],
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
              ),
              if (isLarge)
                Positioned(
                  top: 16, left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.4), blurRadius: 12)],
                    ),
                    child: Text('FEATURED'.tr, style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                )
              else
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Text(
                      (e.category ?? 'EVENT').toUpperCase(),
                      style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, isLarge ? 20 : 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title.toUpperCase(),
                        maxLines: isLarge ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isLarge ? 22 : 14,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          letterSpacing: -0.3,
                          shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 11),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              e.venue?.toUpperCase() ?? 'SECRET LOCATION',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                            ),
                          ),
                          if (!e.hidePrice && e.price > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                LocalizationService.formatPrice(e.price, e.countryCode),
                                style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                            )
                          else if (e.price == 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.tealAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                'FREE'.tr,
                                style: const TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyBento() {
    return Container(
      height: 200, margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(32)),
      child: Center(child: Text('NO_EVENTS_YET'.tr, style: const TextStyle(color: Colors.white24))),
    );
  }
}
