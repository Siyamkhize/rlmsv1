# Network Timeout and Connection Issues - Implementation Plan

## Problem Analysis

**Critical Issues Identified:**
1. **10-second timeout on learner profile sync** - Hard-coded in `database_helper.dart:line 836` causing `TimeoutException after 0:00:10.000000`
2. **Materials sync using port 50666** - The error shows connection attempts to port 50666 instead of 443, suggesting either:
   - Server-side redirect/proxy misconfiguration 
   - DNS resolution issue pointing to wrong server/port
   - Load balancer configuration issue
3. **Direct HTTP calls bypass centralized HttpClientService** - Multiple files make direct `http.post()` calls violating project retry guidelines
4. **Inconsistent timeout values** - Different files use different timeout durations (5s, 8s, 10s, 15s, 30s)

## Root Cause Analysis

### Learner Profile Timeout (10s)
- **File:** `lib/database_helper.dart`
- **Line:** 836 - `.timeout(const Duration(seconds: 10))`
- **Issue:** 10 seconds is too short for profile sync operations which include multiple database updates
- **Current retry:** No retry mechanism - fails immediately on first timeout

### Materials Sync Port Issue (50666)
- **File:** `lib/sync_service.dart` - `syncMaterialsReceivedData()` method
- **Config URL:** `AppConfig.saveMaterialsReceivedUrl` → `https://rlms.rlms.co.za/mobile/save_materials_received.php`
- **Expected port:** 443 (HTTPS)
- **Actual connection:** Port 50666 (from error log)
- **Root cause:** Server-side redirect or proxy configuration issue - NOT a client-side code problem

### Direct HTTP Violations
- **Files with violations:** 47 files found using direct `http.(get|post)()` calls
- **Required pattern:** Must use `HttpClientService.makeRequest()` 
- **Missing:** Centralized timeout, retry, and rate limiting policies

### Timeout Inconsistencies
- `Duration(seconds: 5)` - admin.dart (multiple places)  
- `Duration(seconds: 8)` - sync_service.dart 
- `Duration(seconds: 10)` - database_helper.dart (CRITICAL)
- `Duration(seconds: 15)` - persistent_sync_service.dart
- `Duration(seconds: 30)` - Various file upload operations

## Implementation Plan

### 1. Create Centralized Timeout Configuration

**File:** `lib/config/network_config.dart` (NEW FILE)
**Purpose:** Define safe timeout values and retry policies per operation type
**Content:**
```dart
class NetworkConfig {
  // Timeout values (in seconds)
  static const int profileSyncTimeout = 30;     // Learner profile operations
  static const int fileUploadTimeout = 60;      // Image/document uploads  
  static const int lightweightTimeout = 20;     // Simple GET requests
  static const int defaultTimeout = 25;         // Fallback value
  
  // Retry policies
  static const int syncOperationsMaxRetries = 1;    // Idempotent operations
  static const int nonIdempotentMaxRetries = 0;     // Writes/uploads
  static const int readOperationsMaxRetries = 1;    // GET requests
}
```
**Verify:** Run `flutter analyze lib/config/network_config.dart` - no syntax errors

---

### 2. Update HttpClientService Default Timeouts

**File:** `lib/services/http_client_service.dart` (MODIFY)
**Changes:**
- Line 14: Change `static const int _timeoutSeconds = 30;` to `static const int _timeoutSeconds = 25;` 
- Line 15: Change `static const int _maxRetries = 0;` to `static const int _maxRetries = 1;` for better resilience
- Add import: `import '../config/network_config.dart';`
- Update timeout parameter to use NetworkConfig values when endpoint is specified

**Verify:** Run `flutter analyze lib/services/http_client_service.dart` and existing HttpClientService tests

---

### 3. Fix Critical Learner Profile Timeout

