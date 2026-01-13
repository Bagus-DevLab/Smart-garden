import 'package:flutter/material.dart';
import 'package:smart_farming/theme/app_colors.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pest_api_service.dart';
import 'pest_gallery_page.dart';
import 'package:intl/intl.dart';

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
  
  // ✅ ESP32 Status
  bool _esp32Online = false;
  String? _esp32LastSeen;
  // ignore: unused_field
  int? _esp32LastSeenSeconds;

  String _connectionStatus = 'Connecting';
  String overallStatus = 'Aman';
  Color statusColor = AppColors.success;
  int totalDetections = 0;
  List<PestDetection> recentDetections = [];
  String _lastDetectionTime = '-';

  @override
  void initState() {
    super.initState();
    _apiService = PestApiService();
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

  // ✅ UPDATE: Test connection dengan ESP32 status
  Future<void> _testConnection() async {
    final result = await _apiService.testConnection();
    if (!mounted) return;

    setState(() {
      isSystemConnected = result['success'] == true;
      _connectionStatus = isSystemConnected ? 'Connected' : 'Error: ${result['message']}';
      
      // ✅ Parse ESP32 status dari response
      if (result['success'] == true && result['data'] != null) {
        final data = result['data'] as Map<String, dynamic>;
        _esp32Online = data['esp32_online'] == true;
        _esp32LastSeen = data['esp32_last_seen']?.toString();
        _esp32LastSeenSeconds = data['esp32_last_seen_seconds_ago'] as int?;
        
        debugPrint('🔌 ESP32 Status: $_esp32Online');
      }
    });
  }

  Future<void> _loadHistory() async {
    if (!isSystemEnabled) {
      setState(() {
        isSystemConnected = false;
        _connectionStatus = 'Sistem Nonaktif';
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
        _connectionStatus = 'Connected';
        _updateAlertStatus();
      });

      _cacheImages();
      await _saveCache();
      
      // ✅ Update ESP32 status after loading history
      await _updateEsp32Status();
    } catch (e) {
      if (mounted) {
        setState(() {
          isSystemConnected = false;
          _connectionStatus = e.toString().contains('timeout') ? 'Timeout' : 'Error';
        });
      }
    }
  }

  // ✅ NEW: Update ESP32 status
  Future<void> _updateEsp32Status() async {
    try {
      final result = await _apiService.testConnection();
      if (!mounted) return;
      
      if (result['success'] == true && result['data'] != null) {
        final data = result['data'] as Map<String, dynamic>;
        setState(() {
          _esp32Online = data['esp32_online'] == true;
          _esp32LastSeen = data['esp32_last_seen']?.toString();
          _esp32LastSeenSeconds = data['esp32_last_seen_seconds_ago'] as int?;
        });
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
      _updateEsp32Status(); // ✅ Update ESP32 status setiap polling
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
          _connectionStatus = 'Connected';
          isSystemConnected = true;
          
          // ✅ Update ESP32 status from /data endpoint
          if (data['esp32Status'] != null) {
            final esp32Status = data['esp32Status'] as Map<String, dynamic>;
            _esp32Online = esp32Status['online'] == true;
            _esp32LastSeen = esp32Status['lastSeen']?.toString();
            _esp32LastSeenSeconds = esp32Status['lastSeenSecondsAgo'] as int?;
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
          _connectionStatus = e.toString().contains('timeout') ? 'Timeout' : 'Disconnected';
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
    _showSnackBar('🐛 ${detection.pestName} terdeteksi! (${detection.confidence}%)', isError: false);
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

  void _enableSystem() {
    setState(() {
      isSystemEnabled = true;
      _connectionStatus = 'Connecting';
    });
    _loadHistory().then((_) => _startPolling());
    _showSnackBar('🟢 Sistem monitoring diaktifkan', isError: false);
  }

  void _disableSystem() {
    _stopPolling();
    setState(() {
      isSystemEnabled = false;
      isSystemConnected = false;
      _connectionStatus = 'Sistem Nonaktif';
    });
    _showSnackBar('🔴 Sistem monitoring dinonaktifkan', isError: false);
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
        _showSnackBar('✅ Capture berhasil! Menunggu hasil deteksi...', isError: false);
        await Future.delayed(const Duration(seconds: 2));
        
        for (int i = 0; i < 5; i++) {
          await Future.delayed(const Duration(seconds: 2));
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
                    const SizedBox(height: 8),
                    _buildDetailRow(Icons.fingerprint, 'ID', '#${detection.id}'),
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

  // ✅ Format datetime untuk tampilan user-friendly
  String _formatDateTime(String? datetime) {
    if (datetime == null || datetime.isEmpty) return '-';
    
    try {
      final dt = DateTime.parse(datetime);
      // Format: 09 Jan 2026, 14:30
      return DateFormat('dd MMM yyyy, HH:mm').format(dt);
    } catch (e) {
      return datetime;
    }
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
              // ✅ NEW: ESP32 Status Card (Fixed)
              _buildEsp32StatusCard(),
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
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.bug_report, color: AppColors.warning, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Deteksi Hama', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              Text('Monitoring & identifikasi hama padi', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
        _buildConnectionBadge(),
      ],
    );
  }

  Widget _buildConnectionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isSystemConnected ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (isSystemConnected ? AppColors.success : AppColors.error).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: isSystemConnected ? AppColors.success : AppColors.error, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(_connectionStatus, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSystemConnected ? AppColors.success : AppColors.error)),
        ],
      ),
    );
  }

  // ✅ FIXED: ESP32 Status Card - Tidak bergerak saat update & format datetime lebih mudah dibaca
  Widget _buildEsp32StatusCard() {
    final statusColor = _esp32Online ? AppColors.success : AppColors.error;
    final statusText = _esp32Online ? 'ESP32 Online' : 'ESP32 Offline';
    
    // ✅ Format datetime yang lebih user-friendly
    String lastSeenText = '-';
    if (_esp32Online) {
      lastSeenText = 'Aktif sekarang';
    } else if (_esp32LastSeen != null && _esp32LastSeen!.isNotEmpty) {
      lastSeenText = _formatDateTime(_esp32LastSeen);
    } else {
      lastSeenText = 'Belum pernah terhubung';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Status Indicator
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: statusColor.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.developer_board,
                  color: statusColor,
                  size: 28,
                ),
                if (_esp32Online)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surfaceVariant,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          
          // Status Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: _esp32Online ? [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ] : [],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  lastSeenText,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!_esp32Online) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Perangkat tidak terhubung',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Status Icon
          Icon(
            _esp32Online ? Icons.check_circle : Icons.cancel,
            color: statusColor,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildOverallStatusCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor, statusColor.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status Hama Padi', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(overallStatus.toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      !isSystemEnabled ? 'Sistem monitoring sedang nonaktif'
                          : totalDetections >= 2 ? 'Terdeteksi aktivitas hama di beberapa area'
                          : totalDetections == 1 ? 'Terdeteksi 1 aktivitas hama'
                          : 'Tidak ada deteksi hama saat ini',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                child: Icon(
                  !isSystemEnabled ? Icons.power_settings_new
                      : totalDetections >= 2 ? Icons.warning_amber
                      : totalDetections == 1 ? Icons.info_outline
                      : Icons.check_circle,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusInfo('Total Deteksi', totalDetections.toString()),
                Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.3)),
                _buildStatusInfo('Status', overallStatus),
                Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.3)),
                _buildStatusInfo('Update', _lastDetectionTime != '-' ? PestDetection(id: 0, timestamp: _lastDetectionTime, imageBase64: '', motionDetected: false, confidence: 0, pestName: '').getTimeAgo().split(' ')[0] : '-'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusInfo(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.9))),
      ],
    );
  }

  Widget _buildQuickStats() {
    final avgConfidence = recentDetections.isEmpty ? 0 : (recentDetections.map((d) => d.confidence).reduce((a, b) => a + b) / recentDetections.length).round();

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: [
        _buildStatCard(icon: Icons.pest_control, label: 'Jenis Hama', value: recentDetections.map((d) => d.pestName).toSet().length.toString(), color: AppColors.error),
        _buildStatCard(icon: Icons.trending_up, label: 'Akurasi', value: '$avgConfidence%', color: AppColors.success),
        _buildStatCard(icon: Icons.access_time, label: 'Update', value: _lastDetectionTime != '-' ? PestDetection(id: 0, timestamp: _lastDetectionTime, imageBase64: '', motionDetected: false, confidence: 0, pestName: '').getTimeAgo().split(' ')[0] : '-', color: AppColors.info),
      ],
    );
  }

  Widget _buildStatCard({required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
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
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.textTertiary.withValues(alpha: 0.2)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pest_control_outlined, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(!isSystemEnabled ? 'Sistem monitoring nonaktif' : 'Belum ada deteksi hama', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
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
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 130,
              decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: _imageCache.containsKey(detection.id)
                        ? Image.memory(_imageCache[detection.id]!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                        : Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [severityColor.withValues(alpha: 0.3), severityColor.withValues(alpha: 0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            ),
                            child: Center(child: Icon(Icons.bug_report, size: 60, color: Colors.white.withValues(alpha: 0.5))),
                          ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('${detection.confidence}%', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(detection.pestName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: severityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text(detection.getSeverityLabel(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: severityColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.fingerprint, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(child: Text('ID: ${detection.id}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(detection.getTimeAgo(), style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
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
    // ✅ Button disabled if ESP32 is offline
    final canCapture = isSystemEnabled && isSystemConnected && !_isCapturing && _esp32Online;
    
    return InkWell(
      onTap: canCapture ? _triggerManualCapture : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: canCapture 
                ? [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)] 
                : [AppColors.textTertiary, AppColors.textTertiary.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: canCapture ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: _isCapturing 
                  ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) 
                  : Icon(
                      canCapture ? Icons.camera_alt : Icons.camera_alt_outlined,
                      color: Colors.white, 
                      size: 28,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isCapturing ? 'Mengambil Gambar...' : 'Ambil Gambar Manual', 
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isCapturing 
                        ? 'Mohon tunggu...' 
                        : !isSystemEnabled 
                            ? 'Sistem harus diaktifkan'
                            : !isSystemConnected
                                ? 'API tidak terhubung'
                                : !_esp32Online
                                    ? 'ESP32 tidak terhubung'
                                    : 'Klik untuk mengambil foto hama',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
            if (!_isCapturing) Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.9), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemToggle() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: (isSystemEnabled ? AppColors.success : AppColors.textTertiary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.power_settings_new, color: isSystemEnabled ? AppColors.success : AppColors.textTertiary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sistem Deteksi Hama', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(isSystemEnabled ? 'Sistem aktif dan memantau area' : 'Sistem dinonaktifkan', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(value: isSystemEnabled, onChanged: (value) => value ? _enableSystem() : _disableSystem(), activeColor: AppColors.success),
        ],
      ),
    );
  }
}