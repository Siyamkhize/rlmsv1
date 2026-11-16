# Token Validation Fix - Step by Step Guide

## Problem
HTTP 401: `{"success":false,"message":"Invalid or expired token","error_code":"INVALID_TOKEN"}`

The token exists on client side but the server is rejecting it.

## Root Cause
The `auth_tokens` table exists on the live server, BUT:
1. **Login.php is NOT creating tokens** when users log in
2. OR **Login.php doesn't have the `createAuthToken()` function**

## Solution Steps

### Step 1: Diagnose the Issue

Upload and run the diagnosis script on the live server:

**File**: `mobile/diagnose_auth_token.php`

**Access it**: https://rlms.rlms.co.za/mobile/diagnose_auth_token.php

This will show:
- ✅ auth_tokens table exists
- ✅ Table structure is correct
- ❌ Token count (should show 0 or very few if login isn't working)
- ❌ login.php missing createAuthToken function

### Step 2: Update login.php on Live Server

The live server needs the updated `login.php` with token generation.

**Source file**: `c:\xampp\htdocs\assessorReport2\mobile\login.php`
**Destination**: Upload to `https://rlms.rlms.co.za/mobile/login.php`

**Critical sections that MUST be in login.php**:

1. **Token generation function** (add at top after includes):
```php
// Function to generate a secure random token
function generateSecureToken($length = 64) {
    return bin2hex(random_bytes($length / 2));
}

// Function to create or update an auth token for a user
function createAuthToken($conn, $user_id, $user_role, $expires_hours = 168) { // 1 week expiry
    $token = generateSecureToken();
    $token_hash = hash('sha256', $token); // Hash the token for storage
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
    
    return $token; // Return the raw token to the client
}
```

2. **Call createAuthToken after successful password verification** (for each user type):

**For SDP users**:
```php
if (password_verify($password, $row['password'])) {
    // ... existing session code ...
    
    // Generate auth token
    $auth_token = createAuthToken($conn, $sdp_id, 'sdp');
    
    // ... rest of code ...
    
    echo json_encode([
        'success' => true,
        'role' => 'sdp',
        'auth_token' => $auth_token,  // ⬅️ CRITICAL: Return token
        // ... other fields ...
    ]);
}
```

**For Facilitator/Assessor users**:
```php
if (password_verify($password, $row['password'])) {
    // ... existing session code ...
    
    // Generate auth token
    $auth_token = createAuthToken($conn, $email, $role);
    
    // ... rest of code ...
    
    echo json_encode([
        'success' => true,
        'role' => $role,
        'auth_token' => $auth_token,  // ⬅️ CRITICAL: Return token
        // ... other fields ...
    ]);
}
```

### Step 3: Clear Old Client Tokens

Users who logged in BEFORE this fix have invalid tokens stored on their devices.

**Solution**: User must **log out and log in again** to get a new valid token.

**Alternative** (if logout doesn't work): Clear app data:
```
Settings → Apps → RLMSS → Storage → Clear Data
```

### Step 4: Test the Fix

1. **User logs in** → Server creates token in `auth_tokens` table
2. **Check database**:
   ```sql
   SELECT user_id, user_role, created_at, expires_at 
   FROM auth_tokens 
   WHERE user_id = 'user_email'
   ORDER BY created_at DESC 
   LIMIT 1;
   ```
3. **User attempts manual clocking** → Should work without HTTP 401 error

### Step 5: Verify Fix

**Check server logs** (if available):
```
[AUTH] Token validated for user: xxx
```

**Check app logs**:
```
[COMPREHENSIVE_SYNC] ✅ Image upload successful
```

## Quick Fix Checklist

- [ ] Upload `diagnose_auth_token.php` to live server
- [ ] Run diagnosis and confirm issues
- [ ] Upload updated `login.php` to live server  
- [ ] Verify `createAuthToken()` function exists in login.php
- [ ] Verify token is returned in login response (`'auth_token' => $auth_token`)
- [ ] User logs out completely
- [ ] User logs in again (new token generated)
- [ ] Check `auth_tokens` table has new record
- [ ] Test manual clocking (should work now)

## Files to Upload

1. **mobile/login.php** - Updated with createAuthToken()
2. **mobile/diagnose_auth_token.php** - Diagnosis tool (optional, for testing)

## Expected Results After Fix

**Before fix**:
- auth_tokens table: EMPTY or very few old tokens
- Login response: NO `auth_token` field
- API calls: HTTP 401 INVALID_TOKEN

**After fix**:
- auth_tokens table: New tokens created on each login
- Login response: HAS `auth_token` field with 64-char hex string
- API calls: HTTP 200 SUCCESS

---
**Date**: 2026-11-10  
**Issue**: HTTP 401 INVALID_TOKEN  
**Root Cause**: login.php not creating tokens  
**Fix**: Update login.php with createAuthToken() function  
**User Action**: Log out and log in again
