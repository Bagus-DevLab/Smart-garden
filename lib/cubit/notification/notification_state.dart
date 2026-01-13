import '../../models/app_notification.dart';

class NotificationState {
  final List<AppNotification> notifications;

  const NotificationState({required this.notifications});

  factory NotificationState.initial() {
    return const NotificationState(notifications: []);
  }
}
