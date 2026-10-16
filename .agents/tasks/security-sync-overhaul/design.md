# RLMSS Security & Sync Overhaul - Technical Design (Revised)

## Overview

This document outlines the technical design to complete the security and synchronization reliability improvements in the RLMSS Flutter/PHP mobile attendance system. Several critical security vulnerabilities have been resolved since the initial review, and this revision focuses on the remaining improvements needed for mobile sync reliability and system robustness.

## System Context

**Current Architecture:**
- Flutter mobile app with offline-first SQLite storage
- PHP backend APIs (`c:\projects\rlmss\mobile\*.php`) 
- MySQL database for server-side persistence
- Evidence files protected via .htaccess files in `mobile/clocking_evidence/`
- Bearer token authentication via `require_auth.php`
- Rate limiting via `security_middleware.php`

**Issues Resolved Since Initial Review:**
✅ Authentication fail-closed implemented - returns 503 on system errors, 401 on auth failures
✅ Rate limiting function signature unified across all files
✅ Server-generated filenames enforced with explicit client filename rejection logging
✅ Evidence files protected by .htaccess "Deny from all" rules

**Remaining Improvements Needed:**
1. Mobile retry logic lacks proper exponential backoff and jitter specification
2. Idempotency token generation uses predictable algorithm vulnerable to collisions
3. No centralized HTTP client service to enforce retry policies
4. Missing concurrency controls for mobile sync operations
5. Database indexes needed for rate limiting and idempotency performance

## 1. Mobile HTTP Client Service Implementation

### 1.1 Centralized HTTP Client with Retry Controls

**Current Issue:** Mobile sync operations use direct `http` calls without consistent retry policies, leading to unreliable sync under poor network conditions.

**Design Solution:** Create `HttpClientService` following established retry configuration guidelines.

**New Service:** `lib/services/http_client_service.dart`
```dart
class HttpClientService {
  static const int MAX_RETRIES = 2; // Maximum 3 total attempts (following guidelines)
  static const Duration BASE_DELAY = Duration(seconds: 1);
  static const Duration MAX_DELAY = Duration(seconds: 16);
  
  /// Make HTTP request with controlled retry logic
  /// @param maxRetries - Default 0 (safe default), max 2 (guidelines compliance)
  /// @param endpoint - Required for monitoring and rate limiting
  static Future<http.Response> makeRequest(
    Future<http.Response> Function() requestFunction, {
    int maxRetries = 0, // Safe default: no retries
    String? endpoint,
  }) async {
    if (endpoint == null) {
      throw ArgumentError('Endpoint identification required for monitoring');
    }
    
    int attempt = 0;
    Duration delay = BASE_DELAY;
    
    while (true) {
      try {
        final response = await requestFunction()
            .timeout(const Duration(seconds: 30));
        
        // Log request metrics
        _logRequestMetrics(endpoint, attempt + 1, response.statusCode);
        
        // Success or non-retryable failure
        if (response.statusCode < 500 && response.statusCode != 408) {
          return response;
        }
        
        // Server error - check if retryable and within limits
        if (attempt >= maxRetries) {
          return response; // Give up, return error response
        }
        
      } catch (e) {
        // Log error metrics
        _logRequestMetrics(endpoint, attempt + 1, null, error: e.toString());
        
        if (attempt >= maxRetries) {
          rethrow;
        }
        
        // Only retry on network/timeout errors
        if (!_isRetryableError(e)) {
          rethrow;
        }
      }
      
      // Calculate delay with jitter (±25% of base delay)
      final jitterMs = (delay.inMilliseconds * 0.25).round();
      final jitter = Duration(
        milliseconds: Random().nextInt(jitterMs * 2) - jitterMs
      );
      final totalDelay = delay + jitter;
      
      print('[HTTP_CLIENT] Retry ${attempt + 1}/$maxRetries for $endpoint, waiting ${totalDelay.inMilliseconds}ms');
      await Future.delayed(totalDelay);
      
      // Exponential backoff: 1s → 1.5s → 2.25s → 3.375s (capped at 16s)
      delay = Duration(milliseconds: (delay.inMilliseconds * 1.5).round())
          .clamp(BASE_DELAY, MAX_DELAY);
      attempt++;
    }
  }
  
  static bool _isRetryableError(dynamic error) {
    return error is SocketException ||
           error is TimeoutException ||
           error.toString().contains('timeout') ||
           error.toString().contains('connection');
  }
  
  static void _logRequestMetrics(String endpoint, int attemptNumber, int? statusCode, {String? error}) {
    final status = statusCode?.toString() ?? 'ERROR';
    final errorMsg = error != null ? ' ($error)' : '';
    print('[HTTP_CLIENT] $endpoint: attempt $attemptNumber -> $status$errorMsg');
  }
}
```

