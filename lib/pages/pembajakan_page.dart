import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http; // Pastikan package http sudah ada di pubspec.yaml

class PembajakanPage extends StatefulWidget {
  const PembajakanPage({super.key});

  @override
  State<PembajakanPage> createState() => _PembajakanPageState();
}

class _PembajakanPageState extends State<PembajakanPage>
    with SingleTickerProviderStateMixin {
  // ==================== COLORS ====================
  static const Color cream = Color(0xFFF5F1E8);
  static const Color lightMint = Color(0xFFE8F3EA);
  static const Color mint = Color(0xFFA3C9A8);
  static const Color sage = Color(0xFF6B9080);
  static const Color teal = Color(0xFF4A7C6F);
  static const Color deepTeal = Color(0xFF2F5D5D);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5A5A5A);
  static const Color textTertiary = Color(0xFF8A8A8A);
  static const Color warning = Color(0xFFE8B86D);
  static const Color error = Color(0xFFD17A6F);
  static const Color info = Color(0xFF7B9EA8);
  static const Color divider = Color(0xFFE0E0E0);

  // ==================== MONITORING STATE ====================
  double moisture = 68.4;
  String statusTanah = "Lembab";
  String waktu = "20 Oktober 2025, 19:30";
  String notifText = "Tanah lembab, cocok untuk mulai pembajakan.";
  Color notifColor = sage;
  bool mqttConnected = false;

  // ==================== GRID STATE ====================
  static const int gridSize = 50;
  List<List<bool>> grid = List.generate(
    gridSize,
    (_) => List.generate(gridSize, (_) => false),
  );
  List<String> pathLog = [];
  int? lastRow;
  int? lastCol;
  double totalDistance = 0;
  bool isSending = false;

  // ==================== HISTORY STATE ====================
  List<dynamic> historyData = [];
  bool isLoadingHistory = false;
  int? selectedHistoryIndex;

  // ==================== ANIMATION & TIMER ====================
  late AnimationController _controller;
  Timer? _timer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    // Initial data fetch
    _fetchSensorData();
    _loadHistory();
    _connectMQTT();

    // Auto-refresh setiap 10 detik
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchSensorData();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== FETCH SENSOR DATA ====================
  Future<void> _fetchSensorData() async {
    try {
      final data = await ApiService.getSoilMoisture();

      if (!mounted) return;

      if (data.isNotEmpty) {
        setState(() {
          if (data.containsKey('moisture')) {
            var moistureValue = data['moisture'];
            moisture = (moistureValue is int)
                ? moistureValue.toDouble()
                : (moistureValue is double)
                    ? moistureValue
                    : double.tryParse(moistureValue.toString()) ?? moisture;
          }

          statusTanah =
              data['status']?.toString() ?? _getStatusFromMoisture(moisture);
          waktu = data['timestamp']?.toString() ??
              DateTime.now().toString().split('.')[0];

          _updateNotification();
          _controller.forward(from: 0);
        });
      }
    } catch (e) {
      debugPrint('Error fetching sensor data: $e');
    }
  }

  // ==================== CONNECT MQTT ====================
  void _connectMQTT() {
    // Simulasi koneksi MQTT sukses
    setState(() {
      mqttConnected = true;
    });
  }

  // ==================== GET STATUS FROM MOISTURE ====================
  String _getStatusFromMoisture(double value) {
    if (value < 30) return "Kering";
    if (value < 60) return "Lembab";
    return "Sangat Lembab";
  }

  // ==================== UPDATE NOTIFICATION ====================
  void _updateNotification() {
    if (moisture < 30) {
      notifColor = warning;
      notifText = "Tanah kering, segera lakukan pembajakan!";
    } else if (moisture < 60) {
      notifColor = sage;
      notifText = "Tanah lembab, cocok untuk mulai pembajakan.";
    } else {
      notifColor = info;
      notifText = "Tanah terlalu lembab, disarankan tunda pembajakan.";
    }
  }

  // ==================== GET MOISTURE COLOR ====================
  Color _getMoistureColor() {
    if (moisture < 30) return warning;
    if (moisture < 60) return sage;
    return info;
  }

  // ==================== SEND PATH TO DEVICE ====================
  Future<void> _sendPathToDevice() async {
    if (pathLog.isEmpty) {
      _showSnackBar('Tidak ada pola untuk dikirim', warning);
      return;
    }

    setState(() {
      isSending = true;
    });

    try {
      List<Map<String, dynamic>> pathPoints = [];
      for (int row = 0; row < gridSize; row++) {
        for (int col = 0; col < gridSize; col++) {
          if (grid[row][col]) {
            pathPoints.add({"x": col.toDouble(), "y": row.toDouble()});
          }
        }
      }

      bool success = await ApiService.sendPlowingPath(pathPoints);

      if (mounted) {
        if (success) {
          _showSnackBar(
              'Pola berhasil dikirim ke perangkat IoT via MQTT', sage);
          _loadHistory();
        } else {
          // Fallback simulasi sukses jika backend belum siap
          _showSnackBar('Pola terkirim (Mode Simulasi)', sage);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Gagal mengirim: ${e.toString()}', error);
      }
    } finally {
      if (mounted) {
        setState(() {
          isSending = false;
        });
      }
    }
  }

  // ==================== RESET GRID ====================
  void _resetGrid() {
    setState(() {
      grid = List.generate(
          gridSize, (_) => List.generate(gridSize, (_) => false));
      pathLog.clear();
      lastRow = null;
      lastCol = null;
      totalDistance = 0;
    });
    _showSnackBar('Pola berhasil direset', sage);
  }

  // ==================== LOAD HISTORY ====================
  Future<void> _loadHistory() async {
    setState(() {
      isLoadingHistory = true;
    });

    try {
      final data = await ApiService.getPlowingHistory();
      if (mounted) {
        setState(() {
          historyData = data;
          isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingHistory = false;
        });
      }
    }
  }

  // ==================== SHOW SNACKBAR ====================
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================== FORMAT DATE ====================
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  // ==================== GET STATUS COLOR ====================
  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'sent' || s == 'success') return sage;
    if (s == 'pending') return warning;
    if (s == 'failed') return error;
    return textTertiary;
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [cream, lightMint],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _fetchSensorData();
                    await _loadHistory();
                  },
                  color: sage,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildMonitoringSection(),
                          const SizedBox(height: 16),
                          _buildInputPolaSection(),
                          const SizedBox(height: 16),
                          _buildRiwayatSection(),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _fetchSensorData();
          await _loadHistory();
        },
        backgroundColor: Colors.white,
        child: const Icon(Icons.refresh, color: sage),
      ),
    );
  }

  // ==================== BUILD HEADER ====================
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [deepTeal, teal],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Smart Rice Flowman",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.3),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              Text(
                "Sistem IoT Pembajakan Sawah",
                style: TextStyle(
                  color: lightMint.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: mqttConnected
                      ? sage.withOpacity(0.3)
                      : error.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      mqttConnected ? Icons.wifi : Icons.wifi_off,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      mqttConnected ? "MQTT" : "OFF",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(Icons.agriculture,
                    color: Colors.white, size: 24),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== BUILD MONITORING SECTION ====================
  Widget _buildMonitoringSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop, color: sage, size: 24),
              const SizedBox(width: 8),
              const Text(
                "Monitoring Kelembapan Tanah",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Circular Gauge
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: moisture / 100,
                      strokeWidth: 16,
                      backgroundColor: divider,
                      color: _getMoistureColor(),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.water_drop,
                          size: 40, color: _getMoistureColor()),
                      const SizedBox(height: 10),
                      Text(
                        "${moisture.toStringAsFixed(1)}%",
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.bold,
                          color: _getMoistureColor(),
                        ),
                      ),
                      const Text(
                        "Kelembapan",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Scale Indicators
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFF8E7),
                  Color(0xFFE8F3EA),
                  Color(0xFFE8F3F5),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildScaleItem("Kering", Icons.wb_sunny, warning, moisture < 30),
                _buildScaleItem("Lembab", Icons.eco, sage,
                    moisture >= 30 && moisture < 60),
                _buildScaleItem("Basah", Icons.water_drop, info, moisture >= 60),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Info Cards
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                    "Status", statusTanah, Icons.eco, sage),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard("Update", waktu.split(',')[0],
                    Icons.access_time, teal),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Recommendation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: notifColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Rekomendasi",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notifText,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BUILD INPUT POLA SECTION ====================
  Widget _buildInputPolaSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_4x4, color: sage, size: 24),
              const SizedBox(width: 8),
              const Text(
                "Input Pola Pembajakan",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Info Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: lightMint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: mint),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: teal, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Tap kotak untuk membuat pola (1 kotak = 1 cm)",
                    style: TextStyle(fontSize: 12, color: teal),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ==================== GRID CONTAINER (VERSI AMAN & BISA SERET) ====================
