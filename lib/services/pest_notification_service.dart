import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../cubit/notification/notification_cubit.dart' as notif_cubit;

class PestNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  
  static bool _isInitialized = false;

  // Initialize local notifications
  static Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _isInitialized = true;
    print('✅ Pest Notification Service initialized');
  }

  // Request notification permissions
  static Future<bool> requestPermissions() async {
    if (!_isInitialized) await initialize();

    final android = await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final ios = await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    return android ?? ios ?? false;
  }

  // Handle notification tap
  static void _onNotificationTap(NotificationResponse response) {
    print('📱 Notification tapped: ${response.payload}');
    // Navigate to pest detection page or detail
    // You can use a global navigator key for this
  }

  // Show pest detection notification
  static Future<void> showPestDetection({
    required String pestName,
    required int confidence,
    required int detectionId,
    Uint8List? imageBytes,
    required notif_cubit.NotificationCubit notificationCubit,
  }) async {
    if (!_isInitialized) await initialize();

    // Add to notification cubit
    notificationCubit.addPestDetection(
      pestName: pestName,
      confidence: confidence,
      detectionId: detectionId,
    );

    // Determine notification priority and style based on confidence
    final priority = confidence >= 90
        ? Priority.max
        : confidence >= 70
            ? Priority.high
            : Priority.defaultPriority;

    final importance = confidence >= 90
        ? Importance.max
        : confidence >= 70
            ? Importance.high
            : Importance.defaultImportance;

    final emoji = confidence >= 90 ? '🚨' : confidence >= 70 ? '⚠️' : '🔍';
    final channelId = confidence >= 90 ? 'pest_critical' : 'pest_normal';
    final channelName = confidence >= 90 ? 'Deteksi Hama Kritis' : 'Deteksi Hama';

    // Create notification with image if available
    AndroidNotificationDetails androidDetails;
    
    if (imageBytes != null) {
      final BigPictureStyleInformation bigPictureStyle = BigPictureStyleInformation(
        ByteArrayAndroidBitmap(imageBytes),
        contentTitle: '$emoji Hama Terdeteksi: $pestName',
        summaryText: 'Confidence: $confidence%',
      );

      androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notifikasi deteksi hama pada sawah',
        importance: importance,
        priority: priority,
        styleInformation: bigPictureStyle,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        color: confidence >= 90 
            ? const Color(0xFFEF4444) 
            : confidence >= 70 
                ? const Color(0xFFF59E0B)
                : const Color(0xFF3B82F6),
        ledColor: const Color(0xFFFF0000),
        ledOnMs: 1000,
        ledOffMs: 500,
        ticker: 'Hama terdeteksi: $pestName',
        largeIcon: ByteArrayAndroidBitmap(imageBytes),
        actions: [
          const AndroidNotificationAction(
            'view',
            'Lihat Detail',
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'dismiss',
            'Tutup',
          ),
        ],
      );
    } else {
      androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notifikasi deteksi hama pada sawah',
        importance: importance,
        priority: priority,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        color: confidence >= 90 
            ? const Color(0xFFEF4444) 
            : confidence >= 70 
                ? const Color(0xFFF59E0B)
                : const Color(0xFF3B82F6),
        ledColor: const Color(0xFFFF0000),
        ledOnMs: 1000,
        ledOffMs: 500,
        ticker: 'Hama terdeteksi: $pestName',
      );
    }

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      detectionId,
      '$emoji Hama Terdeteksi: $pestName',
      'Tingkat kepercayaan: $confidence%. Segera periksa area pertanian Anda.',
      details,
      payload: 'pest_detection:$detectionId',
    );

    print('✅ Pest notification shown: $pestName ($confidence%)');
  }

  // Show system status notification
  static Future<void> showSystemStatus({
    required String message,
    required bool isActive,
    required notif_cubit.NotificationCubit notificationCubit,
  }) async {
    if (!_isInitialized) await initialize();

    notificationCubit.addSystemStatus(
      message: message,
      isActive: isActive,
    );

    const androidDetails = AndroidNotificationDetails(
      'system_status',
      'Status Sistem',
      channelDescription: 'Notifikasi status sistem deteksi hama',
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      isActive ? '✅ Sistem Aktif' : '🔴 Sistem Nonaktif',
      message,
      details,
      payload: 'system_status',
    );
  }

  // Cancel specific notification
  static Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }

  // Cancel all notifications
  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  // Get pending notifications
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }
}