import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Smart Rice Flowman - IoT Pembajakan Sawah Otomatis
/// UI/UX Revamp: Modern Clean Interface

class PembajakanPage extends StatefulWidget {
  const PembajakanPage({super.key});

  @override
  State<PembajakanPage> createState() => _PembajakanPageState();
}

class _PembajakanPageState extends State<PembajakanPage>
    with SingleTickerProviderStateMixin {

  // ================= WARNA TEMA MODERN =================
  static const Color bgCream = Color(0xFFFAFAF5); // Lebih terang
  static const Color primaryTeal = Color(0xFF0D5C63); // Teal Gelap (Primary)
  static const Color accentMint = Color(0xFF44A1A0); // Mint Segar (Secondary)
  static const Color surfaceWhite = Colors.white;
  static const Color textDark = Color(0xFF1F2937);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color successGreen = Color(0xFF10B981);
  static const Color errorRed = Color(0xFFEF4444);

  // ================= URL BACKEND =================
  final String baseUrl = "https://smart-garden-backend-production.up.railway.app";

  // ================= STATE =================
  late AnimationController _animController;
  Timer? _sensorTimer;

  // Sensor Data
  double _soilMoisture = 0.0;
  String _soilStatus = "Menunggu...";
  String _lastUpdate = "--:--";
  String _recommendation = "Sedang memuat data...";
  bool _isConnected = false;

  // Grid Navigation
  static const int gridSize = 20;
  late List<List<bool>> grid;
  final List<Map<String, dynamic>> pathLog = [];
  Offset? lastPoint;
  double totalDistance = 0;
  bool isSending = false;

  // History
  List<dynamic> historyData = [];
  bool isLoadingHistory = false;
  int? expandedIndex;

  @override
  void initState() {
    super.initState();
    grid = List.generate(gridSize, (_) => List.filled(gridSize, false));
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
    _fetchRealSensorData();
    _loadHistory();
    _sensorTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchRealSensorData());
  }

  @override
  void dispose() {
    _sensorTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  // ================= LOGIC (TETAP SAMA) =================

  Future<void> _fetchRealSensorData() async {
    try {
      final res = await http.get(
          Uri.parse('$baseUrl/api/soil-data/latest'),
          headers: {"Accept": "application/json"}
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        if (data != null && data['moisture'] != null) {
          var moistVal = data['moisture'];
          double currentMoisture = moistVal is num ? moistVal.toDouble() : double.tryParse(moistVal.toString()) ?? 0.0;

          setState(() {
            _isConnected = true;
            _soilMoisture = currentMoisture;
            _lastUpdate = DateTime.now().toString().substring(11, 16); // Simple timestamp
            _analyzeRealSoilData();
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  void _analyzeRealSoilData() {
    if (_soilMoisture < 35.0) {
      _soilStatus = "Kering";
      _recommendation = "Tanah keras. Tunda pembajakan atau basahi lahan.";
    } else if (_soilMoisture <= 75.0) {
      _soilStatus = "Optimal";
      _recommendation = "Kondisi tanah ideal untuk pembajakan otomatis.";
    } else {
      _soilStatus = "Basah";
      _recommendation = "Tanah lembek. Gunakan pola spiral agar tidak selip.";
    }
  }

  Future<void> _sendPattern() async {
    if (pathLog.isEmpty) {
      _showSnack('Gambar pola jalur terlebih dahulu.', errorRed);
      return;
    }
    setState(() => isSending = true);
    try {
      List<Map<String, int>> coords = [];
      for (int r = 0; r < gridSize; r++) {
        for (int c = 0; c < gridSize; c++) {
          if (grid[r][c]) coords.add({"x": c, "y": r});
        }
      }
      final res = await http.post(
        Uri.parse('$baseUrl/api/plow-path'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "path": coords,
          "device_id": "TITAN-FLOWMAN-01",
          "moisture_at_start": _soilMoisture,
          "total_distance": totalDistance
        }),
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        if (res.statusCode == 200 || res.statusCode == 201) {
          _showSnack('Misi berhasil dikirim ke Traktor!', successGreen);
          _resetGrid();
          Future.delayed(const Duration(seconds: 2), () => _loadHistory());
        } else {
          _showSnack('Gagal sinkronisasi backend.', errorRed);
        }
      }
    } catch (e) {
      _showSnack('Koneksi Error: ${e.toString()}', errorRed);
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => isLoadingHistory = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/plowing-history'));
      if (res.statusCode == 200 && mounted) {
        final decoded = json.decode(res.body);
        setState(() {
          historyData = decoded is List ? decoded : (decoded['data'] ?? []);
          isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoadingHistory = false);
    }
  }

  void _handleGridDraw(Offset localPos, double boxSize) {
    double cellSize = boxSize / gridSize;
    int col = (localPos.dx / cellSize).floor();
    int row = (localPos.dy / cellSize).floor();

    if (row >= 0 && row < gridSize && col >= 0 && col < gridSize) {
      if (!grid[row][col]) {
        setState(() {
          grid[row][col] = true;
          if (lastPoint != null) {
            double dx = col - lastPoint!.dx;
            double dy = row - lastPoint!.dy;
            double dist = sqrt(dx * dx + dy * dy);

            String direction = "";
            if (dy < 0) direction = "Maju"; else if (dy > 0) direction = "Mundur";
            if (dx > 0) direction += (direction.isEmpty ? "" : " ") + "Kanan";
            else if (dx < 0) direction += (direction.isEmpty ? "" : " ") + "Kiri";

            if (direction.isNotEmpty) {
              pathLog.add({"direction": direction, "distance": dist});
              totalDistance += dist;
            }
          }
          lastPoint = Offset(col.toDouble(), row.toDouble());
        });
      }
    }
  }

  void _resetGrid() {
    setState(() {
      grid = List.generate(gridSize, (_) => List.filled(gridSize, false));
      pathLog.clear();
      lastPoint = null;
      totalDistance = 0;
    });
  }

  void _showSnack(String msg, Color col) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: col, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ================= UI BUILD =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      appBar: _buildModernAppBar(),
      body: RefreshIndicator(
        onRefresh: () async { await _fetchRealSensorData(); await _loadHistory(); },
        color: primaryTeal,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConnectionStatus(),
              const SizedBox(height: 20),
              _buildMonitoringCard(),
              const SizedBox(height: 25),
              _buildSectionTitle("Navigasi Traktor", Icons.agriculture_rounded),
              const SizedBox(height: 15),
              _buildGridSystem(),
              const SizedBox(height: 25),
              _buildSectionTitle("Riwayat Aktivitas", Icons.history_rounded),
              const SizedBox(height: 15),
              _buildHistoryList(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      backgroundColor: bgCream,
      elevation: 0,
      centerTitle: true,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      title: const Text("Smart Flowman", style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 18)),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: primaryTeal),
          onPressed: () { _fetchRealSensorData(); _loadHistory(); },
        )
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _isConnected ? successGreen.withOpacity(0.1) : errorRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isConnected ? successGreen.withOpacity(0.3) : errorRed.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: _isConnected ? successGreen : errorRed, size: 18),
          const SizedBox(width: 10),
          Text(
            _isConnected ? "Terhubung ke IoT Gateway" : "Koneksi Terputus",
            style: TextStyle(
                color: _isConnected ? successGreen : errorRed,
                fontWeight: FontWeight.bold,
                fontSize: 12
            ),
          ),
          const Spacer(),
          Text("Update: $_lastUpdate", style: const TextStyle(color: textGrey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildMonitoringCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [primaryTeal, Color(0xFF147A83)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: primaryTeal.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.water_drop_rounded, color: Colors.white70, size: 20),
              SizedBox(width: 8),
              Text("KELEMBAPAN TANAH", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_soilMoisture.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, height: 1)),
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 4),
                child: Text("%", style: TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_soilStatus.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              )
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _soilMoisture / 100,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation(
                  _soilMoisture < 35 ? warningOrange : (_soilMoisture > 75 ? accentMint : successGreen)
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.tips_and_updates_rounded, color: Colors.yellowAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(_recommendation, style: const TextStyle(color: Colors.white, fontSize: 12))),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: primaryTeal, size: 20),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
      ],
    );
  }

  Widget _buildGridSystem() {
    return Container(
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Header Grid
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Gambar Pola", style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
                    Text("Sentuh grid untuk membuat jalur", style: TextStyle(fontSize: 11, color: textGrey.withOpacity(0.8))),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: primaryTeal.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text("Jarak: ${totalDistance.toStringAsFixed(0)} cm", style: const TextStyle(color: primaryTeal, fontWeight: FontWeight.bold, fontSize: 12)),
                )
              ],
            ),
          ),

          // The Grid
          LayoutBuilder(
            builder: (context, constraints) {
              double size = constraints.maxWidth;
              return GestureDetector(
                onPanDown: (d) => _handleGridDraw(d.localPosition, size),
                onPanUpdate: (d) => _handleGridDraw(d.localPosition, size),
                child: Container(
                  height: size,
                  width: size,
                  decoration: BoxDecoration(
                      color: const Color(0xFFEEF2F6),
                      border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                          bottom: BorderSide(color: Colors.grey.shade200)
                      )
                  ),
                  child: CustomPaint(
                    painter: ImprovedGridPainter(grid: grid, activeColor: primaryTeal, resolution: gridSize),
                  ),
                ),
              );
            },
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetGrid,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text("Reset"),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: errorRed,
                        side: const BorderSide(color: errorRed),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: isSending ? null : _sendPattern,
                    icon: isSending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(isSending ? "Mengirim..." : "Kirim Misi"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: primaryTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (historyData.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: surfaceWhite, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Icon(Icons.history, size: 40, color: textGrey.withOpacity(0.3)),
            const SizedBox(height: 10),
            Text("Belum ada riwayat", style: TextStyle(color: textGrey.withOpacity(0.5))),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: historyData.length,
      itemBuilder: (context, index) {
        final data = historyData[index];
        final bool isExpanded = expandedIndex == index;
        final String date = (data['created_at'] ?? "N/A").toString().split("T")[0];

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isExpanded ? primaryTeal : Colors.transparent),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
          ),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                onTap: () => setState(() => expandedIndex = isExpanded ? null : index),
                leading: CircleAvatar(
                  backgroundColor: primaryTeal.withOpacity(0.1),
                  child: const Icon(Icons.check_circle_outline, color: primaryTeal, size: 20),
                ),
                title: Text("Misi #${data['id']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(date, style: const TextStyle(fontSize: 12, color: textGrey)),
                trailing: Text(
                  "${data['total_distance']?.toStringAsFixed(0) ?? 0} cm",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: primaryTeal, fontSize: 13),
                ),
              ),
              if (isExpanded)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFF3F4F6)))
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHistoryDetailRow("Status", "Sinkron Railway", successGreen),
                      _buildHistoryDetailRow("Moisture Awal", "${data['moisture_at_start'] ?? 0}%", textDark),
                      const SizedBox(height: 12),
                      const Text("Koordinat:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textGrey)),
                      const SizedBox(height: 4),
                      Text(
                        (data['path_data'] ?? "[]").toString(),
                        style: const TextStyle(fontFamily: "Monospace", fontSize: 10, color: textGrey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    ],
                  ),
                )
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryDetailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: textGrey)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ================= PAINTERS (DIPERHALUS) =================