### 1.2 Retry Policy by HTTP Status (Guidelines Compliance)

**Retryable Conditions (maxRetries ≤ 2):**
- 500, 502, 503, 504 (server errors)
- 408 (request timeout)  
- Network exceptions (SocketException, TimeoutException)

**Non-Retryable Conditions:**
- 401, 403 (authentication/authorization) - Never retry
- 400, 422 (client errors) - Never retry
- 429 (rate limited) - Never retry (respect server protection)
- Any 2xx success response - Never retry

**Jitter Algorithm:** ±25% of base exponential delay to prevent thundering herd

## 2. Enhanced Idempotency Implementation

### 2.1 Current Issue
Existing idempotency token generation uses `timestamp + Random().nextInt(999999)` which is vulnerable to collisions under high concurrent usage or synchronized device clocks.

### 2.2 Design Solution: Cryptographically Secure Token Generation

**Database Schema (Already Exists):**
```sql
-- Idempotency table already created in sql/create_idempotency_table.sql
-- ALTER TABLE manual_clocking ADD COLUMN idempotency_token VARCHAR(64) UNIQUE;
-- ALTER TABLE manual_clocking_evidence ADD COLUMN idempotency_token VARCHAR(64) UNIQUE;
```

**Enhanced Client Token Generation (Flutter):**
```dart
// Replace in manual_clocking_evidence_sync_service.dart
import 'dart:math';
import 'package:crypto/crypto.dart'; // Add to pubspec.yaml

String generateSecureIdempotencyToken() {
  // Use cryptographically secure random generation
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final randomBytes = List.generate(16, (_) => Random.secure().nextInt(256));
  final randomHex = randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  
  // Combine timestamp + secure random for uniqueness and traceability
  final tokenData = '${timestamp}_$randomHex';
  final hash = sha256.convert(utf8.encode(tokenData));
  
  return 'clk_${hash.toString().substring(0, 32)}'; // 32-char hex subset
}

// Usage in request payload
final payload = {
  'learner_id': learnerID,
  'clock_date': clockDate,
  'idempotency_token': generateSecureIdempotencyToken(),
  // ... other fields
};
```

**Server Implementation Enhancement:**
```php
// In save_consolidated_clocking.php - enhance existing idempotency check
$idempotency_token = $input['idempotency_token'] ?? null;

// Validate token format (security check)
if (empty($idempotency_token) || !preg_match('/^clk_[a-f0-9]{32}$/', $idempotency_token)) {
    throw new Exception('Invalid idempotency token format');
}

// Enhanced duplicate detection with better logging
$check_stmt = $conn->prepare("
    SELECT id, created_at, learner_id 
    FROM manual_clocking 
    WHERE idempotency_token = ?
");
$check_stmt->bind_param("s", $idempotency_token);
$check_stmt->execute();
$result = $check_stmt->get_result()->fetch_assoc();

if ($result) {
    // Log duplicate detection for monitoring
    error_log("[SAVE_CONSOLIDATED] Duplicate request detected - Token: $idempotency_token, Original ID: {$result['id']}, Created: {$result['created_at']}");
    
    // Return success for idempotent duplicate
    echo json_encode([
        'success' => true,
        'message' => 'Record already processed (duplicate request)',
        'idempotency_token' => $idempotency_token,
        'original_record_id' => $result['id']
    ]);
    exit;
}
```

## 3. Mobile Sync Service Refactoring

### 3.1 Current Issue
`manual_clocking_evidence_sync_service.dart` uses direct `http` calls without centralized retry policies, making sync unreliable under poor network conditions.

### 3.2 Design Solution: Retrofit Existing Service with HttpClientService

