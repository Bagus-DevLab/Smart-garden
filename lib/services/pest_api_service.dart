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
  final List<String> pestNames;

  PestDetection({
    required this.id,
    required this.timestamp,
    required this.imageBase64,
    required this.motionDetected,
    required this.confidence,
    required this.pestName,
    List<String>? pestNames,
  }) : pestNames = pestNames ?? [pestName];

  factory PestDetection.fromJson(Map<String, dynamic> json) {
    debugPrint('🔍 JSON Data: ${json.toString()}');
    
    List<String> parsePestNames() {
      if (json.containsKey('pestNames') && json['pestNames'] is List) {
        final names = (json['pestNames'] as List)
            .map((e) => e.toString())
            .where((name) => name.isNotEmpty && name.toLowerCase() != 'unknown')
            .toList();
        if (names.isNotEmpty) return names;
      }

      if (json.containsKey('pest_names') && json['pest_names'] is List) {
        final names = (json['pest_names'] as List)
            .map((e) => e.toString())
            .where((name) => name.isNotEmpty && name.toLowerCase() != 'unknown')
            .toList();
        if (names.isNotEmpty) return names;
      }

      if (json.containsKey('pestName') && json['pestName'] != null) {
        final pestName = json['pestName'].toString().trim();
        if (pestName.isNotEmpty && pestName.toLowerCase() != 'unknown') {
          if (pestName.contains(',')) {
            return pestName.split(',').map((e) => e.trim()).toList();
          }
          return [pestName];
        }
      }

      if (json.containsKey('pest_name') && json['pest_name'] != null) {
        final pestName = json['pest_name'].toString().trim();
        if (pestName.isNotEmpty && pestName.toLowerCase() != 'unknown') {
          return [pestName];
        }
      }

      if (json.containsKey('pest_details')) {
        try {
          final pestDetails = json['pest_details'];
          List<dynamic> details = [];
          
          if (pestDetails is String) {
            details = jsonDecode(pestDetails) as List;
          } else if (pestDetails is List) {
            details = pestDetails;
          }

          final names = details
              .map((detail) => detail['pest_name_id']?.toString() ?? '')
              .where((name) => name.isNotEmpty && name.toLowerCase() != 'unknown')
              .toSet()
              .toList();
          
          if (names.isNotEmpty) return names;
        } catch (e) {
          debugPrint('⚠️ Error parsing pest_details: $e');
        }
      }

      return ['Unknown Pest'];
    }

    final pestNames = parsePestNames();
    final pestName = pestNames.isNotEmpty ? pestNames.join(', ') : 'Unknown Pest';

    return PestDetection(
      id: json['id'] ?? 0,
      timestamp: json['timestamp']?.toString() ?? 
                 json['detection_time']?.toString() ?? 
                 DateTime.now().toString(),
      imageBase64: json['image']?.toString() ?? 
                   json['imageBase64']?.toString() ?? 
                   json['image_base64']?.toString() ?? '',
      motionDetected: json['motion_detected'] ?? 
                      json['motionDetected'] ?? 
                      json['motion'] ?? 
                      false,
      confidence: _parseConfidence(json['confidence'] ?? json['max_confidence']),
      pestName: pestName,
      pestNames: pestNames,
    );
  }

  static int _parseConfidence(dynamic confidence) {
    if (confidence == null) return 0;
    
    if (confidence is int) return confidence;
    
    if (confidence is double) {
      if (confidence <= 1.0) {
        return (confidence * 100).round();
      }
      return confidence.round();
    }
    
    if (confidence is String) {
      final cleanStr = confidence.replaceAll('%', '').trim();
      final parsed = double.tryParse(cleanStr) ?? 0;
      if (parsed <= 1.0) {
        return (parsed * 100).round();
      }
      return parsed.round();
    }
    
    return 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp,
      'image': imageBase64,
      'motion_detected': motionDetected,
      'confidence': confidence,
      'pest_name': pestName,
      'pestName': pestName,
      'pestNames': pestNames,
    };
  }

  String getSeverityLabel() {
    if (confidence >= 90) return 'Tinggi';
    if (confidence >= 70) return 'Sedang';
    return 'Rendah';
  }

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
      : _apiUrl = apiUrl ?? 'https://pestdetectionapi-production.up.railway.app';

  String get apiUrl => _apiUrl;

  void updateApiUrl(String newUrl) {
    _apiUrl = newUrl.endsWith('/') ? newUrl.substring(0, newUrl.length - 1) : newUrl;
    debugPrint('✅ API URL updated: $_apiUrl');
  }

  // =========================================================================
  // ✅ NEW: SYSTEM CONTROL (Camera Sleep/Wake + API Connection)
  // =========================================================================

  /// Set system active state (controls camera sleep mode + database status)
  /// - true: Wake camera + set system_active = true in database
  /// - false: Sleep camera + set system_active = false in database
  Future<Map<String, dynamic>> setSystemActive(bool active) async {
    try {
      final url = '$_apiUrl/api/system/control';
      debugPrint('🔌 Setting system ${active ? "ACTIVE (Camera Wake)" : "INACTIVE (Camera Sleep)"}');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'active': active,
        }),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('System control timeout');
        },
      );

      debugPrint('🔌 System Control Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        debugPrint('✅ System control success: $data');
        
        return {
          'success': true,
          'system_active': data['system_active'] ?? active,
          'mqtt_sent': data['mqtt_sent'] ?? false,
          'message': data['message'] ?? (active ? 'System activated' : 'System deactivated'),
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message': errorData['error'] ?? 'Failed to control system',
        };
      }
    } on TimeoutException {
      return {
        'success': false,
        'message': 'Connection timeout - API might be busy',
      };
    } catch (e) {
      debugPrint('❌ Set system active error: $e');
      return {
        'success': false,
        'message': 'Failed to control system: $e',
      };
    }
  }

  /// Get current system status (from database + ESP32)
  Future<Map<String, dynamic>> getSystemStatus() async {
    try {
      final url = '$_apiUrl/api/system/status';
      debugPrint('📊 Getting system status');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        debugPrint('📊 System Status: $data');
        
        return {
          'success': true,
          'system_active': data['system_active'] ?? false,
          'esp32_online': data['esp32_online'] ?? false,
          'esp32_system_enabled': data['esp32_system_enabled'] ?? false,
          'esp32_camera_sleep_mode': data['esp32_camera_sleep_mode'] ?? false,
          'mqtt_connected': data['mqtt_connected'] ?? false,
          'total_detections': data['total_detections'] ?? 0,
        };
      }
      
      return {'success': false, 'message': 'Failed to get status'};
    } catch (e) {
      debugPrint('❌ Get system status error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  // =========================================================================
  // API METHODS
  // =========================================================================

  /// Fetch history of pest detections
  Future<List<PestDetection>> fetchHistory({int limit = 50}) async {
    try {
      final url = '$_apiUrl/api/history?limit=$limit';
      debugPrint('📡 Fetching history from: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Request timeout - API might be processing detection');
        },
      );

      debugPrint('📥 History Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final dynamic decodedData = json.decode(response.body);
        debugPrint('📥 History Response Type: ${decodedData.runtimeType}');
        
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
            return null;
          }
        }).whereType<PestDetection>().toList();

        debugPrint('✅ Parsed ${detections.length} detections');
        return detections;
      } else if (response.statusCode == 503) {
        throw Exception('API is busy processing - please wait');
      } else {
        throw Exception('Failed to load history: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('Connection timeout - API might be busy with detection');
    } on http.ClientException catch (e) {
      throw Exception('Network error: $e');
    } catch (e) {
      debugPrint('❌ fetchHistory error: $e');
      throw Exception('Failed to load history: $e');
    }
  }

  /// Check for new detection - WITH RETRY LOGIC
  Future<Map<String, dynamic>> checkNewDetection({
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    int retryCount = 0;
    
    while (retryCount <= maxRetries) {
      try {
        final url = '$_apiUrl/data';
        debugPrint('📡 Checking detection (attempt ${retryCount + 1}/$maxRetries)');
        
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ).timeout(
          timeout,
          onTimeout: () {
            if (retryCount < maxRetries) {
              debugPrint('⏰ Timeout - will retry...');
            }
            throw TimeoutException('Request timeout');
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          
          return {
            'success': true,
            'data': data,
          };
        } else if (response.statusCode == 503) {
          if (retryCount < maxRetries) {
            debugPrint('⚠️ API busy (503) - retrying in 3s...');
            await Future.delayed(const Duration(seconds: 3));
            retryCount++;
            continue;
          }
          throw Exception('API is busy processing detection');
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } on TimeoutException {
        if (retryCount < maxRetries) {
          retryCount++;
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        throw Exception('Connection timeout after $maxRetries retries');
      } catch (e) {
        if (retryCount < maxRetries) {
          retryCount++;
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        throw Exception('Failed to check detection: $e');
      }
    }
    
    throw Exception('Max retries exceeded');
  }

  /// Delete a detection by ID
  Future<bool> deleteDetection(int id) async {
    try {
      final url = '$_apiUrl/api/delete/$id';
      debugPrint('🗑️ Deleting from: $url');
      
      final response = await http.delete(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('🗑️ Delete Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Delete detection error: $e');
      return false;
    }
  }

  /// Test connection to API - WITH BETTER ERROR HANDLING
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final url = '$_apiUrl/ping';
      debugPrint('🔍 Testing connection to: $url');
      
      final stopwatch = Stopwatch()..start();
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Connection timeout after 15 seconds');
        },
      );

      stopwatch.stop();
      final responseTime = stopwatch.elapsedMilliseconds;
      
      debugPrint('📡 Ping Response Status: ${response.statusCode} (${responseTime}ms)');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        debugPrint('✅ Connection successful: $data');
        
        return {
          'success': true,
          'message': 'Connected successfully (${responseTime}ms)',
          'responseTime': responseTime,
          'data': data,
        };
      } else if (response.statusCode == 503) {
        return {
          'success': false,
          'message': 'API is busy (initializing or processing)',
          'responseTime': responseTime,
        };
      } else {
        return {
          'success': false,
          'message': 'HTTP ${response.statusCode}',
          'responseTime': responseTime,
        };
      }
    } on TimeoutException catch (e) {
      return {
        'success': false,
        'message': 'Connection timeout - API might be starting up',
        'error': e.toString(),
      };
    } on http.ClientException catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.message}',
        'error': e.toString(),
      };
    } catch (e) {
      debugPrint('❌ Test connection error: $e');
      return {
        'success': false,
        'message': 'Connection failed',
        'error': e.toString(),
      };
    }
  }

  /// Get API statistics
  Future<Map<String, dynamic>?> getStats() async {
    try {
      final url = '$_apiUrl/api/stats';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Get stats error: $e');
      return null;
    }
  }

  /// Trigger manual capture (if ESP32 is connected)
  Future<bool> triggerCapture() async {
    try {
      final url = '$_apiUrl/api/trigger-capture';
      debugPrint('📸 Triggering capture: $url');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('📸 Trigger Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Trigger capture error: $e');
      return false;
    }
  }

  /// Check if API is ready (Roboflow loaded, MQTT connected)
  Future<bool> isApiReady() async {
    try {
      final result = await testConnection();
      
      if (!result['success']) return false;
      
      final data = result['data'] as Map<String, dynamic>?;
      if (data == null) return false;
      
      final roboflowReady = data['roboflow_ready'] == true;
      final mqttConnected = data['mqtt_connected'] == true;
      
      debugPrint('🔍 API Status: Roboflow=$roboflowReady, MQTT=$mqttConnected');
      
      return roboflowReady && mqttConnected;
    } catch (e) {
      return false;
    }
  }

  // =========================================================================
  // HELPER METHODS
  // =========================================================================

  Uint8List? decodeImage(String base64String) {
    if (base64String.isEmpty) return null;
    
    try {
      String cleanBase64 = base64String;
      if (base64String.contains(',')) {
        cleanBase64 = base64String.split(',').last;
      }
      
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');
      
      return base64Decode(cleanBase64);
    } catch (e) {
      debugPrint('❌ Image decode error: $e');
      return null;
    }
  }

  PestDetection? parseDetection(Map<String, dynamic> data) {
    try {
      return PestDetection.fromJson(data);
    } catch (e) {
      debugPrint('❌ Parse detection error: $e');
      return null;
    }
  }
}