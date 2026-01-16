class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime time;
  final NotificationType type;
  final NotificationPriority priority;
  final Map<String, dynamic>? data;
  final String? imageUrl;
  final bool isRead;

  AppNotification({
    String? id,
    required this.title,
    required this.body,
    required this.time,
    this.type = NotificationType.general,
    this.priority = NotificationPriority.medium,
    this.data,
    this.imageUrl,
    this.isRead = false,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  // Factory untuk pest detection notification
  factory AppNotification.pestDetection({
    required String pestName,
    required int confidence,
    required int detectionId,
    String? imageBase64,
  }) {
    final priority = confidence >= 90
        ? NotificationPriority.high
        : confidence >= 70
            ? NotificationPriority.medium
            : NotificationPriority.low;

    final emoji = confidence >= 90 ? '🚨' : confidence >= 70 ? '⚠️' : '🔍';

    return AppNotification(
      title: '$emoji Hama Terdeteksi: $pestName',
      body: 'Tingkat kepercayaan: $confidence%. Segera periksa area pertanian Anda.',
      time: DateTime.now(),
      type: NotificationType.pestDetection,
      priority: priority,
      data: {
        'detectionId': detectionId,
        'pestName': pestName,
        'confidence': confidence,
        'imageBase64': imageBase64,
      },
      imageUrl: imageBase64,
    );
  }

  // Factory untuk system status
  factory AppNotification.systemStatus({
    required String message,
    required bool isActive,
  }) {
    return AppNotification(
      title: isActive ? '✅ Sistem Aktif' : '🔴 Sistem Nonaktif',
      body: message,
      time: DateTime.now(),
      type: NotificationType.systemStatus,
      priority: NotificationPriority.low,
    );
  }

  // Copy with method
  AppNotification copyWith({
    String? title,
    String? body,
    DateTime? time,
    NotificationType? type,
    NotificationPriority? priority,
    Map<String, dynamic>? data,
    String? imageUrl,
    bool? isRead,
  }) {
    return AppNotification(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      time: time ?? this.time,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      data: data ?? this.data,
      imageUrl: imageUrl ?? this.imageUrl,
      isRead: isRead ?? this.isRead,
    );
  }

  // To JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'time': time.toIso8601String(),
      'type': type.toString(),
      'priority': priority.toString(),
      'data': data,
      'imageUrl': imageUrl,
      'isRead': isRead,
    };
  }

  // From JSON
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'],
      title: json['title'],
      body: json['body'],
      time: DateTime.parse(json['time']),
      type: NotificationType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => NotificationType.general,
      ),
      priority: NotificationPriority.values.firstWhere(
        (e) => e.toString() == json['priority'],
        orElse: () => NotificationPriority.medium,
      ),
      data: json['data'],
      imageUrl: json['imageUrl'],
      isRead: json['isRead'] ?? false,
    );
  }

  String getTimeAgo() {
    final difference = DateTime.now().difference(time);
    if (difference.inSeconds < 60) {
      return 'Baru saja';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} menit lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} jam lalu';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} hari lalu';
    } else {
      return '${(difference.inDays / 7).floor()} minggu lalu';
    }
  }
}

enum NotificationType {
  general,
  pestDetection,
  systemStatus,
  weather,
  irrigation,
}

enum NotificationPriority {
  low,
  medium,
  high,
  critical,
}