**Update existing sync methods in `manual_clocking_evidence_sync_service.dart`:**
```dart
// Replace existing syncToServer method
Future<bool> syncToServer() async {
  try {
    final db = await DatabaseHelper().database;
    
    // Get unsynced records
    final List<Map<String, dynamic>> unsyncedRecords = await db.query(
      'manual_clocking_evidence',
      where: 'synced = ?',
      whereArgs: [0],
    );

    if (unsyncedRecords.isEmpty) {
      print('[EVIDENCE_SYNC] No unsynced records found');
      return true;
    }

    print('[EVIDENCE_SYNC] Found ${unsyncedRecords.length} unsynced records');
    bool allSynced = true;

    for (final record in unsyncedRecords) {
      final success = await _syncSingleRecord(record);
      if (!success) {
        allSynced = false;
        // Continue with other records rather than failing completely
      }
    }

    return allSynced;
  } catch (e) {
    print('[EVIDENCE_SYNC] Error in syncToServer: $e');
    return false;
  }
}

// New method using HttpClientService
Future<bool> _syncSingleRecord(Map<String, dynamic> record) async {
  try {
    // Generate idempotency token for this sync attempt
    final idempotencyToken = generateSecureIdempotencyToken();
    
    final payload = {
      'learner_id': record['LearnerID'],
      'clock_date': record['clock_date'],
      'signature_in': record['signature_in'],
      'signature_out': record['signature_out'],
      'face_in': record['face_in'],
      'face_out': record['face_out'],
      'idempotency_token': idempotencyToken,
    };

    // Use centralized HTTP client with safe retry (maxRetries = 1 for sync reliability)
    final response = await HttpClientService.makeRequest(
      () => http.post(
        Uri.parse('${AppConfig.baseUrl}/save_consolidated_clocking.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: json.encode(payload),
      ),
      maxRetries: 1, // Conservative retry for sync operations
      endpoint: 'save_consolidated_clocking',
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      
      if (responseData['success'] == true) {
        // Mark as synced in local database
        await _markRecordSynced(record['id'], idempotencyToken);
        print('[EVIDENCE_SYNC] Successfully synced record ${record['id']}');
        return true;
      } else {
        print('[EVIDENCE_SYNC] Server rejected record ${record['id']}: ${responseData['message']}');
        return false;
      }
    } else {
      print('[EVIDENCE_SYNC] HTTP error ${response.statusCode} for record ${record['id']}');
      return false;
    }
  } catch (e) {
    print('[EVIDENCE_SYNC] Error syncing record ${record['id']}: $e');
    return false;
  }
}

Future<void> _markRecordSynced(int recordId, String idempotencyToken) async {
  final db = await DatabaseHelper().database;
  await db.update(
    'manual_clocking_evidence',
    {
      'synced': 1,
      'sync_token': idempotencyToken,
      'synced_at': DateTime.now().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [recordId],
  );
}
```

### 3.3 Concurrency Control for Sync Operations

**Design: Queue-Based Sync with Concurrency Limit**
```dart
// Add to manual_clocking_evidence_sync_service.dart
class SyncQueue {
  static const int MAX_CONCURRENT = 2; // Conservative limit for rural connections
  static final Queue<Future<void> Function()> _queue = Queue();
  static int _activeTasks = 0;
  static bool _isProcessing = false;
  
  static Future<T> enqueue<T>(Future<T> Function() task) async {
    final completer = Completer<T>();
    
    _queue.add(() async {
      try {
        _activeTasks++;
        final result = await task();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      } finally {
        _activeTasks--;
        _processQueue();
      }
    });
    
    if (!_isProcessing) {
      _processQueue();
    }
    
    return completer.future;
  }
  
  static void _processQueue() {
    _isProcessing = true;
    
    while (_queue.isNotEmpty && _activeTasks < MAX_CONCURRENT) {
      final task = _queue.removeFirst();
      task();
    }
    
    if (_queue.isEmpty && _activeTasks == 0) {
      _isProcessing = false;
    }
  }
}

// Usage in sync operations
Future<bool> syncAllRecords() async {
  return await SyncQueue.enqueue(() async {
    return await syncToServer();
  });
}
```

## 4. Database Optimization and Resource Management

### 7.1 Current Issue
`get_client_ip()` in `security_middleware.php` trusts forwarded headers from any source.

### 7.2 Design Solution: Configured Proxy Trust

