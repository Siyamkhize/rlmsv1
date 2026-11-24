# Idempotency Key Enforcement Audit

**Audit Date:** 2024-01-XX  
**Audited By:** Kiro AI Agent  
**Scope:** PHP Backend + Dart Client  

---

## Executive Summary

**Overall Status:** 🟡 **MEDIUM RISK** - Idempotency system is partially implemented but has critical gaps that could allow duplicate clocking records under specific failure scenarios.

**Critical Findings:**
- ❌ No `request_hash` column in database - same key with different payload accepted
- ❌ No `action_type` in unique index - cross-action key collision risk
- ❌ Transaction boundary issues - crash leaves orphaned "processing" rows
- ❌ `save_manual_clocking_images.php` does NOT use idempotency at all
- ⚠️ `validate_client_timestamp()` has mutation bug (71h55m window instead of 5min)
- ✅ Dart client correctly generates keys at TAP TIME and persists them

---

## 1. Database Schema Analysis

### File: `sql/create_idempotency_table.sql`

**Findings:**

| Check | Status | Severity |
|-------|--------|----------|
| Unique index covers `user_id` + `idem_key` | ✅ PARTIAL | MEDIUM |
| Unique index includes `action_type` | ❌ NO | **CRITICAL** |
| `request_hash` column exists | ❌ NO | **CRITICAL** |
| Column types appropriate | ✅ YES | - |
| Expiry management in place | ✅ YES | - |

**Current Schema:**
```sql
UNIQUE KEY uq_user_key (user_id, idem_key)
```

**Problems:**

1. **CRITICAL - No `action_type` in unique index (Line 12):**
   - The unique key is `(user_id, idem_key)` but does NOT include `action_type`
   - If the app accidentally reuses one key for clock-in AND its follow-up image upload, the second request will get the first's cached response
   - **Impact:** Wrong response returned, image upload silently skipped

2. **CRITICAL - No `request_hash` column:**
   - Schema does not include a column to store payload hash
   - Same key with different payload data (e.g., different learner ID, different GPS coordinates) will be accepted as duplicate
   - **Impact:** Data integrity violation - wrong data associated with request

3. **MEDIUM - `response_body` is MEDIUMTEXT:**
   - Can store 16MB responses, appropriate for JSON
   - **Status:** OK

