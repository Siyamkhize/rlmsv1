# RLMSS Security & Sync Overhaul - Implementation Plan

## Overview

Based on the approved design document, this plan implements the remaining mobile sync reliability improvements. Most security vulnerabilities have been resolved; focus is now on HTTP client service enhancements, idempotency token security, and mobile sync reliability.

## Implementation Steps

- [ ] 1. **Enhance HttpClientService with jitter algorithm and proper error categorization**
      Update existing `lib/services/http_client_service.dart` to add ±25% jitter to exponential backoff, improve error handling for 408 timeouts, and add request metrics logging.
      Files: `lib/services/http_client_service.dart`
      Verify: `flutter test` - new unit tests for jitter algorithm and retry logic pass

- [ ] 2. **Upgrade idempotency token generation to cryptographically secure algorithm**  
      Replace predictable timestamp+random tokens with SHA-256 based secure tokens using crypto package. Add `generateSecureIdempotencyToken()` function in sync service.
      Files: `lib/services/manual_clocking_evidence_sync_service.dart`
      Verify: `flutter test` - token generation tests pass, no collisions in 10k iterations

- [ ] 3. **Implement sync queue with concurrency controls**
      Add `SyncQueue` class to prevent overlapping sync operations. Limit concurrent syncs to 2 maximum to prevent overwhelming rural mobile connections.
      Files: `lib/services/manual_clocking_evidence_sync_service.dart` 
      Verify: `flutter test` - queue respects MAX_CONCURRENT=2 limit, processes items sequentially

- [ ] 4. **Retrofit sync service to use HttpClientService with conservative retry policy**
      Update `syncToServer()` and `_syncSingleRecord()` methods to use centralized HTTP client. Set maxRetries=1 for sync reliability on poor connections.
      Files: `lib/services/manual_clocking_evidence_sync_service.dart`
      Verify: `flutter test` - sync service integration tests pass, respects retry limits

- [ ] 5. **Update signature geofence page to use HttpClientService for all HTTP calls**
      Replace direct `http.post()` calls with `HttpClientService.makeRequest()`. Ensure proper error handling and retry behavior for clocking operations.
      Files: `lib/signature_geofence_clock_in_page.dart`
      Verify: `flutter analyze` - no direct http calls remain in file, all use HttpClientService

- [ ] 6. **Enhance PHP idempotency validation with secure token format checking**
      Update `save_consolidated_clocking.php` to validate token format `^clk_[a-f0-9]{32}$` and improve duplicate detection logging.
      Files: `mobile/save_consolidated_clocking.php`
      Verify: `php -l mobile/save_consolidated_clocking.php` - syntax check passes

- [ ] 7. **Create database optimization script for indexes and performance** 
      Add performance indexes for rate limiting and idempotency tables. Create cleanup script for old entries.
      Files: `mobile/migrations/001_security_indexes.php`, `mobile/cleanup/rate_limit_cleanup.php`
      Verify: Execute scripts against test database - indexes created successfully, cleanup removes old entries

- [ ] 8. **Implement trusted proxy configuration for secure client IP detection**
      Add proxy configuration file and update `get_client_ip()` function to only trust forwarded headers from configured proxy IPs.
      Files: `mobile/config/trusted_proxies.php`, update `mobile/security_middleware.php`
      Verify: `php -l mobile/security_middleware.php` - syntax check passes, IP validation tests

- [ ] 9. **Add image processing resource limits and memory management**  
      Implement file size and dimension validation before image processing. Add memory usage monitoring and cleanup for temporary files.
      Files: `mobile/upload_clocking_evidence_images.php`, `mobile/save_consolidated_clocking.php`
      Verify: Test with large images - memory limits enforced, temporary files cleaned up

- [ ] 10. **Create monitoring and cleanup automation scripts**
       Add automated cleanup for rate limiting, security logs, and request monitoring tables. Include daily maintenance script.
       Files: `mobile/cleanup/daily_maintenance.php`, `mobile/cron/setup_cleanup.sh`
       Verify: Execute cleanup script - old records removed, table sizes reduced

- [ ] 11. **Add network configuration validation and retry policy enforcement**
       Create network configuration class to validate all HTTP requests use HttpClientService. Add build-time validation.
       Files: `lib/config/network_config.dart`, update existing HTTP calls to use service
       Verify: `flutter analyze` - no direct http.get/post calls in codebase outside HttpClientService

- [ ] 12. **Comprehensive testing and integration verification**
       Test complete workflow under poor network conditions, concurrent users, and edge cases. Verify all retry limits respected.
       Files: Create `test/integration/security_sync_integration_test.dart`
       Verify: `flutter test` - integration tests pass for network reliability and security

## Build Commands

- **Flutter Build**: `flutter build apk --release`  
- **PHP Syntax Check**: `find mobile -name "*.php" -exec php -l {} \;`
- **Flutter Test**: `flutter test`
- **Flutter Analyze**: `flutter analyze`

## Verification Requirements

Each step must leave the system in a working state. Security improvements should not break existing functionality. All HTTP requests must use the centralized HttpClientService with appropriate retry policies.

## Dependencies

Steps 1-4 must be completed before Step 5 (signature page update). Database optimization (Step 7) can be done in parallel with mobile app changes. Steps 11-12 are final integration and must be completed last.

## Risk Mitigation

- Conservative retry limits (maxRetries ≤ 1) prevent server overload
- Gradual rollout with existing fallback behavior maintained
- Comprehensive testing under poor network conditions
- Memory and resource limits prevent DoS attacks
