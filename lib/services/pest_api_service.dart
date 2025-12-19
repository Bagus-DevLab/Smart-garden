import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class PestDetection {
  final int id;
  final String timestamp;
  final String imageBase64;
  final bool motionDetected;
  final int confidence;
  final String pestName;

  PestDetection({
    required this.id,
    required this.timestamp,
    required this.imageBase64,
    required this.motionDetected,
    required this.confidence,
    required this.pestName,
  });

  factory PestDetection.fromJson(Map<String, dynamic> json) {
    // Debug print untuk melihat struktur JSON
    debugPrint('🔍 JSON Data: ${json.toString()}');
    
    // Prioritas pengambilan nama hama dengan lebih banyak variasi:
    String getPestName() {
      // List semua kemungkinan key untuk pest name
      final possibleKeys = [
        'pestName',      // camelCase
        'pest_name',     // snake_case
        'name',          // simple
        'pest',          // alternative
        'class',         // dari model detection
        'class_name',    // dari model detection
        'className',     // camelCase variant
        'label',         // dari model detection
        'prediction',    // dari model detection
        'detected_pest', // alternative
      ];

      // Cari key yang ada dan memiliki value
      for (final key in possibleKeys) {
        if (json.containsKey(key)) {
          final value = json[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            final pestName = value.toString().trim();
            // Pastikan bukan string "unknown" atau "null"
            if (pestName.toLowerCase() != 'unknown' && 
                pestName.toLowerCase() != 'null' &&
                pestName != '0') {
              debugPrint('✅ Pest name found: $pestName (from key: $key)');
              return pestName;
            }
          }
        }
      }

      // Jika tidak ada yang ditemukan, cek nested objects
      if (json.containsKey('detection')) {
        final detection = json['detection'];
        if (detection is Map<String, dynamic>) {
          final nestedName = getPestNameFromMap(detection);
          if (nestedName != 'Unknown Pest') {
            return nestedName;
          }
        }
      }

      if (json.containsKey('result')) {
        final result = json['result'];
        if (result is Map<String, dynamic>) {
          final nestedName = getPestNameFromMap(result);
          if (nestedName != 'Unknown Pest') {
            return nestedName;
          }
        }
      }

      debugPrint('⚠️ No valid pest name found, using default');
      return 'Unknown Pest';
    }

    return PestDetection(
      id: json['id'] ?? 0,
      timestamp: json['timestamp']?.toString() ?? DateTime.now().toString(),
      imageBase64: json['image']?.toString() ?? json['imageBase64']?.toString() ?? '',
      motionDetected: json['motion_detected'] ?? json['motionDetected'] ?? false,
      confidence: _parseConfidence(json['confidence']),
      pestName: getPestName(),
    );
  }

  // Helper untuk parse confidence dengan lebih robust
  static int _parseConfidence(dynamic confidence) {
    if (confidence == null) return 0;
    
    if (confidence is int) return confidence;
    
    if (confidence is double) return confidence.round();
    
    if (confidence is String) {
      // Remove % if exists
      final cleanStr = confidence.replaceAll('%', '').trim();
      return int.tryParse(cleanStr) ?? 0;
    }
    
    return 0;
  }

  // Helper untuk mendapatkan pest name dari nested map
  static String getPestNameFromMap(Map<String, dynamic> map) {
    final keys = [
      'pestName', 'pest_name', 'name', 'pest', 'class', 
      'class_name', 'className', 'label', 'prediction'
    ];

    for (final key in keys) {
      if (map.containsKey(key)) {
        final value = map[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          final name = value.toString().trim();
          if (name.toLowerCase() != 'unknown' && 
              name.toLowerCase() != 'null' &&
              name != '0') {
            return name;
          }
        }
      }
    }

    return 'Unknown Pest';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp,
      'image': imageBase64,
      'motion_detected': motionDetected,
      'confidence': confidence,
      'pest_name': pestName,
      'pestName': pestName, // Tambahkan camelCase version
    };
  }

  // Helper untuk mendapatkan severity
  String getSeverityLabel() {
    if (confidence >= 90) return 'Tinggi';
    if (confidence >= 70) return 'Sedang';
    return 'Rendah';
  }

  // Helper untuk mendapatkan time ago
  String getTimeAgo() {
    try {
      final dt = DateTime.parse(timestamp);
      final diff = DateTime.now().difference(dt);

      if (diff.inSeconds < 60) return 'Baru saja';
      if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
      if (diff.inHours < 24) return '${diff.inHours} jam lalu';
      if (diff.inDays < 7) return '${diff.inDays} hari lalu';
      return dt.toString().split(' ')[0];
    } catch (e) {
      return timestamp;
    }
  }
}