class ImprovedGridPainter extends CustomPainter {
  final List<List<bool>> grid;
  final Color activeColor;
  final int resolution;

  ImprovedGridPainter({required this.grid, required this.activeColor, required this.resolution});

  @override
  void paint(Canvas canvas, Size size) {
    double cellW = size.width / resolution;
    double cellH = size.height / resolution;

    // Grid tipis
    Paint gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= resolution; i++) {
      canvas.drawLine(Offset(i * cellW, 0), Offset(i * cellW, size.height), gridPaint);
      canvas.drawLine(Offset(0, i * cellH), Offset(size.width, i * cellH), gridPaint);
    }

    // Sel Aktif
    Paint fillPaint = Paint()..color = activeColor;

    // Path Line (Untuk menghubungkan titik - opsional visualisasi)
    Paint pathPaint = Paint()
      ..color = activeColor.withOpacity(0.5)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    Path pathLine = Path();
    bool first = true;

    for (int r = 0; r < resolution; r++) {
      for (int c = 0; c < resolution; c++) {
        if (grid[r][c]) {
          // Gambar Kotak
          Rect cellRect = Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH);
          canvas.drawRRect(RRect.fromRectAndRadius(cellRect.deflate(2), const Radius.circular(4)), fillPaint);

          // Logic Path Line sederhana
          Offset center = Offset(c * cellW + cellW/2, r * cellH + cellH/2);
          if (first) {
            pathLine.moveTo(center.dx, center.dy);
            first = false;
          } else {
            pathLine.lineTo(center.dx, center.dy);
          }
        }
      }
    }

    // Gambar garis penghubung antar titik agar terlihat seperti jalur
    canvas.drawPath(pathLine, pathPaint);
  }

  @override
  bool shouldRepaint(covariant ImprovedGridPainter oldDelegate) => true;
}