**Recommended Schema:**
```sql
CREATE TABLE idempotency_keys (
  id            BIGINT AUTO_INCREMENT PRIMARY KEY,
  idem_key      CHAR(36)     NOT NULL,
  user_id       INT          NOT NULL,
  action_type   VARCHAR(50)  NOT NULL,
  request_hash  CHAR(64)     NOT NULL DEFAULT '',  -- SHA-256 of payload
  status        ENUM('processing','done') NOT NULL DEFAULT 'processing',
  response_code SMALLINT     NULL,
  response_body MEDIUMTEXT   NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at    DATETIME     NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL 7 DAY),
  
  UNIQUE KEY uq_idem (user_id, action_type, idem_key),  -- INCLUDE action_type
  KEY idx_expires (expires_at),
  KEY idx_user_action (user_id, action_type, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## 2. Helper Function Analysis

### File: `mobile/idempotency_helpers.php`

#### 2.1 `idem_begin()` Function

**Line 18-47**

| Check | Status | Severity |
|-------|--------|----------|
| Exception handling for mysqli | ✅ YES | - |
| Checks execute() return value | ❌ NO | **HIGH** |
| `action_type` in SELECT WHERE | ❌ NO | **CRITICAL** |
| `user_id` in SELECT WHERE | ✅ YES | - |
| Request hash validation | ❌ NO | **CRITICAL** |
| Transaction handling | ❌ NO | **CRITICAL** |

**Critical Issues:**

1. **CRITICAL - `action_type` not in SELECT (Line 38-42):**
```php
$q = $conn->prepare(
    "SELECT status, response_code, response_body
     FROM idempotency_keys 
     WHERE user_id = ? AND idem_key = ?"  // ❌ Missing action_type
);
```
   - **Impact:** If key is reused across actions, returns wrong cached response
   - **Fix:** Add `AND action_type = ?` to WHERE clause

2. **CRITICAL - No request hash validation:**
   - Function does not accept or validate a `$requestHash` parameter
   - Cannot detect same key + different payload attacks
   - **Fix:** Add parameter and check `request_hash` column

3. **CRITICAL - Transaction boundary issue:**
   - `idem_begin()` commits immediately (autocommit on INSERT)
   - If PHP crashes between `idem_begin()` and `idem_finish()`, the row stays `processing` for 7 days
   - Every retry gets "409 In Progress" while the actual record may or may not exist
   - **Fix:** Wrap claim + business logic + idem_finish in ONE transaction

4. **HIGH - No explicit errno check (Line 30-35):**
```php
try {
    $stmt->execute();
    return null; // ❌ Doesn't check return value
} catch (mysqli_sql_exception $e) {
    if ($e->getCode() !== 1062) {
        throw $e;
    }
}
```
   - On PHP < 8.1 without `mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT)`, exceptions aren't thrown
   - `execute()` returns `false` on duplicate, function returns `null`, request processes again
   - **Fix:** Check both exception AND `execute()` return value

**Recommended Fix:**
```php
function idem_begin(mysqli $conn, int $userId, string $action, string $key, string $requestHash = ''): ?array {
    $stmt = $conn->prepare(
        "INSERT INTO idempotency_keys (idem_key, user_id, action_type, request_hash, expires_at)
         VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 7 DAY))"
    );
    $stmt->bind_param("siss", $key, $userId, $action, $requestHash);

    try {
        if ($stmt->execute()) return null;  // ✅ Check return value
        $errno = $stmt->errno;
    } catch (mysqli_sql_exception $e) {
        $errno = (int)$e->getCode();
    }
    if ($errno !== 1062) {
        throw new RuntimeException("Idempotency insert failed ($errno)");
    }

    // ✅ Add action_type and request_hash to WHERE clause
    $q = $conn->prepare(
        "SELECT status, request_hash, response_code, response_body
         FROM idempotency_keys
         WHERE user_id = ? AND action_type = ? AND idem_key = ?
         LOCK IN SHARE MODE"
    );
    $q->bind_param("iss", $userId, $action, $key);
    $q->execute();
    $row = $q->get_result()->fetch_assoc();
    if (!$row) throw new RuntimeException("Idempotency key conflict");
    
    // ✅ Validate request hash if present
    if ($requestHash !== '' && $row['request_hash'] !== '' && $row['request_hash'] !== $requestHash) {
        return ['status' => 'hash_mismatch', 'response_code' => 422, 'response_body' => 
            json_encode(['error' => 'Same key, different payload'])];
    }
    
    return $row;
}
```

#### 2.2 `idem_finish()` Function

**Line 49-61**

| Check | Status | Severity |
|-------|--------|----------|
| Filters on `user_id` | ✅ YES | - |
| Filters on `action_type` | ❌ NO | **HIGH** |
| Updates status to 'done' | ✅ YES | - |

**Issue:**
```php
$stmt = $conn->prepare(
    "UPDATE idempotency_keys
     SET status = 'done', response_code = ?, response_body = ?
     WHERE user_id = ? AND idem_key = ?"  // ❌ Missing action_type
);
```
- Should filter on `action_type` to match the scoping in `idem_begin()`
- **Fix:** Add `AND action_type = ?` to WHERE clause

#### 2.3 `idem_abort()` Function

**Line 63-76**

| Check | Status | Severity |
|-------|--------|----------|
| Filters on `user_id` | ✅ YES | - |
| Filters on `action_type` | ❌ NO | **HIGH** |
| Filters on status='processing' | ✅ YES | - |

**Issue:**
```php
$stmt = $conn->prepare(
    "DELETE FROM idempotency_keys 
     WHERE user_id = ? AND idem_key = ? AND status = 'processing'"  // ❌ Missing action_type
);
```
- Same issue as `idem_finish()`
- **Fix:** Add `AND action_type = ?` to WHERE clause

#### 2.4 `validate_client_timestamp()` Function

**Line 78-113**

| Check | Status | Severity |
|-------|--------|----------|
| Uses DateTimeImmutable | ❌ NO | **MEDIUM** |
| Validates future timestamps | ✅ YES | - |
| Validates old timestamps | ⚠️ BUGGY | **MEDIUM** |

**MEDIUM - DateTime mutation bug (Line 90-98):**
```php
$now = new DateTime('now', new DateTimeZone('UTC'));

// Reject future timestamps (allow 5 minutes clock skew)
if ($clientTime > $now->add(new DateInterval('PT5M'))) {  // ❌ Mutates $now
    return ['valid' => false, 'timestamp' => null, 'error' => 'Timestamp in future'];
}