**File:** `lib/database_helper.dart` (MODIFY)
**Target line:** 836 - `.timeout(const Duration(seconds: 10))`
**Change to:** 
```dart
// Replace direct http call with HttpClientService
final response = await HttpClientService.makeRequest(
  () => http.post(
    Uri.parse(AppConfig.updateLearnerUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'LearnerID': learnerId,
      'data': updateData,
    }),
  ),
  endpoint: 'learner_profile_sync',
  maxRetries: NetworkConfig.syncOperationsMaxRetries,
  timeoutSeconds: NetworkConfig.profileSyncTimeout,
);
```
**Add imports:**
```dart
import 'services/http_client_service.dart';
import 'config/network_config.dart';
```
**Verify:** Run `flutter build apk --debug` to confirm build succeeds

---

### 4. Fix Materials Sync Service

**File:** `lib/sync_service.dart` (MODIFY)
**Target method:** `syncMaterialsReceivedData()` starting at line 2381
**Changes:**
```dart
// Replace direct http.get() call with HttpClientService
final response = await HttpClientService.makeRequest(
  () => http.get(Uri.parse(apiUrl)),
  endpoint: 'materials_received_sync', 
  maxRetries: NetworkConfig.syncOperationsMaxRetries,
  timeoutSeconds: NetworkConfig.lightweightTimeout,
);
```
**Add imports:** Same as above
**Note:** Port 50666 issue is server-side - this change adds proper retry/timeout handling for when server is fixed
**Verify:** Run `flutter analyze lib/sync_service.dart` - no errors

---

### 5. Update Persistent Sync Service Timeouts

**File:** `lib/services/persistent_sync_service.dart` (MODIFY)
**Target lines:** All `.timeout()` calls (lines ~143, ~286, ~355)
**Changes:**
- Line 143: Change `.timeout(const Duration(seconds: 15))` to use `NetworkConfig.lightweightTimeout`
- Line 286: Change transaction timeout from 5 to 8 seconds to prevent database locks
- Line 355: Change clocking sync timeout from 10 to `NetworkConfig.lightweightTimeout`

**Replace all http calls with HttpClientService pattern:**
```dart
final response = await HttpClientService.makeRequest(
  () => http.get(Uri.parse('${AppConfig.getLearnersUrl}?classID=$classID')),
  endpoint: 'learners_by_class',
  maxRetries: NetworkConfig.syncOperationsMaxRetries,
  timeoutSeconds: NetworkConfig.lightweightTimeout,
);
```
**Verify:** Run `flutter test test/services/persistent_sync_service_test.dart` if exists

---

### 6. Fix Sync Service Retry Logic Violation

**File:** `lib/sync_service.dart` (MODIFY)  
**Target:** Lines 30-80 - Custom retry loop with `maxRetries = 2`
**Issue:** Violates project guideline of using HttpClientService for all HTTP requests
**Change:** Replace entire custom retry block with single HttpClientService call:
```dart
// Remove custom retry loop (lines 38-78)
// Replace with:
final response = await HttpClientService.makeRequest(
  () => http.post(url, headers: headers, body: body),
  endpoint: 'learner_clockin_sync',
  maxRetries: NetworkConfig.syncOperationsMaxRetries,
  timeoutSeconds: NetworkConfig.profileSyncTimeout,
);
```
**Verify:** Test clock-in sync functionality to ensure retry behavior still works

---

### 7. Update Query Queue Service Configuration

**File:** `lib/services/query_queue_service.dart` (MODIFY)
**Current settings:**
- `maxRetries = 3` (line 24)
- `initialRetryDelay = Duration(seconds: 1)` (line 25)

**Changes:**
- Line 24: Change `maxRetries = 3` to `maxRetries = 1` (align with project guidelines)
- Add timeout enforcement: Wrap all request executions with configurable timeout
- Import NetworkConfig for consistent timeout values

**Verify:** Run queue service tests to ensure new retry limits work correctly

---

### 8. Create Network Diagnostics Utility (OPTIONAL)

**File:** `lib/utils/network_diagnostics.dart` (NEW FILE)
**Purpose:** Help diagnose the port 50666 issue in production
**Content:**
```dart
class NetworkDiagnostics {
  static Future<Map<String, dynamic>> diagnoseMaterialsSync() async {
    final results = <String, dynamic>{};
    
    try {
      // Test direct URL resolution
      final uri = Uri.parse(AppConfig.saveMaterialsReceivedUrl);
      results['configured_url'] = uri.toString();
      results['configured_host'] = uri.host;
      results['configured_port'] = uri.port;
      
      // Add actual connection test here if needed for production debugging
    } catch (e) {
      results['error'] = e.toString();
    }
    
    return results;
  }
}
```
**Verify:** Add diagnostic call in debug menu if needed for production troubleshooting

