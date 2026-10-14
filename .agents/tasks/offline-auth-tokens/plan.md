# Implementation Plan: Offline Authentication Tokens and Session Expiry Tracking

## Overview
Implement secure offline session tokens with 7-day expiry to match online behavior. After successful offline bcrypt password verification, generate a cryptographically secure token, store it hashed in SQLite, and validate it on app startup to enable persistent offline sessions.

## Current State (Authoritative)
- Offline login: direct bcrypt password verification against SQLite (line ~3621 in database_helper.dart)
- No token generation after offline verification
- No session expiry tracking offline
- Session exists only in memory; app restart forces re-login
- Online login: generates 64-char token saved in SharedPreferences + MySQL, 7-day expiry

## Goal
Enable offline sessions to survive app restarts with same 7-day lifetime as online sessions.

---

# Implementation Plan

- [x] 1. Add offline session configuration constants to config.dart
      Add OFFLINE_SESSION_EXPIRY_DAYS = 7, OFFLINE_TOKEN_REFRESH_ENABLED = true, and OFFLINE_TOKEN_LENGTH = 64 to match online token behavior.
      Files: c:\projects\rlmss\lib\config.dart
      ✅ COMPLETE: Added constants with documentation comment explaining each setting.

- [x] 2. Create SQLite migration version 18 to add offline_sessions table
      Add migration in _initDatabase onUpgrade block: CREATE TABLE offline_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, user_email TEXT NOT NULL UNIQUE, token_hash TEXT NOT NULL, device_id TEXT, created_at TEXT NOT NULL, expires_at TEXT NOT NULL, last_activity_at TEXT NOT NULL). Bump database version from 17 to 18.
      Files: c:\projects\rlmss\lib\database_helper.dart (line ~696: version, line ~697-1280: onUpgrade block)
      ✅ COMPLETE: Database version bumped to 18, migration added with indexes for email and expires_at.

- [x] 3. Add token generation helper method to DatabaseHelper class
      Create method `Future<String> _generateSecureToken()` that generates a cryptographically secure 64-character hex string using dart:math Random.secure() and crypto package already imported. Follow pattern: generate 32 random bytes, convert to hex string.
      Files: c:\projects\rlmss\lib\database_helper.dart (add after line ~2787 near other helper methods)
      ✅ COMPLETE: Method generates 32 random bytes and converts to 64-char hex string.

- [x] 4. Add token hashing helper method to DatabaseHelper class
      Create method `String _hashToken(String token)` that returns SHA-256 hash of the token as hex string. Use the existing `import 'package:crypto/crypto.dart'` (line 4). Pattern: sha256.convert(utf8.encode(token)).toString().
      Files: c:\projects\rlmss\lib\database_helper.dart (add immediately after _generateSecureToken)
      ✅ COMPLETE: Token hashing using SHA-256.

- [x] 5. Add device ID helper method to DatabaseHelper class
      Create method `Future<String> _getDeviceId()` that uses the existing device_info_plus package (already in pubspec.yaml line 48) to get a unique device identifier. Android: androidInfo.id or androidInfo.androidId; fallback to 'unknown_device'.
      Files: c:\projects\rlmss\lib\database_helper.dart (add after _hashToken method, import 'package:device_info_plus/device_info_plus.dart' at top)
      ✅ COMPLETE: Device ID retrieval for Android and iOS, with error handling. Fixed to use androidInfo.id (not androidId).

- [x] 6. Implement createOfflineToken method in DatabaseHelper
      Create method `Future<String?> createOfflineToken(String email)` that: (1) generates secure token via _generateSecureToken, (2) hashes it via _hashToken, (3) gets device_id via _getDeviceId, (4) calculates expires_at = now + 7 days, (5) UPSERTS into offline_sessions (INSERT OR REPLACE WHERE user_email = email), (6) returns the plaintext token (NOT the hash). Store timestamps as ISO8601 strings.
      Files: c:\projects\rlmss\lib\database_helper.dart (add around line ~2700 after getUserCredentials method)
      ✅ COMPLETE: Token creation with debug logging.

- [x] 7. Implement validateOfflineToken method in DatabaseHelper
      Create method `Future<bool> validateOfflineToken(String email, String token)` that: (1) queries offline_sessions WHERE user_email = email, (2) if not found return false, (3) hash the provided token via _hashToken, (4) compare with stored token_hash, (5) check now < expires_at, (6) if valid, update last_activity_at to now and return true, (7) else delete the row and return false.
      Files: c:\projects\rlmss\lib\database_helper.dart (add immediately after createOfflineToken)
      ✅ COMPLETE: Token validation with hash comparison and expiry check.

