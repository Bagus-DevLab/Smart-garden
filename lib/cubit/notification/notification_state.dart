import '../../models/app_notification.dart';

class NotificationState {
  final List<AppNotification> notifications;

  const NotificationState({required this.notifications});

  factory NotificationState.initial() {
    return const NotificationState(notifications: []);
  }

  // Copy with method for state updates
  NotificationState copyWith({
    List<AppNotification>? notifications,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
    );
  }

  // Getters for convenience
  int get totalCount => notifications.length;
  
  int get unreadCount => notifications.where((n) => !n.isRead).length;
  
  int get pestDetectionCount => notifications
      .where((n) => n.type == NotificationType.pestDetection)
      .length;
  
  int get unreadPestDetectionCount => notifications
      .where((n) => n.type == NotificationType.pestDetection && !n.isRead)
      .length;

  List<AppNotification> get unreadNotifications =>
      notifications.where((n) => !n.isRead).toList();

  List<AppNotification> get pestDetectionNotifications =>
      notifications
          .where((n) => n.type == NotificationType.pestDetection)
          .toList();

  List<AppNotification> get readNotifications =>
      notifications.where((n) => n.isRead).toList();

  // Get notifications by type
  List<AppNotification> getNotificationsByType(NotificationType type) {
    return notifications.where((n) => n.type == type).toList();
  }

  // Get notifications by priority
  List<AppNotification> getNotificationsByPriority(NotificationPriority priority) {
    return notifications.where((n) => n.priority == priority).toList();
  }

  // Get high priority unread notifications
  List<AppNotification> get highPriorityUnread => notifications
      .where((n) => 
          !n.isRead && 
          (n.priority == NotificationPriority.high || 
           n.priority == NotificationPriority.critical))
      .toList();

  // Check if has unread notifications
  bool get hasUnread => unreadCount > 0;

  // Check if has pest detection notifications
  bool get hasPestDetections => pestDetectionCount > 0;

  // Get latest notification
  AppNotification? get latestNotification =>
      notifications.isNotEmpty ? notifications.first : null;

  // Get latest pest detection
  AppNotification? get latestPestDetection =>
      pestDetectionNotifications.isNotEmpty 
          ? pestDetectionNotifications.first 
          : null;

  @override
  String toString() {
    return 'NotificationState(total: $totalCount, unread: $unreadCount, pestDetections: $pestDetectionCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationState &&
        other.notifications.length == notifications.length;
  }

  @override
  int get hashCode => notifications.hashCode;
}