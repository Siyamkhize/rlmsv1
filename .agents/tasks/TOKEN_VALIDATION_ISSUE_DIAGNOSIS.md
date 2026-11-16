# Token Validation Issue - HTTP 401 Invalid Token

## Problem
User is getting HTTP 401 error: `{"success":false,"message":"Invalid or expired token","error_code":"INVALID_TOKEN"}`

The token exists on the client side (64 characters) and is being sent correctly in the Authorization header, but the server is rejecting it.

## Root Cause Analysis

### How Token Authentication Works

1. **Login (mobile/login.php)**:
   - User logs in with email/password
   - Server generates a secure random token (64 hex chars)
   - Server stores **hash('sha256', $token)** in `auth_tokens` table
   - Server returns the **raw token** to client
   - Client stores token in SharedPreferences

2. **API Request (mobile/save_manual_clocking_images.php)**:
   - Client sends `Authorization: Bearer <token>` header
   - Server includes `require_auth.php`
   - `requireAuth($conn)` is called

3. **Token Validation (mobile/security_middleware.php -> validate_auth_token)**:
   - Extract token from Authorization header
   - Sanitize token: `preg_replace('/[^a-zA-Z0-9]/', '', $token)`
   - Hash token: `$token_hash = hash('sha256', $token)`
   - Query database:
     ```sql
     SELECT user_id, user_role, created_at, expires_at 
     FROM auth_tokens 
     WHERE token_hash = ? 
       AND expires_at > NOW()
       AND revoked_at IS NULL
     ```
   - If match found → authenticated ✅
   - If no match → HTTP 401 INVALID_TOKEN ❌

## Why Token Validation is Failing

The token validation is failing because one of these issues:

### Issue 1: `auth_tokens` Table Missing on Live Server ⚠️
The `auth_tokens` table might not exist on the live server (rlms.rlms.co.za/mobile).

**Check on live server**:
```sql
SHOW TABLES LIKE 'auth_tokens';
```

**Create table if missing**:
```sql
CREATE TABLE IF NOT EXISTS auth_tokens (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    user_role VARCHAR(50) NOT NULL,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    last_used_at TIMESTAMP NULL,
    revoked_at TIMESTAMP NULL,
    INDEX idx_token_hash (token_hash),
    INDEX idx_user (user_id, user_role),
    INDEX idx_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### Issue 2: Login.php Not Creating Tokens on Live Server ⚠️
The live server's `mobile/login.php` might not have the `createAuthToken()` function.

**Check login.php on live server** for:
```php
function createAuthToken($conn, $user_id, $user_role, $expires_hours = 168) {
    $token = generateSecureToken();
    $token_hash = hash('sha256', $token);
    $expires_at = date('Y-m-d H:i:s', time() + ($expires_hours * 3600));
    
    // Delete existing tokens for this user
    $stmt_delete = $conn->prepare("DELETE FROM auth_tokens WHERE user_id = ? AND user_role = ?");
    if ($stmt_delete) {
        $stmt_delete->bind_param("ss", $user_id, $user_role);
        $stmt_delete->execute();
        $stmt_delete->close();
    }
    
    // Insert new token
    $stmt = $conn->prepare("INSERT INTO auth_tokens (user_id, user_role, token_hash, expires_at) VALUES (?, ?, ?, ?)");
    if ($stmt) {
        $stmt->bind_param("ssss", $user_id, $user_role, $token_hash, $expires_at);
        $stmt->execute();
        $stmt->close();
    }
    
    return $token;
}
```

**And the call to createAuthToken after password verification**:
```php
// Generate auth token
$auth_token = createAuthToken($conn, $user_id, 'facilitator'); // or 'sdp', etc.

// Return token in response
echo json_encode([
    'success' => true,
    'auth_token' => $auth_token,  // ⬅️ THIS IS CRITICAL
    // ... other data ...
]);
```

### Issue 3: Old Tokens in Database ⚠️
If tokens were created before the security update, they might be in an old format or using an old table structure.

**Clear old tokens**:
```sql
DELETE FROM auth_tokens WHERE created_at < DATE_SUB(NOW(), INTERVAL 7 DAY);
```

## Immediate Fix Steps

### Step 1: Verify auth_tokens Table Exists on Live Server
```bash
# SSH into live server or use phpMyAdmin
mysql -u username -p database_name
```

```sql
-- Check if table exists
SHOW TABLES LIKE 'auth_tokens';

-- If exists, check structure
DESCRIBE auth_tokens;

-- Check if there are any tokens
SELECT COUNT(*) as token_count FROM auth_tokens;
SELECT * FROM auth_tokens LIMIT 5;
```

### Step 2: Create auth_tokens Table if Missing
Run the CREATE TABLE statement from Issue 1 above.

### Step 3: Update login.php on Live Server
Copy the updated login.php to the live server:
- From: `c:\xampp\htdocs\assessorReport2\mobile\login.php`
- To: `/var/www/html/rlms/mobile/login.php` (or appropriate path on live server)

Ensure it includes:
1. `generateSecureToken()` function
2. `createAuthToken()` function
3. Call to `createAuthToken()` after successful password verification
4. Return `'auth_token' => $auth_token` in JSON response

### Step 4: Test Token Generation
Have the user **log out and log in again** to generate a new token that will be stored in the `auth_tokens` table.

### Step 5: Verify Token in Database
After user logs in again, check if token was created:
```sql
SELECT user_id, user_role, created_at, expires_at 
FROM auth_tokens 
WHERE user_id = 'user_email_or_id'
ORDER BY created_at DESC 
LIMIT 1;
```

## Files That Need To Be Deployed to Live Server

1. **mobile/login.php** - Must include createAuthToken() function
2. **mobile/security_middleware.php** - Must include validate_auth_token() function  
3. **mobile/require_auth.php** - Must include requireAuth() function
4. **SQL migration** - CREATE auth_tokens table

## Testing After Fix

1. **User logs out completely** (clear app data if needed)
2. **User logs in again** → new token generated and stored in auth_tokens table
3. **User attempts manual clocking** → should work without HTTP 401 error
4. **Check logs**: Should see `[AUTH] Token validated for user: ...`

## Why This Happened

The authentication system was upgraded to use token-based auth instead of session-based auth, but the changes were only deployed to the local XAMPP server, not to the live production server (rlms.rlms.co.za).

---
**Date**: 2026-11-10  
**Issue**: HTTP 401 INVALID_TOKEN on manual clocking image upload  
**Root Cause**: Live server missing auth_tokens table or updated login.php  
**Resolution**: Deploy updated files and create auth_tokens table on live server