- [x] 8. Implement loadOfflineSession method in DatabaseHelper
      Create method `Future<Map<String, dynamic>?> loadOfflineSession(String email)` that: (1) queries offline_sessions WHERE user_email = email, (2) if not found return null, (3) check now < expires_at, (4) if expired, delete the row and return null, (5) if valid return the session record as Map including token_hash, expires_at, last_activity_at.
      Files: c:\projects\rlmss\lib\database_helper.dart (add immediately after validateOfflineToken)
      ✅ COMPLETE: Session loading with expiry check.

- [x] 9. Implement clearOfflineSession method in DatabaseHelper
      Create method `Future<void> clearOfflineSession(String email)` that deletes the offline_sessions row WHERE user_email = email. This is called on logout.
      Files: c:\projects\rlmss\lib\database_helper.dart (add immediately after loadOfflineSession)
      ✅ COMPLETE: Session cleanup on logout.

- [x] 10. Modify _loginOffline in main.dart to call createOfflineToken after successful bcrypt verification
      In _loginOffline method (line ~574), immediately after successful bcrypt verification for both SDP and facilitator paths (after line ~583 for SDP, after line ~642 for facilitator), add: `final token = await dbHelper.createOfflineToken(username); if (token != null) { final prefs = await SharedPreferences.getInstance(); await prefs.setString('offline_token', token); await prefs.setString('offline_user_email', username); }`. This stores the plaintext token in SharedPreferences for session restoration.
      Files: c:\projects\rlmss\lib\main.dart (modify around lines 583, 642 in _loginOffline method)
      ✅ COMPLETE: Token creation after both SDP and facilitator offline login success.

- [x] 11. Add session restoration check in initState of LoginPage
      In initState method (line ~319), after _checkDatabase(), add: `_checkOfflineSession()` call. Create new method `Future<void> _checkOfflineSession()` that: (1) gets SharedPreferences, (2) reads 'offline_token' and 'offline_user_email', (3) if both exist, call dbHelper.loadOfflineSession(email), (4) if session valid, fetch user details from local DB (getSdp or getFacilitator), (5) call _navigateBasedOnRole to auto-login, (6) else clear the invalid SharedPreferences keys.
      Files: c:\projects\rlmss\lib\main.dart (add method around line 380, call it in initState after line 323)
      ✅ COMPLETE: Session restoration on app startup with comprehensive user type handling. Added helper methods getSdpByEmail and getFacilitatorByEmail to database_helper.dart.

- [x] 12. Implement token refresh logic (extend expires_at on activity)
      Modify validateOfflineToken (from step 7): if token is valid AND expires_at - now < 1 day, extend expires_at by another 7 days (new expiry = now + 7 days). This implements automatic token refresh on activity during the last day of the session.
      Files: c:\projects\rlmss\lib\database_helper.dart (modify validateOfflineToken method)
      ✅ COMPLETE: Token refresh when < 24 hours remain, controlled by OFFLINE_TOKEN_REFRESH_ENABLED config.

- [x] 13. Add logout path to clear offline session
      Search for any logout/signOut functionality in the app. If none exists, document that logout must call: `final prefs = await SharedPreferences.getInstance(); final email = prefs.getString('offline_user_email'); if (email != null) { await dbHelper.clearOfflineSession(email); } await prefs.remove('offline_token'); await prefs.remove('offline_user_email');`. Add this as a helper method `Future<void> _logout()` in main.dart.
      Files: c:\projects\rlmss\lib\main.dart (add _logout method around line 1000, after _navigateBasedOnRole)
      ✅ COMPLETE: _logout() method added to LoginPage, clears offline session, SharedPreferences, and auth_token, then navigates back to login.

- [x] 14. Add auto-logout check on app resume
      In main.dart, if there's a WidgetsBindingObserver pattern (check for didChangeAppLifecycleState), add session expiry check when app resumes from background. If no observer exists, document that auto-logout on expiry happens on next app restart via step 11's validation.
      Files: c:\projects\rlmss\lib\main.dart (search for didChangeAppLifecycleState or document the limitation)
      ✅ DOCUMENTED: Auto-logout on expiry happens at app restart via _checkOfflineSession. No WidgetsBindingObserver found in LoginPage (app lifecycle checks not implemented there).

