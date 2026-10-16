import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Centralized HTTP client service with security-first defaults
/// Implements retry configuration guidelines and prevents server overload
class HttpClientService {
  // SECURITY: Circuit breaker state per endpoint
  static final Map<String, DateTime> _circuitBreakerState = {};
  static final Map<String, int> _failureCount = {};
  static const int _maxFailures = 3;
  static const Duration _circuitBreakerTimeout = Duration(minutes: 5);

  /// Make HTTP request with security controls
  /// SECURITY: Default maxRetries = 0 per security guidelines
  static Future<http.Response> makeRequest(
    Future<http.Response> Function() requestFunction, {
    int maxRetries = 0, // SECURITY: Safe default - no retries
    String endpoint = 'unknown',
    Duration timeout = const Duration(seconds: 30),
    bool respectCircuitBreaker = true,
  }) async {
    // SECURITY: Enforce maximum retry limit
    if (maxRetries > 2) {
      throw Exception('maxRetries cannot exceed 2 (max 3 total attempts). Got: $maxRetries');
    }

    // SECURITY: Check circuit breaker
    if (respectCircuitBreaker && _isCircuitBreakerOpen(endpoint)) {
      throw Exception('Circuit breaker open for $endpoint. Service temporarily unavailable.');
    }

    Exception? lastException;
    
    // Retry loop with security controls
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        print('[HTTP_CLIENT] Attempt ${attempt + 1}/${maxRetries + 1} for $endpoint');
        
        final response = await requestFunction().timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'Request timeout after ${timeout.inSeconds}s', timeout),
        );

        // Success - reset circuit breaker
        _resetCircuitBreaker(endpoint);
        
        // SECURITY: Never retry authentication or client errors
        if (response.statusCode == 401) {
          throw HttpException('Authentication failed', uri: Uri.parse(endpoint));
        } else if (response.statusCode == 403) {
          throw HttpException('Access forbidden', uri: Uri.parse(endpoint));
        } else if (response.statusCode == 429) {
          throw HttpException('Rate limited', uri: Uri.parse(endpoint));
        } else if (response.statusCode >= 400 && response.statusCode < 500) {
          throw HttpException('Client error: ${response.statusCode}', 
                            uri: Uri.parse(endpoint));
        }

        // Server errors - may retry if attempts remain
        if (response.statusCode >= 500 && attempt < maxRetries) {
          lastException = HttpException('Server error: ${response.statusCode}',
                                      uri: Uri.parse(endpoint));
          print('[HTTP_CLIENT] Server error ${response.statusCode}, will retry...');
          await _delayBeforeRetry(attempt);
          continue;
        }

        return response;
        
      } catch (e) {
        lastException = e is Exception ? e : Exception('Request failed: $e');
        print('[HTTP_CLIENT] Error on attempt ${attempt + 1}: $e');
        
        // Track failures for circuit breaker
        _recordFailure(endpoint);
        
        // Don't retry permanent errors
        if (e is HttpException && 
           (e.message.contains('Authentication') || 
            e.message.contains('forbidden') ||
            e.message.contains('Rate limited'))) {
          rethrow;
        }
        
        // Delay before retry (exponential backoff with jitter)
        if (attempt < maxRetries) {
          await _delayBeforeRetry(attempt);
        }
      }
    }
    
    // All attempts failed
    _openCircuitBreaker(endpoint);
    throw lastException ?? Exception('All retry attempts failed for $endpoint');
  }

  /// SECURITY: Exponential backoff with jitter to prevent thundering herd
  static Future<void> _delayBeforeRetry(int attempt) async {
    // Base delays: 1s, 2s, 4s with random jitter
    final baseDelayMs = [1000, 2000, 4000][attempt.clamp(0, 2)];
    final jitterMs = (baseDelayMs * 0.1 * (DateTime.now().millisecond % 100) / 100).round();
    final totalDelayMs = baseDelayMs + jitterMs;
    
    print('[HTTP_CLIENT] Waiting ${totalDelayMs}ms before retry (attempt $attempt)...');
    await Future.delayed(Duration(milliseconds: totalDelayMs));
  }

  /// Circuit breaker implementation
  static bool _isCircuitBreakerOpen(String endpoint) {
    final breakerTime = _circuitBreakerState[endpoint];
    if (breakerTime == null) return false;
    
    // Check if timeout has passed
    if (DateTime.now().isAfter(breakerTime.add(_circuitBreakerTimeout))) {
      _circuitBreakerState.remove(endpoint);
      _failureCount.remove(endpoint);
      return false;
    }
    
    return true;
  }

  static void _recordFailure(String endpoint) {
    _failureCount[endpoint] = (_failureCount[endpoint] ?? 0) + 1;
  }

  static void _openCircuitBreaker(String endpoint) {
    if ((_failureCount[endpoint] ?? 0) >= _maxFailures) {
      _circuitBreakerState[endpoint] = DateTime.now();
      print('[HTTP_CLIENT] Circuit breaker opened for $endpoint');
    }
  }

  static void _resetCircuitBreaker(String endpoint) {
    _failureCount.remove(endpoint);
    _circuitBreakerState.remove(endpoint);
  }

  /// Check if endpoint is healthy (circuit breaker closed)
  static bool isEndpointHealthy(String endpoint) {
    return !_isCircuitBreakerOpen(endpoint);
  }
}