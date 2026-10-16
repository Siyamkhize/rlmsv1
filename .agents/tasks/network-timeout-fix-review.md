# Network Timeout Fix Review

## Summary

**Network timeout fix for learner profile sync and materials operations**. The fix addresses critical `TimeoutException after 0:00:10.000000` errors affecting learner profile synchronization by replacing direct HTTP calls with centralized HttpClientService, implementing proper timeout values (30s for profile sync, 20s for reads), and adding structured retry policies. The materials sync port 50666 issue remains a server-side DNS/proxy configuration problem but now has better client-side error handling.

**Watch for:** Two uncaught 10-second timeouts remain in database_helper.dart (lines 4745, 6417), violating the timeout requirements. The port 50666 issue requires server-side investigation and cannot be resolved through client changes alone.

**Verdict**: CHANGES_REQUESTED

## High-level view

Profile sync operations correctly migrated from 10-second timeouts to 30-second timeouts using HttpClientService.makeRequest() with proper endpoint naming and NetworkConfig integration. Materials sync operations now use centralized HTTP handling with 20-second timeouts and single retry attempts, replacing direct http.get() calls. Admin search functionality systematically converted to HttpClientService across six endpoints, maintaining proper endpoint identification. HttpClientService enforces maxRetries ≤ 1 (reduced from default 2) and uses NetworkConfig constants for consistent timeout behavior. Two database helper methods still contain 10-second timeouts that need remediation before the fix is complete.

<details>
<summary>Issues (3)</summary>

1. **Incomplete 10s timeout removal** — Two methods in database_helper.dart (lines 4745, 6417) still use `Duration(seconds: 10)` timeouts instead of HttpClientService. These need conversion to maintain consistency.
2. **Port 50666 server issue** — Client cannot resolve the SocketException targeting port 50666 as this requires server-side DNS/proxy reconfiguration. Client-side retry improvements will help when server is fixed.
3. **Limited scope verification** — Many files still contain 10-second timeouts (signature_geofence_clock_in_page.dart, AddLearnerPage.dart, clock_in_page.dart, etc.) indicating the fix may not be comprehensive across the entire codebase.

</details>

<details><summary>Details</summary>

## Profile sync timeout elimination

The critical fix correctly addresses the `[SYNC-LEARNER-PROFILE] Error syncing learner profile: TimeoutException after 0:00:10.000000` error by replacing direct HTTP calls with HttpClientService in `syncUnsyncedLearnerProfiles()`. The method now uses:

```dart
final response = await HttpClientService.makeRequest(
  () => http.post(Uri.parse(apiUrl), body: updateData),
  endpoint: 'learner_profile_sync',
  maxRetries: NetworkConfig.syncOperationsMaxRetries, // 1 retry
  timeoutSeconds: NetworkConfig.profileSyncTimeout,   // 30 seconds
);
```

This replaces the problematic 10-second timeout pattern and provides proper error handling with structured retry logic. The endpoint naming follows the required convention and integrates with NetworkConfig constants.

**Confirmed**: The specific SYNC-LEARNER-PROFILE operations that generated the timeout exceptions are now properly configured with 30-second timeouts.

## Materials sync port 50666 handling

The materials sync operation in `syncMaterialsReceivedData()` correctly migrates from direct `http.get()` to HttpClientService with proper configuration:

```dart
final response = await HttpClientService.makeRequest(
  () => http.get(Uri.parse(apiUrl)),
  endpoint: 'materials_received_sync',
  maxRetries: NetworkConfig.syncOperationsMaxRetries, // 1 retry  
  timeoutSeconds: NetworkConfig.lightweightTimeout,   // 20 seconds
);
```

However, the port 50666 issue in the error log (`address = rlms.rlms.co.za, port = 50666`) is a server-side problem. The client correctly targets `https://rlms.rlms.co.za/mobile/save_materials_received.php` (standard HTTPS port 443), but DNS resolution or proxy configuration redirects to port 50666. This cannot be resolved through client-side changes.

**Confirmed**: Client-side timeout and retry improvements are properly implemented. Server-side DNS/proxy investigation required for port resolution.

## HttpClientService compliance and enforcement

HttpClientService properly enforces the project's mandatory retry guidelines with `maxRetries` reduced from 2 to 0 as the default, and allows override up to the project limit of 2. All reviewed endpoints correctly specify their identity:

- `admin_learner_search`
- `admin_learner_search_fallback` 
- `admin_learner_search_global`
- `admin_get_details`
- `admin_search_learner_online`
- `check_learner_documents`
- `learner_profile_sync`
- `materials_received_sync`

The service integrates NetworkConfig constants (profileSyncTimeout: 30s, lightweightTimeout: 20s, defaultTimeout: 25s) providing centralized timeout management.

**Confirmed**: All analyzed makeRequest calls specify endpoint names and use appropriate NetworkConfig timeouts.

## Incomplete timeout remediation

Critical gap: Two methods in database_helper.dart retain 10-second timeouts:

**Line 4745**: `http.post(...).timeout(const Duration(seconds: 10))` - needs HttpClientService conversion
**Line 6417**: Similar direct timeout pattern - needs HttpClientService conversion

These violate the timeout correctness requirement and could still generate TimeoutException errors. Additionally, the grep search reveals dozens of other files with 10-second timeouts (AddLearnerPage.dart, clock_in_page.dart, signature_geofence_clock_in_page.dart, etc.), suggesting the fix may have limited scope.

**Confirmed**: Incomplete remediation leaves timeout vulnerabilities in place.

## NetworkConfig centralization

NetworkConfig provides proper timeout constants aligned with the requirements:
- Profile sync: 30s (meets ≥30s requirement) 
- File uploads: 60s (meets ≥60s requirement)
- Lightweight reads: 20s (meets ≥20s requirement)
- Max retries: 1 for sync operations, 0 for non-idempotent (meets ≤2 requirement)

This establishes single source of truth for timeout and retry policies across the application.

**Confirmed**: NetworkConfig values meet all specified timeout requirements.

</details>

<details>
<summary>File map</summary>

- `lib/config/network_config.dart` - **NEW** centralized timeout and retry constants
- `lib/services/http_client_service.dart` - reduced maxRetries to 0, integrated NetworkConfig
- `lib/services/query_queue_service.dart` - reduced maxRetries to 1, added NetworkConfig
- `lib/database_helper.dart` - **CRITICAL** converted profile sync to HttpClientService, 2 methods still need conversion
- `lib/sync_service.dart` - converted materials sync to HttpClientService with 20s timeout
- `lib/services/persistent_sync_service.dart` - converted sync operations to HttpClientService  
- `lib/persistent_sync_service.dart` - converted learner sync to HttpClientService
- `lib/admin.dart` - converted 6 admin search endpoints to HttpClientService

[View full diff with: `git diff main`]

</details>