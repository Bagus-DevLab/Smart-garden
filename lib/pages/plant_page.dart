import 'package:flutter/material.dart';
import 'package:smart_farming/theme/app_colors.dart';

class PlantHealthPage extends StatefulWidget {
  const PlantHealthPage({super.key});

  @override
  State<PlantHealthPage> createState() => _PlantHealthPageState();
}

class _PlantHealthPageState extends State<PlantHealthPage> {
  // Sensor Data
  double phValue = 6.5;
  double soilMoisture = 72.0;
  
  // Fertilizer Pump Status
  bool isPumpActive = false;
  double fertilizerLevel = 65.0; // Persentase level pupuk cair di tangki
  int pumpRuntime = 0; // Waktu pompa berjalan dalam detik
  DateTime? lastFertilizeTime;
  
  String plantStatus = 'Sehat';
  Color plantStatusColor = AppColors.success;

  // Recommendations
  List<Map<String, dynamic>> recommendations = [];

  @override
  void initState() {
    super.initState();
    lastFertilizeTime = DateTime.now().subtract(Duration(hours: 2));
    _analyzeHealthStatus();
  }

  void _analyzeHealthStatus() {
    recommendations.clear();

    // Analyze pH
    if (phValue < 5.5) {
      recommendations.add({
        'title': 'pH Terlalu Asam',
        'description': 'Tambahkan kapur pertanian untuk menaikan pH tanah',
        'icon': Icons.warning_amber,
        'color': AppColors.warning,
      });
      plantStatus = 'Perlu Perhatian';
      plantStatusColor = AppColors.warning;
    } else if (phValue > 7.5) {
      recommendations.add({
        'title': 'pH Terlalu Basa',
        'description': 'Tambahkan sulfur atau kompos untuk menurunkan pH',
        'icon': Icons.warning_amber,
        'color': AppColors.warning,
      });
      plantStatus = 'Perlu Perhatian';
      plantStatusColor = AppColors.warning;
    }

    // Analyze Soil Moisture
    if (soilMoisture < 40) {
      recommendations.add({
        'title': 'Tanah Kering',
        'description': 'Tingkatkan frekuensi penyiraman',
        'icon': Icons.water_drop,
        'color': AppColors.error,
      });
      plantStatus = 'Perlu Penyiraman';
      plantStatusColor = AppColors.error;
    } else if (soilMoisture > 85) {
      recommendations.add({
        'title': 'Tanah Terlalu Basah',
        'description': 'Kurangi penyiraman dan perbaiki drainase',
        'icon': Icons.water_damage,
        'color': AppColors.warning,
      });
      plantStatus = 'Kelebihan Air';
      plantStatusColor = AppColors.warning;
    }

    // Analyze Fertilizer Level
    if (fertilizerLevel < 20) {
      recommendations.add({
        'title': 'Pupuk Cair Hampir Habis',
        'description': 'Segera isi ulang tangki pupuk cair',
        'icon': Icons.local_drink,
        'color': AppColors.error,
      });
    } else if (fertilizerLevel < 40) {
      recommendations.add({
        'title': 'Level Pupuk Rendah',
        'description': 'Persiapkan pengisian tangki pupuk',
        'icon': Icons.info,
        'color': AppColors.warning,
      });
    }

    // Check fertilizer schedule
    if (lastFertilizeTime != null) {
      final hoursSinceLastFertilize = DateTime.now().difference(lastFertilizeTime!).inHours;
      if (hoursSinceLastFertilize > 24 && !isPumpActive) {
        recommendations.add({
          'title': 'Jadwal Pemupukan',
          'description': 'Sudah ${hoursSinceLastFertilize} jam sejak pemupukan terakhir',
          'icon': Icons.schedule,
          'color': AppColors.info,
        });
      }
    }

    if (recommendations.isEmpty) {
      recommendations.add({
        'title': 'Kondisi Optimal',
        'description': 'Semua parameter dalam kondisi baik',
        'icon': Icons.check_circle,
        'color': AppColors.success,
      });
    }

    setState(() {});
  }

