---
inclusion: auto
name: "Retry Configuration Guidelines"
description: "Standards and best practices for HTTP retry configurations to prevent server overload"
---

# HTTP Retry Configuration Guidelines

## Overview
These guidelines prevent retry loop issues that can cause server overload and service disruption. All HTTP requests must follow these standards to maintain system stability.

## Mandatory Standards

### 1. Use Centralized HTTP Client
**REQUIRED**: All HTTP requests MUST use `HttpClientService.makeRequest()` instead of direct `http` calls.

```dart
// ✅ CORRECT - Use centralized service
final response = await HttpClientService.makeRequest(
  () => http.post(url, headers: headers, body: body),
  endpoint: 'save_manual_clockin',
);

// ❌ WRONG - Direct http calls bypass protection
final response = await http.post(url, headers: headers, body: body);
```

### 2. Safe Retry Defaults
**DEFAULT**: `maxRetries = 0` (no retries) unless explicitly justified.

```dart
// ✅ CORRECT - Safe default (no retries)
await HttpClientService.makeRequest(() => http.post(...));

// ⚠️ REQUIRES JUSTIFICATION - Any retry count > 0
await HttpClientService.makeRequest(
  () => http.post(...),
  maxRetries: 1, // Must document why retries are needed
);
```

### 3. Maximum Retry Limits
- **ABSOLUTE MAX**: `maxRetries = 2` (3 total attempts)
- **RECOMMENDED**: `maxRetries = 0` or `maxRetries = 1`
- **NEVER**: `maxRetries > 2` without architecture team approval

### 4. Endpoint Identification
**REQUIRED**: Always specify endpoint name for monitoring and rate limiting.

```dart
// ✅ CORRECT - Endpoint identified
await HttpClientService.makeRequest(
  () => http.post(...),
  endpoint: 'save_manual_clockin', // Required for tracking
);

// ❌ WRONG - Missing endpoint identification
await HttpClientService.makeRequest(() => http.post(...));
```

## Code Review Checklist

### HTTP Request Reviews
When reviewing code with HTTP requests, verify:

- [ ] Uses `HttpClientService.makeRequest()` instead of direct http calls
- [ ] Specifies endpoint name for all requests
- [ ] Uses safe retry defaults (`maxRetries = 0` or `maxRetries = 1`)
- [ ] Documents justification for any `maxRetries > 1`
- [ ] No custom retry loops outside the service
- [ ] Proper error handling without additional retry logic

### Retry Configuration Reviews
For any retry configuration changes:

- [ ] Retry count ≤ 2 (max 3 total attempts)
- [ ] Clear business justification documented
- [ ] Impact assessment: endpoints × retry count × user count
- [ ] Server capacity validation completed
- [ ] Monitoring alerts configured for the endpoint

### Red Flags - Reject Immediately
- `maxRetries > 2` without architecture approval
- Custom retry loops using `while`, `for`, or recursive calls
- Multiple HTTP clients or services (consolidation required)
- Missing endpoint identification
- Aggressive timeout values (< 10 seconds without justification)

## Example Review Comments

### Approve with Safe Configuration
```
✅ APPROVED: Uses HttpClientService with safe defaults (maxRetries = 0).
Good endpoint identification for monitoring.
```

### Request Changes for Unsafe Configuration
```
❌ CHANGES REQUESTED: 
- maxRetries = 3 exceeds safe limit (max 2)
- Missing endpoint identification for rate limiting
- Please document business justification for retries
Please update to use maxRetries ≤ 1 or provide architecture approval.
```

### Reject Dangerous Patterns
```
🚫 REJECTED: Custom retry loop detected. This pattern caused server 
overload in issue #[reference]. Must use HttpClientService.makeRequest() 
with centralized retry protection.
```

## Monitoring Integration

### Required Monitoring
All endpoints using retries must have:
- Request volume monitoring
- Failure rate tracking
- Circuit breaker status monitoring
- Server capacity alerts

### Alert Thresholds
- Request volume: > 30 requests/minute per endpoint
- Failure rate: > 30% over 5-minute window
- Retry loops: Average attempts > 2.0 per request

## Testing Requirements

### Pre-deployment Testing
Before deploying retry configurations:

1. **Load Testing**: Simulate expected user load with retry scenarios
2. **Failure Testing**: Test behavior under server errors (500, timeout)
3. **Network Testing**: Verify behavior with poor connectivity
4. **Circuit Breaker Testing**: Confirm protection activates correctly

### Required Test Cases
```dart
// Test safe retry limits
testRetryLimits() async {
  // Verify maxRetries = 0 makes only 1 attempt
  // Verify maxRetries = 1 makes only 2 attempts
  // Verify maxRetries = 2 makes only 3 attempts
}

// Test rate limiting
testRateLimiting() async {
  // Verify rate limiting prevents excessive requests
  // Verify circuit breaker opens after failures
}
```

## Common Pitfalls to Avoid

### 1. Exponential Request Growth
```dart
// ❌ DANGEROUS: 4 endpoints × 3 attempts = 12 server requests
for (endpoint in ['clock_in', 'upload_image', 'verify_geofence', 'save_signature']) {
  await makeRequestWithRetries(endpoint, maxRetries: 2); // 3 attempts each
}

// ✅ SAFE: 4 endpoints × 1 attempt = 4 server requests  
for (endpoint in endpoints) {
  await HttpClientService.makeRequest(() => http.post(endpoint));
}
```

### 2. Nested Retry Logic
```dart
// ❌ DANGEROUS: Nested retries multiply attempts
Future<void> saveWithRetry() async {
  for (int i = 0; i < 3; i++) { // Outer retry
    try {
      await HttpClientService.makeRequest(
        () => http.post(...),
        maxRetries: 2, // Inner retry: 3 × 3 = 9 attempts!
      );
      break;
    } catch (e) {
      // Nested retry logic
    }
  }
}
```

### 3. Ignoring Circuit Breaker
```dart
// ❌ WRONG: Bypassing circuit breaker protection
if (!HttpClientService.isEndpointHealthy(endpoint)) {
  // Still making request anyway - defeats the purpose!
  await http.post(...); 
}
```

## Architecture Escalation

Escalate to architecture team when:
- Need `maxRetries > 2`
- Custom retry patterns required
- Circuit breaker modifications needed
- New HTTP client implementation
- Performance issues with current service

## Related Documentation
- [HTTP Client Service API](#file:lib/services/http_client_service.dart)
- [Request Monitoring Service](#file:lib/services/request_monitoring_service.dart)
- [Server Overload Incident Report](https://docs.internal/incidents/retry-loop-2024)