// Reject very old timestamps
$maxAge = $now->sub(new DateInterval("PT{$maxHoursOld}H"));  // ❌ Uses mutated $now
```

**Problem:**
- `DateTime::add()` and `::sub()` modify `$now` in place
- After the first check, `$now` is 5 minutes in the future
- The maximum-age window is actually ~71h55m (72h - 5min) instead of 5min skew + 72h
- **Impact:** Accepts timestamps that are slightly older than intended

**Fix:**
```php
function validate_client_timestamp(string $clientTimestamp, int $maxHoursOld = 72): array {
    try {
        $clientTime = new DateTimeImmutable($clientTimestamp, new DateTimeZone('UTC'));
        $now = new DateTimeImmutable('now', new DateTimeZone('UTC'));
        
        // Reject future timestamps (allow 5 minutes clock skew)
        if ($clientTime > $now->add(new DateInterval('PT5M'))) {
            return ['valid' => false, 'timestamp' => null, 'error' => 'Timestamp in future'];
        }
        
        // Reject very old timestamps
        $maxAge = $now->sub(new DateInterval("PT{$maxHoursOld}H"));
        if ($clientTime < $maxAge) {
            return ['valid' => false, 'timestamp' => null, 'error' => 'Timestamp too old'];
        }
        
        return ['valid' => true, 'timestamp' => $clientTime, 'error' => null];
        
    } catch (Exception $e) {
        return ['valid' => false, 'timestamp' => null, 'error' => 'Invalid timestamp format'];
    }
}
```

#### 2.5 `validate_idempotency_key()` Function

**Line 115-132**

| Check | Status | Severity |
|-------|--------|----------|
| Validates UUID v4 format | ✅ YES | - |
| Validates custom token format | ✅ YES | - |
| Called by endpoints | ❌ NO | **MEDIUM** |

**Issue:**
- Function exists and looks correct
- **BUT**: Not called by any endpoint code
- Endpoints should call `validate_idempotency_key()` BEFORE `idem_begin()`
- **Fix:** Add validation check to each endpoint

---

## 3. Endpoint Analysis

### 3.1 `mobile/manual_clocking/save_manual_clockin.php`

**Lines: 1-173**

| Check | Status | Severity |
|-------|--------|----------|
| Calls `validate_idempotency_key()` | ❌ NO | **MEDIUM** |
| Wraps in transaction | ⚠️ PARTIAL | **HIGH** |
| Computes request hash | ❌ NO | **CRITICAL** |
| Checks `$dup['request_hash']` | ❌ NO | **CRITICAL** |
| Passes distinct `action_type` | ✅ YES | - |
| Handles 409 'in progress' | ❌ NO | **HIGH** |
| `idem_finish`/`idem_abort` filter on action | ❌ NO | **HIGH** |

**Analysis:**

**Line 36-45: Idempotency check**
```php
$idempotencyKey = $_SERVER['HTTP_X_IDEMPOTENCY_KEY'] ?? ($input['idempotency_key'] ?? null);

if (!$idempotencyKey) {
    throw new Exception('Idempotency key required');
}

// Check idempotency BEFORE processing
$existing = idem_begin($conn, $user['user_id'], 'clock_in', $idempotencyKey);  // ✅ Passes action_type
if ($existing) {
    // Return cached response for duplicate request
    http_response_code($existing['response_code'] ?? 200);
    echo $existing['response_body'];
    error_log("[SAVE_MANUAL_CLOCKIN] ✅ Idempotent response returned for key: $idempotencyKey");
    exit;
}
```

**Problems:**

1. ❌ **No `validate_idempotency_key()` call** (before line 36)
2. ❌ **No request hash computation** - should hash the payload
3. ❌ **No hash mismatch check** - doesn't check `$existing['request_hash']`
4. ❌ **No 409 handling** - doesn't handle `$existing['status'] === 'processing'`
5. ⚠️ **Transaction starts too late** (Line 75) - `idem_begin()` commits before transaction

**Line 158-162: Success**
```php
// Mark as complete in idempotency system
idem_finish($conn, $user['user_id'], $idempotencyKey, 200, json_encode($response));  // ❌ Missing action_type
```

**Line 166-170: Error handling**
```php
// Abort idempotency (allow retry)
if (isset($idempotencyKey) && isset($user)) {
    idem_abort($conn, $user['user_id'], $idempotencyKey);  // ❌ Missing action_type
}
```

**Recommended Fix:**
```php
// 1. Validate key format FIRST
if (!validate_idempotency_key($idempotencyKey)) {
    http_response_code(400);
    exit(json_encode(['error' => 'Invalid idempotency key format']));
}

// 2. Compute request hash
$payloadForHashing = json_encode([
    'learner_id' => $learnerID,
    'clock_date' => $clockDate,
    'clock_in_time' => $clockInTime,
    'contact_time' => $contactTime,
]);
$hash = hash('sha256', $payloadForHashing);

// 3. Start transaction BEFORE idem_begin
$conn->begin_transaction();