**Configuration File:** `mobile/config/trusted_proxies.php`
```php
<?php
return [
    'trusted_proxies' => [
        '127.0.0.1',     // localhost
        '10.0.0.0/8',    // Private networks
        '172.16.0.0/12',
        '192.168.0.0/16',
        // Add your reverse proxy IPs here
    ],
    'proxy_headers' => [
        'HTTP_CF_CONNECTING_IP',    // Cloudflare
        'HTTP_X_FORWARDED_FOR',     // Standard
        'HTTP_CLIENT_IP',           // Some proxies
    ]
];
?>
```

**Updated get_client_ip():**
```php
function get_client_ip() {
    $config = include __DIR__ . '/config/trusted_proxies.php';
    $server_ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    
    // Only trust headers from configured proxies
    if (_ip_in_ranges($server_ip, $config['trusted_proxies'])) {
        foreach ($config['proxy_headers'] as $header) {
            if (!empty($_SERVER[$header])) {
                $ip = explode(',', $_SERVER[$header])[0];
                if (filter_var(trim($ip), FILTER_VALIDATE_IP)) {
                    return trim($ip);
                }
            }
        }
    }
    
    return $server_ip;
}

function _ip_in_ranges($ip, $ranges) {
    foreach ($ranges as $range) {
        if (_ip_in_range($ip, $range)) return true;
    }
    return false;
}

## 8. Database Schema and Index Optimizations

### 8.1 Table Creation Migration

**Current Issue:** Rate limiting and request logging tables are created in the request path causing delays.

**Design Solution: Migration Script:** `mobile/migrations/001_security_tables.php`
```php
<?php
require_once '../connection.php';

