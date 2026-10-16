# Implementation Plan: Mobile API Authentication Middleware

## Context

This plan secures 7 unsecured mobile API endpoints by integrating the existing `require_auth.php` authentication system. The system uses Bearer token authentication with SHA-256 hashed tokens stored in the `auth_tokens` table.

**Already Secured (3 endpoints):**
- `get_learners.php` - Uses `requireAuth($conn)` + rate limiting
- `add_learner.php` - Uses `requireAuth($conn)`
- `save_manual_clocking_images.php` - Uses `requireAuth($conn)`

**Unsecured (7 endpoints):**
- `get_attendance.php` - Attendance calculation endpoint
- `get_classes.php` - Facilitator class list endpoint
- `save_class_batch_clocking.php` - Batch clocking (HAS auth, needs verification)
- `save_metadata.php` - POE document upload (uses `ob_start()`)
- `get_poe.php` - POE retrieval (uses `include('../connection.php')`)
- `sync_learner.php` - Learner sync endpoint
- `update_learner.php` - Learner update endpoint

**Exempt (must remain public):**
- `login.php` - Authentication endpoint
- `connection.php` - Database configuration
- `security_functions.php` - Security utilities

## Design Decisions

### 1. No New auth_middleware.php File
**Decision:** Use `require_auth.php` directly in all endpoints instead of creating a compatibility shim.

**Rationale:** 
- `require_auth.php` already provides `requireAuth($conn)`, `sendError()`, `sendSuccess()`, `validateRequired()`, and `applyRateLimit()` 
- Creating `auth_middleware.php` would duplicate existing functionality
- Three endpoints already use `require_auth.php` successfully, establishing the pattern
- Simpler dependency graph improves maintainability

### 2. Verify save_class_batch_clocking.php Authentication
**Decision:** Review and verify rather than blindly add auth.

**Rationale:**
- File already includes `require_auth.php` and calls `requireAuth($conn)`
- Authentication appears properly integrated after `set_time_limit(180)`
- Plan item will verify correct placement and token validation

### 3. Handle Edge Cases
**Edge Case Handling:**
- `get_poe.php` uses `include('../connection.php')` (parent directory) → Use `require_once __DIR__ . '/../require_auth.php'`
- `save_class_batch_clocking.php` has `set_time_limit(180)` at top → Auth must come after timeout setting but before business logic
- `save_metadata.php` uses `ob_start()` at top → Auth must come after `ob_start()` since `requireAuth()` may echo JSON on failure

### 4. Testing Strategy
**Decision:** Create standalone PHP test script (no framework).

**Rationale:**
- Project has no visible PHP test framework (Composer, PHPUnit config not found)
- Standalone test script can be run directly: `php mobile/test_auth_middleware.php`
- Tests cover: valid token, invalid token, expired token, missing header, role validation

---

## Implementation Steps

- [ ] **1. Verify save_class_batch_clocking.php authentication is correctly integrated**
  
  **What:** Review `save_class_batch_clocking.php` to confirm `requireAuth($conn)` is properly placed after `set_time_limit(180)` but before business logic. Verify the user ID is captured and used correctly in the batch processing flow.
  
  **Files:** `c:\projects\rlmss\mobile\save_class_batch_clocking.php`
  
  **Verify:** Read the file and confirm:
  - Line ~18-22: `set_time_limit(180)` is first
  - After error configuration and before JSON parsing: `require_once('require_auth.php');` exists
  - After loading auth: `$user = requireAuth($conn);` is called
  - `$userId = $user['user_id'];` is extracted and used in idempotency calls
  - No logic executes before auth check completes

---

- [ ] **2. Secure get_attendance.php**
  
  **What:** Add Bearer token authentication to the attendance calculation endpoint. Insert `require_auth.php` after the existing headers and `connection.php` include, before the parameter extraction (`$classID`, `$month`, `$learnerID`). Store the authenticated user ID for audit logging.
  
  **Files:** `c:\projects\rlmss\mobile\get_attendance.php`
  
  **Changes:**
  - After line ~10 `require_once 'connection.php';`, add:
    ```php
    // SECURITY: Require authentication
    require_once __DIR__ . '/require_auth.php';
    $user = requireAuth($conn);
    $authenticated_user_id = $user['user_id'];
    $authenticated_role = $user['user_role'];
    
    // SECURITY: Apply rate limiting
    applyRateLimit($conn, 'get_attendance', 60);
    ```
  - Before parameter extraction at line ~12
  
  **Verify:** Run `php -l mobile/get_attendance.php` to check syntax, then test with:
  ```bash
  # Should fail without token
  curl http://localhost/rlmss/mobile/get_attendance.php?classID=1
  
  # Should succeed with valid token
  curl -H "Authorization: Bearer VALID_TOKEN" http://localhost/rlmss/mobile/get_attendance.php?classID=1
  ```

