import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'dart:convert'; // Untuk JSON decoding
import 'package:http/http.dart' as http; // Untuk koneksi API
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:smart_farming/cubit/chat/chat_cubit.dart';
import 'package:smart_farming/theme/app_colors.dart';

// --- 2. HALAMAN UTAMA ---
class PlantHealthPage extends StatefulWidget {
  const PlantHealthPage({super.key});

  @override
  State<PlantHealthPage> createState() => _PlantHealthPageState();
}

class _PlantHealthPageState extends State<PlantHealthPage> {
  final String baseUrl = "https://hyperh.smartfarmingpalcomtech.my.id";

  // --- STATE DATA ---
  bool isLoading = true;
  bool isError = false;
  double phWater = 0.0;
  double soilMoisture = 0.0;

  // --- STATE POMPA ---
  bool isPumpActive = false;

  // Karena ESP32 tidak mengirim level tangki (hanya pH & Soil),
  // kita hardcode dulu atau simulasi lokal untuk UI.
  double nutrientTankLevel = 85.0;

  // Timer untuk Auto-Refresh Data
  Timer? _pollingTimer;

  // --- STATE ALERT & LOG ---
  List<Map<String, dynamic>> activeAlerts = [];
  List<Map<String, String>> activityLogs = [];
  String recommendationText = "Menunggu data dari server...";
  bool isAiCritical = false; // Status dari AI Backend

  // Logic Notifikasi
  DateTime? _lastNotifTime;
  final Duration _notifCooldown = const Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    NotificationService.init();
    _addLog("System", "Aplikasi terhubung ke Server.");

    // 1. Ambil data pertama kali
    _fetchDashboardData();

    // 2. Pasang Timer untuk update otomatis setiap 3 detik (Real-time monitoring)
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchDashboardData();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // --- API: AMBIL DATA DASHBOARD ---
  Future<void> _fetchDashboardData() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/dashboard'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          isLoading = false;
          isError = false;

          // Mapping Data dari JSON Backend
          // Backend mengirim: { "sensor": {"ph":..., "soil_percent":...}, "pump_status": "ON/OFF", "ai_analysis": ... }

          phWater = (data['sensor']['ph'] ?? 0.0).toDouble();
          soilMoisture = (data['sensor']['soil_percent'] ?? 0).toDouble();

          // Status Pompa Real dari Alat
          String pumpStatusStr = data['pump_status'] ?? "OFF";
          isPumpActive = pumpStatusStr == "ON";

          // Analisis AI dari Backend
          var aiData = data['ai_analysis'];
          recommendationText = aiData['message'] ?? "Tidak ada data AI";
          isAiCritical = aiData['is_critical'] ?? false;