class PestApiService {
  String _apiUrl;
  
  PestApiService({String? apiUrl}) 
      : _apiUrl = apiUrl ?? 'http://192.168.1.100:5000';

  String get apiUrl => _apiUrl;

  void updateApiUrl(String newUrl) {
    _apiUrl = newUrl;
  }

  // =========================================================================
  // API METHODS
  // =========================================================================

  /// Fetch history of pest detections
  Future<List<PestDetection>> fetchHistory({int limit = 50}) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/api/history?limit=$limit'),
      ).timeout(const Duration(seconds: 10));

      debugPrint('📥 History Response Status: ${response.statusCode}');
      debugPrint('📥 History Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final dynamic decodedData = json.decode(response.body);
        
        // Handle both array and object with array inside
        List<dynamic> data;
        if (decodedData is List) {
          data = decodedData;
        } else if (decodedData is Map && decodedData.containsKey('data')) {
          data = decodedData['data'] as List<dynamic>;
        } else if (decodedData is Map && decodedData.containsKey('detections')) {
          data = decodedData['detections'] as List<dynamic>;
        } else if (decodedData is Map && decodedData.containsKey('history')) {
          data = decodedData['history'] as List<dynamic>;
        } else {
          data = [];
        }

        final detections = data.map((item) {
          try {
            return PestDetection.fromJson(item as Map<String, dynamic>);
          } catch (e) {
            debugPrint('❌ Error parsing detection: $e');
            debugPrint('❌ Item data: $item');
            return null;
          }
        }).whereType<PestDetection>().toList();

        debugPrint('✅ Parsed ${detections.length} detections');
        return detections;
      } else {
        throw Exception('Failed to load history: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('Connection timeout');
    } catch (e) {
      debugPrint('❌ fetchHistory error: $e');
      throw Exception('Failed to load history: $e');
    }
  }

  /// Check for new detection
  Future<Map<String, dynamic>> checkNewDetection() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/data'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        debugPrint('🔄 Check Detection Response: ${data.toString()}');
        
        return {
          'success': true,
          'data': data,
        };
      } else {
        throw Exception('Failed to check detection: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('Connection timeout');
    } catch (e) {
      throw Exception('Failed to check detection: $e');
    }
  }

  /// Delete a detection by ID
  Future<bool> deleteDetection(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$_apiUrl/api/delete/$id'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      debugPrint('🗑️ Delete Response Status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Delete detection error: $e');
      return false;
    }
  }

  /// Test connection to API
  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/data'),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Test connection error: $e');
      return false;
    }
  }

  // =========================================================================
  // HELPER METHODS
  // =========================================================================

  /// Decode base64 image safely
  Uint8List? decodeImage(String base64String) {
    if (base64String.isEmpty) return null;
    
    try {
      // Remove data:image prefix if exists
      String cleanBase64 = base64String;
      if (base64String.contains(',')) {
        cleanBase64 = base64String.split(',').last;
      }
      
      return base64Decode(cleanBase64);
    } catch (e) {
      debugPrint('❌ Image decode error: $e');
      return null;
    }
  }

  /// Parse detection from raw JSON (for real-time updates)
  PestDetection? parseDetection(Map<String, dynamic> data) {
    try {
      debugPrint('🔄 Parsing detection: ${data.toString()}');
      return PestDetection.fromJson(data);
    } catch (e) {
      debugPrint('❌ Parse detection error: $e');
      return null;
    }
  }
}