import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notification_state.dart';
import '../../models/app_notification.dart';

class NotificationCubit extends Cubit<NotificationState> {
  NotificationCubit() : super(NotificationState.initial());

  void addFromFCM(RemoteMessage message) {
    final notif = AppNotification(
      title: message.notification?.title ?? 'No Title',
      body: message.notification?.body ?? 'No Body',
      time: DateTime.now(),
    );

    emit(
      NotificationState(
        notifications: [notif, ...state.notifications],
      ),
    );
  }

  int get unreadCount => state.notifications.length;
}