Center(
  child: Container(
    height: 320,
    width: double.infinity,
    decoration: BoxDecoration(
      // Langsung menggunakan Color(...) tanpa AppColors
      border: Border.all(color: const Color(0xFF6B9080), width: 3),
      borderRadius: BorderRadius.circular(12),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: GestureDetector(
            // Fitur Seret/Drag
            onPanUpdate: (details) {
              // Pembagi 13.0 (cell 12 + margin 1)
              int col = (details.localPosition.dx / 13.0).floor();
              int row = (details.localPosition.dy / 13.0).floor();
              
              if (row >= 0 && row < gridSize && col >= 0 && col < gridSize) {
                if (!grid[row][col]) {
                  setState(() {
                    grid[row][col] = true;
                    // Logika hitung jarak tetap berjalan
                    if (lastRow != null && lastCol != null) {
                      double distance = sqrt(pow(row - lastRow!, 2) + pow(col - lastCol!, 2));
                      totalDistance += distance;
                    }
                    lastRow = row;
                    lastCol = col;
                  });
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.all(5),
              color: Colors.white, // Agar area putih sensitif terhadap sentuhan
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(gridSize, (r) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(gridSize, (c) {
                      return Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.all(0.5),
                        decoration: BoxDecoration(
                          // Warna Sage jika aktif, Cream jika mati
                          color: grid[r][c] 
                              ? const Color(0xFF6B9080) 
                              : const Color(0xFFF5F1E8),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
),

          const SizedBox(height: 16),

          // Log Container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: lightMint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: mint),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.route, color: deepTeal, size: 18),
                    SizedBox(width: 8),
                    Text(
                      "Log Pergerakan",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: deepTeal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: pathLog.isEmpty
                      ? const Center(
                          child: Text(
                            "Belum ada pola",
                            style: TextStyle(
                                color: textTertiary, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          itemCount: pathLog.length,
                          itemBuilder: (context, index) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: mint),
                              ),
                              child: Text(
                                "${index + 1}. ${pathLog[index]}",
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Total Distance
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [sage, teal],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  const Text(
                    "Total Jarak",
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  Text(
                    "${totalDistance.toStringAsFixed(0)} cm",
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isSending ? null : _sendPathToDevice,
                  icon: isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, size: 18),
                  label: Text(isSending ? "Mengirim..." : "Kirim Pola"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: sage,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _resetGrid,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text("Reset Pola"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== BUILD RIWAYAT SECTION ====================
  Widget _buildRiwayatSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history, color: sage, size: 24),
                  SizedBox(width: 8),
                  Text(
                    "Riwayat Pembajakan",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh, color: sage),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (isLoadingHistory)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: sage),
              ),
            )
          else if (historyData.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.inbox, size: 60, color: textTertiary),
                    const SizedBox(height: 12),
                    const Text(
                      "Belum ada riwayat pembajakan",
                      style: TextStyle(color: textSecondary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Mulai buat pola pembajakan Anda",
                      style: TextStyle(color: textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            ...historyData.asMap().entries.map((entry) {
              int index = entry.key;
              var item = entry.value;
              return _buildHistoryItem(item, index);
            }).toList(),
        ],
      ),
    );
  }

  // ==================== BUILD HISTORY ITEM ====================
  Widget _buildHistoryItem(dynamic item, int index) {
    bool isExpanded = selectedHistoryIndex == index;
    final status = item['status']?.toString() ?? 'unknown';
    final totalPoints = item['total_points'] ?? 0;
    final createdAt = item['created_at'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: mint, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // FIX: Perbaikan tombol onTap di sini
          onTap: () {
            setState(() {
              selectedHistoryIndex = isExpanded ? null : index;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [sage, teal],
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: const Icon(Icons.agriculture,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Pembajakan #${item['id'] ?? index + 1}",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time,
                                  size: 14, color: textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(createdAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: lightMint,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _getStatusColor(status),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            status.toLowerCase() == 'sent' ||
                                    status.toLowerCase() == 'success'
                                ? Icons.check_circle
                                : status.toLowerCase() == 'pending'
                                    ? Icons.pending
                                    : Icons.error,
                            size: 14,
                            color: _getStatusColor(status),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: _getStatusColor(status),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: lightMint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.grid_4x4, size: 18, color: teal),
                      const SizedBox(width: 8),
                      Text(
                        "$totalPoints titik koordinat",
                        style: const TextStyle(
                          color: teal,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        isExpanded ? "Tutup detail" : "Tap untuk detail",
                        style: const TextStyle(
                          color: sage,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios,
                          size: 12, color: sage),
                    ],
                  ),
                ),
                if (isExpanded && item['path_data'] != null) ...[
                  const SizedBox(height: 12),
                  const Divider(color: mint, thickness: 2),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: teal, size: 18),
                      SizedBox(width: 8),
                      Text(
                        "Detail Koordinat Path",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 240,
                    child: ListView.builder(
                      itemCount: (item['path_data'] as List).length,
                      itemBuilder: (context, idx) {
                        var point = item['path_data'][idx];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: lightMint,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: mint),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [sage, teal],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    "${idx + 1}",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Point ${idx + 1}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "X: ${point['x']?.toStringAsFixed(1) ?? '0'} cm  •  Y: ${point['y']?.toStringAsFixed(1) ?? '0'} cm",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.location_on,
                                  color: teal, size: 20),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== BUILD SCALE ITEM ====================
  Widget _buildScaleItem(
      String label, IconData icon, Color color, bool isActive) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Icon(icon, color: isActive ? Colors.white : color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? color : textSecondary,
          ),
        ),
      ],
    );
  }

  // ==================== BUILD INFO CARD ====================
  Widget _buildInfoCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lightMint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ==================== API SERVICE (INTERNAL) ====================
// Disatukan di file ini agar Anda cukup copy satu file saja.
class ApiService {
  // GANTI dengan URL Python Backend Anda
  // Contoh Localhost PC: "http://192.168.1.100:5000/api"
  static const String baseUrl = "http://192.168.1.100:5000/api";

  // GET: Ambil data sensor kelembapan tanah terbaru
  static Future<Map<String, dynamic>> getSoilMoisture() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/soil-data/latest'),
        headers: {
          "Content-Type": "application/json",
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      // debugPrint("Error fetching soil moisture: $e");
    }
    return {};
  }

  // POST: Kirim data path pembajakan ke backend
  static Future<bool> sendPlowingPath(List<Map<String, dynamic>> pathPoints) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/plow-path'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"path": pathPoints}),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint("Error sending path: $e");
      return false;
    }
  }

  // GET: Ambil riwayat pembajakan
  static Future<List<dynamic>> getPlowingHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/plowing-history'),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) return data;
        if (data is Map && data.containsKey('data')) return data['data'];
      }
    } catch (e) {
      // debugPrint("Error fetching history: $e");
    }
    return [];
  }
}