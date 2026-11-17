import 'dart:async';
import 'package:flutter/foundation.dart';

/// Service to prevent duplicate requests that can cause server overload
class RequestDeduplicationService {
  static final Map<String, DateTime> _lastRequestTimes = {};
  static final Map<String, Completer<dynamic>> _pendingRequests = {};

  /// Minimum time between requests for the same learner action
  static const Duration _cooldownPeriod = Duration(seconds: 30);

  /// Check if request is allowed or should be blocked
  static bool canMakeRequest(String learnerID, String action) {
    final key = '${learnerID}_$action';
    final lastRequest = _lastRequestTimes[key];

    if (lastRequest != null) {
      final timeSinceLastRequest = DateTime.now().difference(lastRequest);
      if (timeSinceLastRequest.inSeconds < _cooldownPeriod.inSeconds) {
        debugPrint('[DEDUPLICATION] Blocking duplicate request for $key '
            '(last request ${timeSinceLastRequest.inSeconds}s ago)');
        return false;
      }
    }

    return true;
  }

  /// Register that a request was made
  static void recordRequest(String learnerID, String action) {
    final key = '${learnerID}_$action';
    _lastRequestTimes[key] = DateTime.now();
    debugPrint('[DEDUPLICATION] Recorded request for $key');
  }

  /// Deduplicate identical concurrent requests
  /// Returns existing request Future if same request is already pending
  static Future<T> deduplicateRequest<T>(
    String learnerID,
    String action,
    Future<T> Function() requestFunction,
  ) async {
    final key = '${learnerID}_$action';

    // Check if same request is already pending
    if (_pendingRequests.containsKey(key)) {
      debugPrint(
          '[DEDUPLICATION] Request already pending for $key, waiting for result');
      return await _pendingRequests[key]!.future as T;
    }

    // Check cooldown period
    if (!canMakeRequest(learnerID, action)) {
      throw Exception('Request blocked: Too soon after previous request. '
          'Please wait ${_cooldownPeriod.inSeconds} seconds between requests.');
    }

    // Create new request
    final completer = Completer<T>();
    _pendingRequests[key] = completer;

    try {
      debugPrint('[DEDUPLICATION] Starting new request for $key');
      recordRequest(learnerID, action);

      final result = await requestFunction();
      completer.complete(result);
      return result;
    } catch (error) {
      completer.completeError(error);
      rethrow;
    } finally {
      // Clean up pending request
      _pendingRequests.remove(key);
      debugPrint('[DEDUPLICATION] Completed request for $key');
    }
  }

  /// Get time remaining in cooldown period
  static Duration? getRemainingCooldown(String learnerID, String action) {
    final key = '${learnerID}_$action';
    final lastRequest = _lastRequestTimes[key];

    if (lastRequest != null) {
      final timeSinceLastRequest = DateTime.now().difference(lastRequest);
      if (timeSinceLastRequest.inSeconds < _cooldownPeriod.inSeconds) {
        return _cooldownPeriod - timeSinceLastRequest;
      }
    }

    return null;
  }

  /// Check if request is currently pending
  static bool isRequestPending(String learnerID, String action) {
    final key = '${learnerID}_$action';
    return _pendingRequests.containsKey(key);
  }

  /// Clear all tracking data (useful for testing)
  static void clear() {
    _lastRequestTimes.clear();
    _pendingRequests.clear();
  }

  /// Get statistics for monitoring
  static Map<String, dynamic> getStats() {
    final now = DateTime.now();
    final activeCooldowns = <String, int>{};

    for (final entry in _lastRequestTimes.entries) {
      final timeSince = now.difference(entry.value);
      if (timeSince.inSeconds < _cooldownPeriod.inSeconds) {
        activeCooldowns[entry.key] =
            _cooldownPeriod.inSeconds - timeSince.inSeconds;
      }
    }

    return {
      'total_tracked_requests': _lastRequestTimes.length,
      'pending_requests': _pendingRequests.length,
      'active_cooldowns': activeCooldowns,
      'cooldown_period_seconds': _cooldownPeriod.inSeconds,
    };
  }
}
