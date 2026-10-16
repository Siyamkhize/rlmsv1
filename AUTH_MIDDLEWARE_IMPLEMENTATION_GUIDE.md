# Authentication Middleware Implementation Guide

**Date:** October 14, 2026  
**Status:** 🔴 CRITICAL - IMMEDIATE IMPLEMENTATION REQUIRED  
**Priority:** P0 - Security Critical

---

## 🚨 Security Gap Addressed

This implementation fixes the **CRITICAL SECURITY GAP** where authentication tokens were generated but **NOT validated on API requests**, allowing unauthorized access to all endpoints.

### Before (INSECURE):
```php
// ❌ Anyone can call this endpoint
$classID = $_POST['classID'];
$sql = "SELECT * FROM learnerdetails WHERE classID = ?";
```

### After (SECURE):
```php
// ✅ Only authenticated users with proper roles can access
$auth = requireAuth($conn, ['facilitator', 'admin']);
$classID = $_POST['classID'];
// ... verify user has access to this class ...
$sql = "SELECT * FROM learnerdetails WHERE classID = ?";
```

---

## 📦 Files Created

### 1. `mobile/auth_middleware.php`
**Purpose:** Core authentication and authorization functions

**Functions:**
- `validateAuthToken($conn)` - Validates Bearer token from Authorization header
- `checkRoleAuthorization($auth, $allowed_roles)` - Checks user has required role
- `requireAuth($conn, $allowed_roles)` - Complete auth check (use this in endpoints)
- `logAuthEvent($conn, ...)` - Logs security events
- `revokeUserTokens($conn, $user_id, $user_role)` - Logout/security lockout
- `cleanupExpiredTokens($conn)` - Maintenance function

### 2. `mobile/get_learners_secured.php`
**Purpose:** Example of properly secured endpoint

**Shows:**
- Token validation
- Role-based access control (RBAC)
- Data-level authorization (user can only access their own class)
- Security event logging
- Proper error responses (401, 403)

### 3. `sql/create_auth_logs_table.sql`
**Purpose:** Database table for security audit logging

**Tracks:**
- Login attempts (success/failure)
- API access
- Unauthorized access attempts
- User activity patterns
- Suspicious behavior

---

## 🚀 Implementation Steps

### PHASE 1: Database Setup (5 minutes)

#### Step 1.1: Create auth_logs table

```bash
cd c:\projects\rlmss
mysql -u your_username -p your_database < sql\create_auth_logs_table.sql
```

Or run directly in MySQL:

```sql
USE your_database_name;
SOURCE c:/projects/rlmss/sql/create_auth_logs_table.sql;
```

#### Step 1.2: Verify tables exist

```sql
SHOW TABLES LIKE 'auth_%';
-- Should show:
-- auth_tokens (already exists)
-- auth_logs (newly created)

DESCRIBE auth_logs;
```

---

### PHASE 2: Update Flutter App to Send Tokens (30 minutes)

#### Step 2.1: Create HTTP helper with auth headers

**File:** `lib/services/authenticated_http_service.dart` (NEW FILE)

```dart
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AuthenticatedHttpService {
  /// Makes an authenticated POST request with auth token
  static Future<http.Response> post(
    String url,
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated - please login again');
    }
    
    final headers = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': 'Bearer $token',
    };
    
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: body,
    );
    
    // Handle 401 Unauthorized - token expired
    if (response.statusCode == 401) {
      // Clear invalid token
      await prefs.remove('auth_token');
      throw Exception('Session expired - please login again');
    }
    
    // Handle 403 Forbidden - insufficient permissions
    if (response.statusCode == 403) {
      throw Exception('Access denied - insufficient permissions');
    }
    
    return response;
  }
  
  /// Makes an authenticated GET request with auth token
  static Future<http.Response> get(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated - please login again');
    }
    
    final headers = {
      'Authorization': 'Bearer $token',
    };
    
    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );
    
    if (response.statusCode == 401) {
      await prefs.remove('auth_token');
      throw Exception('Session expired - please login again');
    }
    
    if (response.statusCode == 403) {
      throw Exception('Access denied - insufficient permissions');
    }
    
    return response;
  }
}
```

#### Step 2.2: Update existing API calls

**Example - Update learner fetching:**

**Before:**
```dart
final response = await http.post(
  Uri.parse('$baseUrl/mobile/get_learners.php'),
  body: {'classID': classID},
);
```

**After:**
```dart
import 'package:rlmss/services/authenticated_http_service.dart';

final response = await AuthenticatedHttpService.post(
  '$baseUrl/mobile/get_learners.php',
  {'classID': classID},
);
```

#### Step 2.3: Add session expiry handling

**File:** Update `lib/main.dart` login success handler

```dart
// After successful login, save token
await prefs.setString('auth_token', data['auth_token']);
await prefs.setString('token_expiry', DateTime.now().add(Duration(days: 7)).toIso8601String());

// Add global error handler for 401 responses
// Show dialog: "Your session has expired. Please login again."
// Navigate to login page
```

---

### PHASE 3: Secure All PHP Endpoints (2-3 days)