---

- [ ] **3. Secure get_classes.php**
  
  **What:** Add Bearer token authentication to the facilitator class list endpoint. Insert `require_auth.php` after `connection.php` include but before the `facilitator_id` parameter check. Optionally validate that the authenticated user ID matches the requested `facilitator_id` parameter to prevent cross-user data access.
  
  **Files:** `c:\projects\rlmss\mobile\get_classes.php`
  
  **Changes:**
  - After line ~6 `include('connection.php');`, add:
    ```php
    // SECURITY: Require authentication
    require_once __DIR__ . '/require_auth.php';
    $user = requireAuth($conn);
    $authenticated_user_id = $user['user_id'];
    $authenticated_role = $user['user_role'];
    
    // SECURITY: Apply rate limiting
    applyRateLimit($conn, 'get_classes', 60);
    ```
  - Before line ~8 `if (!isset($_GET['facilitator_id']))`
  - Optional: Add authorization check after parameter extraction:
    ```php
    // AUTHORIZATION: Verify user can only access their own classes
    if ($authenticated_role === 'facilitator' && $facilitator_id != $authenticated_user_id) {
        sendError('Access denied', 403, 'FORBIDDEN');
    }
    ```
  
  **Verify:** Run `php -l mobile/get_classes.php` to check syntax, then test with:
  ```bash
  # Should fail without token
  curl http://localhost/rlmss/mobile/get_classes.php?facilitator_id=123
  
  # Should succeed with valid facilitator token
  curl -H "Authorization: Bearer FACILITATOR_TOKEN" http://localhost/rlmss/mobile/get_classes.php?facilitator_id=123
  ```

---

- [ ] **4. Secure save_metadata.php**
  
  **What:** Add Bearer token authentication to the POE document upload endpoint. This file uses `ob_start()` at the top for output buffering. Insert authentication AFTER `ob_start()` and header declarations but BEFORE the `sendResponse()` helper function definition, since `requireAuth()` may call `exit` with JSON output on auth failure.
  
  **Files:** `c:\projects\rlmss\mobile\save_metadata.php`
  
  **Changes:**
  - After line ~11 `include('connection.php');`, add:
    ```php
    // SECURITY: Require authentication
    require_once __DIR__ . '/require_auth.php';
    $user = requireAuth($conn);
    $authenticated_user_id = $user['user_id'];
    $authenticated_role = $user['user_role'];
    
    // SECURITY: Apply rate limiting (POE uploads are larger, allow fewer per minute)
    applyRateLimit($conn, 'save_metadata', 20);
    ```
  - Must be after `ob_start()` (line ~5) and `include('connection.php')` (line ~11)
  - Must be before helper function definitions (line ~13 onwards)
  
  **Verify:** Run `php -l mobile/save_metadata.php` to check syntax, then test with:
  ```bash
  # Should fail without token
  curl -X POST http://localhost/rlmss/mobile/save_metadata.php
  
  # Should succeed with valid token and proper payload
  curl -X POST -H "Authorization: Bearer VALID_TOKEN" \
       -H "Content-Type: multipart/form-data" \
       -F "learnerID=123" -F "type=Formative" \
       http://localhost/rlmss/mobile/save_metadata.php
  ```

---