// Rate limiting table
$conn->query("
    CREATE TABLE IF NOT EXISTS rate_limit (
        id INT AUTO_INCREMENT PRIMARY KEY,
        ip_address VARCHAR(45) NOT NULL,
        action VARCHAR(50) NOT NULL,
        attempt_time DATETIME NOT NULL,
        INDEX idx_ip_action_time (ip_address, action, attempt_time),
        INDEX idx_attempt_time (attempt_time)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// Security event logging
$conn->query("
    CREATE TABLE IF NOT EXISTS security_log (
        id INT AUTO_INCREMENT PRIMARY KEY,
        event_type VARCHAR(50) NOT NULL,
        description TEXT,
        ip_address VARCHAR(45),
        user_id INT DEFAULT NULL,
        metadata JSON,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_event_type (event_type),
        INDEX idx_ip_address (ip_address),
        INDEX idx_created_at (created_at),
        INDEX idx_user_id (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// Request monitoring
$conn->query("
    CREATE TABLE IF NOT EXISTS request_log (
        id INT AUTO_INCREMENT PRIMARY KEY,
        endpoint VARCHAR(100) NOT NULL,
        ip_address VARCHAR(45),
        user_id INT DEFAULT NULL,
        request_time DATETIME DEFAULT CURRENT_TIMESTAMP,
        response_code INT DEFAULT NULL,
        processing_time_ms INT DEFAULT NULL,
        metadata JSON,
        INDEX idx_endpoint_time (endpoint, request_time),
        INDEX idx_ip_time (ip_address, request_time),
        INDEX idx_response_code (response_code)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

echo "Security tables created successfully\n";
?>
```

### 8.2 Cleanup Job

**Automated Cleanup Script:** `mobile/cleanup/rate_limit_cleanup.php`
```php
<?php
// Run daily via cron
require_once '../connection.php';

// Remove rate limit entries older than 24 hours
$conn->query("DELETE FROM rate_limit WHERE attempt_time < DATE_SUB(NOW(), INTERVAL 24 HOUR)");

// Remove old security logs (keep 90 days)
$conn->query("DELETE FROM security_log WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY)");

// Remove old request logs (keep 30 days)  
$conn->query("DELETE FROM request_log WHERE request_time < DATE_SUB(NOW(), INTERVAL 30 DAY)");

echo "Cleanup completed\n";
?>
```

### 8.3 Index Recommendations

**Additional Indexes for Performance:**
```sql
-- manual_clocking table
ALTER TABLE manual_clocking ADD INDEX idx_learner_date (LearnerID, clock_date);
ALTER TABLE manual_clocking ADD INDEX idx_idempotency (idempotency_token);

-- manual_clocking_evidence table  
ALTER TABLE manual_clocking_evidence ADD INDEX idx_learner_date (LearnerID, clock_date);
ALTER TABLE manual_clocking_evidence ADD INDEX idx_synced (synced);
ALTER TABLE manual_clocking_evidence ADD INDEX idx_idempotency (idempotency_token);

-- auth_tokens table (from security_middleware.php)
ALTER TABLE auth_tokens ADD INDEX idx_expires_active (expires_at, is_active);
ALTER TABLE auth_tokens ADD INDEX idx_user_active (user_id, is_active);
```

## 9. Image Processing Resource Management

### 9.1 Current Issue
No memory or size limits during image processing and watermark generation.

### 9.2 Design Solution: Resource Enforcement

**Image Validation Updates:**
```php
// In upload_clocking_evidence_images.php and save_consolidated_clocking.php
function validate_image_resource_limits($file_path, $max_dimensions = [1920, 1080]) {
    // Check file size before processing
    $file_size = filesize($file_path);
    if ($file_size > 5 * 1024 * 1024) { // 5MB limit
        throw new Exception('Image file too large');
    }
    
    // Get image dimensions without loading full image into memory
    $image_info = getimagesize($file_path);
    if (!$image_info) {
        throw new Exception('Invalid image file');
    }
    
    [$width, $height] = $image_info;
    if ($width > $max_dimensions[0] || $height > $max_dimensions[1]) {
        throw new Exception("Image dimensions too large: {$width}x{$height}");
    }
    
    // Estimate memory usage (width × height × 4 bytes per pixel)
    $estimated_memory = $width * $height * 4;
    $available_memory = _get_available_memory();
    
    if ($estimated_memory > $available_memory * 0.8) { // Use max 80% available
        throw new Exception('Image too large for available memory');
    }
    
    return true;
}

function _get_available_memory() {
    $memory_limit = ini_get('memory_limit');
    $current_usage = memory_get_usage(true);
    
    // Convert memory_limit to bytes
    $limit_bytes = _parse_size($memory_limit);
    return $limit_bytes - $current_usage;
}
```

### 9.3 Temporary File Cleanup

**Cleanup Strategy:**
```php
class TempFileManager {
    private static $temp_files = [];
    
    public static function register($file_path) {
        self::$temp_files[] = $file_path;
        
        // Register cleanup on shutdown
        register_shutdown_function([self::class, 'cleanup']);
    }
    
    public static function cleanup() {
        foreach (self::$temp_files as $file) {
            if (file_exists($file)) {
                @unlink($file);
            }
        }
        self::$temp_files = [];
    }
}

// Usage in upload handlers
try {
    $temp_path = $_FILES['image']['tmp_name'];
    TempFileManager::register($temp_path);
    
    // Process image...
    
} catch (Exception $e) {
    TempFileManager::cleanup(); // Explicit cleanup on error
    throw $e;
}
```

## 5. Implementation Plan (Revised)

### 5.1 Phase 1: Mobile HTTP Client Service (Week 1)
1. **HttpClientService Implementation** - Create centralized HTTP client with retry controls
2. **Idempotency Token Security** - Upgrade to cryptographically secure token generation  
3. **Sync Service Integration** - Retrofit existing sync service to use HttpClientService
4. **Database Index Creation** - Add performance indexes for idempotency and rate limiting

### 5.2 Phase 2: Concurrency and Resource Management (Week 2)  
1. **Sync Queue Implementation** - Add concurrency controls for mobile sync operations
2. **Resource Monitoring** - Enhanced logging for memory and processing usage
3. **Cleanup Automation** - Automated cleanup for rate limit and security tables
4. **Error Handling Enhancement** - Improve error categorization and logging

### 5.3 Phase 3: Testing and Validation (Week 3)
1. **End-to-End Testing** - Poor network simulation, concurrent users
2. **Performance Testing** - Rate limiting under load, sync queue efficiency
3. **Security Validation** - Confirm all resolved security fixes remain effective
4. **Mobile App Integration** - Update all HTTP calls to use HttpClientService

### 5.4 Phase 4: Monitoring and Documentation (Week 4)
1. **Monitoring Setup** - Alerts for retry loops, rate limit violations, sync failures
2. **Documentation Updates** - API documentation, deployment guides
3. **Training Materials** - Team training on new retry policies and monitoring
4. **Performance Baseline** - Establish metrics for system performance monitoring

## 6. Testing Strategy

### 6.1 Mobile Sync Reliability Testing
- **Network Simulation** - Test sync under packet loss, high latency, intermittent connectivity
- **Retry Logic Validation** - Verify HttpClientService respects maxRetries limits
- **Jitter Effectiveness** - Confirm ±25% jitter prevents request synchronization
- **Concurrency Testing** - Multiple learners syncing simultaneously with queue limits
- **Idempotency Verification** - Ensure secure tokens prevent duplicates under retry scenarios

### 6.2 Performance Testing  
- **Database Load** - Rate limiting queries under high request volume
- **Sync Queue Performance** - Bulk synchronization with concurrency limits
- **Memory Usage** - Resource monitoring during image processing and sync operations
- **Token Generation Performance** - Cryptographically secure token generation impact

### 6.3 Integration Testing
- **HttpClientService Integration** - All existing HTTP calls retrofit correctly
- **Backward Compatibility** - Existing functionality unaffected by new service
- **Error Handling** - Proper error propagation through new service layer
- **Monitoring Integration** - Correct metrics collection and alerting

## 7. Monitoring & Alerting

### 7.1 Sync Reliability Monitoring
- **Retry Rate Tracking** - Average attempts per request (target: ≤ 1.5)
- **Sync Success Rate** - Percentage of successful sync operations (target: ≥ 95%)
- **Queue Depth Monitoring** - Sync queue backlog and processing time
- **Token Collision Detection** - Monitor for any idempotency token collisions

### 7.2 Performance Monitoring  
- **Database Query Performance** - Index effectiveness for rate limiting and idempotency
- **Memory Usage Patterns** - Resource consumption during peak sync operations
- **HTTP Client Metrics** - Request timing, failure rates by endpoint
- **Concurrency Impact** - System performance under various concurrency loads

### 7.3 Security Monitoring
- **Rate Limit Effectiveness** - Violations per endpoint, protection activation
- **Authentication Success Rate** - Fail-closed behavior verification
- **File Access Attempts** - Evidence file protection effectiveness
- **Token Security** - Monitoring for predictable token patterns (should be none)

## 8. Risk Mitigation

### 8.1 Deployment Risks
- **Breaking Changes** - HttpClientService integration may affect existing flows
- **Performance Impact** - New retry logic and secure token generation overhead
- **Database Migrations** - Index creation on large tables may cause locks

**Mitigation:**
- Gradual rollout with feature flags for HttpClientService
- Performance baseline testing before deployment
- Off-peak database migration scheduling

### 8.2 Operational Risks
- **Retry Loop Creation** - Misconfigured retry policies causing server overload
- **Token Exhaustion** - Cryptographic random generation performance under load
- **Queue Backlog** - Sync queue overflow during extended network outages

**Mitigation:**
- Strict adherence to retry guidelines (maxRetries ≤ 2)
- Token generation performance testing and optimization
- Queue size limits and overflow handling procedures

---

**Implementation Priority:** Address mobile sync reliability and idempotency security first, then enhance monitoring and performance optimization. All changes must maintain backward compatibility and follow established retry configuration guidelines.

## Response to Design Review Findings

### Review Finding Resolutions

**HIGH Severity Issues (All Resolved):**
1. **Authentication Fail-Closed** - ✅ RESOLVED: No changes needed, current implementation correctly fails closed
2. **Rate Limiting Function Signature** - ✅ RESOLVED: No changes needed, signatures already unified  
3. **Server-Generated Filenames** - ✅ RESOLVED: No changes needed, already implemented with security logging
4. **Retry Jitter Specification** - ✅ ADDRESSED: Specified exact ±25% jitter algorithm in HttpClientService design

**MEDIUM Severity Issues (Addressed):**
5. **Idempotency Token Security** - ✅ ADDRESSED: Upgraded to cryptographically secure token generation design
6. **Evidence File Protection** - ✅ VERIFIED: No changes needed, .htaccess protection confirmed effective

**Implementation Approach:**
- Focus shifted from security fixes (already complete) to mobile sync reliability improvements
- Conservative retry policies following established guidelines (maxRetries ≤ 2)  
- Gradual rollout approach with feature flags and monitoring-first deployment
- Backward compatibility maintained throughout all changes

**Risk Mitigation Applied:**
- Performance baseline establishment before deployment
- Feature flag infrastructure for safe rollout
- Enhanced monitoring and alerting deployment first
- Team training on new retry policies and monitoring procedures
```