          // Update Alert Lokal & Notifikasi
          _analyzeSystemLocal();
        });
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      print("Error Fetching Data: $e");
      setState(() {
        isError = true;
        // Jangan ubah isLoading jadi true biar UI gak kedip-kedip, cukup show error banner kalau perlu
      });
    }
  }

  // --- API: KONTROL POMPA ---
  Future<void> _togglePumpApi() async {
    // Optimistic UI Update (Ubah tampilan dulu biar responsif)
    bool previousState = isPumpActive;
    setState(() {
      isPumpActive = !isPumpActive;
    });

    String action = isPumpActive ? "ON" : "OFF";
    _addLog("Kontrol", "Mengirim perintah $action ke alat...");

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/control'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"action": action}),
      );

      if (response.statusCode == 200) {
        _addLog("Sukses", "Alat berhasil di-$action.");
        // Data akan tersinkron ulang saat timer polling berikutnya jalan
      } else {
        throw Exception("Gagal kirim perintah");
      }
    } catch (e) {
      _addLog("Error", "Gagal koneksi ke alat!");
      // Kembalikan switch jika gagal
      setState(() {
        isPumpActive = previousState;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal mengontrol pompa: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // --- HELPER: LOG SYSTEM ---
  void _addLog(String type, String message) {
    if (activityLogs.length > 5) activityLogs.removeLast();
    setState(() {
      activityLogs.insert(0, {
        'time': "${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}",
        'type': type,
        'message': message
      });
    });
  }

  // --- LOGIC: ANALISIS LOKAL (UNTUK UI BANNER) ---
  // Meskipun AI sudah memberi saran, kita tetap butuh ini untuk menampilkan Banner Merah/Kuning di atas
  void _analyzeSystemLocal() {
    activeAlerts.clear();
    bool critical = false;

    // 1. Alert pH
    if (phWater < 5.0) {
      activeAlerts.add({'title': 'pH Kritis', 'msg': 'Air terlalu Asam (${phWater.toStringAsFixed(1)})', 'type': 'danger'});
      critical = true;
    }

    // 2. Alert Tanah
    if (soilMoisture < 30) {
      activeAlerts.add({'title': 'Tanah Kering', 'msg': 'Kelembaban hanya ${soilMoisture.toInt()}%', 'type': 'danger'});
      critical = true;
    }

    // 3. Alert dari AI Backend (Prioritas)
    if (isAiCritical) {
      // Kita bisa tambahkan badge khusus AI jika mau
    }

    // Trigger Notifikasi HP
    if (critical) {
      final now = DateTime.now();
      if (_lastNotifTime == null || now.difference(_lastNotifTime!) > _notifCooldown) {
        NotificationService.showNotification(1, "PERHATIAN KEBUN", "Kondisi tanaman membutuhkan perhatian! Cek Aplikasi.");
        _lastNotifTime = now;
      }
    }
  }

  // --- UI BUILDER ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Smart GreenHouse", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: isError ? Colors.red : (isLoading ? Colors.yellow : Colors.greenAccent),
                      shape: BoxShape.circle
                  ),
                ),
                const SizedBox(width: 6),
                Text(isError ? "Terputus" : "Online (Live)", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
              ],
            ),
          ],
        ),

        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: "Force Refresh",
              onPressed: () {
                _addLog("System", "Manual refresh data.");
                setState(() { isLoading = true; });
                _fetchDashboardData();
              }
          )
        ],
      ),
      body: isLoading && phWater == 0.0
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _fetchDashboardData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. HEADER STATUS ALERT
              if (activeAlerts.isNotEmpty) ...[
                _buildAlertBanner(),
                const SizedBox(height: 20),
              ],

              // 2. REKOMENDASI AI (DARI API)
              _buildRecommendationCard(),
              const SizedBox(height: 20),

              // 3. MONITORING SENSOR DETIL
              const Text("Kondisi Lingkungan", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
              const SizedBox(height: 10),
              _buildDetailedSensorCard(
                title: "Keasaman Air (pH)",
                value: phWater.toStringAsFixed(1),
                unit: "pH",
                icon: Icons.science,
                target: "Target: 5.5 - 7.0",
                status: _getPhStatus(phWater),
                color: _getPhColor(phWater),
                percentage: (phWater / 14).clamp(0.0, 1.0),
              ),
              const SizedBox(height: 10),
              _buildDetailedSensorCard(
                title: "Kelembaban Tanah",
                value: "${soilMoisture.toInt()}",
                unit: "%",
                icon: Icons.water_drop,
                target: "Target: 40% - 80%",
                status: _getMoistureStatus(soilMoisture),
                color: _getMoistureColor(soilMoisture),
                percentage: (soilMoisture / 100).clamp(0.0, 1.0),
              ),

              const SizedBox(height: 24),

              // 4. KONTROL POMPA (VIA API)
              const Text("Kontrol Aktuator", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
              const SizedBox(height: 10),
              _buildPumpControlCard(),

              const SizedBox(height: 24),

              // 5. RIWAYAT AKTIVITAS
              _buildActivityLog(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET COMPONENTS (SAMA SEPERTI SEBELUMNYA) ---

  Widget _buildAlertBanner() {
    return Column(
      children: activeAlerts.map((alert) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: alert['type'] == 'danger' ? AppColors.error.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: alert['type'] == 'danger' ? AppColors.error : AppColors.warning),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: alert['type'] == 'danger' ? AppColors.error : AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert['title'], style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMain)),
                  Text(alert['msg'], style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                ],
              ),
            )
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildRecommendationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAiCritical ? AppColors.error.withOpacity(0.1) : AppColors.info.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isAiCritical ? AppColors.error.withOpacity(0.5) : AppColors.info.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.smart_toy, color: isAiCritical ? AppColors.error : AppColors.info), // Icon Robot/AI
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text("Analisis AI SmartFarming", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(width: 6),
                    if (isLoading) const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(recommendationText, style: const TextStyle(fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedSensorCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required String target,
    required String status,
    required Color color,
    required double percentage,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 60, height: 60,
                child: CircularProgressIndicator(value: percentage, color: color, backgroundColor: color.withOpacity(0.1), strokeWidth: 6),
              ),
              Icon(icon, color: color, size: 24),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                    const SizedBox(width: 4),
                    Text(unit, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSub)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                    ),
                    const SizedBox(width: 8),
                    Text(target, style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPumpControlCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: isPumpActive ? AppColors.secondary.withOpacity(0.1) : Colors.grey.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(Icons.power_settings_new, color: isPumpActive ? AppColors.secondary : Colors.grey),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Pompa Nutrisi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(isPumpActive ? "Status: MENYALA" : "Status: MATI",
                          style: TextStyle(fontSize: 12, color: isPumpActive ? AppColors.secondary : AppColors.textSub, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              // Switch untuk kontrol manual via API
              Switch(
                  value: isPumpActive,
                  onChanged: (v) => _togglePumpApi(),
                  activeColor: AppColors.secondary
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Catatan: Menekan tombol ini akan mengirim perintah langsung ke alat via Internet.", style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildActivityLog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Riwayat Aktivitas", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: activityLogs.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text("Belum ada aktivitas.", style: TextStyle(color: Colors.grey)))
              : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activityLogs.length,
            separatorBuilder: (c, i) => const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              final log = activityLogs[index];
              return ListTile(
                dense: true,
                leading: Text(log['time']!, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSub, fontSize: 12)),
                title: Text(log['message']!, style: const TextStyle(fontSize: 13)),
                trailing: Text(log['type']!, style: TextStyle(fontSize: 10, color: log['type'] == 'Alert' ? AppColors.error : AppColors.primary)),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- HELPER LOGIC WARNA & STATUS ---
  Color _getPhColor(double v) => (v < 5.5 || v > 7.0) ? AppColors.error : AppColors.secondary;
  String _getPhStatus(double v) => (v < 5.5) ? "Asam" : (v > 7.0) ? "Basa" : "Normal";

  Color _getMoistureColor(double v) => (v < 30) ? AppColors.warning : AppColors.info;
  String _getMoistureStatus(double v) => (v < 30) ? "Kering" : "Basah";
}

// --- SERVICE NOTIFIKASI ---
class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(const InitializationSettings(android: android));
  }

  static Future<void> showNotification(int id, String title, String body) async {
    const details = NotificationDetails(android: AndroidNotificationDetails(
        'farm_channel', 'Farming Alerts', importance: Importance.max, priority: Priority.high
    ));
    await _notifications.show(id, title, body, details);
  }
}