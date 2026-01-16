import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'notification_state.dart';
import '../../models/app_notification.dart';

class NotificationCubit extends Cubit<NotificationState> {
  NotificationCubit() : super(NotificationState.initial()) {
    _loadNotifications();
  }

  // Load notifications from cache
  Future<void> _loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('notifications');
      
      if (cached != null) {
        final List<dynamic> data = jsonDecode(cached);
        final notifications = data
            .map((json) => AppNotification.fromJson(json))
            .toList();
        
        emit(NotificationState(notifications: notifications));
      }
    } catch (e) {
      print('❌ Load notifications error: $e');
    }
  }

  // Save notifications to cache
  Future<void> _saveNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = state.notifications.map((n) => n.toJson()).toList();
      await prefs.setString('notifications', jsonEncode(data));
    } catch (e) {
      print('❌ Save notifications error: $e');
    }
  }

  // Add notification from FCM
  void addFromFCM(RemoteMessage message) {
    final notif = AppNotification(
      title: message.notification?.title ?? 'No Title',
      body: message.notification?.body ?? 'No Body',
      time: DateTime.now(),
      data: message.data,
    );

    _addNotification(notif);
  }

  // Add pest detection notification
  void addPestDetection({
    required String pestName,
    required int confidence,
    required int detectionId,
    String? imageBase64,
  }) {
    final notif = AppNotification.pestDetection(
      pestName: pestName,
      confidence: confidence,
      detectionId: detectionId,
      imageBase64: imageBase64,
    );

    _addNotification(notif);
  }

  // Add system status notification
  void addSystemStatus({
    required String message,
    required bool isActive,
  }) {
    final notif = AppNotification.systemStatus(
      message: message,
      isActive: isActive,
    );

    _addNotification(notif);
  }

  // Add custom notification
  void addCustomNotification(AppNotification notification) {
    _addNotification(notification);
  }

  // Internal method to add notification
  void _addNotification(AppNotification notification) {
    final updated = [notification, ...state.notifications];
    
    // Keep only last 100 notifications
    final limited = updated.length > 100 
        ? updated.sublist(0, 100) 
        : updated;
    
    emit(NotificationState(notifications: limited));
    _saveNotifications();
  }

  // Mark notification as read
  void markAsRead(String notificationId) {
    final updated = state.notifications.map((n) {
      if (n.id == notificationId) {
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();

    emit(NotificationState(notifications: updated));
    _saveNotifications();
  }

  // Mark all as read
  void markAllAsRead() {
    final updated = state.notifications
        .map((n) => n.copyWith(isRead: true))
        .toList();

    emit(NotificationState(notifications: updated));
    _saveNotifications();
  }

  // Delete notification
  void deleteNotification(String notificationId) {
    final updated = state.notifications
        .where((n) => n.id != notificationId)
        .toList();

    emit(NotificationState(notifications: updated));
    _saveNotifications();
  }

  // Clear all notifications
  void clearAll() {
    emit(NotificationState.initial());
    _saveNotifications();
  }

  // Clear pest detection notifications only
  void clearPestDetectionNotifications() {
    final updated = state.notifications
        .where((n) => n.type != NotificationType.pestDetection)
        .toList();

    emit(NotificationState(notifications: updated));
    _saveNotifications();
  }

  // Getters
  int get unreadCount => state.notifications.where((n) => !n.isRead).length;
  
  int get pestDetectionCount => state.notifications
      .where((n) => n.type == NotificationType.pestDetection)
      .length;
  
  List<AppNotification> get unreadNotifications => 
      state.notifications.where((n) => !n.isRead).toList();
  
  List<AppNotification> get pestDetectionNotifications =>
      state.notifications
          .where((n) => n.type == NotificationType.pestDetection)
          .toList();
}