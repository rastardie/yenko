import 'package:flutter/material.dart';

import '../../core/data/trip_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/yenko_showcase_widgets.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.repository});
  final TripRepository repository;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) {
      final notifications = repository.notifications;
      final unread = notifications
          .where((notification) => !notification.read)
          .length;
      return YenkoShowcaseBackdrop(
        useWatermark: true,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            children: [
              YenkoScreenTitle(
                title: 'Messages',
                subtitle: unread == 0
                    ? 'You are all caught up.'
                    : '$unread new update${unread == 1 ? '' : 's'}',
                action: unread == 0
                    ? IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.more_horiz_rounded),
                      )
                    : TextButton.icon(
                        onPressed: repository.markNotificationsRead,
                        icon: const Icon(Icons.done_all_rounded, size: 18),
                        label: const Text('Read all'),
                      ),
              ),
              const SizedBox(height: 18),
              if (notifications.isEmpty)
                const YenkoWatermarkEmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'No messages yet',
                  message:
                      'Ride updates, booking confirmations, and important safety notices will appear here.',
                ),
              for (final notification in notifications) ...[
                _MessageCard(
                  title: notification.title,
                  body: notification.body,
                  read: notification.read,
                  createdAt: notification.createdAt,
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 14),
              const YenkoShowcaseCard(
                color: Color(0xFFFFF5D8),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: YenkoColors.charcoal),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Keep conversations and pickup details inside YɛnKɔ. Do not share sensitive personal information.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
  });
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) => YenkoShowcaseCard(
    color: read ? Colors.white : const Color(0xFFFFFCF0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: read ? const Color(0xFFF0F1F3) : const Color(0xFFFFE8A3),
            shape: BoxShape.circle,
          ),
          child: Icon(
            read
                ? Icons.notifications_none_rounded
                : Icons.notifications_active_rounded,
            color: YenkoColors.charcoal,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: read ? FontWeight.w700 : FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    _timeLabel(createdAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: YenkoColors.gray,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  color: YenkoColors.gray,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (!read)
          const Padding(
            padding: EdgeInsets.only(left: 8, top: 5),
            child: CircleAvatar(radius: 4, backgroundColor: Color(0xFFF9B900)),
          ),
      ],
    ),
  );

  String _timeLabel(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return 'Now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    return '${difference.inDays}d';
  }
}
