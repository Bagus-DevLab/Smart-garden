import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// Opsional: untuk format waktu, tapi kita pakai manual string aja biar simple
import 'package:smart_farming/theme/app_colors.dart';

// --- 2. HALAMAN UTAMA ---
class PlantHealthPage extends StatefulWidget {
  const PlantHealthPage({super.key});

  @override
  State<PlantHealthPage> createState() => _PlantHealthPageState();
}

class _PlantHealthPageState extends State<PlantHealthPage> {
  // --- STATE DATA ---
  double phWater = 6.2;
  double soilMoisture = 75.0;

  // --- STATE POMPA ---
  bool isPumpActive = false;
  double nutrientTankLevel = 85.0; // Persen
  double tankCapacityLiters = 50.0; // Kapasitas total tangki
  int pumpRuntimeSeconds = 0;
  Timer? _pumpTimer;

  // --- STATE ALERT & LOG ---
  List<Map<String, dynamic>> activeAlerts = [];
  List<Map<String, String>> activityLogs = []; // Log aktivitas
  String recommendationText = "Kondisi tanaman optimal. Lanjutkan pemantauan.";

  // Logic Notifikasi
  DateTime? _lastNotifTime;
  final Duration _notifCooldown = const Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    NotificationService.init();
    _addLog("System", "Monitoring dimulai.");
    _analyzeSystem();
  }

  @override
  void dispose() {
    _pumpTimer?.cancel();
    super.dispose();
  }

  // --- HELPER: LOG SYSTEM ---
  void _addLog(String type, String message) {
    if (activityLogs.length > 5) activityLogs.removeLast(); // Simpan 5 log terakhir
    setState(() {
      activityLogs.insert(0, {
        'time': "${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}",
        'type': type,
        'message': message
      });
    });
  }

  // --- LOGIC: ANALISIS CERDAS ---
  void _analyzeSystem() {
    activeAlerts.clear();
    bool critical = false;
    String recText = "Kondisi tanaman optimal. Pertahankan.";

    // 1. Analisis pH (Ideal: 5.5 - 7.0)
    if (phWater < 5.5) {
      activeAlerts.add({'title': 'pH Terlalu Asam', 'msg': 'Nilai pH ${phWater.toStringAsFixed(1)}', 'type': 'danger'});
      recText = "Tambahkan larutan pH Up (Basa) segera untuk menetralkan air.";
      critical = true;
    } else if (phWater > 7.0) {
      activeAlerts.add({'title': 'pH Terlalu Basa', 'msg': 'Nilai pH ${phWater.toStringAsFixed(1)}', 'type': 'warning'});
      recText = "Tambahkan larutan pH Down (Asam) atau lemon untuk menurunkan pH.";
    }

    // 2. Analisis Tanah (Ideal: 40% - 80%)
    if (soilMoisture < 30) {
      activeAlerts.add({'title': 'Tanah Kering', 'msg': 'Kelembaban ${soilMoisture.toInt()}%', 'type': 'danger'});
      if (!critical) recText = "Tanah membutuhkan air. Aktifkan sistem irigasi atau siram manual.";
      critical = true;
    } else if (soilMoisture > 90) {
      recText = "Tanah terlalu basah. Hentikan penyiraman untuk mencegah akar busuk.";
    }

    // 3. Analisis Nutrisi
    if (nutrientTankLevel < 15) {
      activeAlerts.add({'title': 'Nutrisi Kritis', 'msg': 'Sisa ${nutrientTankLevel.toInt()}%', 'type': 'warning'});
    }

    setState(() {
      recommendationText = recText;
    });

    // Trigger Notifikasi
    if (critical) {
      final now = DateTime.now();
      if (_lastNotifTime == null || now.difference(_lastNotifTime!) > _notifCooldown) {
        NotificationService.showNotification(1, "PERHATIAN KEBUN", "Terdeteksi anomali pada sensor. Cek aplikasi segera.");
        _lastNotifTime = now;
        _addLog("Alert", "Notifikasi bahaya dikirim.");
      }
    }
  }

  // --- LOGIC: KONTROL POMPA ---
  void _togglePump() {
    if (nutrientTankLevel <= 0 && !isPumpActive) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tangki Kosong!")));
      return;
    }

    setState(() {
      isPumpActive = !isPumpActive;
      if (isPumpActive) {
        _addLog("Pompa", "Pompa Nutrisi dinyalakan.");
        pumpRuntimeSeconds = 0;
        _pumpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            pumpRuntimeSeconds++;
            if (nutrientTankLevel > 0) nutrientTankLevel -= 0.5; // Simulasi boros
            if (nutrientTankLevel <= 0) _togglePump();
          });
        });
      } else {
        _addLog("Pompa", "Pompa Nutrisi dimatikan (${pumpRuntimeSeconds}s).");
        _pumpTimer?.cancel();
      }
    });
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
            Text("Area: Kebun Hidroponik A1", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
          ],
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: "Scan Sensor",
              onPressed: () {
                _addLog("System", "Manual scan sensor.");
                _analyzeSystem();
              }
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await Future.delayed(const Duration(seconds: 1)); _analyzeSystem(); },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. HEADER STATUS ALERT (Jika ada masalah)
              if (activeAlerts.isNotEmpty) ...[
                _buildAlertBanner(),
                const SizedBox(height: 20),
              ],

              // 2. REKOMENDASI AI
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

              // 4. KONTROL POMPA & TANGKI
              const Text("Sistem Fertigasi", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
              const SizedBox(height: 10),
              _buildPumpControlCard(),

              const SizedBox(height: 24),

              // 5. RIWAYAT AKTIVITAS
              _buildActivityLog(),

              // 6. DEBUG TOOLS
              const SizedBox(height: 30),
              Center(
                child: Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton(child: const Text("Simulasi pH Drop"), onPressed: () { setState(() { phWater = 4.5; _lastNotifTime = null; }); _analyzeSystem(); }),
                    OutlinedButton(child: const Text("Reset Normal"), onPressed: () { setState(() { phWater = 6.2; soilMoisture = 75; nutrientTankLevel = 85; }); _analyzeSystem(); }),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET COMPONENTS ---

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
        color: AppColors.info.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Rekomendasi Tindakan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
          // Circular Indicator
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
          // Info Text
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
    double litersLeft = (nutrientTankLevel / 100) * tankCapacityLiters;

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
                    decoration: BoxDecoration(color: AppColors.secondary.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(Icons.settings_input_component, color: isPumpActive ? AppColors.secondary : Colors.grey),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Pompa Nutrisi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(isPumpActive ? "Aktif: ${pumpRuntimeSeconds} detik" : "Status: Standby",
                          style: TextStyle(fontSize: 12, color: isPumpActive ? AppColors.secondary : AppColors.textSub)),
                    ],
                  ),
                ],
              ),
              Switch(value: isPumpActive, onChanged: (v) => _togglePump(), activeColor: AppColors.secondary),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Tangki Nutrisi", style: TextStyle(fontSize: 13, color: AppColors.textSub)),
              Text("${nutrientTankLevel.toInt()}% (${litersLeft.toStringAsFixed(1)} L)",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: nutrientTankLevel / 100,
              minHeight: 10,
              color: nutrientTankLevel < 20 ? AppColors.error : AppColors.primary,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
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
          child: ListView.separated(
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
  String _getPhStatus(double v) => (v < 5.5) ? "Terlalu Asam" : (v > 7.0) ? "Terlalu Basa" : "Normal";

  Color _getMoistureColor(double v) => (v < 30) ? AppColors.warning : AppColors.info;
  String _getMoistureStatus(double v) => (v < 30) ? "Kering" : (v > 90) ? "Jenuh Air" : "Lembab";
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