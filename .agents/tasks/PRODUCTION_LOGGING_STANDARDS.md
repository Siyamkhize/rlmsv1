# Production Logging Standards for RLMSS

**Document Version:** 1.0  
**Last Updated:** 2024-01-XX  
**Status:** PRODUCTION STANDARD  
**Scope:** All Dart services and PHP endpoints in RLMSS system

---

## 1. LOG WHAT

All logging must be structured and actionable. Log the following information to support diagnostics, security monitoring, and performance analysis:

### Request/Response Metadata
- **Timestamps:** UTC ISO-8601 format (`2024-01-15T14:23:45.123Z`)
- **Request ID / Correlation ID:** Generated UUID per request for end-to-end tracing
- **Endpoint:** API endpoint path or service method name
- **HTTP Status Code:** Response status (200, 409, 500, etc.)
- **Duration:** Processing time in milliseconds
- **HTTP Method:** GET, POST, PUT, DELETE

### Sync & Queue Operations
- **Sync Event Type:** `queue_add`, `queue_dispatch`, `sync_start`, `sync_complete`, `sync_failed`
- **Action Type:** `clock_in`, `clock_out`, `upload_evidence`, `batch_clocking`
- **Retry Count:** Number of retry attempts for this operation
- **Queue Depth:** Number of pending items in sync queue
- **Idempotency Key:** For deduplication tracking (first 8 characters only for logs)
- **Batch Size:** Number of items in batch operations

### Connectivity & Network
- **Connectivity Change Events:** `online`, `offline`, `wifi`, `cellular`
- **Timeout Values:** Configured timeout and whether timeout occurred
- **Network Error Type:** `SocketException`, `TimeoutException`, `HttpException`

### Security & Validation
- **User ID:** Authenticated user identifier (internal system ID, NOT learner ID)
- **Clock Drift:** Time difference between device and server (in seconds) when >5s
- **GPS Accuracy:** When <10m (potential spoofing indicator)
- **Authentication Result:** `success`, `failed`, `expired`
- **Validation Errors:** Failed validation type (e.g., `geofence_violation`, `time_drift_excessive`)

### Idempotency & Deduplication
- **Idempotency Key:** Short identifier (prefix + 8 chars: `idem_a1b2c3d4`)
- **Idempotency Hit/Miss:** Whether key was found in cache (`cache_hit`, `cache_miss`, `cache_expired`)
- **Duplicate Detection:** When duplicate request detected

---

## 2. DO NOT LOG

The following information must **NEVER** appear in logs due to security and privacy requirements:

### Authentication & Credentials
- ❌ Bearer tokens or authentication tokens
- ❌ Session tokens or session IDs
- ❌ JWT payloads (even encoded)
- ❌ Database passwords or connection strings
- ❌ API keys or secrets
- ❌ Password hashes
- ❌ Security question answers
- ❌ HTTP `Authorization` header contents

### Personal Identifiable Information (PII)
- ❌ Learner names (first, last, or full)
- ❌ Learner ID numbers or RSA ID numbers
- ❌ Phone numbers
- ❌ Email addresses
- ❌ Physical addresses
- ❌ GPS coordinates (latitude/longitude exact values)
- ❌ Face embeddings or biometric data
- ❌ Signature image data

### Large or Binary Data
- ❌ Base64-encoded images (signatures, face photos)
- ❌ Full request payloads containing images
- ❌ Full SQL queries with data values
- ❌ Stack traces containing file paths with credentials

### System Internals
- ❌ File system paths containing usernames or credentials
- ❌ Database table structures
- ❌ Internal server IP addresses
- ❌ Server configuration details

**Sanitization Rule:** When logging errors, replace sensitive data with placeholders:
- Token: `Bearer ***TOKEN_REDACTED***`
- Learner ID: `learner_***`
- Phone: `+27***`
- GPS: `location_redacted`

---

## 3. LOG FORMAT

All logs must use **structured JSON lines** format for machine parsing and analysis.

