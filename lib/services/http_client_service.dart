import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Centralized HTTP client service with built-in retry protection
///
/// This service provides a single source of truth for all HTTP requests
/// with conservative retry settings to prevent server overload.
class HttpClientService {
  static const int _maxRetries = 0; // SAFE DEFAULT: No retries to prevent loops
  static const int _timeoutSeconds = 30;
  static const int _rateLimitWindowMs = 1000; // 1 second window
  static const int _maxRequestsPerWindow =
      5; // Max 5 requests per second per endpoint

  // Rate limiting tracking
  static final Map<String, List<DateTime>> _requestHistory = {};
  static final Map<String, DateTime> _lastRequestTime = {};

  // Circuit breaker pattern tracking
  static final Map<String, CircuitBreakerState> _circuitBreakers = {};
  static const int _failureThreshold = 5; // Open circuit after 5 failures
  static const int _recoveryTimeoutSeconds = 60; // Try again after 1 minute
  static const int _halfOpenMaxAttempts = 3; // Max attempts in half-open state

  /// Make an authenticated HTTP request with built-in protection
  ///
  /// [requestFunction] - Function that returns the HTTP request
  /// [endpoint] - Endpoint identifier for rate limiting (optional)
  /// [maxRetries] - Maximum retry attempts (default: 0 for safety)
  /// [timeoutSeconds] - Request timeout (default: 30 seconds)
  static Future<http.Response> makeRequest(
    Future<http.Response> Function() requestFunction, {
    String? endpoint,
    int? maxRetries,
    int? timeoutSeconds,
  }) async {
    // Use safe defaults
    final retries = maxRetries ?? _maxRetries;
    final timeout = timeoutSeconds ?? _timeoutSeconds;
    endpoint = endpoint ?? 'unknown';

    // Circuit breaker check
    final circuitState = _getCircuitBreakerState(endpoint);
    if (circuitState == CircuitBreakerStatus.open) {
      throw HttpClientException(
        'Circuit breaker is OPEN for endpoint: $endpoint. '
        'Endpoint is temporarily disabled due to repeated failures.',
      );
    }

    // Rate limiting check
    if (_isRateLimited(endpoint)) {
      _recordFailure(endpoint, 'Rate limit exceeded');
      throw HttpClientException(
        'Rate limit exceeded for endpoint: $endpoint. '
        'Max $_maxRequestsPerWindow requests per ${_rateLimitWindowMs}ms allowed.',
      );
    }

    // Record request attempt
    _recordRequest(endpoint);

    int attempts = 0;
    http.Response? lastResponse;

    while (attempts <= retries) {
      try {
        // Apply timeout to the request
        final response =
            await requestFunction().timeout(Duration(seconds: timeout));

        // Check for HTTP error status codes
        if (response.statusCode >= 400) {
          throw HttpException(
              'HTTP ${response.statusCode}: ${response.reasonPhrase}');
        }

        // Record success and close circuit if it was half-open
        _recordSuccess(endpoint);

        // Log successful request
        if (kDebugMode) {
          print(
              'HttpClientService: Request to $endpoint succeeded on attempt ${attempts + 1}');
        }

        return response;
      } catch (e) {
        attempts++;
        lastResponse = null;

        // Record failure for circuit breaker
        _recordFailure(endpoint, e.toString());

        // Log attempt failure
        if (kDebugMode) {
          print(
              'HttpClientService: Request to $endpoint failed on attempt $attempts: $e');
        }

        // Don't retry if we've reached the limit or circuit is open
        if (attempts > retries ||
            _getCircuitBreakerState(endpoint) == CircuitBreakerStatus.open) {
          break;
        }

        // Brief delay between retries (exponential backoff)
        if (attempts <= retries) {
          final delayMs = 1000 * attempts; // 1s, 2s, 3s...
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    }

    // All attempts failed
    throw HttpClientException(
      'Request to $endpoint failed after ${attempts} attempts. '
      'Circuit breaker state: ${_getCircuitBreakerState(endpoint)}',
    );
  }

  /// Check if endpoint is rate limited
  static bool _isRateLimited(String endpoint) {
    final now = DateTime.now();
    final history = _requestHistory[endpoint] ?? [];

    // Clean old requests outside the window
    final windowStart =
        now.subtract(Duration(milliseconds: _rateLimitWindowMs));
    history.removeWhere((time) => time.isBefore(windowStart));
    _requestHistory[endpoint] = history;

    // Check if we're at the limit
    return history.length >= _maxRequestsPerWindow;
  }

  /// Record a request attempt for rate limiting
  static void _recordRequest(String endpoint) {
    final now = DateTime.now();
    _requestHistory[endpoint] = _requestHistory[endpoint] ?? [];
    _requestHistory[endpoint]!.add(now);
    _lastRequestTime[endpoint] = now;
  }

  /// Get request statistics for monitoring
  static Map<String, dynamic> getStats() {
    final stats = <String, dynamic>{};

    for (final endpoint in _requestHistory.keys) {
      final history = _requestHistory[endpoint]!;
      final lastRequest = _lastRequestTime[endpoint];

      stats[endpoint] = {
        'total_requests': history.length,
        'last_request': lastRequest?.toIso8601String(),
        'requests_in_window': history
            .where((time) => time.isAfter(DateTime.now()
                .subtract(Duration(milliseconds: _rateLimitWindowMs))))
            .length,
      };
    }

    return stats;
  }

  /// Reset rate limiting (for testing)
  static void resetRateLimit() {
    _requestHistory.clear();
    _lastRequestTime.clear();
  }

  /// Circuit breaker pattern - check if endpoint should be temporarily disabled
  static bool isEndpointHealthy(String endpoint) {
    final state = _getCircuitBreakerState(endpoint);
    return state != CircuitBreakerStatus.open;
  }

  /// Get circuit breaker state for endpoint
  static CircuitBreakerStatus _getCircuitBreakerState(String endpoint) {
    final circuitBreaker = _circuitBreakers[endpoint];
    if (circuitBreaker == null) {
      _circuitBreakers[endpoint] = CircuitBreakerState();
      return CircuitBreakerStatus.closed;
    }

    final now = DateTime.now();

    // Check if we should transition from open to half-open
    if (circuitBreaker.status == CircuitBreakerStatus.open &&
        circuitBreaker.lastFailure != null) {
      final timeSinceFailure = now.difference(circuitBreaker.lastFailure!);
      if (timeSinceFailure.inSeconds >= _recoveryTimeoutSeconds) {
        circuitBreaker.status = CircuitBreakerStatus.halfOpen;
        circuitBreaker.halfOpenAttempts = 0;
      }
    }

    return circuitBreaker.status;
  }

  /// Record a successful request
  static void _recordSuccess(String endpoint) {
    final circuitBreaker = _circuitBreakers[endpoint];
    if (circuitBreaker != null) {
      if (circuitBreaker.status == CircuitBreakerStatus.halfOpen) {
        // Success in half-open state - close the circuit
        circuitBreaker.status = CircuitBreakerStatus.closed;
        circuitBreaker.failures = 0;
        circuitBreaker.lastFailure = null;
      } else if (circuitBreaker.status == CircuitBreakerStatus.closed) {
        // Reset failure count on success
        circuitBreaker.failures = 0;
      }
    }
  }

  /// Record a failed request
  static void _recordFailure(String endpoint, String error) {
    final circuitBreaker = _circuitBreakers[endpoint] ?? CircuitBreakerState();
    _circuitBreakers[endpoint] = circuitBreaker;

    circuitBreaker.failures++;
    circuitBreaker.lastFailure = DateTime.now();

    if (circuitBreaker.status == CircuitBreakerStatus.halfOpen) {
      circuitBreaker.halfOpenAttempts++;
      // If we've exceeded half-open attempts, go back to open
      if (circuitBreaker.halfOpenAttempts >= _halfOpenMaxAttempts) {
        circuitBreaker.status = CircuitBreakerStatus.open;
      }
    } else if (circuitBreaker.failures >= _failureThreshold) {
      // Open the circuit after threshold failures
      circuitBreaker.status = CircuitBreakerStatus.open;
    }

    if (kDebugMode) {
      print('HttpClientService: Circuit breaker for $endpoint - '
          'Status: ${circuitBreaker.status}, Failures: ${circuitBreaker.failures}');
    }
  }
}

/// Circuit breaker states
enum CircuitBreakerStatus { closed, open, halfOpen }

/// Circuit breaker state tracking
class CircuitBreakerState {
  CircuitBreakerStatus status = CircuitBreakerStatus.closed;
  int failures = 0;
  DateTime? lastFailure;
  int halfOpenAttempts = 0;

  CircuitBreakerState();
}

/// Exception thrown by HttpClientService
class HttpClientException extends HttpException {
  HttpClientException(String message) : super(message);
}
