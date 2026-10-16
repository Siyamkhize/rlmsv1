# Offline token security fixes

Three targeted fixes to database_helper.dart: persistent offline_sessions table creation, device-bound token validation, and audit logging. The changes address session storage consistency, token hijacking risk, and operational observability.

**Watch for:** The device ID retrieval uses `androidInfo.id` which may not be available on all Android API levels—this could silently degrade to 'unknown_device' and bypass device binding on older devices.

**Verdict**: APPROVED

## High-level view

The `offline_sessions` table is now created in both the v17→v18 migration path and the fresh-install onCreate path with matching schemas (seven columns including device_id, all three indexes). Token validation retrieves the current device ID via `_getDeviceId()` and compares it against the stored `device_id` column, returning false and deleting the session on mismatch. Audit logs are present in all three functions (createOfflineToken, validateOfflineToken, clearOfflineSession) using the `[OFFLINE_TOKEN_SECURITY]` prefix, covering success and all failure branches. The device ID method changed from `androidInfo.androidId` to `androidInfo.id` to resolve a compilation error—this is a property name change in device_info_plus, but the fallback to 'unknown_device' on error means device binding may not work on all devices.

<details>
<summary>Issues (1)</summary>

1. **Device ID fallback weakens security** — The `_getDeviceId()` method returns 'unknown_device' on error or unsupported platforms. validateOfflineToken explicitly skips device binding checks when stored device is 'unknown_device' (line 3847), meaning tokens created with this fallback aren't device-bound. Consider failing token creation instead of silently degrading, or at minimum log a warning when 'unknown_device' is used.

</details>

<details>
<summary>Details</summary>

## offline_sessions table in onCreate

The table is present in the onCreate callback at lines 1927-1947, executed for fresh database installations. The schema matches the onUpgrade v17→v18 migration exactly:

```dart
CREATE TABLE IF NOT EXISTS offline_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_email TEXT NOT NULL UNIQUE,
  token_hash TEXT NOT NULL,
  device_id TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  last_activity_at TEXT NOT NULL
)
```

Seven columns, same types, same constraints. Both paths create the same two indexes (idx_offline_sessions_email on user_email, idx_offline_sessions_expires on expires_at). A database created from scratch will have the table available; a migrated database will receive it during the v18 upgrade.

## Device-bound token validation

validateOfflineToken (lines 3820-3909) retrieves the stored `device_id` from the session row and compares it to the current device ID obtained via `_getDeviceId()`:

```dart
final storedDeviceId = session['device_id'] as String?;
final currentDeviceId = await _getDeviceId();
if (storedDeviceId != null && storedDeviceId != currentDeviceId && storedDeviceId != 'unknown_device') {
  print('[OFFLINE_TOKEN_SECURITY] VALIDATION FAILED: device_id mismatch for $email (stored: $storedDeviceId, current: $currentDeviceId)');
  await db.delete('offline_sessions', where: 'user_email = ?', whereArgs: [email]);
  return false;
}
```

The comparison is correct: if stored device exists, isn't the sentinel 'unknown_device', and doesn't match current device, the validation fails, the session is deleted, and false is returned. This prevents a token stolen from one device from working on another. The sentinel exception (storedDeviceId != 'unknown_device') is intentional—it allows tokens created when device ID retrieval failed to remain valid, which is a deliberate trade-off between availability and security.

The `_getDeviceId()` method (lines 3758-3774) now uses `androidInfo.id` instead of the previously broken `androidInfo.androidId`. On error or unsupported platforms, it returns 'unknown_device'. The 'unknown_device' escape hatch is a design choice—tokens created with this fallback are not device-bound, but the validation logic acknowledges this explicitly.

## Audit logging

All three session management functions include print statements with the `[OFFLINE_TOKEN_SECURITY]` prefix:

**createOfflineToken** (lines 3777-3811):
- Success: line 3806 logs token creation with email, device ID, and expiry timestamp
- Failure: line 3809 logs creation failure with exception message

**validateOfflineToken** (lines 3820-3909):
- No session found: line 3835
- Device ID mismatch: line 3847
- Token hash mismatch: line 3856
- Token expired: line 3865
- Success: line 3901

**clearOfflineSession** (lines 3932-3945):
- Success: line 3941 logs session cleared for email
- Failure: line 3943 logs error with exception message

Every branch that returns false or null has a corresponding audit log. The logs include context (email, device IDs, expiry timestamps) sufficient to investigate token issues.

## Device ID retrieval implementation note

The fallback to 'unknown_device' happens in two cases:
1. Platform is not Android or iOS
2. Exception during device info retrieval (e.g., permission issues, API level incompatibility)

The validateOfflineToken logic explicitly exempts 'unknown_device' from device binding checks (line 3847), so tokens created when device ID retrieval fails are not device-bound. This is a security/availability trade-off—better to allow offline access without device binding than to fail token creation entirely.

A production system should consider whether this trade-off is acceptable. If device binding is mandatory, createOfflineToken should fail (return null) when `_getDeviceId()` returns 'unknown_device', and callers should inform the user that offline sessions require device ID access.

</details>

<details>
<summary>File map</summary>

Changed files:

- **lib/database_helper.dart** — Added offline_sessions table to onCreate, fixed device ID retrieval property name, added device binding check to validateOfflineToken, added audit logs to all three session management functions

[Full diff available via `git diff`]

</details>