- [x] 15. Add backward compatibility handling for existing installations
      The migration in step 2 handles new installations. For existing installations upgrading from version 17, the onUpgrade block will create the offline_sessions table. No data migration needed since offline sessions didn't exist before. Add debug logging in the migration to confirm table creation.
      Files: c:\projects\rlmss\lib\database_helper.dart (add debug logging in migration version 18 block)
      ✅ COMPLETE: Debug logging included in v18 migration block.

- [x] 16. Add debug logging and documentation
      Add debug logging throughout: (1) token generation success/failure, (2) token validation success/failure/expiry, (3) token refresh events, (4) session restoration attempts, (5) session clear events. Use debugPrint with '[OFFLINE_TOKEN]' prefix for easy filtering.
      Files: All modified files (database_helper.dart, main.dart)
      ✅ COMPLETE: Comprehensive debug logging with [OFFLINE_TOKEN] prefix throughout all token operations.

- [x] 17. Update config.dart documentation
      Add a comment block above the new constants explaining: "Offline session configuration - matches online behavior. OFFLINE_SESSION_EXPIRY_DAYS: sessions last 7 days. OFFLINE_TOKEN_REFRESH_ENABLED: auto-extend expiry during last day. OFFLINE_TOKEN_LENGTH: 64-char hex token matches online format."
      Files: c:\projects\rlmss\lib\config.dart
      ✅ COMPLETE: Documentation comment added explaining all three constants.

- [x] 18. Final integration testing
      Build debug APK with `flutter build apk --debug`. Test sequence: (1) fresh install - offline login creates token, (2) close app, reopen - auto-login works, (3) wait until expires_at (or manually modify DB to set expires_at to past), (4) reopen app - forced to re-login, (5) during refresh window (last day) trigger validateOfflineToken - confirm token is extended. Use `adb logcat | grep OFFLINE_TOKEN` to monitor.
      Files: N/A (testing only)
      ⏳ READY FOR TESTING: Implementation complete, awaiting manual testing.

---

## Flutter Analyze Results

Ran `flutter analyze lib/database_helper.dart lib/main.dart lib/config.dart`
- ✅ No errors in modified files
- Pre-existing errors in other files (offline_sync_clock_button.dart, request_monitoring_service.dart) are unrelated to this implementation

Fixed issue: Changed `androidInfo.id ?? androidInfo.androidId` to just `androidInfo.id` as androidId property doesn't exist in newer device_info_plus versions.

---
      Add OFFLINE_SESSION_EXPIRY_DAYS = 7, OFFLINE_TOKEN_REFRESH_ENABLED = true, and OFFLINE_TOKEN_LENGTH = 64 to match online token behavior.
      Files: c:\projects\rlmss\lib\config.dart
      Verify: Run `flutter analyze` and confirm no errors. Grep for the new constants to confirm they exist.

- [ ] 2. Create SQLite migration version 18 to add offline_sessions table
      Add migration in _initDatabase onUpgrade block: CREATE TABLE offline_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, user_email TEXT NOT NULL UNIQUE, token_hash TEXT NOT NULL, device_id TEXT, created_at TEXT NOT NULL, expires_at TEXT NOT NULL, last_activity_at TEXT NOT NULL). Bump database version from 17 to 18.
      Files: c:\projects\rlmss\lib\database_helper.dart (line ~696: version, line ~697-1280: onUpgrade block)
      Verify: Run `flutter clean && flutter pub get && flutter build apk --debug` and confirm build succeeds. Check logs for "[DB] Upgrading database from version 17 to 18".

- [ ] 3. Add token generation helper method to DatabaseHelper class
      Create method `Future<String> _generateSecureToken()` that generates a cryptographically secure 64-character hex string using dart:math Random.secure() and crypto package already imported. Follow pattern: generate 32 random bytes, convert to hex string.
      Files: c:\projects\rlmss\lib\database_helper.dart (add after line ~2787 near other helper methods)
      Verify: Run `flutter analyze` and confirm no errors in database_helper.dart.

