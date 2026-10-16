# Implementation Plan: Offline Token Fix

## Context
This plan fixes three issues in the offline authentication token implementation in `lib/database_helper.dart`:
1. **CRITICAL** — onCreate missing offline_sessions table
2. **HIGH** — Device binding not enforced in validateOfflineToken
3. **MEDIUM** — No audit trail for token operations

The v17→v18 migration (lines 1281-1316) already has the correct CREATE TABLE SQL for `offline_sessions`. The table has columns: `id`, `user_email`, `token_hash`, `device_id`, `created_at`, `expires_at`, `last_activity_at`, plus two indexes.

The `_getDeviceId()` helper method (lines 3735-3750) retrieves the device ID using `DeviceInfoPlugin` and returns `androidInfo.id` on Android.

## Implementation Steps

- [ ] 1. Add offline_sessions table creation to onCreate method
      Copy the exact CREATE TABLE SQL (including indexes) from the v17→v18 migration block (lines 1289-1311) and insert it at the end of the onCreate method, just before the `_seedEssentialData(db)` call (line 1926).
      Files: `lib/database_helper.dart` (lines 1920-1926)
      Verify: Run `flutter analyze lib/database_helper.dart` — no syntax errors reported.

- [ ] 2. Enforce device_id binding in validateOfflineToken method
      In the `validateOfflineToken` method (lines 3793-3863), after retrieving the session row (line 3809) and extracting `storedHash` and `expiresAt`, add a device ID check:
      - Extract `device_id` from the session row: `final storedDeviceId = session['device_id'] as String?;`
      - Call `final currentDeviceId = await _getDeviceId();`
      - Add comparison logic: if `storedDeviceId != null && storedDeviceId != currentDeviceId && storedDeviceId != 'unknown_device'`, then log the mismatch with `debugPrint('[OFFLINE_TOKEN] ❌ Device ID mismatch for $email (stored: $storedDeviceId, current: $currentDeviceId)');`, delete the session with `await db.delete('offline_sessions', where: 'user_email = ?', whereArgs: [email]);`, and return false.
      - Insert this check after line 3815 (after extracting expiresAt and before the token hash comparison).
      Files: `lib/database_helper.dart` (lines 3793-3825)
      Verify: Run `flutter analyze lib/database_helper.dart` — no errors. Run `flutter test` if tests exist for database operations.

- [ ] 3. Add audit trail logging to token operations
      Add `print('[OFFLINE_TOKEN_SECURITY] ...')` statements at key points:
      - In `createOfflineToken` (line 3755): after successful token creation (before the return on line 3784), add: `print('[OFFLINE_TOKEN_SECURITY] Token created for $email on device $deviceId, expires ${expiresAt.toIso8601String()}');`
      - In `validateOfflineToken` (line 3793): after the device ID mismatch check (new code from step 2), add: `print('[OFFLINE_TOKEN_SECURITY] Device ID mismatch detected for $email');` (inside the mismatch block).
      - In `validateOfflineToken`: after the token hash mismatch block (line 3824), add: `print('[OFFLINE_TOKEN_SECURITY] Token hash mismatch for $email');` (before the delete call on line 3825).
      - In `validateOfflineToken`: after the expiry check block (line 3831), add: `print('[OFFLINE_TOKEN_SECURITY] Token expired for $email at $expiresAtStr');` (before the delete call on line 3832).
      - In `clearOfflineSession` (line 3896): after the successful delete (line 3904), change the existing debugPrint to also use the SECURITY tag: `print('[OFFLINE_TOKEN_SECURITY] Session cleared for $email (logout)');`
      Files: `lib/database_helper.dart` (lines 3755-3904)
      Verify: Run `flutter analyze lib/database_helper.dart` — no errors. Build the app with `flutter build apk --debug` to ensure compilation succeeds.

## Verification Commands

After completing all steps, verify the complete fix:

1. **Syntax check**: `flutter analyze lib/database_helper.dart`
   - Expected: No issues found
   
2. **Build check**: `flutter build apk --debug`
   - Expected: Build succeeds without errors
   
3. **Runtime test** (if possible): Install on a test device, clear app data, perform a fresh offline login
   - Expected: No crash on first offline login (table exists)
   - Expected: Device binding enforced (token rejected if device changes)
   - Expected: Security logs visible in `adb logcat | grep OFFLINE_TOKEN_SECURITY`

## Notes

- The CREATE TABLE SQL uses `CREATE TABLE IF NOT EXISTS` which is safe for fresh installs.
- Device ID check allows `'unknown_device'` to pass (handles edge cases where device ID cannot be retrieved).
- All print statements use `[OFFLINE_TOKEN_SECURITY]` prefix for easy filtering in production logs.
- The fix is backward-compatible: existing users with v18 databases (from migration) are unaffected.
