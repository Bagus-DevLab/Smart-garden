import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_farming/theme/app_colors.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

// --- IMPORT CHAT COMPONENTS ---
import 'package:smart_farming/cubit/chat/chat_cubit.dart';
import 'package:smart_farming/services/chat_service.dart';
import 'package:smart_farming/widgets/chat_bottom_sheet.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  // --- API DATA VARIABLES ---
  // Plant Health Data
  double temperature = 0.0;
  double humidity = 0.0;
  double soilMoisture = 0.0;
  double phWater = 0.0;
  bool isPumpActive = false;

  // --- WEATHER DATA VARIABLES (Updated) ---
  String weatherCondition = 'Memuat...'; // final_rain_status
  double weatherHumidity = 0.0;          // sensor_hum
  double windSpeed = 0.0;                // final_wind
  double weatherTemp = 0.0;              // final_temp (New)

  bool isLoading = true;
  String? errorMessage;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchPlantData();
    _fetchWeatherData();
    // Auto refresh setiap 10 detik
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchPlantData();
      _fetchWeatherData();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // --- FETCH DATA DARI PLANT HEALTH API ---
  // --- FETCH DATA DARI PLANT HEALTH API (HyperH) ---
  // Hanya ambil Soil Moisture, pH, dan Pump Status
  Future<void> _fetchPlantData() async {
    try {
      final response = await http
          .get(
        Uri.parse(
          'http://hyperh.smartfarmingpalcomtech.my.id/dashboard',
        ),
      )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (mounted) {
          setState(() {
            isLoading = false;
            errorMessage = null;

            // Mapping data khusus Tanaman/Tanah
            // HAPUS temperature & humidity dari sini
            soilMoisture = (data['sensor']?['soil_percent'] ?? 72.0).toDouble();
            phWater = (data['sensor']?['ph'] ?? 6.5).toDouble();

            String pumpStatus = data['pump_status'] ?? "OFF";
            isPumpActive = pumpStatus == "ON";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // --- FETCH WEATHER DATA DARI AGRISKY API (UPDATED) ---
  // --- FETCH WEATHER DATA DARI AGRISKY API ---
  // Mengambil data Cuaca DAN Sensor Suhu/Kelembaban
  Future<void> _fetchWeatherData() async {
    try {
      final response = await http
          .get(
        Uri.parse('https://agrisky.smartfarmingpalcomtech.my.id/api/weather/status'),
      )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        if (result['status'] == 'success' && result['data'] != null) {
          final data = result['data'];

          if (mounted) {
            setState(() {
              // 1. DATA UNTUK KARTU CUACA (Weather Card)
              weatherCondition = data['final_rain_status'] ?? 'Cerah';
              windSpeed = (data['final_wind'] ?? 0.0).toDouble();
              // 'weatherTemp' ini suhu final gabungan (bisa dari BMKG atau Sensor)
              weatherTemp = (data['final_temp'] ?? 0.0).toDouble();
              // 'weatherHumidity' untuk kartu cuaca
              weatherHumidity = (data['sensor_hum'] ?? 0).toDouble();

              // 2. DATA UNTUK GRID SENSOR (Pindahan dari fungsi sebelah)
              // Kita ambil dari 'sensor_temp' dan 'sensor_hum' (Raw Data Sensor)
              temperature = (data['final_temp'] ?? 0.0).toDouble();
              humidity = (data['sensor_hum'] ?? 0).toDouble();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Weather API error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatCubit(ChatService()),
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildWeatherCard(), // Updated Widget
                  const SizedBox(height: 20),
                  _buildPlantStatusCard(),
                  const SizedBox(height: 20),
                  _buildSensorGrid(),
                  const SizedBox(height: 20),
                  _buildQuickActions(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton(
              backgroundColor: AppColors.primary,
              elevation: 4,
              child: const Icon(Icons.chat_bubble, color: Colors.white),
              onPressed: () => _showChatSheet(context),
            ),
          );
        },
      ),
    );
  }

  void _showChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return BlocProvider.value(
          value: context.read<ChatCubit>(),
          child: const ChatBottomSheet(),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Monitoring Smart Farming',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // --- UPDATED WEATHER CARD ---
  Widget _buildWeatherCard() {
    // Tentukan icon besar berdasarkan kondisi cuaca
    IconData mainIcon;
    if (weatherCondition.toLowerCase().contains('hujan')) {
      mainIcon = Icons.thunderstorm;
    } else if (weatherCondition.toLowerCase().contains('awan') ||
        weatherCondition.toLowerCase().contains('mendung')) {
      mainIcon = Icons.cloud;
    } else {
      mainIcon = Icons.wb_sunny;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          // Ubah warna gradasi sedikit jika hujan agar lebih dramatis (optional)
          colors: weatherCondition.toLowerCase().contains('hujan')
              ? [Colors.blueGrey, AppColors.slate]
              : [AppColors.sage, AppColors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.wb_sunny,
                      color: Colors.white.withOpacity(0.9),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cuaca Hari Ini',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  weatherCondition, // Dari 'final_rain_status'
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Detail 1: Kelembaban (sensor_hum)
                    _buildWeatherDetail(
                      Icons.water_drop,
                      '${weatherHumidity.toStringAsFixed(0)}%',
                    ),
                    const SizedBox(width: 16),

                    // Detail 2: Kecepatan Angin (final_wind)
                    _buildWeatherDetail(
                      Icons.air,
                      '${windSpeed.toStringAsFixed(1)} m/s', // Satuan BMKG biasanya m/s atau knot, sesuaikan label
                    ),
                    const SizedBox(width: 16),

                    // Detail 3: Suhu Udara (final_temp) -> Menggantikan Visibility
                    _buildWeatherDetail(
                        Icons.thermostat,
                        '${weatherTemp.toStringAsFixed(0)}°C'
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(mainIcon, size: 80, color: Colors.white.withOpacity(0.3)),
        ],
      ),
    );
  }

  Widget _buildWeatherDetail(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 16),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
        ),
      ],
    );
  }

  Widget _buildPlantStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.spa, color: AppColors.success, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status Tanaman',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sehat & Optimal',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Kondisi lingkungan mendukung pertumbuhan',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, color: AppColors.success, size: 28),
        ],
      ),
    );
  }

  Widget _buildSensorGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.3,
      children: [
        _buildSensorCard(
          icon: Icons.thermostat,
          title: 'Suhu',
          value: temperature.toStringAsFixed(1),
          unit: '°C',
          status: temperature > 30
              ? 'Tinggi'
              : temperature < 20
              ? 'Rendah'
              : 'Optimal',
          statusColor: temperature > 30
              ? AppColors.warning
              : temperature < 20
              ? AppColors.error
              : AppColors.success,
          iconColor: AppColors.error,
        ),
        _buildSensorCard(
          icon: Icons.water_drop,
          title: 'Kelembaban',
          value: humidity.toStringAsFixed(0),
          unit: '%',
          status: humidity > 80
              ? 'Tinggi'
              : humidity < 40
              ? 'Rendah'
              : 'Normal',
          statusColor: humidity > 80
              ? AppColors.warning
              : humidity < 40
              ? AppColors.error
              : AppColors.info,
          iconColor: AppColors.info,
        ),
        _buildSensorCard(
          icon: Icons.grass,
          title: 'Kelembaban Tanah',
          value: soilMoisture.toStringAsFixed(0),
          unit: '%',
          status: soilMoisture > 80
              ? 'Jenuh'
              : soilMoisture < 40
              ? 'Kering'
              : 'Baik',
          statusColor: soilMoisture > 80
              ? AppColors.warning
              : soilMoisture < 40
              ? AppColors.error
              : AppColors.success,
          iconColor: AppColors.primary,
        ),
        _buildSensorCard(
          icon: Icons.science,
          title: 'pH Air',
          value: phWater.toStringAsFixed(1),
          unit: '',
          status: phWater > 7.5
              ? 'Basa'
              : phWater < 6.5
              ? 'Asam'
              : 'Ideal',
          statusColor: phWater > 7.5
              ? AppColors.warning
              : phWater < 6.5
              ? AppColors.warning
              : AppColors.success,
          iconColor: AppColors.warning,
        ),
      ],
    );
  }

  Widget _buildSensorCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required String status,
    required Color statusColor,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        unit,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
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
              child: GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/weather');
                },
                child: _buildActionButton(
                  icon: Icons.water,
                  label: 'Weatheri',
                  color: AppColors.info,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/pembajakan');
                },
                child: _buildActionButton(
                  icon: Icons.agriculture,
                  label: 'Riwayat',
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/setting');
                },
                child: _buildActionButton(
                  icon: Icons.settings,
                  label: 'Pengaturan',
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
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
    );
  }
}