- [ ] **5. Secure get_poe.php**
  
  **What:** Add Bearer token authentication to the POE retrieval endpoint. This file uses `include('../connection.php')` from parent directory, so the auth require must use `__DIR__ . '/../require_auth.php'` to match. Insert authentication after the CORS headers and connection include, before the request method check.
  
  **Files:** `c:\projects\rlmss\mobile\get_poe.php`
  
  **Changes:**
  - After line ~5 `include('../connection.php');`, add:
    ```php
    // SECURITY: Require authentication
    // NOTE: require_auth.php is in mobile/ but this file includes ../connection.php
    require_once __DIR__ . '/../mobile/require_auth.php';
    $user = requireAuth($conn);
    $authenticated_user_id = $user['user_id'];
    $authenticated_role = $user['user_role'];
    
    // SECURITY: Apply rate limiting
    applyRateLimit($conn, 'get_poe', 60);
    ```
  - WAIT - verify directory structure: if `get_poe.php` is in `mobile/` and uses `include('../connection.php')`, then `require_auth.php` is in the same directory
  - Correct path: `require_once __DIR__ . '/require_auth.php';` (same directory as get_poe.php)
  - Before line ~8 `if ($_SERVER['REQUEST_METHOD'] == 'POST' || $_SERVER['REQUEST_METHOD'] == 'GET')`
  
  **Verify:** Run `php -l mobile/get_poe.php` to check syntax, then test with:
  ```bash
  # Should fail without token
  curl http://localhost/rlmss/mobile/get_poe.php?learnerId=123
  
  # Should succeed with valid token
  curl -H "Authorization: Bearer VALID_TOKEN" \
       http://localhost/rlmss/mobile/get_poe.php?learnerId=123
  ```

---

- [ ] **6. Secure sync_learner.php**
  
  **What:** Add Bearer token authentication to the learner sync endpoint. This is a critical data modification endpoint that accepts JSON payloads and creates/updates learner records including bank details. Insert authentication after `include 'connection.php'` and headers, before JSON input parsing.
  
  **Files:** `c:\projects\rlmss\mobile\sync_learner.php`
  
  **Changes:**
  - After line ~2 `include 'connection.php';` and line ~4 `header('Content-Type: application/json');`, add:
    ```php
    // SECURITY: Require authentication
    require_once __DIR__ . '/require_auth.php';
    $user = requireAuth($conn);
    $authenticated_user_id = $user['user_id'];
    $authenticated_role = $user['user_role'];
    
    // SECURITY: Apply rate limiting (sync can be heavy, limit to 30/min)
    applyRateLimit($conn, 'sync_learner', 30);
    ```
  - Before line ~40 `$input = json_decode(file_get_contents('php://input'), true);`
  
  **Verify:** Run `php -l mobile/sync_learner.php` to check syntax, then test with:
  ```bash
  # Should fail without token
  curl -X POST http://localhost/rlmss/mobile/sync_learner.php
  
  # Should succeed with valid token and proper payload
  curl -X POST -H "Authorization: Bearer VALID_TOKEN" \
       -H "Content-Type: application/json" \
       -d '[{"learner":{"IDNumber":"1234567890123","classID":1,"Name":"Test"}}]' \
       http://localhost/rlmss/mobile/sync_learner.php
  ```

---

- [ ] **7. Secure update_learner.php**
  
  **What:** Add Bearer token authentication to the learner update endpoint. This endpoint updates learner details and bank information. Insert authentication after headers and OPTIONS handling, before the POST method check. The endpoint already has field protection logic that should be preserved.
  
  **Files:** `c:\projects\rlmss\mobile\update_learner.php`
  
  **Changes:**
  - After line ~2 `include 'connection.php';` and after the OPTIONS handler (line ~14), add:
    ```php
    // SECURITY: Require authentication
    require_once __DIR__ . '/require_auth.php';
    $user = requireAuth($conn);
    $authenticated_user_id = $user['user_id'];
    $authenticated_role = $user['user_role'];
    
    // SECURITY: Apply rate limiting
    applyRateLimit($conn, 'update_learner', 60);
    ```
  - After the OPTIONS handler completes (line ~15) but before the POST method check (line ~17)
  
  **Verify:** Run `php -l mobile/update_learner.php` to check syntax, then test with:
  ```bash
  # Should fail without token
  curl -X POST http://localhost/rlmss/mobile/update_learner.php
  
  # Should succeed with valid token and proper payload
  curl -X POST -H "Authorization: Bearer VALID_TOKEN" \
       -H "Content-Type: application/json" \
       -d '{"LearnerID":"123","data":{"Email":"test@example.com"}}' \
       http://localhost/rlmss/mobile/update_learner.php
  ```

---