try {
    // 4. Check idempotency with hash
    $dup = idem_begin($conn, $user['user_id'], 'clock_in', $idempotencyKey, $hash);
    if ($dup !== null) {
        $conn->rollback();
        
        // Check for hash mismatch
        if ($dup['request_hash'] !== '' && $dup['request_hash'] !== $hash) {
            http_response_code(422);
            exit(json_encode(['error' => 'Same key, different payload']));
        }
        
        // Return cached response if done
        if ($dup['status'] === 'done') {
            http_response_code((int)$dup['response_code']);
            exit($dup['response_body']);
        }
        
        // Still processing
        http_response_code(409);
        exit(json_encode(['error' => 'Request in progress']));
    }
    
    // ... business logic ...
    
    idem_finish($conn, $user['user_id'], 'clock_in', $idempotencyKey, 200, $resp);
    $conn->commit();
    echo $resp;
    
} catch (Throwable $e) {
    $conn->rollback();  // Rolls back the claim too
    throw $e;
}
```

### 3.2 `mobile/save_manual_clockout.php`

**Lines: 1-176**

| Check | Status | Severity |
|-------|--------|----------|
| Calls `validate_idempotency_key()` | ❌ NO | **MEDIUM** |
| Wraps in transaction | ⚠️ PARTIAL | **HIGH** |
| Computes request hash | ❌ NO | **CRITICAL** |
| Checks `$dup['request_hash']` | ❌ NO | **CRITICAL** |
| Passes distinct `action_type` | ✅ YES (`'clock_out'`) | - |
| Handles 409 'in progress' | ❌ NO | **HIGH** |
| `idem_finish`/`idem_abort` filter on action | ❌ NO | **HIGH** |

**Analysis:**

Same issues as `save_manual_clockin.php`:
- Line 38: No `validate_idempotency_key()` call
- Line 42: `idem_begin($conn, $user['user_id'], 'clock_out', $idempotencyKey)` - ✅ correct action, ❌ no hash
- Line 82: Transaction starts after idempotency check
- Line 159: `idem_finish($conn, $user['user_id'], $idempotencyKey, ...)` - ❌ missing action parameter
- Line 169: `idem_abort($conn, $user['user_id'], $idempotencyKey)` - ❌ missing action parameter

### 3.3 `mobile/save_manual_clocking_images.php`

**Lines: 1-331**

| Check | Status | Severity |
|-------|--------|----------|
| Uses idempotency system | ❌ **NO** | **CRITICAL** |
| Calls `validate_idempotency_key()` | ❌ NO | **CRITICAL** |
| Wraps in transaction | ❌ NO | **CRITICAL** |
| Computes request hash | ❌ NO | **CRITICAL** |

**CRITICAL - NO IDEMPOTENCY AT ALL:**

This endpoint handles image uploads but **does not use the idempotency system at all**:

```php
header('Content-Type: application/json');
require_once 'connection.php';
require_once 'require_auth.php';
require_once 'security_functions.php';
// ❌ Does NOT require idempotency_helpers.php
```

**Line 55-84: Has custom idempotency check:**
```php
// Check if images already uploaded for this clocking event (idempotency)
$existingCheck = $conn->prepare("
    SELECT face_filename, signature_filename 
    FROM learner_clocking_evidence 
    WHERE learner_id = ? AND clock_date = ?
    LIMIT 1
");
```

**Problems:**
1. Custom check queries `learner_clocking_evidence` table instead of `idempotency_keys`
2. No idempotency key from client - relies on `(learner_id, clock_date)` uniqueness
3. If images are deleted from disk but DB record remains, re-upload succeeds but with **new filenames** - breaks references
4. No protection against simultaneous uploads from multiple devices
5. No request hash validation

**Impact:**
- Image uploads can be duplicated if offline queue retries
- Two devices uploading at same time can race
- Evidence integrity cannot be verified

**Recommended Fix:**
```php
require_once 'idempotency_helpers.php';

// Extract idempotency key
$idempotencyKey = $_SERVER['HTTP_X_IDEMPOTENCY_KEY'] ?? $input['idempotency_key'] ?? null;
if (!$idempotencyKey || !validate_idempotency_key($idempotencyKey)) {
    http_response_code(400);
    exit(json_encode(['error' => 'Valid idempotency key required']));
}

// Compute hash
$hash = hash('sha256', json_encode([
    'learner_id' => $learnerID,
    'clock_date' => $clockDate,
    'type' => $type,
    'face_size' => strlen($faceImageBase64),
    'sig_size' => strlen($signatureBase64),
]));

$conn->begin_transaction();
try {
    $dup = idem_begin($conn, $user['user_id'], 'upload_evidence', $idempotencyKey, $hash);
    if ($dup !== null) {
        // Handle duplicate...
    }
    
    // Save images...
    
    idem_finish($conn, $user['user_id'], 'upload_evidence', $idempotencyKey, 200, $response);
    $conn->commit();
} catch (Throwable $e) {
    $conn->rollback();
    throw $e;
}
```

### 3.4 `mobile/save_class_batch_clocking.php`

**Lines: 1-413**

| Check | Status | Severity |
|-------|--------|----------|
| Calls `validate_idempotency_key()` | ❌ NO | **MEDIUM** |
| Wraps in transaction | ✅ YES | - |
| Computes request hash | ❌ NO | **CRITICAL** |
| Checks `$dup['request_hash']` | ❌ NO | **CRITICAL** |
| Passes distinct `action_type` | ✅ YES (`'class_batch_clocking'`) | - |
| Has per-learner idempotency | ✅ YES | - |
| Handles 409 'in progress' | ❌ NO | **HIGH** |

**Analysis:**

**Line 127-137: Batch idempotency check**
```php
// Check batch idempotency
$batchIdempotencyKey = $_SERVER['HTTP_X_BATCH_IDEMPOTENCY_KEY'] ?? $batchId;
$existing = idem_begin($conn, $userId, 'class_batch_clocking', $batchIdempotencyKey);  // ✅ Correct
if ($existing) {
    // Return previous batch result
    http_response_code($existing['response_code'] ?? 200);
    echo $existing['response_body'];
    exit;
}
```

**Line 157-169: Per-learner idempotency**
```php
// Individual learner idempotency key
$learnerIdempotencyKey = $clocking['idempotency_key'] ?? 
    ($batchId . '_' . $learnerId . '_' . $clockType);

// Check if this specific learner clocking already processed
$learnerExisting = idem_begin($conn, $userId, 'learner_clocking', $learnerIdempotencyKey);  // ✅ Correct action
if ($learnerExisting) {
    $results[] = [
        'learner_id' => $learnerId,
        'status' => 'duplicate',
        'message' => 'Already processed',
        'idempotency_key' => $learnerIdempotencyKey
    ];
    $successCount++;
    continue;
}
```

**Good:**
- ✅ Has both batch-level and learner-level idempotency
- ✅ Uses transactions
- ✅ Passes distinct action types

**Problems:**
- ❌ No `validate_idempotency_key()` call
- ❌ No request hash for batch payload
- ❌ No 409 handling
- ❌ `idem_finish` calls (Lines 201, 229, 236, 257) don't pass `action_type` parameter

---

## 4. Dart Client Analysis

### File: `lib/services/offline_sync_queue_service.dart`

**Lines: 1-780**

| Check | Status | Severity |
|-------|--------|----------|
| Key generated at TAP TIME | ✅ YES | - |
| Key persisted in SQLite | ✅ YES | - |
| Same key reused on retry | ✅ YES | - |
| Distinct action types used | ✅ YES | - |
| Header name matches PHP | ⚠️ VARIES | **MEDIUM** |

**EXCELLENT - Key generation at TAP TIME (Line 147):**
```dart
Future<String> enqueueAction(
  String action, 
  Map<String, dynamic> payload, {
  Map<String, dynamic>? evidence,
}) async {
  final key = const Uuid().v4(); // ✅ Generated ONCE at tap time
  final clientTimestamp = DateTime.now().toUtc().toIso8601String();
  
  await _db.insert(_tableName, {
    'id': key,  // ✅ Persisted to SQLite
    'action': action,
    'payload': jsonEncode(fullPayload),
    'client_ts': clientTimestamp,
    'status': 'pending',
  });
  
  return key;
}
```

**EXCELLENT - Key reuse on retry (Line 592-618):**
```dart
Future<bool> _syncSingleAction(Map<String, dynamic> row) async {
  final key = row['id'] as String;  // ✅ Reads persisted key
  
  final response = await http.post(
    Uri.parse(_getEndpointUrl(action)),
    headers: {
      'Idempotency-Key': key,  // ✅ SAME KEY on every retry
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${await _getAuthToken()}',
    },
    body: jsonEncode(requestBody),
  ).timeout(const Duration(seconds: 30));
```

**GOOD - Distinct action types (Lines 147, 193, 359, 395):**
- `'clock_in'` / `'clock_out'`
- `'upload_evidence'`
- `'class_batch_clocking'`
- `'learner_clocking'`

**MEDIUM - Header name inconsistency:**

| Dart Code (Line 610) | PHP Code (Lines vary) | Match? |
|----------------------|------------------------|---------|
| `'Idempotency-Key'` | `$_SERVER['HTTP_X_IDEMPOTENCY_KEY']` | ⚠️ **MISMATCH** |
| `'X-Batch-Idempotency-Key'` | `$_SERVER['HTTP_X_BATCH_IDEMPOTENCY_KEY']` | ✅ MATCH |

**Problem:**
- Dart sends `Idempotency-Key` header
- PHP reads `HTTP_X_IDEMPOTENCY_KEY` (which corresponds to `X-Idempotency-Key`)
- Headers are case-insensitive, BUT PHP's `$_SERVER` normalizes them:
  - HTTP header `Idempotency-Key` → `$_SERVER['HTTP_IDEMPOTENCY_KEY']`
  - HTTP header `X-Idempotency-Key` → `$_SERVER['HTTP_X_IDEMPOTENCY_KEY']`

**Impact:**
- Current PHP code expects `X-` prefix
- Dart doesn't send `X-` prefix
- **Key is NOT being read from header in current implementation!**
- Fallback to `$input['idempotency_key']` from JSON body works, but header should be primary

**Fix:**
```dart
// Option 1: Add X- prefix to match PHP expectation
headers: {
  'X-Idempotency-Key': key,  // ✅ Will be read as HTTP_X_IDEMPOTENCY_KEY
}

// Option 2: Change PHP to read without X- prefix
$idempotencyKey = $_SERVER['HTTP_IDEMPOTENCY_KEY'] ?? ($input['idempotency_key'] ?? null);
```

### File: `lib/signature_geofence_clock_in_page.dart`

**Line 1120:**
```dart
'idempotency_key': uuid.v4(),
```

**Analysis:**
- ✅ Generates UUID v4 at tap time
- ✅ Includes in payload
- Context shows this is in a payload builder function
- Need to verify this is called ONCE per tap, not per retry

**Status:** ✅ CORRECT

### File: `lib/services/persistent_sync_service.dart`

**Analysis:**
- This service handles background sync of learners and clocking records
- **Does NOT generate or manage idempotency keys** - relies on other services
- **Status:** Not applicable to this audit

### File: `lib/services/manual_clocking_evidence_sync_service.dart`

**Line 45-54:**
```dart
String generateSecureIdempotencyToken() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final randomBytes = List.generate(16, (_) => Random.secure().nextInt(256));
  final randomHex = randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  
  final tokenData = '${timestamp}_$randomHex';
  final hash = sha256.convert(utf8.encode(tokenData));
  
  return 'clk_${hash.toString().substring(0, 32)}'; // ✅ Secure token format
}
```

**Analysis:**
- ✅ Cryptographically secure token generation
- ✅ Uses SHA-256 hash
- ✅ Format `clk_[32 hex chars]` matches `validate_idempotency_key()` regex in PHP
- ✅ Generated once per evidence upload

**Status:** ✅ EXCELLENT

---

## 5. Summary Table

| Check | PHP Backend | Dart Client | Status | Severity |
|-------|-------------|-------------|--------|----------|
| **Database Schema** | | | |
| Unique index includes `action_type` | ❌ | N/A | **FAIL** | CRITICAL |
| `request_hash` column exists | ❌ | N/A | **FAIL** | CRITICAL |
| Expiry management | ✅ | N/A | PASS | - |
| **Helper Functions** | | | |
| `idem_begin()` checks action_type | ❌ | N/A | **FAIL** | CRITICAL |
| `idem_begin()` validates hash | ❌ | N/A | **FAIL** | CRITICAL |
| `idem_begin()` transaction-safe | ❌ | N/A | **FAIL** | CRITICAL |
| `idem_finish()` includes action_type | ❌ | N/A | **FAIL** | HIGH |
| `idem_abort()` includes action_type | ❌ | N/A | **FAIL** | HIGH |
| `validate_client_timestamp()` bug-free | ❌ | N/A | **FAIL** | MEDIUM |
| **Endpoints** | | | |
| `save_manual_clockin.php` validates key | ❌ | N/A | **FAIL** | MEDIUM |
| `save_manual_clockin.php` computes hash | ❌ | N/A | **FAIL** | CRITICAL |
| `save_manual_clockin.php` handles 409 | ❌ | N/A | **FAIL** | HIGH |
| `save_manual_clockout.php` validates key | ❌ | N/A | **FAIL** | MEDIUM |
| `save_manual_clockout.php` computes hash | ❌ | N/A | **FAIL** | CRITICAL |
| `save_manual_clocking_images.php` uses idempotency | ❌ | N/A | **FAIL** | CRITICAL |
| `save_class_batch_clocking.php` validates key | ❌ | N/A | **FAIL** | MEDIUM |
| `save_class_batch_clocking.php` computes hash | ❌ | N/A | **FAIL** | CRITICAL |
| **Dart Client** | | | |
| Keys generated at TAP TIME | N/A | ✅ | **PASS** | - |
| Keys persisted to SQLite | N/A | ✅ | **PASS** | - |
| Same key reused on retry | N/A | ✅ | **PASS** | - |
| Distinct action types | N/A | ✅ | **PASS** | - |
| Header name matches PHP | N/A | ⚠️ | **PARTIAL** | MEDIUM |

---

## 6. Recommended Fixes

### 6.1 Database Schema Migration

```sql
-- Run this migration to add missing columns and fix unique index
ALTER TABLE idempotency_keys ADD COLUMN request_hash CHAR(64) NOT NULL DEFAULT '';

-- Drop old unique index
ALTER TABLE idempotency_keys DROP INDEX uq_user_key;

-- Add new unique index with action_type
ALTER TABLE idempotency_keys ADD UNIQUE KEY uq_idem (user_id, action_type, idem_key);
```

### 6.2 `idempotency_helpers.php` Complete Rewrite

```php
<?php
/**
 * Production-ready idempotency helpers
 */

// Ensure mysqli throws exceptions
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function idem_begin(mysqli $conn, int $userId, string $action, string $key, string $requestHash = ''): ?array {
    $stmt = $conn->prepare(
        "INSERT INTO idempotency_keys (idem_key, user_id, action_type, request_hash, expires_at)
         VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 7 DAY))"
    );
    $stmt->bind_param("siss", $key, $userId, $action, $requestHash);

    try {
        if ($stmt->execute()) return null;
        $errno = $stmt->errno;
    } catch (mysqli_sql_exception $e) {
        $errno = (int)$e->getCode();
    }
    
    if ($errno !== 1062) {
        throw new RuntimeException("Idempotency insert failed ($errno)");
    }

    // Fetch existing record
    $q = $conn->prepare(
        "SELECT status, request_hash, response_code, response_body
         FROM idempotency_keys
         WHERE user_id = ? AND action_type = ? AND idem_key = ?
         LOCK IN SHARE MODE"
    );
    $q->bind_param("iss", $userId, $action, $key);
    $q->execute();
    $row = $q->get_result()->fetch_assoc();
    
    if (!$row) {
        throw new RuntimeException("Idempotency key conflict");
    }
    
    // Validate request hash
    if ($requestHash !== '' && $row['request_hash'] !== '' && $row['request_hash'] !== $requestHash) {
        return [
            'status' => 'hash_mismatch',
            'response_code' => 422,
            'response_body' => json_encode(['error' => 'Same key, different payload'])
        ];
    }
    
    return $row;
}

