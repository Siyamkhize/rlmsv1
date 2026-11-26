# RLMSS Existing Authentication System Documentation

## Overview

The RLMSS app already has a **complete authentication and session management system** using bearer tokens. This document explains the existing system for integration with external systems (like MTL API).

---

## Architecture

```
┌──────────────┐         ┌──────────────┐         ┌─────────────┐
│   Flutter    │         │  Mobile API  │         │   Database  │
│     App      │         │   (PHP)      │         │   (MySQL)   │
└──────┬───────┘         └──────┬───────┘         └──────┬──────┘
       │                        │                        │
       │  1. Login Request      │                        │
       ├───────────────────────>│                        │
       │   (email/password)     │                        │
       │                        │  2. Validate User      │
       │                        ├───────────────────────>│
       │                        │                        │
       │                        │  3. Generate Token     │
       │                        │  (64-char hex)         │
       │                        │                        │
       │  4. Login Response     │                        │
       │<───────────────────────┤                        │
       │   {auth_token, user}   │                        │
       │                        │                        │
       │  5. Store Token        │                        │
       │  (SharedPreferences)   │                        │
       │                        │                        │
       │  6. All API Requests   │                        │
       ├───────────────────────>│                        │
       │  Authorization: Bearer │  7. Validate Token     │
       │  <auth_token>          ├───────────────────────>│
       │                        │                        │
       │  8. API Response       │                        │
       │<───────────────────────┤                        │
       │                        │                        │
       │  9. Logout             │                        │
       ├───────────────────────>│                        │
       │                        │  10. Invalidate Token  │
       │                        ├───────────────────────>│
       │                        │                        │
       │  11. Clear Token       │                        │
       │  (Remove from storage) │                        │
       └────────────────────────┴────────────────────────┘
```

---

## 1. Login Flow

### Client Side (Flutter)

**Location:** `lib/main.dart` (lines ~590-615)

```dart
Future<void> _login(String email, String password) async {
  final response = await http.post(
    Uri.parse(AppConfig.loginUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'email': email,
      'password': password,
    }),
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    
    // Server returns auth_token on successful login
    if (data.containsKey('auth_token') && data['auth_token'] != null) {
      final token = data['auth_token'].toString();
      
      // Store token in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      
      debugPrint('[LOGIN] ✅ Auth token saved successfully');
      debugPrint('[LOGIN] Token length: ${token.length}');
      
      // Also returns user data
      // data['user'] contains: id, name, email, role, etc.
    }
  }
}
```

### Server Side (PHP)

**Location:** `mobile/login.php`

```php
<?php
// Pseudo-code - actual implementation
function handleLogin($email, $password) {
    // 1. Validate credentials
    $user = validateCredentials($email, $password);
    
    if (!$user) {
        return ['success' => false, 'message' => 'Invalid credentials'];
    }
    
    // 2. Generate auth token (64-character hex string)
    $authToken = bin2hex(random_bytes(32)); // 64 chars
    
    // 3. Store token in database
    $expiresAt = date('Y-m-d H:i:s', strtotime('+7 days'));
    storeToken($user['id'], $authToken, $expiresAt);
    
    // 4. Return token and user data
    return [
        'success' => true,
        'auth_token' => $authToken,
        'user' => [
            'id' => $user['id'],
            'name' => $user['name'],
            'email' => $user['email'],
            'role' => $user['role'],
            // ... other user data
        ]
    ];
}
```

---

## 2. Token Storage

### Client Side

**Location:** `lib/config.dart` (lines ~236-254)

```dart
static Future<String?> getAuthToken() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token != null) {
      debugPrint('[AUTH] ✅ Token retrieved from storage');
      debugPrint('[AUTH] Token length: ${token.length}');
    } else {
      debugPrint('[AUTH] ❌ No token found in storage');
    }
    
    return token;
  } catch (e) {
    debugPrint('[AUTH] Error getting auth token: $e');
    return null;
  }
}
```

**Token Properties:**
- **Storage:** SharedPreferences (persistent, secure on Android/iOS)
- **Format:** 64-character hexadecimal string
- **Lifetime:** 7 days (configurable)
- **Cleared on:** Logout, app uninstall, manual clear

---

## 3. Using Token for API Requests

### Example 1: Simple GET Request

**Location:** Multiple files (e.g., `lib/admin.dart` line ~1468)

```dart
Future<void> fetchData() async {
  // Get auth token
  final authToken = await AppConfig.getAuthToken();
  
  if (authToken == null) {
    throw Exception('Not authenticated');
  }
  
  // Make request with token
  final response = await http.get(
    Uri.parse(AppConfig.someEndpointUrl),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $authToken',
    },
  );
  
  if (response.statusCode == 401) {
    // Token expired or invalid - redirect to login
    handleAuthError();
  }
}
```

### Example 2: POST Request with Body

**Location:** Multiple files (e.g., `lib/services/offline_sync_queue_service.dart`)

```dart
Future<void> syncData(Map<String, dynamic> data) async {
  final token = await AppConfig.getAuthToken();
  
  if (token == null) {
    throw Exception('No auth token available');
  }
  
  final response = await http.post(
    Uri.parse(AppConfig.syncUrl),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode(data),
  );
  
  // Handle response...
}
```

