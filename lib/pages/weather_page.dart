import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_farming/theme/app_colors.dart';

class WeatherDashboardScreen extends StatefulWidget {
  const WeatherDashboardScreen({super.key});

  @override
  State<WeatherDashboardScreen> createState() => _WeatherDashboardScreenState();
}

class _WeatherDashboardScreenState extends State<WeatherDashboardScreen> {
  // --- CONFIG ---
  final String baseUrl = 'https://agrisky.smartfarmingpalcomtech.my.id';
  final String deviceId = 'PCB01';

  // --- STATE VARIABLES ---
  Map<String, dynamic>? currentWeather;
  List<dynamic> recentLogs = [];
  bool isLoading = true;
  String? errorMessage;
  Timer? _timer;

  // --- NOTIFICATION VARS ---
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  String lastStatus = "Cerah";
  DateTime? lastNotificationTime;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestPermissions();

    // 1. Load data cache dulu (supaya tidak loading lama)
    _loadCachedData();

    // 2. Fetch data baru dari server
    _fetchWeatherData();

    // 3. Auto Refresh tiap 10 detik
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchWeatherData(isBackground: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // --- SETUP NOTIFIKASI ---
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
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'weather_channel',
          'Peringatan Cuaca',
          importance: Importance.max,
          priority: Priority.high,
          color: AppColors.error,
        );
    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  // --- LOGIC CACHE (PENYIMPANAN LOKAL) ---
  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedWeather = prefs.getString('cached_weather');
      final String? cachedLogs = prefs.getString('cached_logs');