#### Step 3.1: Identify all API endpoints

```bash
cd c:\projects\rlmss\mobile
ls *.php
```

**Endpoints that need securing (~50 files):**
- add_learner.php
- update_learner.php
- get_learners.php
- get_classes.php
- save_attendance.php
- get_poe.php
- save_arpl_*.php
- sync_*.php
- ... (all others)

#### Step 3.2: Secure each endpoint (template)

**Pattern to follow:**

```php
<?php
require_once('connection.php');
require_once('auth_middleware.php');

// ✅ ADD THIS AT THE TOP OF EVERY ENDPOINT
$auth = requireAuth($conn, ['allowed', 'role', 'names']);

// Extract user info if needed
$user_id = $auth['user_id'];
$user_role = $auth['user_role'];

// Rest of your existing code...
// Just add the requireAuth() call, keep everything else the same
?>
```

#### Step 3.3: Role matrix for endpoints

**Copy this into each endpoint's requireAuth() call:**

| Endpoint Pattern | Allowed Roles |
|-----------------|---------------|
| `get_learners.php` | `['facilitator', 'admin', 'sdp', 'arpl_assessor']` |
| `add_learner.php` | `['facilitator', 'admin', 'sdp']` |
| `update_learner.php` | `['facilitator', 'admin', 'sdp']` |
| `get_classes.php` | `['facilitator', 'admin', 'sdp', 'arpl_assessor']` |
| `save_attendance.php` | `['facilitator', 'arpl_assessor']` |
| `get_poe.php` | `['facilitator', 'arpl_assessor', 'moderator']` |
| `save_arpl_*.php` | `['arpl_assessor', 'admin']` |
| `sync_*.php` | `['facilitator', 'admin', 'sdp']` |
| Admin endpoints | `['admin']` |

#### Step 3.4: Example - Secure get_learners.php

**Replace** `mobile/get_learners.php` **with:**

```php
<?php
require_once('connection.php');
require_once('auth_middleware.php');

// ✅ SECURE: Only authenticated users with these roles
$auth = requireAuth($conn, ['facilitator', 'admin', 'sdp', 'arpl_assessor']);

$classID = $_POST['classID'] ?? '';

if (empty($classID)) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing classID']);
    exit;
}

// ✅ SECURE: Verify user has access to this class (optional but recommended)
if ($auth['user_role'] === 'facilitator') {
    $stmt = $conn->prepare("SELECT classID FROM facilitator WHERE facilitator_id = ? AND classID = ?");
    $stmt->bind_param("ss", $auth['user_id'], $classID);
    $stmt->execute();
    if ($stmt->get_result()->num_rows === 0) {
        http_response_code(403);
        echo json_encode(['error' => 'Access denied to this class']);
        exit;
    }
}

// Original query - no changes needed
$stmt = $conn->prepare("SELECT * FROM learnerdetails WHERE classID = ?");
$stmt->bind_param("s", $classID);
$stmt->execute();
$result = $stmt->get_result();

$learners = [];
while ($row = $result->fetch_assoc()) {
    $learners[] = $row;
}

echo json_encode($learners);
$conn->close();
?>
```

---

### PHASE 4: Testing (1 day)

#### Test 4.1: Valid token works

```bash
# Get a valid token by logging in via the app
# Then test with curl:

curl -X POST https://your-server.com/mobile/get_learners.php \
  -H "Authorization: Bearer <your-token-here>" \
  -d "classID=12345"

# Expected: 200 OK with learner data
```

#### Test 4.2: Missing token fails

```bash
curl -X POST https://your-server.com/mobile/get_learners.php \
  -d "classID=12345"

# Expected: 401 Unauthorized
# {"success":false,"error":"Missing Authorization header"}
```

#### Test 4.3: Invalid token fails

```bash
curl -X POST https://your-server.com/mobile/get_learners.php \
  -H "Authorization: Bearer invalid-token-12345" \
  -d "classID=12345"

# Expected: 401 Unauthorized
# {"success":false,"error":"Invalid or expired authentication token"}
```

#### Test 4.4: Wrong role fails

```bash
# Login as 'learner' role (if exists), get token
# Try to access facilitator-only endpoint

curl -X POST https://your-server.com/mobile/add_learner.php \
  -H "Authorization: Bearer <learner-token>" \
  -d "..."

# Expected: 403 Forbidden
# {"success":false,"error":"Access denied. Required roles: facilitator, admin, sdp"}
```

#### Test 4.5: Expired token fails

```bash
# Wait 7 days, or manually set expires_at in past:
UPDATE auth_tokens SET expires_at = DATE_SUB(NOW(), INTERVAL 1 DAY) WHERE user_id = '678';

# Then try to access endpoint
# Expected: 401 Unauthorized
```

---

## 🔒 Security Benefits

### ✅ BEFORE vs AFTER