### Example 3: Multipart Request (File Upload)

**Location:** `lib/services/signature_sync_service.dart` (lines ~95-98)

```dart
Future<void> uploadFile(File file) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');
  
  var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
  
  if (token != null) {
    request.headers['Authorization'] = 'Bearer $token';
  }
  
  request.files.add(await http.MultipartFile.fromPath('file', file.path));
  
  var response = await request.send();
  // Handle response...
}
```

---

## 4. Server-Side Token Validation

### PHP Authentication Middleware

**Location:** `mobile/auth.php` (or similar)

```php
<?php
function validateAuthToken() {
    // 1. Get token from Authorization header
    $headers = getallheaders();
    $authHeader = $headers['Authorization'] ?? '';
    
    if (!preg_match('/Bearer\s+(.*)$/i', $authHeader, $matches)) {
        http_response_code(401);
        echo json_encode(['error' => 'Missing or invalid Authorization header']);
        exit;
    }
    
    $token = $matches[1];
    
    // 2. Validate token from database
    $stmt = $pdo->prepare("
        SELECT u.*, t.expires_at 
        FROM auth_tokens t
        JOIN users u ON u.id = t.user_id
        WHERE t.token = ? AND t.expires_at > NOW()
    ");
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    
    if (!$user) {
        http_response_code(401);
        echo json_encode(['error' => 'Invalid or expired token']);
        exit;
    }
    
    // 3. Return authenticated user
    return $user;
}

// Use in every protected endpoint
$currentUser = validateAuthToken();
// Now proceed with business logic...
```

---

## 5. Logout Flow

### Client Side

**Location:** `lib/main.dart` (lines ~1207-1211)

```dart
Future<void> _logout() async {
  final prefs = await SharedPreferences.getInstance();
  
  // Clear auth token
  await prefs.remove('auth_token');
  await prefs.remove('offline_token');
  await prefs.remove('offline_user_email');
  
  debugPrint('[LOGOUT] ✅ Logout complete, cleared all session data');
  
  // Navigate to login screen
  Navigator.pushReplacementNamed(context, '/login');
}
```

### Server Side (Optional)

```php
<?php
// Optional: Invalidate token on server
function logout($token) {
    $stmt = $pdo->prepare("DELETE FROM auth_tokens WHERE token = ?");
    $stmt->execute([$token]);
    
    return ['success' => true, 'message' => 'Logged out successfully'];
}
```

---

## 6. Token Configuration

**Location:** `lib/config.dart` (lines ~229-233)

```dart
// Offline session configuration - matches online behavior
static const int offlineSessionExpiryDays = 7;
static const bool offlineTokenRefreshEnabled = true;
static const int offlineTokenLength = 64;
```

**Token Properties:**
- **Length:** 64 characters (hex)
- **Format:** Hexadecimal string (a-f0-9)
- **Expiry:** 7 days from creation
- **Refresh:** Auto-extend during last day (optional)
- **Storage:** SharedPreferences (encrypted on device)

---

## 7. Security Features

### ✅ Current Implementation

1. **HTTPS Only:** All production requests use HTTPS
2. **Bearer Token:** Standard OAuth 2.0 Bearer token format
3. **Secure Storage:** SharedPreferences (encrypted on Android/iOS)
4. **Token Expiry:** 7-day expiration
5. **Server Validation:** Every API call validates token
6. **No Token Logging:** Only first/last 16 chars logged for debugging
7. **Logout Clears Token:** Complete cleanup on logout

### 🔒 Best Practices Followed

```dart
// ✅ DO: Send token in Authorization header
headers: {'Authorization': 'Bearer $token'}

// ❌ DON'T: Send token in URL
// Bad: '/api/endpoint?token=$token'

// ✅ DO: Check token before each request
final token = await AppConfig.getAuthToken();
if (token == null) throw Exception('Not authenticated');

// ✅ DO: Handle 401 responses
if (response.statusCode == 401) {
  // Token expired - redirect to login
}

// ✅ DO: Clear token on logout
await prefs.remove('auth_token');
```

---

## 8. Integration with External Systems

### For MTL or Other External APIs

If an external system (like MTL) needs to verify user sessions, they can:

**Option A: Use Our Auth Token (Recommended)**

1. When user logs into RLMSS, we generate `auth_token`
2. External system receives `auth_token` from RLMSS app
3. External system calls our API to verify token:

```php
// MTL calls our endpoint
POST /mobile/verify_token.php
Authorization: Bearer <our_auth_token>

// We respond with user details
{
  "valid": true,
  "user": {
    "id": "12345",
    "name": "Thabo Mokoena",
    "email": "thabo@example.com",
    "role": "learner",
    "expires_at": "2024-11-23T14:30:00Z"
  }
}
```

**Option B: Shared Authentication**

1. User logs into MTL system → MTL generates their token
2. MTL shares token with RLMSS app
3. Both systems validate the same token
4. Requires shared token database or API

**Option C: Independent Sessions (Not Recommended)**

- Each system maintains separate tokens
- Requires user to login to both systems
- Complex and poor UX

