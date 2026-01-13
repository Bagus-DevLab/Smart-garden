import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_farming/theme/app_colors.dart'; // Pastikan path ini benar

class WeatherDashboardScreen extends StatefulWidget {
  const WeatherDashboardScreen({super.key});

  @override
  State<WeatherDashboardScreen> createState() => _WeatherDashboardScreenState();
}

class _WeatherDashboardScreenState extends State<WeatherDashboardScreen> {
  // --- CONFIG ---
  final String baseUrl = 'https://agrisky-api-production.up.railway.app';
  final String deviceId = 'PCB01';

  // --- STATE VARIABLES ---
  Map<String, dynamic>? currentWeather;
  List<dynamic> recentLogs = [];
  bool isLoading = true;
  String? errorMessage;
  Timer? _timer;

  // --- NOTIFICATION VARS ---
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  String lastStatus = "Cerah";
  DateTime? lastNotificationTime;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestPermissions();
    _fetchWeatherData();

    // Auto Refresh tiap 10 detik
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchWeatherData(isBackground: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // --- 1. SETUP NOTIFIKASI ---
  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'weather_channel', 'Peringatan Cuaca',
      importance: Importance.max,
      priority: Priority.high,
      color: AppColors.error,
    );
    await flutterLocalNotificationsPlugin.show(0, title, body, NotificationDetails(android: androidDetails));
  }

  // --- 2. AMBIL DATA DARI API ---
  Future<void> _fetchWeatherData({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() { isLoading = true; errorMessage = null; });
    }

    try {
      // Panggil 2 Endpoint sekaligus
      final currentResponse = await http.get(Uri.parse('$baseUrl/api/weather/status'));
      final historyResponse = await http.get(Uri.parse('$baseUrl/api/weather/history?limit=10'));

      if (currentResponse.statusCode == 200) {
        final jsonResponse = json.decode(currentResponse.body);

        if (jsonResponse['status'] == 'success') {
          final backendData = jsonResponse['data'];

          // Cek Trigger Notifikasi
          _checkAndTriggerNotification(backendData);

          if (mounted) {
            setState(() {
              // Simpan Data Utama
              currentWeather = {
                'location': 'Kebun Percobaan',
                'data': {
                  'temperature': backendData['final_temp'],
                  'humidity': backendData['sensor_hum'],
                  'wind_speed': backendData['final_wind'],
                  'rainfall_pct': backendData['sensor_rain_pct'] ?? 0,
                  'status': backendData['final_rain_status'],
                  'source': backendData['decision_source'],
                }
              };

              // Simpan Data History
              if (historyResponse.statusCode == 200) {
                final jsonHistory = json.decode(historyResponse.body);
                if (jsonHistory['status'] == 'success') {
                  List<dynamic> rawLogs = jsonHistory['data'];
                  recentLogs = rawLogs.map((log) {
                    DateTime dt = DateTime.parse(log['created_at'].toString());
                    // Tambah 7 Jam jika server UTC, tapi biasanya Python sudah WIB.
                    // Sesuaikan jika jam meleset.
                    return {
                      'time': "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}",
                      'temp': log['final_temp'].toString(),
                      'status': log['final_rain_status'],
                      'source': log['decision_source'].toString().split('|').first.trim(),
                    };
                  }).toList();
                }
              }
              isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      print("Error: $e");
      if (!isBackground) {
        setState(() { errorMessage = "Gagal koneksi internet"; isLoading = false; });
      }
    }
  }

  void _checkAndTriggerNotification(Map<String, dynamic> data) {
    String currentStatus = data['final_rain_status'].toString();
    double temp = double.parse(data['final_temp'].toString());

    // Logic Hujan
    if (currentStatus.contains("Hujan") && !lastStatus.contains("Hujan")) {
      _showNotification("⚠️ Peringatan Hujan", "Hujan terdeteksi! Segera amankan area kebun.");
    }
    // Logic Panas
    if (temp > 35.0) {
      final now = DateTime.now();
      if (lastNotificationTime == null || now.difference(lastNotificationTime!).inMinutes > 60) {
        _showNotification("🔥 Suhu Ekstrem", "Suhu panas ($temp°C) terdeteksi.");
        lastNotificationTime = now;
      }
    }
    lastStatus = currentStatus;
  }

  // --- 3. UI BUILDER (TAMPILAN CANTIK) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // Cream
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("AGRISKY AI", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18)),
            Text(currentWeather != null ? "Online • Live Update" : "Connecting...", style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined, color: AppColors.warning),
            onPressed: () => _showNotification("Test Notifikasi", "Sistem notifikasi berjalan normal."),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _fetchWeatherData,
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : errorMessage != null
            ? Center(child: Text(errorMessage!, style: const TextStyle(color: AppColors.error)))
            : _buildDashboardBody(),
      ),
    );
  }

  Widget _buildDashboardBody() {
    final data = currentWeather!['data'];
    bool isRaining = data['status'].toString().contains("Hujan");

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      children: [
        // --- 1. CARD UTAMA ---
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant, // Putih
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 15, offset: Offset(0, 5))],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['status'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text("Kebun Percobaan", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  Icon(
                    isRaining ? Icons.cloudy_snowing : Icons.wb_sunny_rounded,
                    size: 48,
                    color: isRaining ? AppColors.primary : AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("${data['temperature']}", style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: AppColors.primary, height: 1)),
                  const Text("°C", style: TextStyle(fontSize: 24, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
                child: Text("Sumber: ${data['source']}", style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), textAlign: TextAlign.center),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // --- 2. GRID STATISTIK ---
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 1.6,
          children: [
            _buildStatCard("Kelembapan", "${data['humidity']}%", Icons.water_drop, AppColors.info),
            _buildStatCard("Angin", "${data['wind_speed']} m/s", Icons.air, AppColors.secondary),
            _buildStatCard("Curah Hujan", "${data['rainfall_pct']}%", Icons.show_chart, AppColors.warning),
            _buildStatCard("AI Confidence", "100%", Icons.psychology, AppColors.primary),
          ],
        ),

        const SizedBox(height: 25),

        // --- 3. LOG RIWAYAT ---
        Row(
          children: const [
            Icon(Icons.history, size: 18, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text("Riwayat Aktivitas", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 10),

        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider.withOpacity(0.5)),
          ),
          child: Column(
            children: recentLogs.asMap().entries.map((entry) {
              int idx = entry.key;
              Map log = entry.value;
              return Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
                      child: Text(log['time'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary)),
                    ),
                    title: Text("${log['status']} • ${log['temp']}°C", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(log['source'], style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Icon(
                        log['status'].toString().contains("Hujan") ? Icons.cloud : Icons.wb_sunny,
                        size: 16,
                        color: log['status'].toString().contains("Hujan") ? AppColors.primary : AppColors.warning
                    ),
                  ),
                  if (idx != recentLogs.length - 1) const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.shadow.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const Spacer(),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}