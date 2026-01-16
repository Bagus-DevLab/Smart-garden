import 'package:flutter/material.dart';
import 'package:smart_farming/theme/app_colors.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Bloc imports
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/notification/notification_cubit.dart';
import '../cubit/notification/notification_state.dart';

// Service imports
import '../services/pest_api_service.dart';
import '../services/pest_notification_service.dart';

// Model imports
import '../models/app_notification.dart';

// Page imports
import 'pest_gallery_page.dart';

class PestDetectionPage extends StatefulWidget {
  const PestDetectionPage({super.key});

  @override
  State<PestDetectionPage> createState() => _PestDetectionPageState();
}

class _PestDetectionPageState extends State<PestDetectionPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late PestApiService _apiService;
  Timer? _pollTimer;
  Set<int> _processedIds = {};
  Map<int, Uint8List> _imageCache = {};

  bool isSystemConnected = false;
  bool isSystemEnabled = true;
  bool _isCapturing = false;
  bool _isInitialized = false;
  bool _isTogglingSystem = false;
  
  // ESP32 Status
  bool _esp32Online = false;
  bool _esp32CameraSleepMode = false;

  String overallStatus = 'Aman';
  Color statusColor = AppColors.success;
  int totalDetections = 0;
  List<PestDetection> recentDetections = [];
  String _lastDetectionTime = '-';
  DateTime? _lastOnlineTime;

  @override
  void initState() {
    super.initState();
    _apiService = PestApiService();
    
    // Initialize notification service
    PestNotificationService.initialize();
    PestNotificationService.requestPermissions();
    
    _initializeApp();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = recentDetections.map((d) => d.toJson()).toList();
      await prefs.setString('cached_detections', jsonEncode(data));
      await prefs.setInt('total_detections', totalDetections);
      await prefs.setString('overall_status', overallStatus);
      await prefs.setString('last_detection_time', _lastDetectionTime);
      await prefs.setBool('system_enabled', isSystemEnabled);
      
      // Save last online time
      if (_lastOnlineTime != null) {
        await prefs.setString('last_online_time', _lastOnlineTime!.toIso8601String());
      }
    } catch (e) {
      debugPrint('❌ Save cache error: $e');
    }
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_detections');
      
      if (cached != null && mounted) {
        final List<dynamic> data = jsonDecode(cached);
        setState(() {
          recentDetections = data.map((json) => PestDetection.fromJson(json)).toList();
          _processedIds = recentDetections.map((d) => d.id).toSet();
          totalDetections = prefs.getInt('total_detections') ?? 0;
          overallStatus = prefs.getString('overall_status') ?? 'Aman';
          _lastDetectionTime = prefs.getString('last_detection_time') ?? '-';
          isSystemEnabled = prefs.getBool('system_enabled') ?? true;
          
          // Load last online time
          final lastOnlineStr = prefs.getString('last_online_time');
          if (lastOnlineStr != null) {
            _lastOnlineTime = DateTime.parse(lastOnlineStr);
          }
          
          _updateStatusColor();
        });
        _cacheImages();
        debugPrint('✅ Loaded ${recentDetections.length} cached detections');
      }
    } catch (e) {
      debugPrint('❌ Load cache error: $e');
    }
  }

  Future<void> _initializeApp() async {
    await _loadApiUrl();
    await _loadCache();
    
    if (!_isInitialized) {
      await _testConnection();
      await _loadHistory();
      _isInitialized = true;
    }
    
    if (isSystemEnabled) _startPolling();
  }

  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('api_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _apiService.updateApiUrl(savedUrl);
    } else {
      await prefs.setString('api_url', 'https://pestdetectionapi-production.up.railway.app');
    }
  }

  Future<void> _testConnection() async {
    final result = await _apiService.testConnection();
    if (!mounted) return;

    setState(() {
      final wasOnline = _esp32Online;
      isSystemConnected = result['success'] == true;
      
      if (result['success'] == true && result['data'] != null) {
        final data = result['data'] as Map<String, dynamic>;
        _esp32Online = data['esp32_online'] == true;
        _esp32CameraSleepMode = data['esp32_camera_sleep_mode'] ?? false;
        
        // Track online/offline transitions
        if (_esp32Online && !wasOnline) {
          // Just came online
          _lastOnlineTime = DateTime.now();
        } else if (!_esp32Online && wasOnline) {
          // Just went offline - record the time
          _lastOnlineTime = DateTime.now();
        } else if (_esp32Online) {
          // Still online - update time
          _lastOnlineTime = DateTime.now();
        }
        // If offline and was offline, keep the existing _lastOnlineTime
        
        debugPrint('🔌 ESP32 Status: $_esp32Online');
        debugPrint('📷 Camera Sleep: $_esp32CameraSleepMode');
        if (_lastOnlineTime != null) {
          debugPrint('⏰ Last online: $_lastOnlineTime');
        }
      }
    });
    
    _saveCache();
  }

  Future<void> _loadHistory() async {
    if (!isSystemEnabled) {
      setState(() {
        isSystemConnected = false;
      });
      return;
    }

    try {
      final detections = await _apiService.fetchHistory(limit: 50);
      if (!mounted) return;

      setState(() {
        recentDetections = detections;
        _processedIds = detections.map((d) => d.id).toSet();
        totalDetections = detections.length;
        isSystemConnected = true;
        _updateAlertStatus();
      });

      _cacheImages();
      await _saveCache();
      await _updateEsp32Status();
    } catch (e) {
      if (mounted) {
        setState(() {
          isSystemConnected = false;
        });
      }
    }
  }

  Future<void> _updateEsp32Status() async {
    try {
      final result = await _apiService.testConnection();
      if (!mounted) return;
      
      if (result['success'] == true && result['data'] != null) {
        final data = result['data'] as Map<String, dynamic>;
        final wasOnline = _esp32Online;
        final isNowOnline = data['esp32_online'] == true;
        
        setState(() {
          _esp32Online = isNowOnline;
          _esp32CameraSleepMode = data['esp32_camera_sleep_mode'] ?? false;
          
          // Track online/offline transitions
          if (isNowOnline && !wasOnline) {
            // Just came online
            _lastOnlineTime = DateTime.now();
          } else if (!isNowOnline && wasOnline) {
            // Just went offline
            _lastOnlineTime = DateTime.now();
          } else if (isNowOnline) {
            // Still online
            _lastOnlineTime = DateTime.now();
          }
          // If offline and was offline, keep existing time
        });
        
        _saveCache();
      }
    } catch (e) {
      debugPrint('❌ Update ESP32 status error: $e');
    }
  }

  void _cacheImages() {
    for (var detection in recentDetections) {
      if (!_imageCache.containsKey(detection.id)) {
        final imageData = _apiService.decodeImage(detection.imageBase64);
        if (imageData != null) _imageCache[detection.id] = imageData;
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkNewDetection();
      _updateEsp32Status();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
  }

  Future<void> _checkNewDetection() async {
    if (!isSystemEnabled) return;

    try {
      final result = await _apiService.checkNewDetection();
      if (!mounted) return;

      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>;

        setState(() {
          _lastDetectionTime = data['lastDetection']?.toString() ?? '-';
          isSystemConnected = true;
          
          if (data['esp32Status'] != null) {
            final esp32Status = data['esp32Status'] as Map<String, dynamic>;
            _esp32Online = esp32Status['online'] == true;
            _esp32CameraSleepMode = esp32Status['cameraSleepMode'] ?? false;
          }
        });

        if (data['newDetection'] == true && data['id'] != null) {
          final newId = data['id'] as int;
          if (!_processedIds.contains(newId)) {
            final newDetection = _apiService.parseDetection(data);
            if (newDetection != null) _addNewDetection(newDetection);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isSystemConnected = false;
        });
      }
    }
  }

  void _addNewDetection(PestDetection detection) {
    if (_processedIds.contains(detection.id) || !mounted) return;

    setState(() {
      recentDetections.insert(0, detection);
      _processedIds.add(detection.id);

      final imageData = _apiService.decodeImage(detection.imageBase64);
      if (imageData != null) _imageCache[detection.id] = imageData;

      if (recentDetections.length > 50) {
        final removed = recentDetections.removeLast();
        _processedIds.remove(removed.id);
        _imageCache.remove(removed.id);
      }

      totalDetections = recentDetections.length;
      _updateAlertStatus();
    });

    _saveCache();
    
    _triggerPestNotification(detection);
    
    _showSnackBar('🐛 ${detection.pestName} terdeteksi! (${detection.confidence}%)', isError: false);
  }

  Future<void> _triggerPestNotification(PestDetection detection) async {
    try {
      final notificationCubit = context.read<NotificationCubit>();
      final imageData = _apiService.decodeImage(detection.imageBase64);
      
      await PestNotificationService.showPestDetection(
        pestName: detection.pestName,
        confidence: detection.confidence,
        detectionId: detection.id,
        imageBytes: imageData,
        notificationCubit: notificationCubit,
      );
      
      debugPrint('✅ Notification triggered for: ${detection.pestName}');
    } catch (e) {
      debugPrint('❌ Failed to trigger notification: $e');
    }
  }

  Future<void> _deleteDetection(int id) async {
    final success = await _apiService.deleteDetection(id);

    if (success) {
      setState(() {
        recentDetections.removeWhere((d) => d.id == id);
        _processedIds.remove(id);
        _imageCache.remove(id);
        totalDetections = recentDetections.length;
        _updateAlertStatus();
      });
      await _saveCache();
      _showSnackBar('✅ Deteksi berhasil dihapus', isError: false);
    } else {
      _showSnackBar('❌ Gagal menghapus deteksi', isError: true);
    }
  }

  void _updateAlertStatus() {
    final count = recentDetections.length;
    overallStatus = count >= 2 ? 'Bahaya' : count > 0 ? 'Waspada' : 'Aman';
    _updateStatusColor();
  }

  void _updateStatusColor() {
    statusColor = overallStatus == 'Bahaya' ? AppColors.error 
                : overallStatus == 'Waspada' ? AppColors.warning 
                : AppColors.success;
  }

  Future<void> _enableSystem() async {
    if (_isTogglingSystem) return;
    
    setState(() {
      _isTogglingSystem = true;
    });

    try {
      _showSnackBar('🔄 Mengaktifkan sistem...', isError: false);
      
      final result = await _apiService.setSystemActive(true);
      
      if (result['success'] == true) {
        if (mounted) {
          setState(() {
            isSystemEnabled = true;
            _esp32CameraSleepMode = false;
          });
        }
        
        await _saveCache();
        await _loadHistory();
        _startPolling();
        
        if (mounted) {
          final notificationCubit = context.read<NotificationCubit>();
          await PestNotificationService.showSystemStatus(
            message: 'Sistem monitoring diaktifkan. Kamera mulai beroperasi.',
            isActive: true,
            notificationCubit: notificationCubit,
          );
          
          _showSnackBar('🟢 Sistem aktif! Kamera diaktifkan', isError: false);
        }
      } else {
        _showSnackBar(
          '❌ ${result['message'] ?? 'Gagal mengaktifkan sistem'}', 
          isError: true
        );
      }
    } catch (e) {
      _showSnackBar('❌ Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingSystem = false;
        });
      }
    }
  }

  Future<void> _disableSystem() async {
    if (_isTogglingSystem) return;
    
    setState(() {
      _isTogglingSystem = true;
    });

    try {
      _showSnackBar('🔄 Menonaktifkan sistem...', isError: false);
      
      final result = await _apiService.setSystemActive(false);
      
      _stopPolling();
      
      if (mounted) {
        setState(() {
          isSystemEnabled = false;
          isSystemConnected = false;
          _esp32CameraSleepMode = true;
        });
      }
      
      await _saveCache();
      
      if (result['success'] == true) {
        if (mounted) {
          final notificationCubit = context.read<NotificationCubit>();
          await PestNotificationService.showSystemStatus(
            message: 'Sistem monitoring dinonaktifkan. Kamera berhenti beroperasi.',
            isActive: false,
            notificationCubit: notificationCubit,
          );
          
          _showSnackBar('🔴 Sistem nonaktif! Kamera dimatikan', isError: false);
        }
      } else {
        if (mounted) {
          _showSnackBar(
            '⚠️ Sistem dinonaktifkan (warning: ${result['message']})', 
            isError: false
          );
        }
      }
    } catch (e) {
      _showSnackBar('⚠️ Sistem dinonaktifkan (error: ${e.toString()})', isError: false);
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingSystem = false;
        });
      }
    }
  }

  Future<void> _triggerManualCapture() async {
    if (_isCapturing || !isSystemConnected || !isSystemEnabled) {
      _showSnackBar('❌ ${!isSystemConnected ? "Sistem tidak terhubung" : "Sedang mengambil gambar..."}', isError: true);
      return;
    }

    setState(() => _isCapturing = true);

    try {
      _showSnackBar('📸 Mengirim perintah capture...', isError: false);
      final success = await _apiService.triggerCapture();

      if (success) {
        _showSnackBar('✅ Gambar sedang diproses...', isError: false);
        await Future.delayed(const Duration(milliseconds: 1500));
        
        for (int i = 0; i < 3; i++) {
          await Future.delayed(const Duration(milliseconds: 800));
          await _checkNewDetection();
        }
        
        await _loadHistory();
      } else {
        _showSnackBar('❌ Gagal mengirim perintah capture', isError: true);
      }
    } catch (e) {
      _showSnackBar('❌ Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
  }

  void _showDetailDialog(PestDetection detection) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailImage(detection),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(detection.pestName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getSeverityColor(detection.confidence).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${detection.confidence}%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _getSeverityColor(detection.confidence))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(Icons.access_time, 'Waktu', detection.getTimeAgo()),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showDeleteDialog(detection.id, detection.pestName);
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Hapus'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: BorderSide(color: AppColors.error),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            child: const Text('Tutup'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(int id, String pestName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Deteksi?'),
        content: Text('Anda yakin ingin menghapus deteksi "$pestName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteDetection(id);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailImage(PestDetection detection) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: _imageCache.containsKey(detection.id)
          ? Image.memory(_imageCache[detection.id]!, fit: BoxFit.cover, height: 300, width: double.infinity)
          : Container(
              height: 300,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Icon(Icons.bug_report, size: 80, color: AppColors.textSecondary),
            ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text('$label:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
      ],
    );
  }

  Color _getSeverityColor(int confidence) {
    if (confidence >= 90) return AppColors.error;
    if (confidence >= 70) return AppColors.warning;
    return AppColors.info;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Container(
      color: AppColors.background,
      child: RefreshIndicator(
        onRefresh: _loadHistory,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildCameraStatusCard(),
              const SizedBox(height: 20),
              _buildOverallStatusCard(),
              const SizedBox(height: 20),
              _buildQuickStats(),
              const SizedBox(height: 20),
              _buildDetectionGallery(),
              const SizedBox(height: 20),
              _buildActionButtons(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return BlocBuilder<NotificationCubit, NotificationState>(
      builder: (context, state) {
        final pestNotifCount = state.notifications
            .where((n) => n.type == NotificationType.pestDetection && !n.isRead)
            .length;
        
        if (pestNotifCount > 0) {
          debugPrint('📬 Unread pest notifications: $pestNotifCount');
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.bug_report_outlined,
                  color: AppColors.warning,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deteksi Hama',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Monitoring & identifikasi',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _buildWifiIndicator(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWifiIndicator() {
    final bool isConnected = isSystemConnected && _esp32Online;
    final Color wifiColor = isConnected ? AppColors.success : AppColors.error;
    
    return GestureDetector(
      onTap: _showConnectionDetails,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: wifiColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: wifiColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Icon(
          isConnected ? Icons.wifi : Icons.wifi_off,
          color: wifiColor,
          size: 20,
        ),
      ),
    );
  }

  void _showConnectionDetails() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isSystemConnected ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isSystemConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: isSystemConnected ? AppColors.success : AppColors.error,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status Koneksi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSystemConnected ? 'Sistem terhubung' : 'Ada masalah koneksi',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildConnectionItem(
              icon: Icons.cloud_rounded,
              label: 'Server API',
              status: isSystemConnected ? 'Terhubung' : 'Terputus',
              isConnected: isSystemConnected,
            ),
            const SizedBox(height: 12),
            _buildConnectionItem(
              icon: Icons.memory_rounded,
              label: 'ESP32 Device',
              status: _esp32Online ? 'Online' : 'Offline',
              isConnected: _esp32Online,
            ),
            const SizedBox(height: 12),
            _buildConnectionItem(
              icon: Icons.videocam_rounded,
              label: 'Kamera',
              status: _esp32CameraSleepMode ? 'Sleep Mode' : (_esp32Online ? 'Aktif' : 'Nonaktif'),
              isConnected: _esp32Online && !_esp32CameraSleepMode,
            ),
            const SizedBox(height: 12),
            _buildConnectionItem(
              icon: Icons.power_settings_new_rounded,
              label: 'Sistem',
              status: isSystemEnabled ? 'Diaktifkan' : 'Dinonaktifkan',
              isConnected: isSystemEnabled,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _testConnection();
                  _updateEsp32Status();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Refresh Status',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionItem({
    required IconData icon,
    required String label,
    required String status,
    required bool isConnected,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected 
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.error.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isConnected ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isConnected ? AppColors.success : AppColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? AppColors.success : AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraStatusCard() {
    final bool cameraActive = isSystemEnabled && _esp32Online && !_esp32CameraSleepMode;
    final Color cameraColor = cameraActive ? AppColors.success : AppColors.textSecondary;
    final String cameraStatusText = !isSystemEnabled 
        ? 'Kamera Nonaktif' 
        : _esp32CameraSleepMode 
            ? 'Kamera Sleep' 
            : _esp32Online 
                ? 'Kamera Aktif' 
                : 'Kamera Offline';
    
    final IconData cameraIcon = !isSystemEnabled || _esp32CameraSleepMode
        ? Icons.videocam_off_outlined
        : Icons.videocam;

    String statusMessage = '';
    if (!isSystemEnabled) {
      statusMessage = 'Sistem monitoring dinonaktifkan';
    } else if (_esp32CameraSleepMode) {
      statusMessage = 'Kamera dalam mode hemat energi';
    } else if (_esp32Online) {
      statusMessage = 'Monitoring area secara realtime';
    } else {
      // Show offline time if available
      if (_lastOnlineTime != null) {
        statusMessage = 'Offline sejak ${_formatOfflineTime(_lastOnlineTime!)}';
      } else {
        statusMessage = 'Menunggu koneksi ESP32...';
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cameraColor.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cameraColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              cameraIcon,
              color: cameraColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: cameraColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      cameraStatusText,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  statusMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to format offline time
  String _formatOfflineTime(DateTime offlineTime) {
    final now = DateTime.now();
    
    // If offline happened today, show time
    if (offlineTime.year == now.year && 
        offlineTime.month == now.month && 
        offlineTime.day == now.day) {
      return 'pukul ${offlineTime.hour.toString().padLeft(2, '0')}:${offlineTime.minute.toString().padLeft(2, '0')}';
    }
    
    // If yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    if (offlineTime.year == yesterday.year && 
        offlineTime.month == yesterday.month && 
        offlineTime.day == yesterday.day) {
      return 'kemarin pukul ${offlineTime.hour.toString().padLeft(2, '0')}:${offlineTime.minute.toString().padLeft(2, '0')}';
    }
    
    // Otherwise show date and time
    return '${offlineTime.day}/${offlineTime.month} pukul ${offlineTime.hour.toString().padLeft(2, '0')}:${offlineTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildOverallStatusCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STATUS HAMA PADI',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      overallStatus.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      !isSystemEnabled ? 'Sistem monitoring sedang nonaktif'
                          : totalDetections >= 2 ? 'Terdeteksi aktivitas hama di beberapa area'
                          : totalDetections == 1 ? 'Terdeteksi 1 aktivitas hama'
                          : 'Tidak ada deteksi hama saat ini',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  !isSystemEnabled ? Icons.power_settings_new
                      : totalDetections >= 2 ? Icons.warning_amber_rounded
                      : totalDetections == 1 ? Icons.info_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusInfo('Total Deteksi', totalDetections.toString()),
                Container(
                  width: 1,
                  height: 32,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                _buildStatusInfo('Status', overallStatus),
                Container(
                  width: 1,
                  height: 32,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                _buildStatusInfo('Update', _getUpdateValue()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getUpdateValue() {
    if (_lastDetectionTime == '-') return '-';
    try {
      final testDetection = PestDetection(
        id: 0,
        timestamp: _lastDetectionTime,
        imageBase64: '',
        motionDetected: false,
        confidence: 0,
        pestName: '',
      );
      final timeAgo = testDetection.getTimeAgo();
      final parts = timeAgo.split(' ');
      return parts.isNotEmpty ? parts[0] : '-';
    } catch (e) {
      return '-';
    }
  }

  Widget _buildStatusInfo(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.75),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats() {
    final avgConfidence = recentDetections.isEmpty ? 0 : (recentDetections.map((d) => d.confidence).reduce((a, b) => a + b) / recentDetections.length).round();
    
    String updateValue = '-';
    if (_lastDetectionTime != '-') {
      try {
        final testDetection = PestDetection(
          id: 0, 
          timestamp: _lastDetectionTime, 
          imageBase64: '', 
          motionDetected: false, 
          confidence: 0, 
          pestName: ''
        );
        final timeAgo = testDetection.getTimeAgo();
        final parts = timeAgo.split(' ');
        updateValue = parts.isNotEmpty ? parts[0] : '-';
      } catch (e) {
        updateValue = '-';
      }
    }

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.pest_control,
            label: 'Jenis Hama',
            value: recentDetections.map((d) => d.pestName).toSet().length.toString(),
            color: AppColors.error,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.trending_up,
            label: 'Akurasi',
            value: '$avgConfidence%',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.access_time,
            label: 'Update',
            value: updateValue,
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Deteksi Terbaru', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            if (recentDetections.isNotEmpty)
              TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PestGalleryPage(detections: recentDetections, imageCache: _imageCache, onDelete: _deleteDetection, apiService: _apiService))).then((_) { if (mounted) setState(() {}); }),
                icon: const Icon(Icons.grid_view, size: 16),
                label: Text('Lihat Semua (${recentDetections.length})'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        recentDetections.isEmpty ? _buildEmptyState() : SizedBox(height: 270, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: recentDetections.take(10).length, itemBuilder: (context, index) => _buildDetectionCard(recentDetections[index]))),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.textTertiary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.pest_control_outlined,
                size: 48,
                color: AppColors.textSecondary.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              !isSystemEnabled ? 'Sistem Nonaktif' : 'Belum Ada Deteksi',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              !isSystemEnabled ? 'Aktifkan sistem untuk monitoring' : 'Area terpantau aman',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionCard(PestDetection detection) {
    final severityColor = _getSeverityColor(detection.confidence);

    return GestureDetector(
      onTap: () => _showDetailDialog(detection),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 14, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.textTertiary.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 130,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: _imageCache.containsKey(detection.id)
                        ? Image.memory(
                            _imageCache[detection.id]!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          )
                        : Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: AppColors.surfaceVariant,
                            child: Center(
                              child: Icon(
                                Icons.bug_report_outlined,
                                size: 48,
                                color: AppColors.textSecondary.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: severityColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${detection.confidence}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    detection.pestName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          detection.getTimeAgo(),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tindakan Cepat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        _buildFeaturedCaptureButton(),
        const SizedBox(height: 16),
        _buildSystemToggle(),
      ],
    );
  }

  Widget _buildFeaturedCaptureButton() {
    final canCapture = isSystemEnabled && isSystemConnected && !_isCapturing && _esp32Online;
    
    return InkWell(
      onTap: canCapture ? _triggerManualCapture : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: canCapture ? AppColors.primary : AppColors.textTertiary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          boxShadow: canCapture ? [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ] : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isCapturing 
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isCapturing ? 'Memproses...' : 'Ambil Gambar Manual',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isCapturing 
                        ? 'Sedang mendeteksi hama...' 
                        : !isSystemEnabled 
                            ? 'Sistem harus diaktifkan'
                            : !isSystemConnected
                                ? 'API tidak terhubung'
                                : !_esp32Online
                                    ? 'ESP32 tidak terhubung'
                                    : 'Klik untuk mengambil foto',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isCapturing && canCapture)
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemToggle() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isSystemEnabled ? AppColors.success : AppColors.textTertiary).withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isSystemEnabled ? AppColors.success : AppColors.textTertiary).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.power_settings_new_rounded,
              color: isSystemEnabled ? AppColors.success : AppColors.textTertiary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sistem Deteksi Hama',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isSystemEnabled 
                      ? 'Kamera aktif & monitoring' 
                      : 'Kamera nonaktif',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_isTogglingSystem)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            )
          else
            Switch(
              value: isSystemEnabled,
              onChanged: (value) => value ? _enableSystem() : _disableSystem(),
              activeColor: AppColors.success,
              inactiveThumbColor: AppColors.textTertiary,
            ),
        ],
      ),
    );
  }
}