### JSON Structure
```json
{
  "timestamp": "2024-01-15T14:23:45.123Z",
  "level": "info",
  "event": "sync_queue_dispatch",
  "correlation_id": "req_a1b2c3d4e5f6",
  "service": "offline_sync_queue",
  "action": "clock_in",
  "status": "success",
  "data": {
    "queue_depth": 5,
    "retry_count": 0,
    "duration_ms": 234,
    "idempotency_key": "idem_x7y8z9"
  }
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `timestamp` | string | ✅ | UTC ISO-8601 timestamp |
| `level` | string | ✅ | `debug`, `info`, `warning`, `error` |
| `event` | string | ✅ | Event type (see Event Types below) |
| `correlation_id` | string | ✅ | Request correlation ID |
| `service` | string | ✅ | Service/module name |
| `action` | string | ⬜ | Action type if applicable |
| `status` | string | ⬜ | `success`, `failed`, `pending`, `timeout` |
| `data` | object | ⬜ | Additional structured data |
| `error` | string | ⬜ | Error message (sanitized) |

### Event Types

**Queue Operations:**
- `queue_add` - Item added to sync queue
- `queue_dispatch` - Item sent to server
- `queue_success` - Item successfully synced
- `queue_failed` - Item sync failed
- `queue_retry` - Retry scheduled

**Sync Operations:**
- `sync_start` - Sync operation started
- `sync_complete` - Sync completed successfully
- `sync_failed` - Sync failed
- `connectivity_change` - Network connectivity changed

**HTTP Operations:**
- `http_request` - HTTP request sent
- `http_response` - HTTP response received
- `http_timeout` - Request timed out
- `http_error` - HTTP error occurred

**Idempotency:**
- `idempotency_hit` - Duplicate request detected
- `idempotency_miss` - New request processed
- `idempotency_expired` - Cached response expired

---

## 4. EXAMPLE LOG ENTRIES

### Example 1: Successful Sync
```json
{
  "timestamp": "2024-01-15T14:23:45.123Z",
  "level": "info",
  "event": "queue_success",
  "correlation_id": "req_abc123def456",
  "service": "offline_sync_queue",
  "action": "clock_in",
  "status": "success",
  "data": {
    "queue_depth": 3,
    "retry_count": 0,
    "duration_ms": 234,
    "idempotency_key": "idem_7x8y9z",
    "http_status": 200
  }
}
```

### Example 2: Failed Sync with Retry
```json
{
  "timestamp": "2024-01-15T14:25:12.456Z",
  "level": "warning",
  "event": "queue_retry",
  "correlation_id": "req_def456ghi789",
  "service": "offline_sync_queue",
  "action": "upload_evidence",
  "status": "failed",
  "data": {
    "queue_depth": 8,
    "retry_count": 2,
    "next_retry_seconds": 120,
    "error_type": "TimeoutException"
  },
  "error": "Request timeout after 30s"
}
```

### Example 3: Image Upload Timeout
```json
{
  "timestamp": "2024-01-15T14:30:00.789Z",
  "level": "error",
  "event": "http_timeout",
  "correlation_id": "req_ghi789jkl012",
  "service": "manual_clocking_evidence_sync",
  "action": "upload_evidence",
  "status": "timeout",
  "data": {
    "endpoint": "/save_manual_clocking_images.php",
    "timeout_ms": 30000,
    "retry_count": 1,
    "payload_size_kb": 250
  },
  "error": "Connection timeout during image upload"
}
```

### Example 4: Idempotency Duplicate Detected
```json
{
  "timestamp": "2024-01-15T14:35:22.111Z",
  "level": "info",
  "event": "idempotency_hit",
  "correlation_id": "req_jkl012mno345",
  "service": "offline_sync_queue",
  "action": "clock_in",
  "status": "duplicate",
  "data": {
    "idempotency_key": "idem_p9q8r7",
    "original_timestamp": "2024-01-15T14:34:50.000Z",
    "cache_age_seconds": 32
  }
}
```

### Example 5: Connectivity Lost/Restored
```json
{
  "timestamp": "2024-01-15T14:40:05.333Z",
  "level": "info",
  "event": "connectivity_change",
  "correlation_id": "system_event",
  "service": "persistent_sync",
  "status": "offline",
  "data": {
    "previous_state": "wifi",
    "current_state": "none",
    "queue_depth": 12,
    "pending_batches": 2
  }
}
```

```json
{
  "timestamp": "2024-01-15T14:45:30.555Z",
  "level": "info",
  "event": "connectivity_change",
  "correlation_id": "system_event",
  "service": "persistent_sync",
  "status": "online",
  "data": {
    "previous_state": "none",
    "current_state": "cellular",
    "queue_depth": 12,
    "sync_triggered": true
  }
}
```

---

## 5. CORRELATION IDs

Correlation IDs enable tracing a single operation through multiple services and systems.

### Generation Rules
- **Client-side:** Generate UUID v4 at start of user action: `final correlationId = Uuid().v4()`
- **Format:** Prefix with `req_` for readability: `req_a1b2c3d4e5f6`
- **Propagation:** Include in all HTTP requests as `X-Request-ID` header
- **Server-side:** Extract from header or generate if missing: `$_SERVER['HTTP_X_REQUEST_ID'] ?? generateUuid()`
- **Response:** Server returns same ID in response header: `X-Request-ID: req_a1b2c3d4e5f6`

### Correlation Flow Example

**User taps "Clock In" button**

1. **Dart (Client):** Generate correlation ID `req_abc123`
   - Log: `{"event": "queue_add", "correlation_id": "req_abc123", "action": "clock_in"}`

2. **Offline Queue Service:** Store with correlation ID
   - Log: `{"event": "queue_dispatch", "correlation_id": "req_abc123", "status": "pending"}`

3. **HTTP Request:** Include header `X-Request-ID: req_abc123`
   - Log: `{"event": "http_request", "correlation_id": "req_abc123", "endpoint": "/save_manual_clockin.php"}`

4. **PHP Server:** Extract correlation ID from header
   - Log: `{"event": "request_received", "correlation_id": "req_abc123", "endpoint": "save_manual_clockin"}`

5. **Database Insert:** Process with correlation ID in context
   - Log: `{"event": "database_insert", "correlation_id": "req_abc123", "table": "manual_clocking"}`

6. **HTTP Response:** Return with same `X-Request-ID` header
   - Log: `{"event": "request_complete", "correlation_id": "req_abc123", "status": 200, "duration_ms": 245}`

7. **Dart (Client):** Receive response and mark as synced
   - Log: `{"event": "queue_success", "correlation_id": "req_abc123", "status": "success"}`

**Result:** Searching logs for `req_abc123` shows complete end-to-end flow

---

## 6. RETENTION & LOG LEVELS

### Retention Policy

| Environment | Retention Period | Rotation |
|-------------|-----------------|----------|
| **Development** | 7 days | Daily |
| **Staging** | 30 days | Daily |
| **Production** | 90 days | Daily |

### Log Level Severity Mapping

| Level | Use When | Example |
|-------|----------|---------|
| **debug** | Development diagnostics only | Variable values, detailed flow |
| **info** | Normal operations, state changes | Sync started, queue dispatched |
| **warning** | Recoverable errors, retries | Network timeout, retry scheduled |
| **error** | Operation failures, system issues | Sync failed permanently, auth failed |

### Environment Configuration

```dart
// Development: verbose logging
const LOG_LEVEL = 'debug';
const LOG_TO_FILE = true;
const LOG_TO_CONSOLE = true;