- [ ] **8. Create standalone authentication test script**
  
  **What:** Create `test_auth_middleware.php` in the `mobile/` directory that exercises all authentication scenarios without requiring a test framework. The script connects directly to the database, creates test tokens, and makes internal function calls to validate behavior. Each test prints PASS/FAIL with a descriptive message.
  
  **Files:** `c:\projects\rlmss\mobile\test_auth_middleware.php` (new file)
  
  **Test Coverage:**
  1. **Valid token test**: Create valid token in `auth_tokens`, call `validate_auth_token()`, expect user data returned
  2. **Invalid token test**: Call `validate_auth_token()` with random string, expect `false`
  3. **Expired token test**: Create token with `expires_at` in past, call `validate_auth_token()`, expect `false`
  4. **Missing Authorization header test**: Simulate request without header, expect 401 response
  5. **Role-based check test**: Create token with role 'facilitator', call `requireAuth($conn, 'admin')`, expect 403 Forbidden
  6. **Rate limiting test**: Make 61 rapid requests to `check_rate_limit()`, expect last one blocked
  
  **Script Structure:**
  ```php
  <?php
  /**
   * Authentication Middleware Test Suite
   * Run: php mobile/test_auth_middleware.php
   */
  
  require_once 'connection.php';
  require_once 'require_auth.php';
  
  $testResults = [];
  
  function runTest($name, $callable) {
      global $testResults;
      try {
          $result = $callable();
          $testResults[] = ['name' => $name, 'status' => $result ? 'PASS' : 'FAIL', 'error' => null];
          echo ($result ? '✓' : '✗') . " $name\n";
      } catch (Exception $e) {
          $testResults[] = ['name' => $name, 'status' => 'FAIL', 'error' => $e->getMessage()];
          echo "✗ $name - Error: " . $e->getMessage() . "\n";
      }
  }
  
  // Test 1: Valid token
  runTest('Valid token returns user data', function() use ($conn) {
      $token = bin2hex(random_bytes(32));
      $userId = 999;
      $role = 'facilitator';
      $expires = date('Y-m-d H:i:s', strtotime('+1 hour'));
      
      $stmt = $conn->prepare("INSERT INTO auth_tokens (token, user_id, user_role, expires_at) VALUES (?, ?, ?, ?)");
      $stmt->bind_param("siss", $token, $userId, $role, $expires);
      $stmt->execute();
      
      $user = validate_auth_token($conn, $token);
      
      // Cleanup
      $conn->query("DELETE FROM auth_tokens WHERE token = '$token'");
      
      return $user && $user['user_id'] == $userId && $user['user_role'] == $role;
  });
  
  // Test 2: Invalid token
  runTest('Invalid token returns false', function() use ($conn) {
      $user = validate_auth_token($conn, 'invalid_token_12345');
      return $user === false;
  });
  
  // Test 3: Expired token
  runTest('Expired token returns false', function() use ($conn) {
      $token = bin2hex(random_bytes(32));
      $userId = 999;
      $role = 'facilitator';
      $expires = date('Y-m-d H:i:s', strtotime('-1 hour')); // Expired 1 hour ago
      
      $stmt = $conn->prepare("INSERT INTO auth_tokens (token, user_id, user_role, expires_at) VALUES (?, ?, ?, ?)");
      $stmt->bind_param("siss", $token, $userId, $role, $expires);
      $stmt->execute();
      
      $user = validate_auth_token($conn, $token);
      
      // Cleanup
      $conn->query("DELETE FROM auth_tokens WHERE token = '$token'");
      
      return $user === false;
  });
  
  // Test 4: Rate limiting
  runTest('Rate limiting blocks after max requests', function() use ($conn) {
      $testIp = '192.168.1.100';
      $action = 'test_action_' . time();
      
      // Cleanup any existing entries
      $conn->query("DELETE FROM rate_limit WHERE ip_address = '$testIp' AND action = '$action'");
      
      // Make max_attempts requests (should all succeed)
      for ($i = 0; $i < 10; $i++) {
          $result = check_rate_limit($conn, $testIp, $action, 10, 60);
          if (!$result['allowed']) {
              // Cleanup
              $conn->query("DELETE FROM rate_limit WHERE ip_address = '$testIp' AND action = '$action'");
              return false; // Should not block yet
          }
      }
      
      // The 11th request should be blocked
      $result = check_rate_limit($conn, $testIp, $action, 10, 60);
      
      // Cleanup
      $conn->query("DELETE FROM rate_limit WHERE ip_address = '$testIp' AND action = '$action'");
      
      return !$result['allowed']; // Should be blocked
  });
  
  // Print summary
  echo "\n=== Test Summary ===\n";
  $passed = count(array_filter($testResults, fn($r) => $r['status'] === 'PASS'));
  $failed = count($testResults) - $passed;
  echo "Passed: $passed\n";
  echo "Failed: $failed\n";
  
  exit($failed > 0 ? 1 : 0);
  ?>
  ```
  
  **Verify:** Run the test script:
  ```bash
  php mobile/test_auth_middleware.php
  ```
  Expected output:
  ```
  ✓ Valid token returns user data
  ✓ Invalid token returns false
  ✓ Expired token returns false
  ✓ Rate limiting blocks after max requests
  
  === Test Summary ===
  Passed: 4
  Failed: 0
  ```