  void _toggleFertilizerPump() {
    setState(() {
      isPumpActive = !isPumpActive;
      if (isPumpActive) {
        lastFertilizeTime = DateTime.now();
        pumpRuntime = 0;
        // Simulasi pengurangan level pupuk
        Future.delayed(Duration(seconds: 1), _updatePumpRuntime);
      }
    });
  }

  void _updatePumpRuntime() {
    if (isPumpActive && mounted) {
      setState(() {
        pumpRuntime++;
        if (fertilizerLevel > 0) {
          fertilizerLevel -= 0.5; // Kurangi 0.5% per detik
          if (fertilizerLevel < 0) fertilizerLevel = 0;
        }
        
        if (fertilizerLevel <= 0) {
          isPumpActive = false;
        }
      });
      
      if (isPumpActive) {
        Future.delayed(Duration(seconds: 1), _updatePumpRuntime);
      } else {
        _analyzeHealthStatus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(),
            const SizedBox(height: 24),

            // Plant Status Card
            _buildPlantStatusCard(),
            const SizedBox(height: 20),

            // Sensor Monitoring
            _buildSensorMonitoring(),
            const SizedBox(height: 20),

            // Fertilizer Pump Control
            _buildFertilizerPumpCard(),
            const SizedBox(height: 20),

            // Recommendations
            _buildRecommendations(),
            const SizedBox(height: 20),

            // History Chart
            _buildHistoryChart(),
          ],
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
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.eco,
                color: AppColors.success,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kesehatan Tanaman',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Monitoring kondisi tanah & sistem pemupukan',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _analyzeHealthStatus,
              icon: Icon(Icons.refresh),
              color: AppColors.primary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlantStatusCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [plantStatusColor, plantStatusColor.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: plantStatusColor.withOpacity(0.3),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status Kesehatan',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    plantStatus,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Terakhir update: Baru saja',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.spa,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorMonitoring() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monitoring Sensor',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),

        // pH Tanah
        _buildSensorCard(
          title: 'pH Tanah',
          value: phValue,
          unit: '',
          icon: Icons.science,
          color: AppColors.warning,
          minValue: 0,
          maxValue: 14,
          optimalMin: 5.5,
          optimalMax: 7.5,
          description: _getPhDescription(phValue),
        ),
        const SizedBox(height: 16),

        // Soil Moisture
        _buildSensorCard(
          title: 'Kelembaban Tanah',
          value: soilMoisture,
          unit: '%',
          icon: Icons.grass,
          color: AppColors.primary,
          minValue: 0,
          maxValue: 100,
          optimalMin: 40,
          optimalMax: 80,
          description: _getSoilMoistureDescription(soilMoisture),
        ),
      ],
    );
  }