// Production: essential logging only
const LOG_LEVEL = 'info';
const LOG_TO_FILE = true;
const LOG_TO_CONSOLE = false; // Suppress console logs in prod
```

### File Rotation Example (Dart)
```dart
// Keep last 7 days only (development)
final logsDir = Directory('${appDocDir}/logs');
final files = logsDir.listSync()
  .where((f) => f.path.endsWith('.log'))
  .map((f) => File(f.path))
  .toList();

files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

// Delete files older than 7 days
for (final file in files.skip(7)) {
  await file.delete();
}
```

---

## 7. IMPLEMENTATION GUIDELINES

### Dart Services (Client-Side)

**DO:**
- ✅ Use structured logger helper: `_log('info', 'queue_add', {'action': 'clock_in'})`
- ✅ Generate correlation IDs at start of user actions
- ✅ Include correlation ID in all HTTP request headers
- ✅ Log sync queue depth for diagnostics
- ✅ Log retry counts and backoff schedules
- ✅ Write logs to application documents directory (rotated daily)

**DON'T:**
- ❌ Use `print()` or `debugPrint()` with unstructured strings
- ❌ Log full HTTP request/response bodies
- ❌ Log authentication tokens or headers
- ❌ Log learner PII (names, IDs, phone numbers)
- ❌ Log image data or large payloads

### PHP Endpoints (Server-Side)

**DO:**
- ✅ Use structured logger helper: `log_request($correlationId, $endpoint, $userId, $data)`
- ✅ Extract correlation ID from `$_SERVER['HTTP_X_REQUEST_ID']`
- ✅ Return correlation ID in response header
- ✅ Log HTTP status codes and processing time
- ✅ Log idempotency key (first 8 chars only)
- ✅ Write logs to `/var/log/rlmss/api_YYYYMMDD.log`

**DON'T:**
- ❌ Use `error_log()` with unstructured strings
- ❌ Log SQL queries with actual data values
- ❌ Log database connection strings
- ❌ Expose internal system details in error responses
- ❌ Log full stack traces to client (log server-side only)

---

## 8. SECURITY CONSIDERATIONS

### Log Access Control
- Logs contain sensitive operational data (user IDs, processing times)
- Restrict log file access to authorized personnel only
- Use file permissions: `chmod 640` (owner read/write, group read)
- Store logs outside web root to prevent HTTP access

### Sanitization Functions

**Dart:**
```dart
String sanitizeToken(String? token) {
  if (token == null || token.isEmpty) return 'none';
  return '***TOKEN_REDACTED***';
}

