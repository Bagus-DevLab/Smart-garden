import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:smart_farming/theme/app_colors.dart';

class WeatherDashboardScreen extends StatefulWidget {
  const WeatherDashboardScreen({super.key});

  @override
  State<WeatherDashboardScreen> createState() => _WeatherDashboardScreenState();
}

class _WeatherDashboardScreenState extends State<WeatherDashboardScreen> {
  final String baseUrl = 'YOUR_API_URL'; // Ganti dengan URL API Anda
  final String deviceId = 'PCB01';

  Map<String, dynamic>? currentWeather;
  List<dynamic> alerts = [];
  Map<String, dynamic>? statistics;
  List<dynamic> dailySummary = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchWeatherData();
  }

  Future<void> _fetchWeatherData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Fetch current weather
      final currentResponse = await http.get(
        Uri.parse('$baseUrl/api/weather/current/$deviceId'),
      );

      // Fetch alerts
      final alertsResponse = await http.get(
        Uri.parse('$baseUrl/api/weather/alerts/$deviceId'),
      );

      // Fetch statistics (7 days)
      final statsResponse = await http.get(
        Uri.parse('$baseUrl/api/weather/statistics/$deviceId/7'),
      );

      // Fetch daily summary
      final summaryResponse = await http.get(
        Uri.parse('$baseUrl/api/weather/daily-summary'),
      );

      if (currentResponse.statusCode == 200) {
        setState(() {
          currentWeather = json.decode(currentResponse.body);
          alerts = json.decode(alertsResponse.body)['data'] ?? [];
          statistics = json.decode(statsResponse.body);
          dailySummary = json.decode(summaryResponse.body)['data'] ?? [];
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load weather data');
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.accent,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smart Agriculture IoT',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Sistem Monitoring & Kontrol Pertanian Cerdas',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          // Badge untuk alerts
          Stack(
            children: [
              const Icon(Icons.notifications_none, size: 22, color: AppColors.textSecondary),
              if (alerts.isNotEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      '${alerts.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          const Icon(Icons.settings_outlined, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          const Icon(Icons.person_outline, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _fetchWeatherData,
        child: isLoading
            ? const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        )
            : errorMessage != null
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Error: $errorMessage',
                style: const TextStyle(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchWeatherData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        )
            : ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SizedBox(height: 8),
            const Text(
              'Cuaca Pintar',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 16),

            // Alerts Section (jika ada)
            if (alerts.isNotEmpty) ...[
              _buildAlertsSection(),
              const SizedBox(height: 16),
            ],

            // Top small cards (2x2 grid)
            _buildStatCards(),

            const SizedBox(height: 24),

            // Main current weather card
            _buildMainWeatherCard(),

            // Historical Statistics Section
            if (statistics != null) ...[
              const SizedBox(height: 24),
              _buildStatisticsSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Peringatan Aktif',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.error,
                  ),
                ),
                Text(
                  '${alerts.length} peringatan memerlukan perhatian',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.error.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.error),
        ],
      ),
    );
  }

  Widget _buildStatCards() {
    if (currentWeather == null) return const SizedBox.shrink();

    final data = currentWeather!['data'];
    final temp = data['temperature']?.toDouble() ?? 0.0;
    final humidity = data['humidity']?.toInt() ?? 0;
    final windSpeed = data['wind_speed']?.toDouble() ?? 0.0;
    final rainfall = data['rainfall']?.toDouble() ?? 0.0;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildStatCard(
          title: 'Suhu Udara',
          value: temp.toStringAsFixed(0),
          unit: '°C',
          icon: Icons.thermostat,
          iconBg: AppColors.primary.withOpacity(0.15),
          iconColor: AppColors.primary,
        ),
        _buildStatCard(
          title: 'Kelembaban',
          value: '$humidity',
          unit: '%',
          icon: Icons.water_drop,
          iconBg: AppColors.info.withOpacity(0.15),
          iconColor: AppColors.info,
        ),
        _buildStatCard(
          title: 'Kecepatan Angin',
          value: windSpeed.toStringAsFixed(1),
          unit: 'km/h',
          icon: Icons.air,
          iconBg: AppColors.secondary.withOpacity(0.3),
          iconColor: AppColors.primaryDark,
        ),
        _buildStatCard(
          title: 'Curah Hujan',
          value: rainfall.toStringAsFixed(1),
          unit: 'mm',
          icon: Icons.water,
          iconBg: AppColors.warning.withOpacity(0.2),
          iconColor: AppColors.warning,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 16 * 2 - 12) / 2,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider.withOpacity(0.5)),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: AppColors.textPrimary),
                      children: [
                        TextSpan(
                          text: value,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: ' $unit',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainWeatherCard() {
    if (currentWeather == null) return const SizedBox.shrink();

    final data = currentWeather!['data'];
    final temp = data['temperature']?.toDouble() ?? 0.0;
    final humidity = data['humidity']?.toInt() ?? 0;
    final windSpeed = data['wind_speed']?.toDouble() ?? 0.0;
    final pressure = data['pressure']?.toDouble() ?? 0.0;
    final location = currentWeather!['location'] ?? 'Unknown Location';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider.withOpacity(0.5)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cuaca Saat Ini',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.wb_sunny, color: AppColors.warning, size: 30),
            ],
          ),

          const SizedBox(height: 24),

          // Temperature
          Center(
            child: Column(
              children: [
                Text(
                  '${temp.toStringAsFixed(0)}°C',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getWeatherDescription(temp, humidity),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 12),

          // Bottom Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomStat(
                icon: Icons.water_drop,
                label: 'Kelembaban',
                value: '$humidity%',
              ),
              _buildBottomStat(
                icon: Icons.air,
                label: 'Angin',
                value: '${windSpeed.toStringAsFixed(1)} km/h',
              ),
              _buildBottomStat(
                icon: Icons.compress,
                label: 'Tekanan',
                value: '${pressure.toStringAsFixed(0)} hPa',
              ),
            ],
          ),

          // Daily Summary
          if (dailySummary.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Divider(color: AppColors.divider),
            const SizedBox(height: 10),
            const Text(
              'Prakiraan 7 Hari',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: dailySummary.take(7).map((day) {
                  final date = DateTime.parse(day['date']);
                  final avgTemp = day['avg_temperature']?.toDouble() ?? 0.0;
                  final dayNames = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];
                  final dayLabel = dayNames[date.weekday % 7];

                  return Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider.withOpacity(0.5)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          dayLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Icon(Icons.wb_sunny, color: AppColors.warning, size: 20),
                        const SizedBox(height: 6),
                        Text(
                          '${avgTemp.toStringAsFixed(0)}°C',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatisticsSection() {
    if (statistics == null) return const SizedBox.shrink();

    final stats = statistics!['data'];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider.withOpacity(0.5)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Statistik 7 Hari Terakhir',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatRow('Suhu Rata-rata', '${stats['temperature']['avg']?.toStringAsFixed(1) ?? '-'}°C'),
          _buildStatRow('Suhu Maksimal', '${stats['temperature']['max']?.toStringAsFixed(1) ?? '-'}°C'),
          _buildStatRow('Suhu Minimal', '${stats['temperature']['min']?.toStringAsFixed(1) ?? '-'}°C'),
          const Divider(color: AppColors.divider, height: 24),
          _buildStatRow('Kelembaban Rata-rata', '${stats['humidity']['avg']?.toStringAsFixed(0) ?? '-'}%'),
          _buildStatRow('Total Curah Hujan', '${stats['rainfall']['total']?.toStringAsFixed(1) ?? '-'} mm'),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _getWeatherDescription(double temp, int humidity) {
    if (temp > 30) return 'Panas';
    if (temp > 25) return 'Hangat';
    if (temp > 20) return 'Nyaman';
    return 'Sejuk';
  }
}