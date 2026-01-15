import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Smart Rice Flowman - IoT Pembajakan Sawah Otomatis
/// Versi: 16.0 Production (Updated Connection to smart-garden-backend)

class PembajakanPage extends StatefulWidget {
  const PembajakanPage({super.key});

  @override
  State<PembajakanPage> createState() => _PembajakanPageState();
}

class _PembajakanPageState extends State<PembajakanPage>
    with SingleTickerProviderStateMixin {
  
  // ================= WARNA TEMA (TETAP) =================
  static const cream = Color(0xFFF5F1E8);
  static const lightMint = Color(0xFFE8F3EA);
  static const mint = Color(0xFFA3C9A8);
  static const sage = Color(0xFF6B9080);
  static const teal = Color(0xFF4A7C6F);
  static const deepTeal = Color(0xFF2F5D5D);
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF5A5A5A);
  static const warning = Color(0xFFE8B86D);
  static const error = Color(0xFFD17A6F);
  static const info = Color(0xFF7B9EA8);

  // ================= URL BACKEND RAILWAY =================
  final String baseUrl = "https://smart-garden-backend-production.up.railway.app";

  // ================= STATE MANAGEMENT =================
  late AnimationController _animController;
  Timer? _sensorTimer;

  // Data Sensor (Sinkron dengan tabel sensor_logs)
  double _soilMoisture = 0.0;
  String _soilStatus = "Menunggu data sensor...";
  String _lastUpdate = "N/A";
  String _recommendation = "Sistem sedang menghubungkan ke sensor Soil Moisture L.V 12...";
  Color _statusColor = sage;
  bool _isConnected = false;

  // Grid Navigation
  static const int gridSize = 20; 
  late List<List<bool>> grid;
  final List<Map<String, dynamic>> pathLog = [];
  Offset? lastPoint;
  double totalDistance = 0;
  bool isSending = false;

  // History (Sinkron dengan tabel plowing_history)
  List<dynamic> historyData = [];
  bool isLoadingHistory = false;
  int? expandedIndex;

  @override
  void initState() {
    super.initState();
    grid = List.generate(gridSize, (_) => List.filled(gridSize, false));
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _fetchRealSensorData();
    _loadHistory();
    // Refresh otomatis data sensor setiap 10 detik
    _sensorTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchRealSensorData());
  }

  @override
  void dispose() {
    _sensorTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  // ================= PENYEMPURNAAN KONEKSI BACKEND =================

  // Ambil data terbaru dari tabel sensor_logs via backend Python
  Future<void> _fetchRealSensorData() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/soil-data/latest'),
        headers: {"Accept": "application/json"}
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        
        // Cek jika ada data sensor yang valid
        if (data != null && data['moisture'] != null) {
          var moistVal = data['moisture'];
          double currentMoisture = moistVal is num ? moistVal.toDouble() : double.tryParse(moistVal.toString()) ?? 0.0;

          setState(() {
            _isConnected = true;
            _soilMoisture = currentMoisture;
            // Gunakan timestamp dari database atau waktu sekarang
            _lastUpdate = data['timestamp']?.toString() ?? DateTime.now().toString().substring(11, 16);
            _analyzeRealSoilData();
          });
        } else {
          setState(() {
            _isConnected = true;
            _soilStatus = "Sensor Belum Aktif";
            _recommendation = "Data sensor_logs kosong. Pastikan alat IoT telah mengirim data.";
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isConnected = false);
      debugPrint("Sensor Error: $e");
    }
  }

  void _analyzeRealSoilData() {
    if (_soilMoisture < 35.0) {
      _soilStatus = "Tanah Kering";
      _statusColor = warning;
      _recommendation = "Kelembapan rendah terdeteksi. Tanah keras, disarankan tunda pembajakan.";
    } else if (_soilMoisture <= 75.0) {
      _soilStatus = "Kondisi Optimal";
      _statusColor = sage;
      _recommendation = "Kelembapan ideal terdeteksi. Kondisi tanah sempurna untuk pembajakan otomatis.";
    } else {
      _soilStatus = "Tanah Basah";
      _statusColor = info;
      _recommendation = "Kelembapan tinggi terdeteksi. Tanah terlalu lembab, disarankan menggunakan pola spiral agar traktor tidak selip.";
    }
  }

  // Kirim pola ke backend (Akan disimpan ke plowing_history & dikirim ke MQTT)
  Future<void> _sendPattern() async {
    if (pathLog.isEmpty) {
      _showSnack('Tidak ada pola untuk dikirim! Silakan gambar pada grid.', error);
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
          _showSnack('Pola terkirim ke alat & Tersimpan di MySQL Railway', sage);
          _resetGrid();
          Future.delayed(const Duration(seconds: 2), () => _loadHistory());
        } else {
          _showSnack('Gagal sinkronisasi backend (Status: ${res.statusCode})', error);
        }
      }
    } catch (e) {
      _showSnack('Gagal menghubungkan ke Railway: ${e.toString()}', error);
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  // Ambil daftar riwayat dari tabel plowing_history
  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => isLoadingHistory = true);
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/plowing-history'),
        headers: {"Accept": "application/json"}
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 && mounted) {
        final decoded = json.decode(res.body);
        setState(() {
          historyData = decoded is List ? decoded : (decoded['data'] ?? []);
          isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoadingHistory = false);
      debugPrint("History Error: $e");
    }
  }

  // ================= LOGIKA GRID & UI (TETAP UTUH) =================

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
            if (dy < 0) direction = "Maju";
            else if (dy > 0) direction = "Mundur";
            if (dx > 0) direction += (direction.isEmpty ? "" : " ") + "Kanan";
            else if (dx < 0) direction += (direction.isEmpty ? "" : " ") + "Kiri";
            
            if (direction.isNotEmpty) {
              pathLog.add({
                "direction": direction,
                "distance": dist,
                "from": lastPoint!,
                "to": Offset(col.toDouble(), row.toDouble())
              });
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: col,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cream,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: BGPainter())),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: RefreshIndicator(
                    color: teal,
                    onRefresh: () async {
                      await _fetchRealSensorData();
                      await _loadHistory();
                    },
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildMonitoring(),
                          const SizedBox(height: 20),
                          _buildNavigation(),
                          const SizedBox(height: 20),
                          _buildHistory(),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

Widget _buildHeader() {
  return Container(
    padding: const EdgeInsets.fromLTRB(25, 20, 25, 30),
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [deepTeal, teal]),
      borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 8))],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // TOMBOL BACK DITAMBAHKAN DI SINI
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 24),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Smart Rice Flowman", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                        boxShadow: [BoxShadow(color: _isConnected ? Colors.greenAccent : Colors.redAccent, blurRadius: 8)],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(_isConnected ? "CONNECTED" : "SIGNAL DISCONNECTED",
                      style: const TextStyle(color: lightMint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  ],
                ),
              ],
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 28),
          onPressed: () async {
            await _fetchRealSensorData();
            await _loadHistory();
          },
        ),
      ],
    ),
  );
}

  Widget _buildMonitoring() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop_rounded, color: teal, size: 24),
              const SizedBox(width: 12),
              const Text("Monitoring Kelembapan Tanah", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: deepTeal)),
            ],
          ),
          const SizedBox(height: 25),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: CircularProgressIndicator(
                  value: _soilMoisture / 100,
                  strokeWidth: 18,
                  backgroundColor: cream,
                  color: _statusColor,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("${_soilMoisture.toInt()}%",
                    style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: _statusColor, letterSpacing: -2)),
                  const Text("KELEMBAPAN", style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              _buildInfo("Status", _soilStatus, Icons.eco_rounded, _statusColor),
              const SizedBox(width: 15),
              _buildInfo("Update", _lastUpdate, Icons.schedule_rounded, teal),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: _statusColor.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_rounded, color: _statusColor, size: 26),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Rekomendasi Pembajakan Sawah:", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: deepTeal)),
                      const SizedBox(height: 6),
                      Text(_recommendation, style: TextStyle(color: deepTeal.withOpacity(0.85), height: 1.5, fontSize: 12.5)),
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

  Widget _buildNavigation() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_rounded, color: teal, size: 24),
              const SizedBox(width: 12),
              const Text("Sistem Penentuan Navigasi Jalur", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: deepTeal)),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Gambarkan pola pada grid untuk navigasi traktor otomatis.",
            style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4)),
          const SizedBox(height: 20),
          
          LayoutBuilder(
  builder: (context, constraints) {
    double size = constraints.maxWidth;
    return Container(
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: deepTeal, width: 4),
        borderRadius: BorderRadius.circular(25),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: deepTeal.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: GestureDetector(
          // PENTING: onPanDown dan onPanUpdate mencegah scroll
          onPanDown: (details) => _handleGridDraw(details.localPosition, size),
          onPanUpdate: (details) => _handleGridDraw(details.localPosition, size),
          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            size: Size(size, size),
            painter: ImprovedGridPainter(
              grid: grid, 
              activeColor: sage, 
              resolution: gridSize
            ),
          ),
        ),
      ),
    );
  },
),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: lightMint,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: mint),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.route_rounded, color: deepTeal, size: 18),
                    SizedBox(width: 8),
                    Text("Detail Pergerakan", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: deepTeal)),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
                  child: pathLog.isEmpty
                    ? const Center(child: Text("Silakan gambar pola pada grid", style: TextStyle(color: textSecondary, fontSize: 12)))
                    : ListView.builder(
                      itemCount: pathLog.length,
                      itemBuilder: (c, i) {
                        var log = pathLog[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: mint),
                          ),
                          child: Text(
                            "${i + 1}. Arah: ${log['direction']} | Jarak: ${log['distance'].toStringAsFixed(0)} cm",
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        );
                      },
                    ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [sage, teal]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Column(
                children: [
                  const Text("Total Jarak Misi", style: TextStyle(fontSize: 12, color: Colors.white70)),
                  Text("${totalDistance.toStringAsFixed(0)} cm", style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isSending ? null : _sendPattern,
                  icon: isSending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_to_mobile_rounded, size: 20),
                  label: Text(isSending ? "MENGIRIM..." : "KIRIM KOORDINAT"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: deepTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _resetGrid,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text("Reset"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 10, bottom: 15),
          child: Text("Riwayat Pembajakan", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: deepTeal)),
        ),
        if (isLoadingHistory)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else if (historyData.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(45),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
            child: Column(
              children: [
                Icon(Icons.history_toggle_off_rounded, size: 55, color: mint.withOpacity(0.5)),
                const SizedBox(height: 15),
                const Text("Belum ada riwayat Pembajakan", style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600)),
              ],
            ),
          )
        else
          ...historyData.asMap().entries.map((e) => _buildHistoryCard(e.value, e.key)).toList(),
      ],
    );
  }

  Widget _buildHistoryCard(dynamic data, int index) {
    bool isExp = expandedIndex == index;
    // Sinkronisasi field created_at dari database MySQL Railway
    final String fullDate = (data['created_at'] ?? "N/A").toString();
    final String dateDisplay = fullDate.contains("T") ? fullDate.split("T")[0] : fullDate;
    
    // Sinkronisasi field path_data (JSON String -> List)
    var rawPath = data['path_data'];
    List coords = [];
    if (rawPath is String) {
      coords = json.decode(rawPath);
    } else if (rawPath is List) {
      coords = rawPath;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: isExp ? teal : Colors.transparent, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            onTap: () => setState(() => expandedIndex = isExp ? null : index),
            leading: const CircleAvatar(backgroundColor: lightMint, radius: 24, child: Icon(Icons.agriculture_rounded, color: sage)),
            title: Text("Misi Pembajakan #${data['id'] ?? index}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            subtitle: Text("Tanggal: $dateDisplay", style: const TextStyle(fontSize: 12)),
            trailing: Icon(isExp ? Icons.expand_less : Icons.expand_more, color: mint, size: 28),
          ),
          if (isExp)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 25, thickness: 1),
                  Row(
                    children: [
                      const Icon(Icons.verified_user_rounded, size: 16, color: Colors.green),
                      const SizedBox(width: 10),
                      const Text("Status Database:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      const Text("Sinkron Railway", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.straighten_rounded, size: 16, color: teal),
                      const SizedBox(width: 10),
                      const Text("Jarak Tempuh:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text("${data['total_distance']?.toStringAsFixed(0) ?? '0'} cm", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: teal)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.water_drop_rounded, size: 16, color: info),
                      const SizedBox(width: 10),
                      const Text("Kelembapan Awal:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text("${data['moisture_at_start']?.toStringAsFixed(1) ?? '0'} %", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: info)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  const Text("LOG KOORDINAT MISI:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: cream, borderRadius: BorderRadius.circular(15)),
                    child: Text(
                      coords.isEmpty ? "Tidak ada koordinat tersimpan" : coords.take(20).map((e) => "(${e['x']},${e['y']})").join(" • "),
                      style: const TextStyle(fontSize: 11, fontFamily: 'Monospace', color: deepTeal),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfo(String label, String value, IconData icon, Color col) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cream.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: col.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: col),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textPrimary), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ================= CUSTOM PAINTERS (TETAP) =================

class ImprovedGridPainter extends CustomPainter {
  final List<List<bool>> grid;
  final Color activeColor;
  final int resolution;

  ImprovedGridPainter({required this.grid, required this.activeColor, required this.resolution});

  @override
  void paint(Canvas canvas, Size size) {
    double cellW = size.width / resolution;
    double cellH = size.height / resolution;

    // Garis grid yang lebih tebal dan jelas
    Paint gridPaint = Paint()
      ..color = const Color(0xFF2F5D5D).withOpacity(0.4)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Gambar garis grid vertikal dan horizontal
    for (int i = 0; i <= resolution; i++) {
      canvas.drawLine(
        Offset(i * cellW, 0), 
        Offset(i * cellW, size.height), 
        gridPaint
      );
      canvas.drawLine(
        Offset(0, i * cellH), 
        Offset(size.width, i * cellH), 
        gridPaint
      );
    }

    // Garis tepi lebih tebal
    Paint borderPaint = Paint()
      ..color = const Color(0xFF2F5D5D)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);

    // Paint untuk sel aktif dengan efek glow
    Paint fillPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    
    Paint glowPaint = Paint()
      ..color = activeColor.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // Gambar sel yang aktif
    for (int r = 0; r < resolution; r++) {
      for (int c = 0; c < resolution; c++) {
        if (grid[r][c]) {
          Rect cellRect = Rect.fromLTWH(
            c * cellW + 2, 
            r * cellH + 2, 
            cellW - 4, 
            cellH - 4
          );
          
          // Efek glow
          canvas.drawRRect(
            RRect.fromRectAndRadius(cellRect.inflate(3), const Radius.circular(4)), 
            glowPaint
          );
          
          // Sel aktif
          canvas.drawRRect(
            RRect.fromRectAndRadius(cellRect, const Radius.circular(4)), 
            fillPaint
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ImprovedGridPainter oldDelegate) => true;
}

class BGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint p = Paint()..color = const Color(0xFFA3C9A8).withOpacity(0.1);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.1), 160, p);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.7), 220, p);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}