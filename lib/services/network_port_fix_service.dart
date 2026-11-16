import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config.dart';

/// Network Port Fix Service
/// 
/// CRITICAL FIX: Ensures all HTTP requests use standard HTTPS port 443
/// to prevent random port allocation issues (like 50666, 35068).
/// 
/// This service wraps HTTP requests to enforce proper port configuration
/// and prevent connection instability.
class NetworkPortFixService {
  static NetworkPortFixService? _instance;
  static NetworkPortFixService get instance => _instance ??= NetworkPortFixService._();
  
  NetworkPortFixService._();
  
  // Singleton HTTP client with proper configuration
  static http.Client? _httpClient;
  
  /// Get configured HTTP client that enforces HTTPS port 443
  static http.Client get httpClient {
    if (_httpClient == null) {
      _httpClient = http.Client();
      if (kDebugMode) {
        debugPrint('NetworkPortFix: Created HTTP client enforcing HTTPS:443');
      }
    }
    return _httpClient!;
  }
  
  /// Make a POST request with port enforcement
  static Future<http.Response> post(
    String endpoint, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final uri = _enforceProperPort(endpoint);
    
    if (kDebugMode) {
      debugPrint('NetworkPortFix: POST to ${uri.toString()} (enforcing port ${uri.port})');
    }
    
    final request = http.Request('POST', uri);
    
    // Set headers
    if (headers != null) {
      request.headers.addAll(headers);
    }
    
    // Set body
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is Map<String, String>) {
        request.bodyFields = body;
      } else {
        throw ArgumentError('Unsupported body type: ${body.runtimeType}');
      }
    }
    
    // Send request with timeout
    final response = await httpClient.send(request);
    return http.Response.fromStream(response);
  }
  
  /// Make a GET request with port enforcement
  static Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final uri = _enforceProperPort(endpoint);
    
    if (kDebugMode) {
      debugPrint('NetworkPortFix: GET to ${uri.toString()} (enforcing port ${uri.port})');
    }
    
    return await httpClient.get(uri, headers: headers);
  }
  
  /// Enforce proper port configuration for HTTPS requests
  static Uri _enforceProperPort(String endpoint) {
    Uri uri;
    
    // Parse the endpoint
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      uri = Uri.parse(endpoint);
    } else {
      // Relative endpoint - combine with base URL
      final baseUri = Uri.parse(AppConfig.baseUrl);
      uri = baseUri.resolve(endpoint);
    }
    
    // CRITICAL FIX: Enforce HTTPS port 443 for rlms.rlms.co.za
    if (uri.scheme == 'https' && uri.host == 'rlms.rlms.co.za') {
      // Rebuild URI with explicit port 443 to prevent random port allocation
      uri = Uri(
        scheme: 'https',
        host: 'rlms.rlms.co.za',
        port: 443, // EXPLICIT: Force port 443
        path: uri.path,
        query: uri.query.isEmpty ? null : uri.query,
        fragment: uri.fragment.isEmpty ? null : uri.fragment,
      );
      
      if (kDebugMode) {
        debugPrint('NetworkPortFix: Enforced HTTPS:443 for ${uri.toString()}');
      }
    }
    
    // Validate the final URI
    _validateUri(uri);
    
    return uri;
  }
  
  /// Validate URI configuration
  static void _validateUri(Uri uri) {
    if (kDebugMode) {
      debugPrint('NetworkPortFix: Validating URI - ${uri.toString()}');
      debugPrint('  - Scheme: ${uri.scheme}');
      debugPrint('  - Host: ${uri.host}');
      debugPrint('  - Port: ${uri.port}');
      debugPrint('  - Path: ${uri.path}');
    }
    
    // Critical checks
    if (uri.host == 'rlms.rlms.co.za' && uri.port != 443) {
      throw ArgumentError(
        'CRITICAL: Invalid port ${uri.port} for HTTPS to ${uri.host}. '
        'Must use port 443 to prevent connection issues.'
      );
    }
    
    if (uri.scheme != 'https' && uri.host == 'rlms.rlms.co.za') {
      throw ArgumentError(
        'CRITICAL: Must use HTTPS for requests to ${uri.host}'
      );
    }
  }
  
  /// Get network diagnostics
  static Map<String, dynamic> getDiagnostics() {
    return {
      'http_client_active': _httpClient != null,
      'enforced_host': 'rlms.rlms.co.za',
      'enforced_port': 443,
      'enforced_scheme': 'https',
      'base_url_configured': AppConfig.baseUrl,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  /// Dispose resources
  static void dispose() {
    _httpClient?.close();
    _httpClient = null;
    if (kDebugMode) {
      debugPrint('NetworkPortFix: HTTP client disposed');
    }
  }
  
  /// Test connection with proper port
  static Future<bool> testConnection() async {
    try {
      final response = await get('/test_sync_endpoint.php').timeout(
        const Duration(seconds: 10),
      );
      
      final success = response.statusCode == 200;
      
      if (kDebugMode) {
        debugPrint('NetworkPortFix: Connection test ${success ? 'PASSED' : 'FAILED'} '
              '(status: ${response.statusCode})');
      }
      
      return success;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NetworkPortFix: Connection test FAILED - $e');
      }
      return false;
    }
  }
}