# HTTP Retry Prevention Guide

## Table of Contents
- [Overview](#overview)
- [The Problem](#the-problem) 
- [Solution Architecture](#solution-architecture)
- [Implementation Guide](#implementation-guide)
- [Best Practices](#best-practices)
- [Monitoring & Alerting](#monitoring--alerting)
- [Troubleshooting](#troubleshooting)
- [Testing](#testing)

## Overview

This guide provides comprehensive strategies to prevent HTTP retry loops that can cause server overload. It covers the centralized HTTP client service, monitoring, and development best practices to maintain system stability.

## The Problem

### What Happened
In October 2024, the manual clocking system experienced server overload due to aggressive retry configurations:

- **Root Cause**: `maxRetries = 2` in `_makeAuthenticatedRequest()` function
- **Impact**: Each user action triggered up to 12 server requests (4 endpoints × 3 attempts each)
- **Symptoms**: Multiple POSTs per second from same IP, 401 authentication errors, 301 redirects
- **Result**: Server overload and service disruption

### Why Retries Matter
Retries are designed to handle:
- Network connectivity issues
- Temporary server errors (500, 503)
- Timeout conditions
- Poor mobile coverage

However, **aggressive retry settings amplify problems** instead of solving them.

## Solution Architecture

### 1. Centralized HTTP Client Service
**File**: `lib/services/http_client_service.dart`

**Key Features**:
- Safe retry defaults (`maxRetries = 0`)
- Built-in rate limiting (5 requests/second per endpoint)
- Circuit breaker pattern (opens after 5 failures)
- Request timeout protection (30 seconds)
- Comprehensive logging and monitoring

### 2. Request Monitoring Service  
**File**: `lib/services/request_monitoring_service.dart`

**Capabilities**:
- Real-time pattern detection
- Anomaly alerting (high volume, failure rates, retry loops)
- Statistical analysis and reporting
- Anti-spam alert protection

### 3. Code Review Guidelines
**File**: `.kiro/steering/retry_configuration_guidelines.md`

**Standards**:
- Mandatory use of centralized HTTP client
- Maximum retry limits and justification requirements
- Review checklist and red flags
- Testing requirements

## Implementation Guide

### Step 1: Replace Direct HTTP Calls

**Before (Dangerous)**:
```dart
// ❌ Direct HTTP call with custom retries
Future<http.Response> _makeAuthenticatedRequest(...) async {
  int maxRetries = 2; // 3 total attempts per request!
  // Custom retry logic...
}
```

**After (Safe)**:
```dart
// ✅ Use centralized service
Future<http.Response> _makeRequest(...) async {
  return await HttpClientService.makeRequest(
    () => http.post(url, headers: headers, body: body),
    endpoint: 'save_manual_clockin', // Required for monitoring
    // maxRetries defaults to 0 (safe)
  );
}
```

### Step 2: Update Function Signatures

Replace all instances of the old function:
```bash
# Find usage of old retry functions
grep -r "_makeAuthenticatedRequest" lib/
grep -r "maxRetries.*[1-9]" lib/
```

### Step 3: Initialize Monitoring
```dart
// In main.dart or app initialization
void main() {
  // Start request monitoring
  RequestMonitoringService.startMonitoring();
  
  runApp(MyApp());
}
```

### Step 4: Add Error Handling
```dart
try {
  final response = await HttpClientService.makeRequest(
    () => http.post(url, headers: headers, body: body),
    endpoint: 'save_manual_clockin',
  );
  
  // Handle successful response
  if (response.statusCode == 200) {
    // Process success
  }
} on HttpClientException catch (e) {
  // Handle client-side issues (rate limiting, circuit breaker)
  print('Client error: ${e.message}');
  // Show user-friendly message
} catch (e) {
  // Handle other errors
  print('Request failed: $e');
  // Fallback behavior
}
```

## Best Practices

### 1. Safe Retry Configuration

**✅ Recommended Settings**:
```dart
// No retries (safest)
maxRetries: 0  // 1 total attempt

// Minimal retries (for critical operations)
maxRetries: 1  // 2 total attempts
```

**⚠️ Requires Justification**:
```dart
// Document why retries are needed
maxRetries: 2  // 3 total attempts - MAX ALLOWED
```

**❌ Never Allowed**:
```dart
maxRetries: 3  // 4+ attempts - causes server overload
```

### 2. Endpoint Identification

Always specify endpoint names for monitoring:
```dart
// ✅ Good - enables monitoring and rate limiting
await HttpClientService.makeRequest(
  () => http.post(...),
  endpoint: 'save_manual_clockin', // Clear, descriptive name
);

// ❌ Bad - anonymous requests can't be monitored
await HttpClientService.makeRequest(() => http.post(...));
```

### 3. Multiple Endpoint Patterns

**❌ Dangerous - Exponential Growth**:
```dart
// 4 endpoints × 3 attempts = 12 server requests per user action!
for (String endpoint in ['clockin', 'image', 'geofence', 'signature']) {
  await makeRequest(endpoint, maxRetries: 2);
}
```

**✅ Safe - Linear Growth**:
```dart
// 4 endpoints × 1 attempt = 4 server requests per user action
for (String endpoint in endpoints) {
  await HttpClientService.makeRequest(
    () => http.post(endpoint, ...),
    endpoint: endpoint.split('/').last,
  );
}
```

### 4. Error Recovery Strategies

Instead of retries, use these patterns:

**Queue and Retry Later**:
```dart
// Store failed requests for background retry
await OfflineRequestQueue.add(requestData);
```

**Graceful Degradation**:
```dart
try {
  await HttpClientService.makeRequest(...);
} catch (e) {
  // Continue with offline mode
  await saveLocally(data);
  showOfflineMessage();
}
```

**User Feedback**:
```dart
try {
  await HttpClientService.makeRequest(...);
  showSuccessMessage();
} catch (e) {
  showRetryButton(); // Let user decide to retry
}
```

## Monitoring & Alerting

### Key Metrics to Track

1. **Request Volume**: > 30 requests/minute per endpoint
2. **Failure Rate**: > 30% over 5-minute window  
3. **Average Attempts**: > 2.0 per request (indicates retry loops)
4. **Circuit Breaker State**: Open circuits indicate failing services

### Monitoring Dashboard

```dart
// Get monitoring statistics
final stats = RequestMonitoringService.getStats();
print('Current monitoring stats:');
for (final endpoint in stats['endpoints'].keys) {
  final endpointStats = stats['endpoints'][endpoint];
  print('$endpoint:');
  print('  Requests/min: ${endpointStats['requests_per_minute']}');
  print('  Success rate: ${(endpointStats['success_rate'] * 100).toStringAsFixed(1)}%');
  print('  Avg attempts: ${endpointStats['avg_attempts'].toStringAsFixed(1)}');
}
```

### Alert Configuration

Alerts are automatically generated for:
- High request volume (>30/min)
- High failure rates (>30%)
- Retry loop detection (>2 avg attempts)
- Circuit breaker activation

## Troubleshooting

### Common Issues

**1. Rate Limit Exceeded**
```
Error: Rate limit exceeded for endpoint: save_manual_clockin
```

**Solutions**:
- Reduce request frequency in your code
- Check for duplicate calls
- Verify endpoint identification is correct

**2. Circuit Breaker Open**
```
Error: Circuit breaker is OPEN for endpoint: upload_image
```

**Solutions**:
- Check server status and connectivity
- Wait for recovery timeout (60 seconds)
- Investigate underlying service issues

**3. High Failure Rate Alerts**
```
Alert: High failure rate: 45.2% (10/22) for endpoint: verify_geofence
```

**Solutions**:
- Check server logs for errors
- Verify request format and authentication
- Review recent code changes

### Debugging Commands

```bash
# Find retry configurations in code
grep -r "maxRetries.*[1-9]" lib/ --include="*.dart"

# Find direct HTTP calls (should use HttpClientService)
grep -r "http\.\(get\|post\|put\|delete\)" lib/ --include="*.dart"

# Check for custom retry logic
grep -r "while.*retry\|for.*retry" lib/ --include="*.dart"
```

### Performance Analysis

Use monitoring stats to identify problems:
```dart
void analyzeEndpointPerformance(String endpoint) {
  final stats = HttpClientService.getStats();
  if (stats.containsKey(endpoint)) {
    final endpointStats = stats[endpoint];
    print('$endpoint analysis:');
    print('Total requests: ${endpointStats['total_requests']}');
    print('Requests in current window: ${endpointStats['requests_in_window']}');
    
    // Check if circuit breaker is healthy
    final isHealthy = HttpClientService.isEndpointHealthy(endpoint);
    print('Circuit breaker healthy: $isHealthy');
  }
}
```

## Testing

### Automated Testing

**File**: `test/services/http_client_service_test.dart`

Run tests to verify retry behavior:
```bash
flutter test test/services/http_client_service_test.dart
```

**Key Test Cases**:
- Retry limits are respected (0, 1, 2 max retries)
- Rate limiting prevents excessive requests
- Circuit breaker opens after failures
- Timeouts work correctly
- Multiple endpoints don't cause exponential growth

### Load Testing

Before deploying retry configurations:

1. **Simulate User Load**: Test expected number of concurrent users
2. **Failure Scenarios**: Test behavior when server returns errors
3. **Network Issues**: Test with poor connectivity simulation
4. **Resource Monitoring**: Monitor server CPU, memory, and response times

### Manual Testing Checklist

- [ ] Single request succeeds without retries
- [ ] Failed requests don't retry excessively  
- [ ] Rate limiting blocks excessive requests
- [ ] Circuit breaker opens after repeated failures
- [ ] Monitoring alerts trigger correctly
- [ ] User experience remains smooth during network issues

## Migration Checklist

For existing projects, follow this migration plan:

### Phase 1: Assessment
- [ ] Identify all HTTP request locations
- [ ] Document current retry configurations  
- [ ] Assess server capacity and current load

### Phase 2: Implementation  
- [ ] Add HttpClientService to project
- [ ] Add RequestMonitoringService
- [ ] Update steering guidelines
- [ ] Create automated tests

### Phase 3: Migration
- [ ] Replace direct HTTP calls with HttpClientService
- [ ] Update retry configurations to safe defaults
- [ ] Add endpoint identification to all requests
- [ ] Initialize monitoring service

### Phase 4: Validation
- [ ] Run automated test suite
- [ ] Perform load testing
- [ ] Monitor production metrics
- [ ] Validate alert thresholds

## Related Resources

- [HttpClientService API Documentation](lib/services/http_client_service.dart)
- [Request Monitoring Service](lib/services/request_monitoring_service.dart)  
- [Code Review Guidelines](.kiro/steering/retry_configuration_guidelines.md)
- [Test Suite](test/services/http_client_service_test.dart)

## Support

For questions about retry prevention:
1. Review this guide and related documentation
2. Check monitoring dashboards for current system health
3. Escalate to architecture team for complex scenarios
4. Report issues with detailed monitoring statistics

---

**Remember**: The goal is system stability, not perfect retry behavior. It's better to have a single failed request than a server overload affecting all users.