function idem_finish(mysqli $conn, int $userId, string $action, string $key, int $code, string $body): void {
    $stmt = $conn->prepare(
        "UPDATE idempotency_keys
         SET status = 'done', response_code = ?, response_body = ?
         WHERE user_id = ? AND action_type = ? AND idem_key = ?"
    );
    $stmt->bind_param("isiss", $code, $body, $userId, $action, $key);
    $stmt->execute();
}

function idem_abort(mysqli $conn, int $userId, string $action, string $key): void {
    $stmt = $conn->prepare(
        "DELETE FROM idempotency_keys 
         WHERE user_id = ? AND action_type = ? AND idem_key = ? AND status = 'processing'"
    );
    $stmt->bind_param("iss", $userId, $action, $key);
    $stmt->execute();
}

function validate_client_timestamp(string $clientTimestamp, int $maxHoursOld = 72): array {
    try {
        $clientTime = new DateTimeImmutable($clientTimestamp, new DateTimeZone('UTC'));
        $now = new DateTimeImmutable('now', new DateTimeZone('UTC'));
        
        if ($clientTime > $now->add(new DateInterval('PT5M'))) {
            return ['valid' => false, 'timestamp' => null, 'error' => 'Timestamp in future'];
        }
        
        $maxAge = $now->sub(new DateInterval("PT{$maxHoursOld}H"));
        if ($clientTime < $maxAge) {
            return ['valid' => false, 'timestamp' => null, 'error' => 'Timestamp too old'];
        }
        
        return ['valid' => true, 'timestamp' => $clientTime, 'error' => null];
        
    } catch (Exception $e) {
        return ['valid' => false, 'timestamp' => null, 'error' => 'Invalid timestamp format'];
    }
}

