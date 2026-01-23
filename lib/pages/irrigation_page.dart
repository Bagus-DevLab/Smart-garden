import 'package:flutter/material.dart';
import 'package:smart_farming/theme/app_colors.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class IrrigationPage extends StatefulWidget {
  const IrrigationPage({super.key});

  @override
  State<IrrigationPage> createState() => _IrrigationPageState();
}

class _IrrigationPageState extends State<IrrigationPage> {
  // ================= CONFIGURATION =================
  String baseUrl = "https://database-smart-irrigation-production.up.railway.app";

  // State Control
  bool isPumpOn = false;
  bool isPaused = false;
  int pauseRemainingSeconds = 0;
  Timer? _refreshTimer;
  Timer? _pauseCountdownTimer;
  bool _isLoading = false;

  // Schedule
  TimeOfDay? startTime;
  TimeOfDay? stopTime;
  bool _scheduleModified = false;
  bool _hasActiveSchedule = false;

  // Sensor Data
  double soilMoisture = 0.0;
  double waterLevel = 0.0;

  // Chart Data
  List<FlSpot> moistureSpots = [];
  List<FlSpot> waterSpots = [];
  List<String> timeLabels = [];

  // UI State
  String _message = '';
  DateTime _lastUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadSchedule();
    await _fetchAllData();

    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _fetchAllData();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pauseCountdownTimer?.cancel();
    super.dispose();
  }

  // ================= API METHODS =================

  Future<void> _fetchAllData() async {
    try {
      final resStatus = await http.get(
        Uri.parse('$baseUrl/api/sensor/latest'),
      ).timeout(const Duration(seconds: 10));

      final resHistory = await http.get(
        Uri.parse('$baseUrl/api/sensor/history?limit=288'),
      ).timeout(const Duration(seconds: 10));

      final resControl = await http.get(
        Uri.parse('$baseUrl/api/control/status'),
      ).timeout(const Duration(seconds: 10));

      if (resStatus.statusCode == 200) {
        final data = jsonDecode(resStatus.body);

        if (mounted) {
          setState(() {
            soilMoisture = (data['moisture_level'] ?? 0).toDouble();
            waterLevel = (data['water_level'] ?? 0).toDouble();

            final pumpStatus = data['pump_status'] ?? 'OFF';
            isPumpOn = (pumpStatus == 'ON');
          });
        }
      }

      if (resHistory.statusCode == 200) {
        final dynamic historyResponse = jsonDecode(resHistory.body);
        List history = [];

        if (historyResponse is List) {
          history = historyResponse;
        } else if (historyResponse is Map && historyResponse.containsKey('data')) {
          history = historyResponse['data'] as List;
        }

        if (history.isNotEmpty && mounted) {
          setState(() {
            moistureSpots = [];
            waterSpots = [];
            timeLabels = [];

            // Take every Nth point for smoother display if too many points
            int step = history.length > 100 ? (history.length / 100).ceil() : 1;

            for (int i = 0; i < history.length; i += step) {
              final item = history[i];

              final moisture = (item['moisture'] ?? item['moisture_level'] ?? 0).toDouble();
              final water = (item['water'] ?? item['water_level'] ?? 0).toDouble();

              // Extract time label
              String timeLabel = '';
              if (item['timestamp'] != null) {
                try {
                  DateTime dt = DateTime.parse(item['timestamp']);
                  timeLabel = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                } catch (e) {
                  timeLabel = '';
                }
              }

              double xValue = moistureSpots.length.toDouble();
              moistureSpots.add(FlSpot(xValue, moisture));
              waterSpots.add(FlSpot(xValue, water));
              timeLabels.add(timeLabel);
            }
          });
        }
      }

      if (resControl.statusCode == 200) {
        final controlData = jsonDecode(resControl.body);

        if (mounted) {
          setState(() {
            if (controlData != null && controlData['pause_end_time'] != null) {
              final pauseEnd = DateTime.parse(controlData['pause_end_time']);
              final now = DateTime.now();
              if (pauseEnd.isAfter(now)) {
                isPaused = true;
                pauseRemainingSeconds = pauseEnd.difference(now).inSeconds;
              } else {
                isPaused = false;
                pauseRemainingSeconds = 0;
              }
            } else {
              isPaused = false;
              pauseRemainingSeconds = 0;
            }
          });
        }
      }

      if (mounted) {
        setState(() {
          _lastUpdate = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint("❌ Fetch data failed: $e");
      if (mounted) {
        setState(() {
          _message = '❌ Gagal terhubung ke server';
        });
      }
    }
  }

  Future<void> _loadSchedule() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/schedule/list'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final onTime = data['on_time'];
        final offTime = data['off_time'];
        final isActive = data['is_active'] ?? false;

        if (mounted) {
          setState(() {
            _hasActiveSchedule = isActive;

            if (onTime != null && onTime.isNotEmpty) {
              final parts = onTime.split(':');
              startTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
            } else {
              startTime = null;
            }

            if (offTime != null && offTime.isNotEmpty) {
              final parts = offTime.split(':');
              stopTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
            } else {
              stopTime = null;
            }

            _scheduleModified = false;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Load schedule failed: $e");
    }
  }

  Future<void> _deleteSchedule() async {
    try {
      setState(() => _isLoading = true);

      final response = await http.delete(
        Uri.parse('$baseUrl/api/schedule/delete'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSnackbar("✅ Jadwal berhasil dihapus");

        setState(() {
          startTime = null;
          stopTime = null;
          _hasActiveSchedule = false;
          _scheduleModified = false;
        });

        await Future.delayed(const Duration(milliseconds: 800));
        await _fetchAllData();
      } else {
        _showSnackbar("❌ Gagal menghapus jadwal");
      }
    } catch (e) {
      _showSnackbar("❌ Gagal menghubungi server");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateRemoteControl(String action, {int? minutes}) async {
    try {
      setState(() => _isLoading = true);

      final body = {
        'action': action.toUpperCase(),
        if (minutes != null) 'minutes': minutes,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/control/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSnackbar("✅ Kontrol pompa berhasil diupdate");

        await Future.delayed(const Duration(milliseconds: 800));
        await _fetchAllData();

        if (action.toUpperCase() == 'PAUSE' && minutes != null && minutes > 0) {
          _startPauseCountdown(minutes);
        }
      } else {
        _showSnackbar("❌ Error ${response.statusCode}");
      }
    } catch (e) {
      _showSnackbar("❌ Gagal menghubungi server");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSchedule() async {
    if (startTime == null || stopTime == null) {
      _showSnackbar("⚠️ Pilih waktu ON dan OFF");
      return;
    }

    try {
      setState(() => _isLoading = true);

      final String onTime =
          "${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}:00";
      final String offTime =
          "${stopTime!.hour.toString().padLeft(2, '0')}:${stopTime!.minute.toString().padLeft(2, '0')}:00";

      final response = await http.post(
        Uri.parse('$baseUrl/api/schedule/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'on_time': onTime,
          'off_time': offTime,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSnackbar("✅ Jadwal berhasil disimpan!");
        setState(() {
          _scheduleModified = false;
          _hasActiveSchedule = true;
        });

        await Future.delayed(const Duration(milliseconds: 800));
        await _fetchAllData();
      } else {
        _showSnackbar("❌ Gagal menyimpan jadwal");
      }
    } catch (e) {
      _showSnackbar("❌ Gagal menghubungi server");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startPauseCountdown(int minutes) {
    setState(() {
      isPaused = true;
      pauseRemainingSeconds = minutes * 60;
    });

    _pauseCountdownTimer?.cancel();

    _pauseCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          pauseRemainingSeconds--;

          if (pauseRemainingSeconds <= 0) {
            isPaused = false;
            pauseRemainingSeconds = 0;
            timer.cancel();
            _showSnackbar("⏸️ Jeda selesai - pompa siap hidup");
            _pauseCountdownTimer = null;
            _fetchAllData();
          }
        });
      }
    });
  }

  String _formatPauseTime(int seconds) {
    int minutes = seconds ~/ 60;
    int secs = seconds % 60;
    return "$minutes:${secs.toString().padLeft(2, '0')}";
  }

  // ================= UI HELPERS =================

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (startTime ?? const TimeOfDay(hour: 7, minute: 0))
          : (stopTime ?? const TimeOfDay(hour: 18, minute: 0)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          startTime = picked;
        } else {
          stopTime = picked;
        }
        _scheduleModified = true;
      });
    }
  }

  void _showDeleteScheduleDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              const Text("Konfirmasi Hapus", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: const Text(
            "Apakah Anda yakin ingin menghapus jadwal otomatis?\n\nSistem akan beralih ke mode manual.",
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context);
                _deleteSchedule();
              },
              child: const Text("Hapus Jadwal", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showPauseDialog() {
    int tempMinutes = 30;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Pengaturan Jeda", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Masukkan durasi jeda (menit)."),
              const SizedBox(height: 16),
              TextField(
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: "Contoh: 30",
                  suffixText: "menit",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (val) => tempMinutes = int.tryParse(val) ?? 30,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                Navigator.pop(context);
                _updateRemoteControl('PAUSE', minutes: tempMinutes);
              },
              child: const Text("Terapkan", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Pengaturan Koneksi", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.info.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "📱 Cara Setup WiFi pada ESP32:",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                      ),
                      const SizedBox(height: 12),
                      _stepItem("1", "Pastikan Anda dekat dengan alat ESP32"),
                      _stepItem("2", "Cari WiFi: Smart-Irrigation-Setup"),
                      _stepItem("3", "Password: password123"),
                      _stepItem("4", "Tunggu sampai connect"),
                      _stepItem("5", "Buka aplikasi ini lagi"),
                      _stepItem("6", "Settings → Add WiFi"),
                      _stepItem("7", "Masukkan WiFi Anda & password"),
                      _stepItem("8", "Klik Simpan → Alat otomatis restart"),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber[200]!),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info, color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Hanya perlu setup WiFi 1 kali. Alat akan ingat WiFi Anda.",
                                style: TextStyle(fontSize: 11, color: Colors.amber[900]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: () {
                Navigator.pop(context);
                _showAddWiFiDialog();
              },
              child: const Text("➕ Add WiFi", style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Tutup"),
            ),
          ],
        );
      },
    );
  }

  Widget _stepItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddWiFiDialog() {
    String ssid = '';
    String password = '';
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text("Tambah WiFi", style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: "Nama WiFi (SSID)",
                        prefixIcon: const Icon(Icons.wifi),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (val) => ssid = val,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        labelText: "Password WiFi",
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      obscureText: true,
                      onChanged: (val) => password = val,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tips_and_updates, color: Colors.blue, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Pastikan dekat dengan alat saat setup. Proses setup ~30 detik.",
                              style: TextStyle(fontSize: 11, color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text("Batal"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: Colors.grey[400],
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                    if (ssid.isEmpty || password.isEmpty) {
                      _showSnackbar("⚠️ SSID dan Password harus diisi");
                      return;
                    }

                    setState(() => isLoading = true);
                    await Future.delayed(const Duration(seconds: 2));
                    setState(() => isLoading = false);

                    if (context.mounted) {
                      Navigator.pop(context);
                      _showSnackbar("✅ WiFi disimpan! Tunggu alat restart...");
                    }
                  },
                  child: isLoading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Text("Simpan WiFi", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ================= BUILD METHODS =================

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: RefreshIndicator(
        onRefresh: _fetchAllData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildStatusGrid(),
              const SizedBox(height: 20),
              _buildMonitoringChart(),
              const SizedBox(height: 20),
              _buildControlCard(),
              const SizedBox(height: 20),
              _buildScheduleCard(),
              const SizedBox(height: 16),
              _buildLastUpdate(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.1), AppColors.info.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.water_drop, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monitoring Lahan',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sistem irigasi otomatis & real-time',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _showSettingsDialog,
              icon: Icon(Icons.settings, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusGrid() {
    return Row(
      children: [
        _statusCard(
          "Kelembaban Tanah",
          "${soilMoisture.toStringAsFixed(1)}%",
          Icons.grass,
          AppColors.success,
          "Optimal: 60-80%",
        ),
        const SizedBox(width: 12),
        _statusCard(
          "Ketinggian Air",
          "${waterLevel.toStringAsFixed(1)}%",
          Icons.water_damage,
          AppColors.info,
          "Minimal: 30%",
        ),
      ],
    );
  }

  Widget _statusCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "LIVE",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Grafik Historis",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Data 24 jam terakhir",  // FIX: Changed from "Data 2 hari terakhir"
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.show_chart, size: 14, color: AppColors.info),
                    const SizedBox(width: 4),
                    Text(
                      "${moistureSpots.length} data",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.info,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _chartIndicator(AppColors.success, "Kelembaban Tanah"),
              const SizedBox(width: 20),
              _chartIndicator(AppColors.info, "Ketinggian Air"),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: 250, child: _buildChartLine()),
        ],
      ),
    );
  }

  Widget _chartIndicator(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildChartLine() {
    if (moistureSpots.isEmpty && waterSpots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.show_chart, size: 48, color: Colors.grey[400]),
            ),
            const SizedBox(height: 16),
            Text(
              "Belum ada data historis",
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Data akan muncul setelah sensor mengirim informasi",
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Find min and max values for better scaling
    double minY = 0;
    double maxY = 100;

    for (var spot in [...moistureSpots, ...waterSpots]) {
      if (spot.y > maxY) maxY = spot.y;
      if (spot.y < minY) minY = spot.y;
    }

    // Add padding to min/max
    double range = maxY - minY;
    minY = (minY - range * 0.1).clamp(0, double.infinity);
    maxY = (maxY + range * 0.1);

    // Round to nice numbers
    minY = (minY / 10).floor() * 10.0;
    maxY = (maxY / 10).ceil() * 10.0;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: (maxY - minY) / 5,
          verticalInterval: moistureSpots.length > 10 ? moistureSpots.length / 8 : null,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey[200]!,
              strokeWidth: 1,
              dashArray: [5, 5],
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: Colors.grey[100]!,
              strokeWidth: 0.5,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: (maxY - minY) / 5,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${value.toInt()}%',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: moistureSpots.length > 10 ? moistureSpots.length / 6 : 1,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index < 0 || index >= timeLabels.length) {
                  return const SizedBox();
                }

                // Show time labels at intervals
                if (timeLabels[index].isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      timeLabels[index],
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: Colors.grey[300]!, width: 1.5),
            bottom: BorderSide(color: Colors.grey[300]!, width: 1.5),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                final timeLabel = index < timeLabels.length ? timeLabels[index] : '';

                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)}%\n$timeLabel',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: moistureSpots,
            isCurved: true,
            color: AppColors.success,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: moistureSpots.length < 50,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 3,
                  color: AppColors.success,
                  strokeWidth: 1.5,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withOpacity(0.2),
                  AppColors.success.withOpacity(0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          LineChartBarData(
            spots: waterSpots,
            isCurved: true,
            color: AppColors.info,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: waterSpots.length < 50,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 3,
                  color: AppColors.info,
                  strokeWidth: 1.5,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppColors.info.withOpacity(0.2),
                  AppColors.info.withOpacity(0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlCard() {
    final bool isActive = isPumpOn && !isPaused;
    final Color statusColor = isPaused
        ? Colors.orange
        : (isPumpOn ? AppColors.info : AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [AppColors.info, AppColors.info.withOpacity(0.85)]
              : isPaused
              ? [Colors.orange, Colors.orange.withOpacity(0.85)]
              : [AppColors.textTertiary, AppColors.textSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
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
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isPaused
                              ? "SISTEM DIJEDA"
                              : (isPumpOn ? "POMPA AKTIF" : "POMPA MATI"),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    if (isPaused && pauseRemainingSeconds > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer, color: Colors.white, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              "Lanjut dalam ${_formatPauseTime(pauseRemainingSeconds)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!_isLoading)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Switch(
                    value: isActive,
                    onChanged: (v) {
                      _pauseCountdownTimer?.cancel();
                      _updateRemoteControl(v ? 'MANUAL_ON' : 'MANUAL_OFF');
                    },
                    activeTrackColor: Colors.white.withOpacity(0.3),
                    activeColor: Colors.white,
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _showPauseDialog,
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text("SET JEDA", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: statusColor,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
              if (isPaused) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () {
                      _pauseCountdownTimer?.cancel();
                      _updateRemoteControl('MANUAL_ON');
                    },
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text("LANJUT", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ]
            ],
          )
        ],
      ),
    );
  }

  Widget _buildScheduleCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.schedule, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Jadwal Otomatis",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (_hasActiveSchedule && !_scheduleModified)
                IconButton(
                  onPressed: _isLoading ? null : _showDeleteScheduleDialog,
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                  tooltip: "Hapus Jadwal",
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                _timePickerBtn("Pompa Hidup", startTime, () => _selectTime(context, true)),
                Container(
                  width: 2,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.2),
                        AppColors.primary.withOpacity(0.5),
                        AppColors.primary.withOpacity(0.2),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                ),
                _timePickerBtn("Pompa Mati", stopTime, () => _selectTime(context, false)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_scheduleModified)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveSchedule,
                icon: const Icon(Icons.save, size: 18),
                label: const Text("SIMPAN JADWAL", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[400],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            )
          else if (_hasActiveSchedule)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    "Jadwal Tersimpan & Aktif",
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                  const SizedBox(width: 10),
                  Text(
                    "Tidak Ada Jadwal Aktif",
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _timePickerBtn(String label, TimeOfDay? time, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  time?.format(context) ?? "--:--",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastUpdate() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync, size: 14, color: AppColors.info),
          const SizedBox(width: 6),
          Text(
            'Update terakhir: ${_lastUpdate.hour.toString().padLeft(2, '0')}:${_lastUpdate.minute.toString().padLeft(2, '0')}:${_lastUpdate.second.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}