- [ ] 4. Add token hashing helper method to DatabaseHelper class
      Create method `String _hashToken(String token)` that returns SHA-256 hash of the token as hex string. Use the existing `import 'package:crypto/crypto.dart'` (line 4). Pattern: sha256.convert(utf8.encode(token)).toString().
      Files: c:\projects\rlmss\lib\database_helper.dart (add immediately after _generateSecureToken)
      Verify: Run `flutter analyze` and confirm no errors in database_helper.dart.

- [ ] 5. Add device ID helper method to DatabaseHelper class
      Create method `Future<String> _getDeviceId()` that uses the existing device_info_plus package (already in pubspec.yaml line 48) to get a unique device identifier. Android: androidInfo.id or androidInfo.androidId; fallback to 'unknown_device'.
      Files: c:\projects\rlmss\lib\database_helper.dart (add after _hashToken method, import 'package:device_info_plus/device_info_plus.dart' at top)
      Verify: Run `flutter analyze` and confirm no errors in database_helper.dart.

- [ ] 6. Implement createOfflineToken method in DatabaseHelper
      Create method `Future<String?> createOfflineToken(String email)` that: (1) generates secure token via _generateSecureToken, (2) hashes it via _hashToken, (3) gets device_id via _getDeviceId, (4) calculates expires_at = now + 7 days, (5) UPSERTS into offline_sessions (INSERT OR REPLACE WHERE user_email = email), (6) returns the plaintext token (NOT the hash). Store timestamps as ISO8601 strings.
      Files: c:\projects\rlmss\lib\database_helper.dart (add around line ~2700 after getUserCredentials method)
      Verify: Run `flutter analyze` and confirm no errors. Add debug logging to print when token is created.

- [ ] 7. Implement validateOfflineToken method in DatabaseHelper
      Create method `Future<bool> validateOfflineToken(String email, String token)` that: (1) queries offline_sessions WHERE user_email = email, (2) if not found return false, (3) hash the provided token via _hashToken, (4) compare with stored token_hash, (5) check now < expires_at, (6) if valid, update last_activity_at to now and return true, (7) else delete the row and return false.
      Files: c:\projects\rlmss\lib\database_helper.dart (add immediately after createOfflineToken)
      Verify: Run `flutter analyze` and confirm no errors.

- [ ] 8. Implement loadOfflineSession method in DatabaseHelper
      Create method `Future<Map<String, dynamic>?> loadOfflineSession(String email)` that: (1) queries offline_sessions WHERE user_email = email, (2) if not found return null, (3) check now < expires_at, (4) if expired, delete the row and return null, (5) if valid return the session record as Map including token_hash, expires_at, last_activity_at.
      Files: c:\projects\rlmss\lib\database_helper.dart (add immediately after validateOfflineToken)
      Verify: Run `flutter analyze` and confirm no errors.

- [ ] 9. Implement clearOfflineSession method in DatabaseHelper
      Create method `Future<void> clearOfflineSession(String email)` that deletes the offline_sessions row WHERE user_email = email. This is called on logout.
      Files: c:\projects\rlmss\lib\database_helper.dart (add immediately after loadOfflineSession)
      Verify: Run `flutter analyze` and confirm no errors.

- [ ] 10. Modify _loginOffline in main.dart to call createOfflineToken after successful bcrypt verification
      In _loginOffline method (line ~574), immediately after successful bcrypt verification for both SDP and facilitator paths (after line ~583 for SDP, after line ~642 for facilitator), add: `final token = await dbHelper.createOfflineToken(username); if (token != null) { final prefs = await SharedPreferences.getInstance(); await prefs.setString('offline_token', token); await prefs.setString('offline_user_email', username); }`. This stores the plaintext token in SharedPreferences for session restoration.
      Files: c:\projects\rlmss\lib\main.dart (modify around lines 583, 642 in _loginOffline method)
      Verify: Run `flutter analyze` and confirm no errors in main.dart. Add debug logging to print when offline token is created.

- [ ] 11. Add session restoration check in initState of LoginPage
      In initState method (line ~319), after _checkDatabase(), add: `_checkOfflineSession()` call. Create new method `Future<void> _checkOfflineSession()` that: (1) gets SharedPreferences, (2) reads 'offline_token' and 'offline_user_email', (3) if both exist, call dbHelper.loadOfflineSession(email), (4) if session valid, fetch user details from local DB (getSdp or getFacilitator), (5) call _navigateBasedOnRole to auto-login, (6) else clear the invalid SharedPreferences keys.
      Files: c:\projects\rlmss\lib\main.dart (add method around line 380, call it in initState after line 323)
      Verify: Run `flutter analyze` and confirm no errors. Test by closing app after offline login and reopening - should auto-login without password prompt.