  Widget _buildSensorCard({
    required String title,
    required double value,
    required String unit,
    required IconData icon,
    required Color color,
    required double minValue,
    required double maxValue,
    required double optimalMin,
    required double optimalMax,
    required String description,
  }) {
    final isOptimal = value >= optimalMin && value <= optimalMax;
    final percentage = ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isOptimal
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isOptimal ? 'Optimal' : 'Warning',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isOptimal ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Value Display
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    unit,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Progress Bar
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: percentage,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    minValue.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  Text(
                    'Optimal: $optimalMin - $optimalMax$unit',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    maxValue.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFertilizerPumpCard() {
    Color statusColor = isPumpActive ? AppColors.success : AppColors.textSecondary;
    
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.local_florist,
                      color: AppColors.success,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pompa Pupuk Cair',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        isPumpActive ? 'Aktif - Sedang Memompa' : 'Tidak Aktif',
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                width: 56,
                height: 32,
                decoration: BoxDecoration(
                  color: isPumpActive ? AppColors.success : AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: Duration(milliseconds: 200),
                      left: isPumpActive ? 28 : 4,
                      top: 4,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Pump Stats
          Row(
            children: [
              Expanded(
                child: _buildPumpStat(
                  Icons.timer,
                  'Waktu Jalan',
                  '${pumpRuntime}s',
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildPumpStat(
                  Icons.history,
                  'Terakhir',
                  lastFertilizeTime != null 
                      ? _formatLastFertilize(lastFertilizeTime!)
                      : '-',
                  AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Fertilizer Level
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Level Pupuk Cair',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${fertilizerLevel.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _getFertilizerLevelColor(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: fertilizerLevel / 100,
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _getFertilizerLevelColor(),
                              _getFertilizerLevelColor().withOpacity(0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Estimasi: ${(fertilizerLevel * 1.5).toStringAsFixed(0)} liter tersisa',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Control Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: fertilizerLevel > 0 ? _toggleFertilizerPump : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isPumpActive ? AppColors.error : AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: isPumpActive ? 4 : 2,
              ),
              icon: Icon(
                isPumpActive ? Icons.stop : Icons.play_arrow,
                size: 24,
              ),
              label: Text(
                isPumpActive ? 'Hentikan Pompa' : 'Jalankan Pompa',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          if (fertilizerLevel <= 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tangki pupuk kosong! Isi ulang sebelum menggunakan pompa.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPumpStat(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getFertilizerLevelColor() {
    if (fertilizerLevel > 60) return AppColors.success;
    if (fertilizerLevel > 30) return AppColors.warning;
    return AppColors.error;
  }

  String _formatLastFertilize(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m lalu';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}j lalu';
    } else {
      return '${diff.inDays}h lalu';
    }
  }

  Widget _buildRecommendations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rekomendasi',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        ...recommendations.map((rec) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: rec['color'].withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: rec['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(rec['icon'], color: rec['color'], size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rec['title'],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rec['description'],
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildHistoryChart() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tren 7 Hari Terakhir',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text('Lihat Detail'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildChartLegend(),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: Size(double.infinity, 120),
              painter: SimpleChartPainter(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _buildLegendItem(AppColors.warning, 'pH'),
        _buildLegendItem(AppColors.primary, 'Kelembaban'),
        _buildLegendItem(AppColors.success, 'Pemupukan'),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  String _getPhDescription(double ph) {
    if (ph < 5.5) return 'Sangat Asam';
    if (ph < 6.0) return 'Asam';
    if (ph < 6.5) return 'Sedikit Asam';
    if (ph < 7.5) return 'Netral (Ideal)';
    if (ph < 8.0) return 'Sedikit Basa';
    return 'Basa';
  }

  String _getSoilMoistureDescription(double moisture) {
    if (moisture < 30) return 'Sangat Kering';
    if (moisture < 40) return 'Kering';
    if (moisture < 60) return 'Lembab (Baik)';
    if (moisture < 80) return 'Basah (Optimal)';
    if (moisture < 90) return 'Sangat Basah';
    return 'Jenuh Air';
  }
}

// Simple Chart Painter
class SimpleChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Sample data points for 7 days
    final phData = [6.2, 6.4, 6.5, 6.3, 6.5, 6.6, 6.5];
    final moistureData = [65.0, 68.0, 72.0, 70.0, 72.0, 75.0, 72.0];
    final fertilizerData = [90.0, 85.0, 80.0, 75.0, 70.0, 68.0, 65.0];

    // Draw pH line
    paint.color = AppColors.warning;
    _drawLine(canvas, size, phData, 0, 14, paint);

    // Draw moisture line
    paint.color = AppColors.primary;
    _drawLine(canvas, size, moistureData, 0, 100, paint);

    // Draw fertilizer level line
    paint.color = AppColors.success;
    _drawLine(canvas, size, fertilizerData, 0, 100, paint);
  }

  void _drawLine(Canvas canvas, Size size, List<double> data,
      double minVal, double maxVal, Paint paint) {
    final path = Path();
    final spacing = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * spacing;
      final normalizedY = (data[i] - minVal) / (maxVal - minVal);
      final y = size.height - (normalizedY * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}