---

### 9. Update High-Priority Direct HTTP Call Files

**Priority files** (most critical for app stability):
1. `lib/admin.dart` - 4 locations using `http.get().timeout()`
2. `lib/clock_in_page.dart` - 3 locations 
3. `lib/attendance_page.dart` - 1 location
4. `lib/AddLearnerPage.dart` - 2 locations

**Change pattern for each:**
```dart
// Before:
final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: X));

// After:  
final response = await HttpClientService.makeRequest(
  () => http.get(Uri.parse(url)),
  endpoint: 'descriptive_name',
  timeoutSeconds: NetworkConfig.appropriateTimeout,
);
```

**Verify:** Test core app functionality (admin search, clock-in, attendance) after changes

---

### 10. Document Network Configuration Policy

**File:** `lib/config/network_config.dart` (ADD DOCUMENTATION)
**Add comprehensive documentation:**
```dart
/// Network Configuration Policy
/// 
/// MANDATORY RULES:
/// 1. All HTTP requests MUST use HttpClientService.makeRequest()
/// 2. Direct http.get/post calls are FORBIDDEN
/// 3. Default maxRetries = 1 for idempotent operations  
/// 4. Default maxRetries = 0 for non-idempotent operations
/// 5. Use NetworkConfig constants for all timeout values
/// 
/// TIMEOUT VALUES:
/// - Profile sync: 30s (complex multi-field operations)
/// - File uploads: 60s (network-dependent transfers)
/// - Lightweight reads: 20s (simple queries)
/// - Default fallback: 25s
```

**Verify:** Review documentation with team for policy compliance

---

## Port 50666 Issue - Server-Side Investigation Required

**Analysis:** The error log shows the Flutter app correctly configured to use `https://rlms.rlms.co.za/mobile/save_materials_received.php` (port 443), but actual connections hit port 50666. This indicates:

1. **DNS resolution issue** - Domain resolving to wrong server  
2. **Load balancer misconfiguration** - Proxy redirecting to internal server on port 50666
3. **Server-side redirect** - Web server sending 3xx redirect to port 50666

**NOT a client-side code issue** - The Flutter code correctly uses port 443 HTTPS URLs.

**Recommendation:** 
- Server administrator should check nginx/Apache configuration
- Verify DNS A/AAAA records for rlms.rlms.co.za  
- Check load balancer routing rules
- Review server firewall rules

---

## Testing Strategy

### Unit Tests
1. Test NetworkConfig constants are correctly applied
2. Test HttpClientService timeout enforcement  
3. Test retry behavior follows new limits (maxRetries ≤ 1)

### Integration Tests  
1. Test learner profile sync with 30-second timeout
2. Test materials sync with proper error handling for port issue
3. Test clock-in sync without custom retry loops

### User Acceptance Testing
1. Verify learner profile sync no longer times out at 10 seconds
2. Verify app handles materials sync connection error gracefully  
3. Confirm overall app responsiveness improved with centralized timeout management

---

## Risk Assessment

**Low Risk:**
- Timeout configuration changes (easily reversible)
- HttpClientService adoption (improves reliability)

**Medium Risk:**  
- Removing custom retry loops (verify functionality preserved)
- Database transaction timeout changes (test thoroughly)

**No Risk:**
- Port 50666 issue (server-side, no client code changes needed)
- Documentation updates

---

## Success Criteria

1. **No more 10-second timeout errors** in learner profile sync logs
2. **Centralized timeout management** - all HTTP requests use NetworkConfig values  
3. **HttpClientService adoption** - no direct http.get/post calls in critical paths
4. **Consistent retry behavior** - maxRetries ≤ 1 across all operations
5. **Port 50666 issue documented** for server-side resolution
6. **Build success** - `flutter build apk` completes without errors
7. **Performance maintained** - app responsiveness not degraded by timeout changes