String sanitizeUserId(int? userId) {
  if (userId == null) return 'anonymous';
  return 'user_$userId'; // Use internal ID, not learner ID
}
```

**PHP:**
```php
function sanitize_error_message($error) {
  // Remove SQL query details
  $error = preg_replace('/SELECT .+ FROM .+/i', 'SQL_QUERY_REDACTED', $error);
  // Remove file paths
  $error = preg_replace('/\/var\/www\/.+/', 'PATH_REDACTED', $error);
  return $error;
}
```

### Audit Log Integrity
- Production logs should be write-once (append-only)
- Consider log forwarding to centralized logging system (future enhancement)
- Regular log review for security anomalies (excessive failures, auth attempts)

---

## 9. MONITORING & ALERTING

Use logs to trigger alerts for critical conditions:

| Condition | Alert Threshold | Action |
|-----------|----------------|--------|
| **High retry rate** | >20% of syncs require retry | Investigate network/server issues |
| **Queue depth growth** | Queue >50 items for >30 min | Check server availability |
| **Excessive clock drift** | >5 devices with >30s drift | Potential time manipulation |
| **Auth failure spike** | >10 failures in 5 min | Potential security incident |
| **Timeout spike** | >30% of requests timeout | Server performance issue |

### Log Analysis Examples

**Find all failed sync operations today:**
```bash
grep '"event":"queue_failed"' logs/sync_20240115.log | jq -r '[.timestamp, .action, .error]'
```

**Calculate average sync duration:**
```bash
grep '"event":"queue_success"' logs/sync_20240115.log | jq -r '.data.duration_ms' | awk '{sum+=$1; n++} END {print sum/n}'
```

**Identify devices with excessive retries:**
```bash
grep '"retry_count"' logs/sync_20240115.log | jq -r 'select(.data.retry_count > 3) | [.correlation_id, .data.retry_count]'
```

---

## 10. COMPLIANCE & PRIVACY

### POPIA Compliance (South Africa)
- Logs must not contain learner personal information
- Learner consent not required for operational logs (legitimate interest)
- Logs must be secured against unauthorized access
- Data retention policy must be documented and enforced

### Audit Requirements
- All authentication attempts must be logged (success and failure)
- All data modification operations must be traceable
- Correlation IDs enable audit trail reconstruction

---

## SUMMARY CHECKLIST

Before deploying to production, verify:

- [ ] All services use structured JSON logging
- [ ] No authentication tokens in logs
- [ ] No learner PII in logs
- [ ] Correlation IDs propagate through full request chain
- [ ] Log files have restricted permissions (640)
- [ ] Log rotation configured (7 days dev, 90 days prod)
- [ ] Sanitization functions applied to all error messages
- [ ] Monitoring alerts configured for critical conditions

---

**End of Production Logging Standards**

Document Owner: RLMSS Development Team  
Review Frequency: Quarterly  
Next Review: 2024-04-XX