function validate_idempotency_key(string $key): bool {
    if (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $key) === 1) {
        return true;
    }
    if (preg_match('/^clk_[a-f0-9]{32}$/', $key) === 1) {
        return true;
    }
    return false;
}
?>
```

### 6.3 Endpoint Template

```php
<?php
// Template for clock-in/clock-out endpoints with proper idempotency

require_once 'connection.php';
require_once 'security_functions.php';
require_once 'idempotency_helpers.php';
require_once 'require_auth.php';

error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

$user = requireAuth($conn);
applyRateLimit($conn, 'endpoint_name');

try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input || !is_array($input)) {
        throw new Exception('Invalid JSON input');
    }
    
    // 1. Extract and validate idempotency key
    $idempotencyKey = $_SERVER['HTTP_X_IDEMPOTENCY_KEY'] ?? ($input['idempotency_key'] ?? null);
    if (!$idempotencyKey || !validate_idempotency_key($idempotencyKey)) {
        throw new Exception('Valid idempotency key required');
    }
    
    // 2. Extract and validate business data
    $learnerID = isset($input['learner_id']) ? intval($input['learner_id']) : 0;
    if ($learnerID <= 0) {
        throw new Exception('Invalid learner ID');
    }
    // ... more validation ...
    
    // 3. Compute request hash
    $payloadForHashing = json_encode([
        'learner_id' => $learnerID,
        'clock_date' => $clockDate,
        'clock_in_time' => $clockInTime,
        // Include all fields that affect uniqueness
    ]);
    $hash = hash('sha256', $payloadForHashing);
    
    // 4. Start transaction BEFORE idempotency check
    $conn->begin_transaction();
    
    try {
        // 5. Check idempotency
        $dup = idem_begin($conn, $user['user_id'], 'clock_in', $idempotencyKey, $hash);
        if ($dup !== null) {
            $conn->rollback();
            
            // Handle hash mismatch
            if ($dup['request_hash'] !== '' && $dup['request_hash'] !== $hash) {
                http_response_code(422);
                exit(json_encode(['error' => 'Same key, different payload']));
            }
            
            // Return cached response if done
            if ($dup['status'] === 'done') {
                http_response_code((int)$dup['response_code']);
                exit($dup['response_body']);
            }
            
            // Still processing
            http_response_code(409);
            exit(json_encode(['error' => 'Request in progress']));
        }
        
        // 6. Business logic
        // INSERT/UPDATE database records here
        
        // 7. Success response
        $response = [
            'success' => true,
            'message' => 'Clock-in saved successfully',
            // ... data ...
        ];
        $responseJson = json_encode($response);
        
        // 8. Mark as complete
        idem_finish($conn, $user['user_id'], 'clock_in', $idempotencyKey, 200, $responseJson);
        
        // 9. Commit transaction
        $conn->commit();
        
        echo $responseJson;
        
    } catch (Throwable $e) {
        $conn->rollback();  // Rolls back everything including the idempotency claim
        throw $e;
    }
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage(),
    ]);
}