      if (cachedWeather != null && mounted) {
        setState(() {
          currentWeather = json.decode(cachedWeather);
          if (cachedLogs != null) {
            recentLogs = List<Map<String, dynamic>>.from(
              json.decode(cachedLogs),
            );
          }
          // Matikan loading karena data cache sudah tampil
          isLoading = false;
        });
      }
    } catch (e) {
      print("Cache error: $e");
    }
  }

  // --- AMBIL DATA API ---
  Future<void> _fetchWeatherData({bool isBackground = false}) async {
    // Hanya tampilkan loading jika data kosong sama sekali (belum ada cache)
    if (!isBackground && currentWeather == null) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      final currentResponse = await http.get(
        Uri.parse('$baseUrl/api/weather/status'),
      );
      final historyResponse = await http.get(
        Uri.parse('$baseUrl/api/weather/history?limit=10'),
      );

      if (currentResponse.statusCode == 200) {
        final jsonResponse = json.decode(currentResponse.body);

        if (jsonResponse['status'] == 'success') {
          final backendData = jsonResponse['data'];
          _checkAndTriggerNotification(backendData);

          // Siapkan Data Baru
          Map<String, dynamic> newWeatherData = {
            'location': 'Kebun Percobaan',
            'id': backendData['id'],
            'data': {
              'temperature': backendData['final_temp'],
              'humidity': backendData['sensor_hum'],
              'wind_speed': backendData['final_wind'],
              'rainfall_pct': backendData['sensor_rain_pct'] ?? 0,
              'status': backendData['final_rain_status'],
              'source': backendData['decision_source'],
            },
            'sensor_data': {
              'sensor_temp': backendData['sensor_temp'],
              'sensor_hum': backendData['sensor_hum'],
              'sensor_wind': backendData['sensor_wind'],
              'sensor_rpm': backendData['sensor_rpm'],
              'sensor_rain_raw': backendData['sensor_rain_raw'],
              'sensor_rain_pct': backendData['sensor_rain_pct'],
            },
            'bmkg_data': {
              'bmkg_temp': backendData['bmkg_temp'],
              'bmkg_wind': backendData['bmkg_wind'],
            },
            'created_at': backendData['created_at'],
          };

          List<dynamic> newLogs = [];
          if (historyResponse.statusCode == 200) {
            final jsonHistory = json.decode(historyResponse.body);
            if (jsonHistory['status'] == 'success') {
              List<dynamic> rawLogs = jsonHistory['data'];
              newLogs = rawLogs.map((log) {
                DateTime dt = DateTime.parse(log['created_at'].toString());
                return {
                  'time':
                      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}",
                  'temp': log['final_temp'].toString(),
                  'status': log['final_rain_status'],
                  'source': log['decision_source']
                      .toString()
                      .split('|')
                      .first
                      .trim(),
                };
              }).toList();
            }
          }

          if (mounted) {
            setState(() {
              currentWeather = newWeatherData;
              recentLogs = newLogs;
              isLoading = false;
              errorMessage = null; // Reset error jika berhasil
            });

            // SIMPAN KE CACHE
            final prefs = await SharedPreferences.getInstance();
            prefs.setString('cached_weather', json.encode(newWeatherData));
            prefs.setString('cached_logs', json.encode(newLogs));
          }
        }
      }
    } catch (e) {
      print("Error API: $e");
      // Jika error dan tidak ada data cache sama sekali, baru tampilkan error
      if (!isBackground && currentWeather == null) {
        setState(() {
          errorMessage = "Gagal koneksi internet";
          isLoading = false;
        });
      }
      // Jika sudah ada data (cache), biarkan saja user melihat data lama, jangan ditimpa error
    }
  }

  void _checkAndTriggerNotification(Map<String, dynamic> data) {
    String currentStatus = data['final_rain_status'].toString();
    double temp = double.parse(data['final_temp'].toString());

    if (currentStatus.contains("Hujan") && !lastStatus.contains("Hujan")) {
      _showNotification(
        "⚠️ Peringatan Hujan",
        "Hujan terdeteksi! Segera amankan area kebun.",
      );
    }
    if (temp > 35.0) {
      final now = DateTime.now();
      if (lastNotificationTime == null ||
          now.difference(lastNotificationTime!).inMinutes > 60) {
        _showNotification(
          "🔥 Suhu Ekstrem",
          "Suhu panas ($temp°C) terdeteksi.",
        );
        lastNotificationTime = now;
      }
    }
    lastStatus = currentStatus;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
            const Text(
              "AGRISKY AI",
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            // Indikator status koneksi kecil di bawah judul
            Text(
              isLoading && currentWeather == null
                  ? "Connecting..."
                  : (errorMessage != null
                        ? "Offline Mode (Cached)"
                        : "Online • Live Update"),
              style: TextStyle(
                color: errorMessage != null
                    ? AppColors.warning
                    : AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: const [SizedBox(width: 20)],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _fetchWeatherData(),
        child: isLoading && currentWeather == null
            // Loading HANYA muncul jika belum punya data sama sekali (install pertama)
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : errorMessage != null && currentWeather == null
            // Error HANYA muncul jika internet mati DAN belum ada cache
            ? Center(
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: AppColors.error),
                ),
              )
            : _buildDashboardBody(),
      ),
    );
  }

  // ... (Bagian _buildDashboardBody dan _buildStatCard SAMA PERSIS seperti sebelumnya)
  Widget _buildDashboardBody() {
    final data = currentWeather!['data'];
    bool isRaining = data['status'].toString().contains("Hujan");

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 15,
                offset: Offset(0, 5),
              ),
            ],
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
                        data['status'],
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Kebun Percobaan",
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
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
                  Text(
                    "${data['temperature']}",
                    style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      height: 1,
                    ),
                  ),
                  const Text(
                    "°C",
                    style: TextStyle(
                      fontSize: 24,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Sumber: ${data['source']}",
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 1.6,
          children: [
            _buildStatCard(
              "Kelembapan",
              "${data['humidity']}%",
              Icons.water_drop,
              AppColors.info,
            ),
            _buildStatCard(
              "Angin",
              "${data['wind_speed']} m/s",
              Icons.air,
              AppColors.secondary,
            ),
            _buildStatCard(
              "Curah Hujan",
              "${data['rainfall_pct']}%",
              Icons.show_chart,
              AppColors.warning,
            ),
            _buildStatCard(
              "AI Confidence",
              "100%",
              Icons.psychology,
              AppColors.primary,
            ),
          ],
        ),

        const SizedBox(height: 25),

        Row(
          children: const [
            Icon(Icons.memory, size: 18, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text(
              "Data Sensor",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
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
            children: [
              _buildDataRow(
                "Suhu Sensor",
                "${currentWeather!['sensor_data']['sensor_temp']}°C",
                0,
              ),
              _buildDataRow(
                "Kelembapan Sensor",
                "${currentWeather!['sensor_data']['sensor_hum']}%",
                1,
              ),
              _buildDataRow(
                "Angin Sensor",
                "${currentWeather!['sensor_data']['sensor_wind']} m/s",
                2,
              ),
              _buildDataRow(
                "RPM Motor",
                "${currentWeather!['sensor_data']['sensor_rpm']} rpm",
                3,
              ),
              _buildDataRow(
                "Curah Hujan (Raw)",
                "${currentWeather!['sensor_data']['sensor_rain_raw']}",
                4,
              ),
              _buildDataRow(
                "Curah Hujan (%)",
                "${currentWeather!['sensor_data']['sensor_rain_pct']}%",
                5,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Row(
          children: const [
            Icon(Icons.cloud_upload, size: 18, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text(
              "Data BMKG",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
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
            children: [
              _buildDataRow(
                "Suhu BMKG",
                "${currentWeather!['bmkg_data']['bmkg_temp']}°C",
                0,
              ),
              _buildDataRow(
                "Angin BMKG",
                "${currentWeather!['bmkg_data']['bmkg_wind']} m/s",
                1,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Row(
          children: const [
            Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text(
              "Informasi Lainnya",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
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
            children: [
              _buildDataRow("ID Data", "${currentWeather!['id']}", 0),
              _buildDataRow(
                "Timestamp",
                _formatDateTime(currentWeather!['created_at']),
                1,
              ),
              _buildDataRowLong(
                "Sumber Keputusan",
                currentWeather!['data']['source'],
                2,
              ),
            ],
          ),
        ),

        const SizedBox(height: 25),

        Row(
          children: const [
            Icon(Icons.history, size: 18, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text(
              "Riwayat Aktivitas",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        log['time'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    title: Text(
                      "${log['status']} • ${log['temp']}°C",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      log['source'],
                      style: const TextStyle(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      log['status'].toString().contains("Hujan")
                          ? Icons.cloud
                          : Icons.wb_sunny,
                      size: 16,
                      color: log['status'].toString().contains("Hujan")
                          ? AppColors.primary
                          : AppColors.warning,
                    ),
                  ),
                  if (idx != recentLogs.length - 1)
                    const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.divider,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.shadow.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value, int index) {
    bool isLast = false;
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          dense: true,
          title: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (index < 5)
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: AppColors.divider,
          ),
      ],
    );
  }

  Widget _buildDataRowLong(String label, String value, int index) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      DateTime dt = DateTime.parse(dateTimeStr);
      return "${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateTimeStr;
    }
  }
}