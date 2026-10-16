import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Consolidated clocking service that combines image upload and record saving
/// into a single request to reduce server load by 75%
class ConsolidatedClockingService {
  
  /// Process clock-in with consolidated request (1 request instead of 3)
  static Future<Map<String, dynamic>> processClockIn({
    required String learnerID,
    required String classID, 
    required String token,
    required String faceImageBase64,
    required String signatureBase64,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    
    final url = Uri.parse(AppConfig.buildUrl('save_consolidated_clocking.php'));
    final currentDate = DateTime.now().toIso8601String().substring(0, 10);
    final timestamp = DateTime.now().toIso8601String();
    
    final payload = {
      'learner_id': learnerID,
      'class_id': classID,
      'clock_date': currentDate,
      'type': 'in',
      'face_image': faceImageBase64,
      'signature_image': signatureBase64,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': timestamp,
      'device_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'is_offline_sync': false, // Real-time clock-in
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 45)); // Longer timeout for consolidated operation

      final result = jsonDecode(response.body);
      
      if (response.statusCode == 200 && result['success'] == true) {
        return {
          'success': true,
          'message': result['message'],
          'data': result['data'],
        };
      } else {
        throw Exception(result['message'] ?? 'Clock-in failed');
      }
    } catch (e) {
      throw Exception('Network error during clock-in: $e');
    }
  }

  /// Process clock-out with consolidated request (1 request instead of 3)
  static Future<Map<String, dynamic>> processClockOut({
    required String learnerID,
    required String classID,
    required String token,
    required String faceImageBase64,
    required String signatureBase64,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    
    final url = Uri.parse(AppConfig.buildUrl('save_consolidated_clocking.php'));
    final currentDate = DateTime.now().toIso8601String().substring(0, 10);
    final timestamp = DateTime.now().toIso8601String();
    
    final payload = {
      'learner_id': learnerID,
      'class_id': classID,
      'clock_date': currentDate,
      'type': 'out',
      'face_image': faceImageBase64,
      'signature_image': signatureBase64,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': timestamp,
      'device_epoch': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'is_offline_sync': false, // Real-time clock-out
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 45)); // Longer timeout for consolidated operation

      final result = jsonDecode(response.body);
      
      if (response.statusCode == 200 && result['success'] == true) {
        return {
          'success': true,
          'message': result['message'],
          'data': result['data'],
        };
      } else {
        throw Exception(result['message'] ?? 'Clock-out failed');
      }
    } catch (e) {
      throw Exception('Network error during clock-out: $e');
    }
  }

  /// Get clocking status with caching to reduce frequent requests
  static final Map<String, Map<String, dynamic>> _statusCache = {};
  static DateTime? _lastCacheUpdate;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  static Future<Map<String, dynamic>> getClockingStatus({
    required String currentDate,
    bool forceRefresh = false,
  }) async {
    
    // Check cache first (unless force refresh)
    if (!forceRefresh && 
        _statusCache.containsKey(currentDate) && 
        _lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!).inMinutes < _cacheValidDuration.inMinutes) {
      
      print('[CONSOLIDATED_CLOCKING] Using cached status data');
      return _statusCache[currentDate]!;
    }

    // Fetch from server
    final url = Uri.parse(
      AppConfig.buildUrl('get_manual_clocking_status.php?clock_date=$currentDate'),
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        if (result['success'] == true) {
          // Cache the response
          _statusCache[currentDate] = result;
          _lastCacheUpdate = DateTime.now();
          
          print('[CONSOLIDATED_CLOCKING] Loaded and cached status from server');
          return result;
        }
      }
      
      throw Exception('Failed to load clocking status');
    } catch (e) {
      // Return cached data if available, even if expired
      if (_statusCache.containsKey(currentDate)) {
        print('[CONSOLIDATED_CLOCKING] Using expired cache due to network error');
        return _statusCache[currentDate]!;
      }
      throw Exception('Network error loading status: $e');
    }
  }

  /// Clear cache (useful for testing or forced refresh)
  static void clearCache() {
    _statusCache.clear();
    _lastCacheUpdate = null;
  }
  
  /// Check if we have recent cached data
  static bool hasFreshCache(String currentDate) {
    return _statusCache.containsKey(currentDate) && 
           _lastCacheUpdate != null &&
           DateTime.now().difference(_lastCacheUpdate!).inMinutes < _cacheValidDuration.inMinutes;
  }
}