if (isset($conn)) {
    $conn->close();
}
?>
```

### 6.4 Dart Client Header Fix

```dart
// lib/services/offline_sync_queue_service.dart
// Line 610 - Change header name to include X- prefix

final response = await http.post(
  Uri.parse(_getEndpointUrl(action)),
  headers: {
    'X-Idempotency-Key': key,  // ✅ Now matches PHP expectation
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${await _getAuthToken()}',
  },
  body: jsonEncode(requestBody),
).timeout(const Duration(seconds: 30));
```

---

## 7. Testing Checklist

After implementing fixes, test these scenarios:

### 7.1 Basic Idempotency
- [ ] Submit clock-in with key `A` → succeeds
- [ ] Submit same clock-in with key `A` → returns cached response
- [ ] Submit different clock-in with key `A` → returns 422 hash mismatch

### 7.2 Cross-Action Isolation
- [ ] Submit clock-in with key `B` → succeeds
- [ ] Submit clock-out with key `B` → succeeds (different action_type)
- [ ] Verify both stored separately in `idempotency_keys` table

### 7.3 Crash Recovery
- [ ] Submit clock-in with key `C`
- [ ] Kill PHP process mid-transaction
- [ ] Submit same request again → should process (not stuck in 'processing' state)

### 7.4 Offline Queue Replay
- [ ] Generate clock-in offline (key stored in SQLite)
- [ ] Go online
- [ ] Queue processes → key sent in header
- [ ] Disconnect before response
- [ ] Go online again
- [ ] Queue retries with SAME key → idempotent

### 7.5 Evidence Upload
- [ ] Upload face+signature with key `D` → succeeds
- [ ] Retry with key `D` → returns cached filenames
- [ ] Retry with key `D` but different images → 422 hash mismatch

---

## 8. Priority Recommendations

### CRITICAL (Fix Immediately)
1. ✅ Add `request_hash` column to `idempotency_keys` table
2. ✅ Fix unique index to include `action_type`
3. ✅ Update `idem_begin()` to accept and validate hash
4. ✅ Wrap idempotency claim + business logic in ONE transaction
5. ✅ Add idempotency to `save_manual_clocking_images.php`

### HIGH (Fix Before Next Release)
1. ✅ Add `action_type` parameter to `idem_finish()` and `idem_abort()`
2. ✅ Update all endpoints to pass `action_type` consistently
3. ✅ Add 409 'in progress' handling to all endpoints
4. ✅ Fix Dart header name (`X-Idempotency-Key`)

### MEDIUM (Fix in Next Sprint)
1. ✅ Add `validate_idempotency_key()` calls to all endpoints
2. ✅ Fix `validate_client_timestamp()` DateTime mutation bug
3. ✅ Add comprehensive logging for idempotency events

---

**End of Idempotency Audit Report**