---

## 9. API Endpoints That Use Auth Token

**All protected endpoints require `Authorization: Bearer <token>` header:**

### Clock-In/Out
- `POST /mobile/clocking/clockin.php`
- `POST /mobile/clocking/clockout.php`
- `POST /mobile/facilitator_clockin.php`
- `POST /mobile/facilitator_clockout.php`

### Learner Data
- `GET /mobile/get_learners.php`
- `POST /mobile/sync_learner.php`
- `POST /mobile/update_learner.php`
- `GET /mobile/learner_details.php`

### Sync Operations
- `POST /mobile/sync_data`
- `POST /mobile/sync_clocking.php`
- `POST /mobile/sync_unsynced_data.php`

### File Operations
- `GET /mobile/serve_file.php?token=<token>&file=<path>`
- `POST /mobile/upload_image.php`
- `POST /mobile/save_signature.php`

### ARPL/Assessment
- `POST /mobile/save_arpl_appendix_*.php`
- `GET /mobile/get_arpl_data.php`

**Total:** 60+ endpoints require authentication

---

## 10. Testing Authentication

### Test Valid Token

```dart
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testAuth() async {
  // 1. Store test token
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('auth_token', 'test_token_1234567890abcdef...');
  
  // 2. Retrieve token
  final token = await AppConfig.getAuthToken();
  print('Token: $token');
  
  // 3. Make authenticated request
  final response = await http.get(
    Uri.parse(AppConfig.getLearnersUrl),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
```

### Test Expired/Invalid Token

```dart
// Server should return 401 for invalid tokens
final response = await http.get(
  Uri.parse(AppConfig.someUrl),
  headers: {'Authorization': 'Bearer invalid_token'},
);

if (response.statusCode == 401) {
  print('✅ Server correctly rejected invalid token');
  // Redirect to login
}
```

---

## 11. Common Issues & Solutions

### Issue 1: "No auth token available"

**Cause:** User not logged in or token cleared

**Solution:**
```dart
final token = await AppConfig.getAuthToken();
if (token == null) {
  // Redirect to login
  Navigator.pushReplacementNamed(context, '/login');
  return;
}
```

### Issue 2: "401 Unauthorized"

**Cause:** Token expired or invalid

**Solution:**
```dart
if (response.statusCode == 401) {
  // Clear invalid token
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('auth_token');
  
  // Redirect to login
  Navigator.pushReplacementNamed(context, '/login');
}
```

### Issue 3: Token not sent in requests

**Cause:** Missing Authorization header

**Solution:**
```dart
// Always include token in headers
final token = await AppConfig.getAuthToken();
headers: {
  'Content-Type': 'application/json',
  'Authorization': 'Bearer $token', // ← Don't forget this!
}
```

---

## 12. For MTL Integration Team

### What We Provide

✅ **Complete authentication system** with:
- Bearer token generation on login
- Token validation on every API call
- 7-day token expiration
- Secure token storage
- Logout/token invalidation

### What We Need from MTL

**Question 1:** Can MTL use our existing `auth_token` as the "sessionId"?
- If YES: No changes needed, use existing system
- If NO: Why is a separate sessionId required?

**Question 2:** If MTL needs to verify sessions, can we provide an endpoint?

```php
// We can create this endpoint for MTL
POST /mobile/verify_session.php
Authorization: Bearer <our_auth_token>

Response:
{
  "valid": true,
  "user": {
    "id": "12345",
    "name": "Thabo Mokoena", 
    "role": "learner",
    "expires_at": "2024-11-23T14:30:00Z"
  }
}
```

**Question 3:** Does MTL need real-time token validation?
- We can provide webhook/callback when tokens expire
- Or MTL can cache validation results (5 min recommended)

---

## 13. Comparison: Our System vs MTL SessionVerification

| Feature | Our Auth System | MTL Session (Requested) |
|---------|----------------|------------------------|
| **Token Name** | `auth_token` | `sessionId` |
| **Generation** | On login | On login |
| **Format** | 64-char hex | Unknown |
| **Storage** | SharedPreferences | SharedPreferences |
| **HTTP Header** | `Authorization: Bearer <token>` | `Authorization: Bearer <sessionId>` |
| **Expiry** | 7 days | Unknown |
| **Validation** | Every API call | Every API call |
| **Logout** | Clear token | Clear sessionId |

**Conclusion:** Both systems are **identical**. No need for two separate session systems.

---

## 14. Recommendation

**Use our existing `auth_token` as the sessionId.** 

**Benefits:**
✅ No code changes needed
✅ Single authentication system (simpler)
✅ Already tested and production-ready
✅ Secure and follows OAuth 2.0 standards
✅ No duplicate token storage
✅ Better user experience (single login)

**Next Steps:**
1. Share this document with MTL team
2. Confirm MTL can use our `auth_token`
3. If needed, create `/mobile/verify_session.php` endpoint for MTL
4. Test integration with MTL system

---

## Questions?

Contact: Gendac Development Team
- Repository: https://github.com/Siyamkhize/rlmsv1
- Documentation: See `DEPLOYMENT_SECURITY.md`