- [ ] 12. Implement token refresh logic (extend expires_at on activity)
      Modify validateOfflineToken (from step 7): if token is valid AND expires_at - now < 1 day, extend expires_at by 7 days (new expiry = now + 7 days). This implements automatic token refresh on activity during the last day of the session.
      Files: c:\projects\rlmss\lib\database_helper.dart (modify validateOfflineToken method)
      Verify: Run `flutter analyze` and confirm no errors. Add debug logging to print when token is refreshed.

- [ ] 13. Add logout path to clear offline session
      Search for any logout/signOut functionality in the app. If none exists, document that logout must call: `final prefs = await SharedPreferences.getInstance(); final email = prefs.getString('offline_user_email'); if (email != null) { await dbHelper.clearOfflineSession(email); } await prefs.remove('offline_token'); await prefs.remove('offline_user_email');`. Add this as a helper method `Future<void> _logout()` in main.dart.
      Files: c:\projects\rlmss\lib\main.dart (add _logout method around line 1000, after _navigateBasedOnRole)
      Verify: Run `flutter analyze` and confirm no errors. Document the logout path clearly.

- [ ] 14. Add auto-logout check on app resume
      In main.dart, if there's a WidgetsBindingObserver pattern (check for didChangeAppLifecycleState), add session expiry check when app resumes from background. If no observer exists, document that auto-logout on expiry happens on next app restart via step 11's validation.
      Files: c:\projects\rlmss\lib\main.dart (search for didChangeAppLifecycleState or document the limitation)
      Verify: Run `flutter analyze` and confirm no errors. Document the auto-logout behavior.

- [ ] 15. Add backward compatibility handling for existing installations
      The migration in step 2 handles new installations. For existing installations upgrading from version 17, the onUpgrade block will create the offline_sessions table. No data migration needed since offline sessions didn't exist before. Add debug logging in the migration to confirm table creation.
      Files: c:\projects\rlmss\lib\database_helper.dart (add debug logging in migration version 18 block)
      Verify: Run `flutter analyze` and confirm no errors. Test upgrade path by installing v17 APK, then v18 APK - confirm no crashes.

- [ ] 16. Add debug logging and documentation
      Add debug logging throughout: (1) token generation success/failure, (2) token validation success/failure/expiry, (3) token refresh events, (4) session restoration attempts, (5) session clear events. Use debugPrint with '[OFFLINE_TOKEN]' prefix for easy filtering.
      Files: All modified files (database_helper.dart, main.dart)
      Verify: Run the app with `flutter run` and check logs for '[OFFLINE_TOKEN]' entries. Confirm all key events are logged.

- [ ] 17. Update config.dart documentation
      Add a comment block above the new constants explaining: "Offline session configuration - matches online behavior. OFFLINE_SESSION_EXPIRY_DAYS: sessions last 7 days. OFFLINE_TOKEN_REFRESH_ENABLED: auto-extend expiry during last day. OFFLINE_TOKEN_LENGTH: 64-char hex token matches online format."
      Files: c:\projects\rlmss\lib\config.dart
      Verify: Run `flutter analyze` and confirm no errors. Grep for the documentation comment.

- [ ] 18. Final integration testing
      Build debug APK with `flutter build apk --debug`. Test sequence: (1) fresh install - offline login creates token, (2) close app, reopen - auto-login works, (3) wait until expires_at (or manually modify DB to set expires_at to past), (4) reopen app - forced to re-login, (5) during refresh window (last day) trigger validateOfflineToken - confirm token is extended. Use `adb logcat | grep OFFLINE_TOKEN` to monitor.
      Files: N/A (testing only)
      Verify: All test scenarios pass: token creation, session restoration, expiry enforcement, token refresh.

---

## Key Design Decisions

### 1. Token Storage Strategy
**Decision:** Store plaintext token in SharedPreferences, hashed token in SQLite.
**Rationale:** SharedPreferences is isolated per-app (Android sandbox), plaintext needed for validation. SQLite stores hash for security - if DB is compromised, tokens can't be extracted.

### 2. Token Format
**Decision:** 64-character hex string (32 random bytes).
**Rationale:** Matches online token format for consistency. Provides 256 bits of entropy, cryptographically secure against brute force.

