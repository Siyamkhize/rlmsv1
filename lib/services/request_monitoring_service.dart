import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'http_client_service.dart';

/// Service for monitoring HTTP request patterns and detecting potential issues
class RequestMonitoringService {
  static const int _monitoringWindowMinutes = 5;
  static const int _alertThresholdRequestsPerMinute = 30;
  static const double _alertThresholdFailureRate = 0.3; // 30% failure rate
  
  static Timer? _monitoringTimer;
  static final List<RequestEvent> _eventHistory = [];
  static final Map<String, AlertState> _alertStates = {};
  
  /// Start monitoring request patterns
  static void startMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkForAnomalies(),
    );
    
    if (kDebugMode) {
      print('RequestMonitoringService: Started monitoring');
    }
  }
  
  /// Stop monitoring
  static void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    
    if (kDebugMode) {
      print('RequestMonitoringService: Stopped monitoring');
    }
  }
  
  /// Record a request event
  static void recordRequest({
    required String endpoint,
    required bool success,
    required int attempts,
    String? error,
  }) {
    final event = RequestEvent(
      timestamp: DateTime.now(),
      endpoint: endpoint,
      success: success,
      attempts: attempts,
      error: error,
    );
    
    _eventHistory.add(event);
    
    // Keep only events within monitoring window
    final cutoff = DateTime.now().subtract(
      Duration(minutes: _monitoringWindowMinutes),
    );
    _eventHistory.removeWhere((event) => event.timestamp.isBefore(cutoff));
  }
  
  /// Check for request pattern anomalies
  static void _checkForAnomalies() {
    final now = DateTime.now();
    final windowStart = now.subtract(Duration(minutes: _monitoringWindowMinutes));
    
    // Get events in monitoring window
    final windowEvents = _eventHistory
        .where((event) => event.timestamp.isAfter(windowStart))
        .toList();
    
    // Group events by endpoint
    final endpointGroups = <String, List<RequestEvent>>{};
    for (final event in windowEvents) {
      endpointGroups[event.endpoint] = endpointGroups[event.endpoint] ?? [];
      endpointGroups[event.endpoint]!.add(event);
    }
    
    // Check each endpoint for issues
    for (final endpoint in endpointGroups.keys) {
      final events = endpointGroups[endpoint]!;
      _checkEndpointHealth(endpoint, events);
    }
  }
  
  /// Check health of a specific endpoint
  static void _checkEndpointHealth(String endpoint, List<RequestEvent> events) {
    if (events.isEmpty) return;
    
    final alertState = _alertStates[endpoint] ?? AlertState();
    _alertStates[endpoint] = alertState;
    
    // Calculate metrics
    final requestsPerMinute = events.length / _monitoringWindowMinutes;
    final failures = events.where((e) => !e.success).length;
    final failureRate = failures / events.length;
    final totalAttempts = events.fold(0, (sum, e) => sum + e.attempts);
    final avgAttempts = totalAttempts / events.length;
    
    // Check for high request volume
    if (requestsPerMinute > _alertThresholdRequestsPerMinute) {
      _triggerAlert(
        endpoint,
        AlertType.highVolume,
        'High request volume: ${requestsPerMinute.toStringAsFixed(1)} requests/min',
      );
    }
    
    // Check for high failure rate
    if (failureRate > _alertThresholdFailureRate && events.length >= 5) {
      _triggerAlert(
        endpoint,
        AlertType.highFailureRate,
        'High failure rate: ${(failureRate * 100).toStringAsFixed(1)}% (${failures}/${events.length})',
      );
    }
    
    // Check for retry loops (high average attempts)
    if (avgAttempts > 2.0 && events.length >= 3) {
      _triggerAlert(
        endpoint,
        AlertType.retryLoop,
        'Potential retry loop detected: ${avgAttempts.toStringAsFixed(1)} avg attempts per request',
      );
    }
    
    // Log metrics in debug mode
    if (kDebugMode && events.isNotEmpty) {
      print('RequestMonitoring [$endpoint]: '
            'Requests/min: ${requestsPerMinute.toStringAsFixed(1)}, '
            'Failure rate: ${(failureRate * 100).toStringAsFixed(1)}%, '
            'Avg attempts: ${avgAttempts.toStringAsFixed(1)}');
    }
  }
  
  /// Trigger an alert for an endpoint
  static void _triggerAlert(String endpoint, AlertType type, String message) {
    final alertState = _alertStates[endpoint]!;
    final now = DateTime.now();
    
    // Prevent alert spam (max 1 alert per type per 5 minutes)
    if (alertState.lastAlert[type] != null) {
      final timeSinceAlert = now.difference(alertState.lastAlert[type]!);
      if (timeSinceAlert.inMinutes < 5) {
        return; // Too soon to alert again
      }
    }
    
    alertState.lastAlert[type] = now;
    
    // Log the alert
    if (kDebugMode) {
      print('🚨 ALERT [$endpoint] ${type.toString().split('.').last}: $message');
    }
    
    // In production, you might want to send this to a monitoring service
    // or display a notification to the user
  }
  
  /// Get monitoring statistics
  static Map<String, dynamic> getStats() {
    final now = DateTime.now();
    final windowStart = now.subtract(Duration(minutes: _monitoringWindowMinutes));
    
    final windowEvents = _eventHistory
        .where((event) => event.timestamp.isAfter(windowStart))
        .toList();
    
    final endpointStats = <String, Map<String, dynamic>>{};
    
    // Group by endpoint
    final endpointGroups = <String, List<RequestEvent>>{};
    for (final event in windowEvents) {
      endpointGroups[event.endpoint] = endpointGroups[event.endpoint] ?? [];
      endpointGroups[event.endpoint]!.add(event);
    }
    
    // Calculate stats for each endpoint
    for (final endpoint in endpointGroups.keys) {
      final events = endpointGroups[endpoint]!;
      final failures = events.where((e) => !e.success).length;
      final totalAttempts = events.fold(0, (sum, e) => sum + e.attempts);
      
      endpointStats[endpoint] = {
        'total_requests': events.length,
        'failures': failures,
        'success_rate': events.isEmpty ? 0.0 : (events.length - failures) / events.length,
        'requests_per_minute': events.length / _monitoringWindowMinutes,
        'avg_attempts': events.isEmpty ? 0.0 : totalAttempts / events.length,
        'circuit_breaker_healthy': HttpClientService.isEndpointHealthy(endpoint),
      };
    }
    
    return {
      'monitoring_window_minutes': _monitoringWindowMinutes,
      'total_events_in_window': windowEvents.length,
      'endpoints': endpointStats,
    };
  }
  
  /// Clear monitoring data (for testing)
  static void clearData() {
    _eventHistory.clear();
    _alertStates.clear();
  }
}

/// Types of alerts that can be triggered
enum AlertType {
  highVolume,
  highFailureRate,
  retryLoop,
}

/// State tracking for alerts per endpoint
class AlertState {
  final Map<AlertType, DateTime> lastAlert = {};
}

/// Represents a single HTTP request event
class RequestEvent {
  final DateTime timestamp;
  final String endpoint;
  final bool success;
  final int attempts;
  final String? error;
  
  RequestEvent({
    required this.timestamp,
    required this.endpoint,
    required this.success,
    required this.attempts,
    this.error,
  });
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'endpoint': endpoint,
    'success': success,
    'attempts': attempts,
    if (error != null) 'error': error,
  };
}