| Security Aspect | Before (INSECURE) | After (SECURE) |
|----------------|-------------------|----------------|
| **API Access Control** | ❌ None - anyone can call any endpoint | ✅ Token required for all requests |
| **User Identity** | ❌ No way to know who made request | ✅ Every request linked to user_id |
| **Role Enforcement** | ❌ No role checking | ✅ RBAC on every endpoint |
| **Session Expiry** | ❌ No expiration | ✅ 7-day token expiry enforced |
| **Token Revocation** | ❌ Not possible | ✅ Instant revocation via database |
| **Audit Logging** | ❌ No audit trail | ✅ All access logged to auth_logs |
| **Attack Detection** | ❌ No monitoring | ✅ Failed attempts logged and queryable |

---

## 📊 Monitoring Queries

### Failed login attempts (last 24 hours)
```sql
SELECT user_id, ip_address, COUNT(*) as attempts, MAX(created_at) as last_attempt
FROM auth_logs 
WHERE event_type = 'unauthorized_access' 
AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY user_id, ip_address
ORDER BY attempts DESC;
```

### API usage by user (last 7 days)
```sql
SELECT user_id, user_role, COUNT(*) as api_calls
FROM auth_logs 
WHERE event_type = 'api_access' 
AND created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY user_id, user_role
ORDER BY api_calls DESC
LIMIT 20;
```

### Most accessed endpoints
```sql
SELECT request_uri, COUNT(*) as hits
FROM auth_logs 
WHERE event_type = 'api_access'
AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY request_uri
ORDER BY hits DESC
LIMIT 10;
```

### Suspicious activity alerts
```sql
-- Multiple failed attempts from same IP
SELECT ip_address, COUNT(*) as failed_attempts,
       COUNT(DISTINCT user_id) as users_tried
FROM auth_logs 
WHERE event_type = 'unauthorized_access'
AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)
GROUP BY ip_address
HAVING failed_attempts > 10
ORDER BY failed_attempts DESC;
```

---

## 🛠️ Maintenance Tasks

### Daily: Clean expired tokens

**Create:** `mobile/cron_cleanup_tokens.php`

```php
<?php
require_once('connection.php');
require_once('auth_middleware.php');

$deleted = cleanupExpiredTokens($conn);
echo "Deleted $deleted expired tokens\n";

$conn->close();
?>
```

**Add to crontab:**
```bash
0 2 * * * php /path/to/rlmss/mobile/cron_cleanup_tokens.php
```

### Weekly: Review auth logs

```sql
-- Run this every Monday
SELECT 
    DATE(created_at) as date,
    event_type,
    COUNT(*) as count
FROM auth_logs
WHERE created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(created_at), event_type
ORDER BY date DESC, count DESC;
```

---

## 🚨 Incident Response

### If unauthorized access detected:

1. **Revoke all tokens for compromised user:**
```php
revokeUserTokens($conn, $user_id, $user_role);
```

2. **Review auth logs for that user:**
```sql
SELECT * FROM auth_logs 
WHERE user_id = '<compromised_user_id>'
AND created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
ORDER BY created_at DESC;
```

3. **Force user to reset password**

4. **Check for data access:**
```sql
SELECT request_uri, details, created_at
FROM auth_logs
WHERE user_id = '<compromised_user_id>'
AND event_type = 'api_access'
ORDER BY created_at DESC;
```

---

## ✅ Rollout Checklist

- [ ] **Phase 1: Database Setup**
  - [ ] Create auth_logs table
  - [ ] Verify auth_tokens table exists
  - [ ] Test database connection

- [ ] **Phase 2: Flutter App Updates**
  - [ ] Create AuthenticatedHttpService class
  - [ ] Update all http.post/get calls
  - [ ] Add session expiry handling
  - [ ] Test token storage after login

- [ ] **Phase 3: PHP Endpoint Security**
  - [ ] Upload auth_middleware.php to server
  - [ ] Create endpoint priority list
  - [ ] Secure HIGH PRIORITY endpoints first:
    - [ ] get_learners.php
    - [ ] add_learner.php
    - [ ] update_learner.php
    - [ ] save_attendance.php
    - [ ] get_poe.php
  - [ ] Secure MEDIUM PRIORITY endpoints:
    - [ ] All sync_*.php files
    - [ ] All get_*.php files
  - [ ] Secure LOW PRIORITY endpoints:
    - [ ] Everything else

- [ ] **Phase 4: Testing**
  - [ ] Test valid token works
  - [ ] Test missing token fails
  - [ ] Test invalid token fails
  - [ ] Test wrong role fails
  - [ ] Test expired token fails

- [ ] **Phase 5: Monitoring Setup**
  - [ ] Set up daily token cleanup cron
  - [ ] Create monitoring dashboard queries
  - [ ] Set up failed login alerts
  - [ ] Document incident response procedure

---

## 📞 Support

If you encounter issues during implementation:

1. Check auth_logs table for error details
2. Verify auth_middleware.php is uploaded to server
3. Confirm connection.php is being included properly
4. Test token generation in mobile/login.php
5. Use curl to test endpoints directly

---

**Implementation Priority:** 🔴 CRITICAL  
**Estimated Total Time:** 2-3 days  
**Impact:** Fixes major security vulnerability  
**Status:** Ready for immediate deployment

---

**Document Version:** 1.0  
**Last Updated:** October 14, 2026  
**Prepared By:** RLMSS Development Team
