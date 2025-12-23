import 'package:flutter/material.dart';
import 'package:smart_farming/theme/app_colors.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pest_api_service.dart';

class PestDetectionPage extends StatefulWidget {
  const PestDetectionPage({super.key});

  @override
  State<PestDetectionPage> createState() => _PestDetectionPageState();
}

class _PestDetectionPageState extends State<PestDetectionPage> {
  // API Service
  late PestApiService _apiService;
  Timer? _pollTimer;
  Set<int> _processedIds = {};
  final Map<int, Uint8List> _imageCache = {};

  // System Status
  bool isSystemConnected = false;
  bool isSystemEnabled = true;
  String _connectionStatus = 'Connecting';

  // Pest Status
  String overallStatus = 'Aman';
  Color statusColor = AppColors.success;
  int totalDetections = 0;

  // Latest Detections
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

  // =========================================================================
  // INITIALIZATION
  // =========================================================================

  Future<void> _initializeApp() async {
    await _loadApiUrl();
    await _loadHistory();
    if (isSystemEnabled) {
      _startPolling();
    }
  }

  Future<void> _loadApiUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('api_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _apiService.updateApiUrl(savedUrl);
      }
    } catch (e) {
      debugPrint('Load API URL error: $e');
    }
  }

  Future<void> _saveApiUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_url', url);
      _apiService.updateApiUrl(url);
    } catch (e) {
      debugPrint('Save API URL error: $e');
    }
  }

  // =========================================================================
  // API CALLS
  // =========================================================================

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
    } catch (e) {
      if (mounted) {
        setState(() {
          isSystemConnected = false;
          _connectionStatus = e.toString().contains('timeout') ? 'Timeout' : 'Error';
        });
      }
      debugPrint('Load history error: $e');
    }
  }

  void _cacheImages() {
    for (var detection in recentDetections) {
      if (!_imageCache.containsKey(detection.id)) {
        final imageData = _apiService.decodeImage(detection.imageBase64);
        if (imageData != null) {
          _imageCache[detection.id] = imageData;
        }
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkNewDetection());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _checkNewDetection() async {
    if (!isSystemEnabled) {
      if (_connectionStatus != 'Sistem Nonaktif') {
        setState(() {
          _connectionStatus = 'Sistem Nonaktif';
          isSystemConnected = false;
        });
      }
      return;
    }

    try {
      final result = await _apiService.checkNewDetection();
      
      if (!mounted) return;

      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>;

        setState(() {
          _lastDetectionTime = data['lastDetection']?.toString() ?? '-';
          _connectionStatus = 'Connected';
          isSystemConnected = true;
        });

        if (data['newDetection'] == true && data['id'] != null) {
          final newId = data['id'] as int;
          if (!_processedIds.contains(newId)) {
            final newDetection = _apiService.parseDetection(data);
            if (newDetection != null) {
              _addNewDetection(newDetection);
            }
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
    try {
      if (_processedIds.contains(detection.id) || !mounted) return;

      setState(() {
        recentDetections.insert(0, detection);
        _processedIds.add(detection.id);

        // Cache image
        final imageData = _apiService.decodeImage(detection.imageBase64);
        if (imageData != null) {
          _imageCache[detection.id] = imageData;
        }

        // Limit to 50 detections
        if (recentDetections.length > 50) {
          final removed = recentDetections.removeLast();
          _processedIds.remove(removed.id);
          _imageCache.remove(removed.id);
        }

        totalDetections = recentDetections.length;
        _updateAlertStatus();
      });

      _showSnackBar(
        '🐛 ${detection.pestName} terdeteksi! (${detection.confidence}%)',
        isError: false,
      );
    } catch (e) {
      debugPrint('Add detection error: $e');
    }
  }

  Future<void> _deleteDetection(int id) async {
    try {
      final success = await _apiService.deleteDetection(id);

      if (success) {
        setState(() {
          recentDetections.removeWhere((d) => d.id == id);
          _processedIds.remove(id);
          _imageCache.remove(id);
          totalDetections = recentDetections.length;
          _updateAlertStatus();
        });
        _showSnackBar('Deteksi berhasil dihapus', isError: false);
      } else {
        _showSnackBar('Gagal menghapus deteksi', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', isError: true);
    }
  }

  void _updateAlertStatus() {
    final count = recentDetections.length;
    
    setState(() {
      // Logic baru: <1 atau =0 = Aman, >0 dan <2 = Waspada, >=2 = Bahaya
      if (count >= 2) {
        overallStatus = 'Bahaya';
        statusColor = AppColors.error;
      } else if (count > 0 && count < 2) {
        overallStatus = 'Waspada';
        statusColor = AppColors.warning;
      } else {
        overallStatus = 'Aman';
        statusColor = AppColors.success;
      }
    });
  }

  // =========================================================================
  // SYSTEM CONTROL
  // =========================================================================

  void _enableSystem() {
    setState(() {
      isSystemEnabled = true;
      _connectionStatus = 'Connecting';
    });
    
    _loadHistory().then((_) {
      _startPolling();
    });
    
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

  // =========================================================================
  // UI HELPERS
  // =========================================================================

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
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

  void _showSettingsDialog() {
    final controller = TextEditingController(text: _apiService.apiUrl);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.settings, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Pengaturan API'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan URL API Server:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'https://web-production-849bb.up.railway.app/',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'https://web-production-849bb.up.railway.app/',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isEmpty) {
                _showSnackBar('URL tidak boleh kosong', isError: true);
                return;
              }
              
              if (!newUrl.startsWith('http://') && !newUrl.startsWith('https://')) {
                _showSnackBar('URL harus dimulai dengan http:// atau https://', isError: true);
                return;
              }

              Navigator.pop(context);
              
              await _saveApiUrl(newUrl);
              _showSnackBar('API URL berhasil disimpan', isError: false);
              
              setState(() {
                recentDetections.clear();
              });
              await _loadHistory();
              
              if (isSystemEnabled) {
                _startPolling();
              }
            },
            child: const Text('Simpan'),
          ),
        ],
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
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

  void _showDetailDialog(PestDetection detection) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_imageCache.containsKey(detection.id))
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Image.memory(
                    _imageCache[detection.id]!,
                    fit: BoxFit.cover,
                    height: 300,
                    width: double.infinity,
                  ),
                )
              else
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Icon(
                    Icons.bug_report,
                    size: 80,
                    color: AppColors.textSecondary,
                  ),
                ),
              
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            detection.pestName,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getSeverityColor(detection.confidence).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${detection.confidence}%',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _getSeverityColor(detection.confidence),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(Icons.access_time, 'Waktu', detection.getTimeAgo()),
                    const SizedBox(height: 8),
                    _buildDetailRow(Icons.verified, 'Confidence', '${detection.confidence}%'),
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
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Color _getSeverityColor(int confidence) {
    if (confidence >= 90) return AppColors.error;
    if (confidence >= 70) return AppColors.warning;
    return AppColors.info;
  }

  // =========================================================================
  // BUILD UI
  // =========================================================================

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 24),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.bug_report,
                color: AppColors.warning,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Deteksi Hama',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Monitoring & identifikasi hama padi',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSystemConnected 
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSystemConnected 
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isSystemConnected ? AppColors.success : AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _connectionStatus,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSystemConnected ? AppColors.success : AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
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
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
                    Text(
                      'Status Hama Padi',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          overallStatus.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      !isSystemEnabled
                          ? 'Sistem monitoring sedang nonaktif'
                          : totalDetections >= 2
                              ? 'Terdeteksi aktivitas hama di beberapa area'
                              : totalDetections == 1
                                  ? 'Terdeteksi 1 aktivitas hama'
                                  : 'Tidak ada deteksi hama saat ini',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  !isSystemEnabled 
                      ? Icons.power_settings_new 
                      : totalDetections >= 2 
                          ? Icons.warning_amber 
                          : totalDetections == 1
                              ? Icons.info_outline
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
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusInfo('Total Deteksi', totalDetections.toString()),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                _buildStatusInfo('Status', overallStatus),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                _buildStatusInfo('Update', _lastDetectionTime != '-' 
                    ? PestDetection(
                        id: 0, 
                        timestamp: _lastDetectionTime, 
                        imageBase64: '', 
                        motionDetected: false, 
                        confidence: 0, 
                        pestName: ''
                      ).getTimeAgo().split(' ')[0] 
                    : '-'),
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
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats() {
    final avgConfidence = recentDetections.isEmpty
        ? 0
        : (recentDetections.map((d) => d.confidence).reduce((a, b) => a + b) /
            recentDetections.length).round();

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: [
        _buildStatCard(
          icon: Icons.pest_control,
          label: 'Jenis Hama',
          value: recentDetections.map((d) => d.pestName).toSet().length.toString(),
          color: AppColors.error,
        ),
        _buildStatCard(
          icon: Icons.trending_up,
          label: 'Akurasi',
          value: '$avgConfidence%',
          color: AppColors.success,
        ),
        _buildStatCard(
          icon: Icons.access_time,
          label: 'Update',
          value: _lastDetectionTime != '-' 
              ? PestDetection(
                  id: 0, 
                  timestamp: _lastDetectionTime, 
                  imageBase64: '', 
                  motionDetected: false, 
                  confidence: 0, 
                  pestName: ''
                ).getTimeAgo().split(' ')[0] 
              : '-',
          color: AppColors.info,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            Text(
              'Deteksi Terbaru',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (recentDetections.length > 3)
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.grid_view, size: 16),
                label: Text('Lihat Semua (${recentDetections.length})'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        recentDetections.isEmpty
            ? _buildEmptyState()
            : SizedBox(
                height: 270,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: recentDetections.take(10).length,
                  itemBuilder: (context, index) {
                    final detection = recentDetections[index];
                    return _buildDetectionCard(detection);
                  },
                ),
              ),
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
            Icon(
              Icons.pest_control_outlined,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              !isSystemEnabled 
                  ? 'Sistem monitoring nonaktif'
                  : 'Belum ada deteksi hama',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
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
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 8,
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
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  severityColor.withValues(alpha: 0.3),
                                  severityColor.withValues(alpha: 0.6),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.bug_report,
                                size: 60,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${detection.confidence}%',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          detection.pestName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: severityColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          detection.getSeverityLabel(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: severityColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.fingerprint, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'ID: ${detection.id}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        detection.getTimeAgo(),
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary,
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
        Text(
          'Tindakan Cepat',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.refresh,
                label: 'Refresh',
                color: AppColors.info,
                onTap: () => _loadHistory(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.settings,
                label: 'Setting API',
                color: AppColors.textSecondary,
                onTap: () => _showSettingsDialog(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSystemToggle(),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
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
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSystemEnabled 
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.textTertiary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.power_settings_new,
              color: isSystemEnabled ? AppColors.success : AppColors.textTertiary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sistem Deteksi Hama',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isSystemEnabled 
                      ? 'Sistem aktif dan memantau area'
                      : 'Sistem dinonaktifkan',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isSystemEnabled,
            onChanged: (value) {
              if (value) {
                _enableSystem();
              } else {
                _disableSystem();
              }
            },
            activeThumbColor: AppColors.success,
          ),
        ],
      ),
    );
  }
}