# Token Mismatch Issue - RESOLVED

## Issue Summary
Online clock-in failing with 401 "Invalid or expired token" error.

## Root Cause
**The device is using an OUTDATED token that no longer exists in the database.**

### Evidence:
1. **Device Token:** `c93883b50bf29398a560adc3ae6ae8714663705fb7ef54457d3c861c17cae461`
   - Hashes to: `6bbf91722ca0426fafcaae2e16925a1fa06f7130cebee1e537ef81288aaa0a61`
   - **NOT FOUND in database**

2. **Database Token (for user 148):**
   - Hash: `4e5fb410bf0ca148999ddfecc39a40714b2ddf1e3601a0d430572eeffbb3386f`
   - Created: `2026-10-16 09:11:56` (today at 9:11 AM)
   - Status: ✅ Valid, not expired, not revoked
   - **This is the CURRENT token**

3. **Why the mismatch?**
   - User logged in at 9:11 AM, which created a NEW token
   - The login endpoint DELETES all old tokens and creates a fresh one (security feature)
   - The device still has the token from a PREVIOUS login
   - The old token hash was deleted from database

## How Token Authentication Works

```
Login Flow:
┌──────────┐                    ┌──────────┐                    ┌──────────┐
│  Device  │                    │  Server  │                    │ Database │
└────┬─────┘                    └────┬─────┘                    └────┬─────┘
     │                               │                               │
     │ POST /login                   │                               │
     ├──────────────────────────────►│                               │
     │ {email, password}             │ 1. Verify credentials         │
     │                               ├──────────────────────────────►│
     │                               │                               │
     │                               │ 2. DELETE old tokens          │
     │                               │    for this user              │
     │                               ├──────────────────────────────►│
     │                               │                               │
     │                               │ 3. Generate random            │
     │                               │    raw_token (64 chars)       │
     │                               │                               │
     │                               │ 4. Hash token                 │
     │                               │    token_hash = SHA256(       │
     │                               │       raw_token)              │
     │                               │                               │
     │                               │ 5. INSERT INTO auth_tokens    │
     │                               ├──────────────────────────────►│
     │                               │    (token_hash, expires_at)   │
     │                               │                               │
     │ Response:                     │                               │
     │ {auth_token: raw_token}       │                               │
     │◄──────────────────────────────┤                               │
     │                               │                               │
     │ STORE raw_token locally       │                               │
     │                               │                               │
     └───────────────────────────────┴───────────────────────────────┘


API Request Flow (Clock-In):
┌──────────┐                    ┌──────────┐                    ┌──────────┐
│  Device  │                    │  Server  │                    │ Database │
└────┬─────┘                    └────┬─────┘                    └────┬─────┘
     │                               │                               │
     │ POST /save_manual_clocking    │                               │
     │ Authorization: Bearer TOKEN   │                               │
     ├──────────────────────────────►│                               │
     │                               │ 1. Extract token from header  │
     │                               │                               │
     │                               │ 2. Hash received token        │
     │                               │    hash = SHA256(token)       │
     │                               │                               │
     │                               │ 3. SELECT FROM auth_tokens    │
     │                               ├──────────────────────────────►│
     │                               │    WHERE token_hash = hash    │
     │                               │      AND expires_at > NOW()   │
     │                               │      AND revoked_at IS NULL   │
     │                               │◄──────────────────────────────┤
     │                               │                               │
     │                               │ IF FOUND:                     │
     │                               │   ✅ Allow request            │
     │                               │ ELSE:                         │
     │                               │   ❌ 401 Invalid token        │
     │                               │                               │
     └───────────────────────────────┴───────────────────────────────┘
```

## Why Device Has Old Token

**Scenario:**
1. User logged in on **Day 1** → Device received token `ABC...123`
2. APK was **rebuilt and reinstalled multiple times**
3. Device **kept the stored token** in SharedPreferences (persistent storage)
4. User logged in **again today at 9:11 AM** (maybe from another session or after app reinstall)
5. Server **deleted old token `ABC...123`** and created new token `XYZ...789`
6. But the device **still using old token `ABC...123`** from storage
7. Server says: "Token `ABC...123` not found" → 401 error

## Solution

**USER ACTION REQUIRED: Log out and log back in on device RZ8X306F7TZ**

### Steps:
1. Open the app on device RZ8X306F7TZ
2. **Log out** (this clears the stored token)
3. **Log back in** with credentials
4. The app will receive the CURRENT token
5. Clock-in will work

### Why This Fixes It:
```dart
// When user logs out:
await prefs.remove('auth_token');  // Old token cleared ✅

// When user logs in again:
final response = await http.post('/login', ...);
final newToken = response['auth_token'];
await prefs.setString('auth_token', newToken);  // NEW token stored ✅

// Next clock-in will use the NEW token that exists in database ✅
```

## Prevention

### For Future APK Releases:
No code changes needed. This is **expected behavior** when:
- Multiple installs happen
- User logs in from different contexts
- Testing involves multiple login sessions

### Token Expiry Policy:
- ✅ Tokens expire after **7 days** (168 hours)
- ✅ Each login **deletes old tokens** (security feature)
- ✅ Only **one active token per user** (prevents token proliferation)
- ✅ Token refresh requires **re-login** (standard practice)

## Verification

After user logs back in, verify with:

```bash
# On device, check stored token matches database
php mobile/debug_token_validation.php
```

Expected output:
```
✅ Token Found!
✅ QUERY SUCCESSFUL
✅ FUNCTION RETURNED USER DATA
```

## Summary

✅ **Server authentication is working correctly**
✅ **Token validation logic is correct**
✅ **Anti-flooding protection is in place**
✅ **Database schema is correct**

❌ **Device has outdated token**
✅ **Solution: User must log out and log back in**

## Technical Notes

### Token Security Features Working As Designed:
1. ✅ **Token hashing** - Raw tokens never stored in database
2. ✅ **Token rotation** - Old tokens deleted on new login
3. ✅ **Expiration checking** - 7-day expiry enforced
4. ✅ **Revocation support** - `revoked_at` column checked
5. ✅ **Rate limiting** - 10 login attempts per minute max

### No Server-Side Changes Needed:
- authentication middleware is correct
- validate_auth_token() is correct
- endpoints are correct
- database schema is correct

### Device-Side Behavior:
- Token persists in SharedPreferences
- Survives APK reinstalls (if app data not cleared)
- Must be manually refreshed via re-login

---

**STATUS: Issue diagnosed. Waiting for user to log out/in on device.**

**NEXT STEP: After re-login, test online clock-in to confirm it works.**
