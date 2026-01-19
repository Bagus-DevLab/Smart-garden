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

  // Sensor Data
  double soilMoisture = 0.0;
  double waterLevel = 0.0;

  // Chart Data
  List<FlSpot> moistureSpots = [];
  List<FlSpot> waterSpots = [];

  // UI State
  bool _showSettings = false;
  String _message = '';
  DateTime _lastUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Load existing schedule
    await _loadSchedule();

    // Initial data fetch
    await _fetchAllData();

    // Refresh data setiap 5 detik
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

  /// Fetch semua data dari API
  Future<void> _fetchAllData() async {
    try {
      // Ambil latest data
      final resStatus = await http.get(
        Uri.parse('$baseUrl/api/sensor/latest'),
      ).timeout(const Duration(seconds: 10));

      // Ambil history untuk chart
      final resHistory = await http.get(
        Uri.parse('$baseUrl/api/sensor/history?limit=288'),
      ).timeout(const Duration(seconds: 10));

      // Ambil control status
      final resControl = await http.get(
        Uri.parse('$baseUrl/api/control/status'),
      ).timeout(const Duration(seconds: 10));

      if (resStatus.statusCode == 200 && resHistory.statusCode == 200) {
        final data = jsonDecode(resStatus.body);
        final List history = jsonDecode(resHistory.body);
        final controlData = resControl.statusCode == 200 ? jsonDecode(resControl.body) : null;

        if (mounted) {
          setState(() {
            // Update sensor cards
            soilMoisture = (data['moisture_level'] ?? 0).toDouble();
            waterLevel = (data['water_level'] ?? 0).toDouble();

            // Ambil status pompa dari response
            final pumpStatus = data['pump_status'] ?? 'OFF';
            isPumpOn = (pumpStatus == 'ON');

            // Update pause status dari control
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

            debugPrint("🔄 Refreshed - Pump: $pumpStatus, Soil: $soilMoisture%, Water: $waterLevel%, Paused: $isPaused");

            // Update chart
            if (history.isNotEmpty) {
              moistureSpots = history.asMap().entries.map((e) {
                return FlSpot(
                  e.key.toDouble(),
                  (e.value['moisture'] ?? 0).toDouble(),
                );
              }).toList();

              waterSpots = history.asMap().entries.map((e) {
                return FlSpot(
                  e.key.toDouble(),
                  (e.value['water'] ?? 0).toDouble(),
                );
              }).toList();
            }

            _lastUpdate = DateTime.now();
          });
        }
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

  /// Load existing schedule
  Future<void> _loadSchedule() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/schedule/list'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final onTime = data['on_time'];
        final offTime = data['off_time'];

        if (mounted) {
          setState(() {
            if (onTime != null && onTime.isNotEmpty) {
              final parts = onTime.split(':');
              startTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
            }
            if (offTime != null && offTime.isNotEmpty) {
              final parts = offTime.split(':');
              stopTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
            }
            _scheduleModified = false;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Load schedule failed: $e");
    }
  }

  /// Update kontrol pompa
  Future<void> _updateRemoteControl(String action, {int? minutes}) async {
    try {
      setState(() => _isLoading = true);

      final body = {
        'action': action.toUpperCase(),
        if (minutes != null) 'minutes': minutes,
      };

      debugPrint("🔌 Sending control: $body");

      final response = await http.post(
        Uri.parse('$baseUrl/api/control/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      debugPrint("📡 Response Status: ${response.statusCode}");
      debugPrint("📡 Response Body: ${response.body}");

      if (response.statusCode == 200) {
        debugPrint("✅ Control update success: $action");
        _showSnackbar("✅ Kontrol pompa berhasil diupdate");

        // Fetch data terbaru untuk sync state
        await Future.delayed(const Duration(milliseconds: 800));
        await _fetchAllData();

        // Jika pause, set countdown
        if (action.toUpperCase() == 'PAUSE' && minutes != null && minutes > 0) {
          _startPauseCountdown(minutes);
        }
      } else {
        debugPrint("❌ Error: ${response.statusCode} - ${response.body}");
        _showSnackbar("❌ Error ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Error: $e");
      _showSnackbar("❌ Gagal menghubungi server");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Simpan jadwal
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

      debugPrint("📅 Saving schedule: $onTime to $offTime");

      final response = await http.post(
        Uri.parse('$baseUrl/api/schedule/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'on_time': onTime,
          'off_time': offTime,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("✅ Schedule saved successfully");
        _showSnackbar("✅ Jadwal berhasil disimpan!");

        setState(() => _scheduleModified = false);

        await Future.delayed(const Duration(milliseconds: 800));
        await _fetchAllData();
      } else {
        debugPrint("❌ Save schedule failed: ${response.statusCode}");
        _showSnackbar("❌ Gagal menyimpan jadwal");
      }
    } catch (e) {
      debugPrint("❌ Error saving schedule: $e");
      _showSnackbar("❌ Gagal menghubungi server");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Start pause countdown timer
  void _startPauseCountdown(int minutes) {
    debugPrint("⏸️ Starting pause countdown: $minutes minutes");

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
                number.split('').last,
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

                    // Simulate saving WiFi config
                    await Future.delayed(const Duration(seconds: 2));

                    setState(() => isLoading = false);

                    if (mounted) {
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
              const SizedBox(height: 24),
              _buildStatusGrid(),
              const SizedBox(height: 20),
              _buildMonitoringChart(),
              const SizedBox(height: 20),
              _buildControlCard(),
              const SizedBox(height: 20),
              _buildScheduleCard(),
              const SizedBox(height: 12),
              _buildLastUpdate(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.water_drop, color: AppColors.info, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Monitoring Lahan',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Kelembaban tanah & sistem irigasi otomatis',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _showSettingsDialog,
          icon: Icon(Icons.settings, color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildStatusGrid() {
    return Row(
      children: [
        _statusCard("Kelembaban Tanah", "${soilMoisture.toStringAsFixed(1)}%", Icons.grass, AppColors.success),
        const SizedBox(width: 16),
        _statusCard("Ketinggian Air", "${waterLevel.toStringAsFixed(1)}%", Icons.water_damage, AppColors.info),
      ],
    );
  }

  Widget _statusCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringChart() {
    return Container(
      height: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Grafik Historis (24 jam)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _indicator(AppColors.success, "Kelembaban Tanah"),
              const SizedBox(width: 16),
              _indicator(AppColors.info, "Ketinggian Air"),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildChartLine()),
        ],
      ),
    );
  }

  Widget _indicator(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildControlCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPumpOn && !isPaused
              ? [AppColors.info, AppColors.info.withOpacity(0.8)]
              : [AppColors.textTertiary, AppColors.textSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPaused
                        ? "⏸️ SISTEM DIJEDA"
                        : (isPumpOn ? "✅ POMPA AKTIF" : "⭕ POMPA MATI"),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  if (isPaused && pauseRemainingSeconds > 0)
                    Text(
                      "Otomatis lanjut dalam ${_formatPauseTime(pauseRemainingSeconds)}",
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                    ),
                ],
              ),
              if (!_isLoading)
                Switch(
                  value: isPumpOn && !isPaused,
                  onChanged: (v) {
                    debugPrint("🔌 Switch toggled to: $v");
                    _pauseCountdownTimer?.cancel();
                    _updateRemoteControl(v ? 'MANUAL_ON' : 'MANUAL_OFF');
                  },
                  activeTrackColor: Colors.white24,
                  activeColor: Colors.white,
                )
              else
                const SizedBox(
                  width: 40,
                  height: 24,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _showPauseDialog,
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text("SET JEDA"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.textPrimary,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (isPaused) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                      debugPrint("🔌 Manual continue button pressed");
                      _pauseCountdownTimer?.cancel();
                      _updateRemoteControl('MANUAL_ON');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("LANJUT"),
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
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Jadwal Otomatis", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              _timePickerBtn("Pompa Hidup", startTime, () => _selectTime(context, true)),
              Container(
                width: 1,
                height: 40,
                color: AppColors.divider,
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              _timePickerBtn("Pompa Mati", stopTime, () => _selectTime(context, false)),
            ],
          ),
          const SizedBox(height: 16),
          if (_scheduleModified)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveSchedule,
                icon: const Icon(Icons.save, size: 18),
                label: const Text("SIMPAN JADWAL"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[400],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "Jadwal Tersimpan",
                    style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w500),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              time?.format(context) ?? "--:--",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartLine() {
    if (moistureSpots.isEmpty && waterSpots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              "Tidak ada data\nTambahkan sensor data untuk melihat grafik",
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: moistureSpots,
            isCurved: true,
            color: AppColors.success,
            barWidth: 3,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: waterSpots,
            isCurved: true,
            color: AppColors.info,
            barWidth: 3,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _buildLastUpdate() {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        '🔄 Update: ${_lastUpdate.hour.toString().padLeft(2, '0')}:${_lastUpdate.minute.toString().padLeft(2, '0')}:${_lastUpdate.second.toString().padLeft(2, '0')}',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    );
  }
}