---

## Edge Cases & Notes

### Directory Structure Verification
- **get_poe.php location**: Confirmed in `mobile/` directory, uses `include('../connection.php')` to access parent
- **require_auth.php location**: Confirmed in `mobile/` directory
- **Resolution**: Use `require_once __DIR__ . '/require_auth.php';` (same directory)

### Output Buffering Handling
- **save_metadata.php** uses `ob_start()` for output control
- **Solution**: Place auth after `ob_start()` so `requireAuth()` can use `ob_end_clean()` if needed

### Timeout Configuration
- **save_class_batch_clocking.php** sets `set_time_limit(180)` for large batch processing
- **Solution**: Auth goes after timeout setting (already correctly placed)

### Role-Based Authorization
- **get_classes.php** should optionally verify facilitator can only access their own classes
- **Implementation**: Optional check comparing `$authenticated_user_id` with `$facilitator_id` parameter

### Rate Limit Tuning
Different endpoints have different rate limit needs:
- **Read operations** (get_attendance, get_classes, get_poe, get_learners): 60 requests/minute
- **Write operations** (update_learner): 60 requests/minute  
- **Heavy operations** (sync_learner, save_metadata): 20-30 requests/minute
- **Batch operations** (save_class_batch_clocking): 10 requests/minute (already has idempotency)

### Protected Fields
- **update_learner.php** already protects signature fields, profile images, and fingerprint data
- **Preservation**: Keep existing protection logic intact, auth is additive

---

## Verification Commands

After completing all steps, verify the security posture:

```bash
# 1. Verify all 7 endpoints require authentication
grep -r "requireAuth" mobile/get_attendance.php mobile/get_classes.php mobile/save_class_batch_clocking.php mobile/save_metadata.php mobile/get_poe.php mobile/sync_learner.php mobile/update_learner.php

# 2. Run test suite
php mobile/test_auth_middleware.php

# 3. Test each endpoint manually (should all return 401 without token)
curl -v http://localhost/rlmss/mobile/get_attendance.php?classID=1
curl -v http://localhost/rlmss/mobile/get_classes.php?facilitator_id=1
curl -v -X POST http://localhost/rlmss/mobile/save_metadata.php
curl -v http://localhost/rlmss/mobile/get_poe.php?learnerId=1
curl -v -X POST http://localhost/rlmss/mobile/sync_learner.php
curl -v -X POST http://localhost/rlmss/mobile/update_learner.php

# 4. Verify rate limiting works
for i in {1..65}; do curl -H "Authorization: Bearer TOKEN" http://localhost/rlmss/mobile/get_classes.php?facilitator_id=1; done
# Should see 429 Too Many Requests after ~60 requests
```

---

## Success Criteria

1. All 7 unsecured endpoints require Bearer token authentication
2. Invalid/missing tokens return 401 Unauthorized with proper JSON error
3. Rate limiting is active on all secured endpoints
4. Test suite passes all authentication scenarios
5. No existing functionality is broken (signatures, uploads, sync still work)
6. Security event logging captures all auth failures
7. Manual curl tests confirm 401 responses without valid tokens

---

## Security Notes

- **Token Format**: SHA-256 hashed tokens stored in `auth_tokens` table
- **Token Extraction**: `requireAuth()` extracts from `Authorization: Bearer <token>` header
- **Token Validation**: Checks `expires_at > NOW()` and `is_active = 1`
- **Role Enforcement**: Optional `requireAuth($conn, 'role')` parameter for role-based access
- **Rate Limiting**: Prevents abuse via `applyRateLimit()` function
- **Audit Logging**: `log_security_event()` captures all authentication events
- **Error Messages**: Generic errors prevent information leakage about valid user IDs or tokens