### 3. Session Expiry
**Decision:** 7 days, matching online behavior.
**Rationale:** User requirement for parity. Balances security (periodic re-authentication) with convenience (week-long offline sessions).

### 4. Token Refresh Strategy
**Decision:** Auto-extend expires_at by 7 days when validated within last day of expiry.
**Rationale:** Prevents abrupt logout for active users. Similar to sliding window sessions in web apps.

### 5. Device Binding
**Decision:** Store device_id but don't enforce it for validation in v1.
**Rationale:** Future-proofing for multi-device detection. Current scope is session persistence, not device security. Can add validation in future without schema change.

### 6. Backward Compatibility
**Decision:** Migration creates table, no data migration needed.
**Rationale:** Feature didn't exist before - no old data to migrate. Existing users simply start fresh with new tokens on next offline login.

### 7. Logout Implementation
**Decision:** Document logout pattern, add helper method, but don't integrate into UI in this plan.
**Rationale:** No existing logout UI found in codebase exploration. Providing the building block for future UI integration. Manual testing can call the method directly.

---

## Verification Commands

1. **Build check:** `flutter clean && flutter pub get && flutter build apk --debug`
2. **Static analysis:** `flutter analyze`
3. **Log monitoring:** `adb logcat | grep -E "OFFLINE_TOKEN|DB.*version"`
4. **Database inspection:** `adb shell "run-as com.example.rlmss cat /data/data/com.example.rlmss/databases/local_data.db" | sqlite3` (requires rooted device or debug build)

---

## Dependencies
- crypto: ^3.0.3 (already in pubspec.yaml)
- device_info_plus: ^11.0.0 (already in pubspec.yaml)
- shared_preferences: ^2.2.0 (already in pubspec.yaml)
- sqflite: ^2.3.3+1 (already in pubspec.yaml)

No new dependencies required.

---

## Security Considerations

1. **Token Entropy:** 256 bits from Random.secure() - CSPRNG quality
2. **Token Hashing:** SHA-256 before storage prevents rainbow table attacks
3. **Expiry Enforcement:** Hard 7-day limit, no indefinite sessions
4. **Device Isolation:** SharedPreferences is sandboxed per-app by Android
5. **SQLite Security:** Plain text passwords NOT stored (bcrypt hashes only, existing behavior)
6. **Future Enhancement:** Device binding field ready for multi-device lockout feature

---

## Testing Scenarios

1. **Happy Path:** Offline login → token created → app restart → auto-login
2. **Expiry Path:** Offline login → manually set expires_at to past → app restart → forced re-login
3. **Refresh Path:** Offline login → wait 6 days → trigger validation → expires_at extended
4. **Upgrade Path:** Install v17 → upgrade to v18 → offline login → confirm no crashes
5. **Invalid Token Path:** Offline login → manually corrupt token in SharedPreferences → app restart → forced re-login
6. **Logout Path:** Offline login → call _logout() → app restart → forced re-login

---

## Files Modified

1. c:\projects\rlmss\lib\config.dart - Add constants
2. c:\projects\rlmss\lib\database_helper.dart - Migration, token methods
3. c:\projects\rlmss\lib\main.dart - Session restoration, logout helper

## Files Created

None (all changes are modifications to existing files)

---

## Rollback Plan

If issues arise:
1. Revert database version from 18 to 17
2. Remove offline_sessions table creation from onUpgrade
3. Remove token generation calls from _loginOffline
4. Remove session restoration from initState
5. System reverts to original behavior (memory-only sessions)

---

## Future Enhancements (Out of Scope)

1. Multi-device session management (device_id enforcement)
2. Session revocation API endpoint
3. Biometric unlock for token access
4. Offline session analytics (login frequency, expiry patterns)
5. Integration with online token refresh (sync expiry times)

---

## Notes

- Online tokens stored in SharedPreferences + MySQL (per exploration of main.dart line ~477)
- Online token validation found in multiple service files (offline_sync_queue_service.dart, signature_geofence_clock_in_page.dart, etc.) via Authorization header
- Database helper already imports crypto, convert, device_info_plus is in pubspec
- Current database version is 17 (database_helper.dart line 696)
- Offline login paths: SDP check (line ~583), Facilitator check (line ~642)
- No existing logout functionality found in codebase - building block provided
