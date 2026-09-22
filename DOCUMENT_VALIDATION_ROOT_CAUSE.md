# 🔍 ROOT CAUSE: Document Validation Issue for Learner 21568

**Date:** September 22, 2026  
**Issue:** Learner 21568 cannot clock in despite having approved documents  
**Root Cause Found:** Endpoint switched from working to non-working version

---

## What Happened

### The Working Code (Backup)
**File:** `lib/clock_in_page copy.dart`  
**Endpoint Used:** `get_document_statuses.php`

```dart
final response = await http.post(
  Uri.parse(AppConfig.buildUrl('get_document_statuses.php')),
  body: {'learner_id': learnerId},
);
```

**Returns:**
```json
{
  "success": true,
  "documents": {
    "ID Document": {
      "status": "Approved",
      "rejection_reason": null,
      "upload_date": "2026-08-15"
    },
    "Qualifications": {
      "status": "Approved",
      "rejection_reason": null,
      "upload_date": "2026-08-16"
    },
    "Proof of Residence": {
      "status": "Pending",
      "rejection_reason": null,
      "upload_date": "2026-08-20"
    }
  }
}
```

### The Broken Code (Current)
**File:** `lib/clock_in_page.dart`  
**Endpoint Used:** `check_learner_documents.php`

```dart
final response = await http.post(
  Uri.parse(AppConfig.buildUrl('check_learner_documents.php')),
  body: body,
);
```

**Returns:**
```json
{
  "success": true,
  "documents": [
    "ID Document",
    "Qualifications",
    "Proof of Residence"
  ]
}
```

**Problem:** No status information! Can't tell if documents are approved, pending, or declined.

---

## Why It Broke

Someone changed the endpoint from:
- ✅ `get_document_statuses.php` (returns status info)
- ❌ `check_learner_documents.php` (returns names only)

The current code tries to check for `status == 'approved'` but the endpoint doesn't return status, so ALL documents appear as "not approved" even when they are.

---

## The Fix

### Option 1: Revert to Working Endpoint (RECOMMENDED)

Change `clock_in_page.dart` back to use `get_document_statuses.php`:

```dart
// CURRENT (BROKEN):
final response = await http.post(
  Uri.parse(AppConfig.buildUrl('check_learner_documents.php')),
  body: body,
);

// CHANGE TO (WORKING):
final response = await http.post(
  Uri.parse(AppConfig.buildUrl('get_document_statuses.php')),
  body: {'learner_id': learnerId},
);
```

Then update the parsing logic to handle the Map format with status.

### Option 2: Keep Current Endpoint but Fix It

Update `check_learner_documents.php` to return status information:

```php
$query = "SELECT documentName, status 
          FROM learner_document 
          WHERE learner_id = ? 
          AND LOWER(status) = 'approved'";
```

But this changes the contract of an existing endpoint which might break other code.

---

## Comparison Table

| Feature | `get_document_statuses.php` | `check_learner_documents.php` |
|---------|----------------------------|-------------------------------|
| **Returns Status** | ✅ YES | ❌ NO |
| **Returns Dates** | ✅ YES | ❌ NO |
| **Returns Rejection Reason** | ✅ YES | ❌ NO |
| **Filters by Approved** | ❌ NO (returns all) | ❌ NO (returns all) |
| **Used in Working Code** | ✅ YES | ❌ NO |

---

## Timeline of Events

1. **Working State** - `clock_in_page copy.dart` used `get_document_statuses.php`
2. **Code Change** - Someone switched to `check_learner_documents.php`
3. **Issue Appears** - Learners with approved docs can't clock in
4. **Today** - Issue reported for learner 21568

---

## Recommended Action

**Revert to using `get_document_statuses.php` endpoint** in `clock_in_page.dart`.

This is the safest fix because:
1. ✅ Proven to work (it's in the backup)
2. ✅ Returns all needed information
3. ✅ No need to modify server endpoints
4. ✅ No risk of breaking other code

---

## Files Involved

### Server Side
- ✅ `mobile/get_document_statuses.php` - Working endpoint with full info
- ❌ `mobile/check_learner_documents.php` - Incomplete endpoint (no status)

### Client Side
- ✅ `lib/clock_in_page copy.dart` - Working version (backup)
- ❌ `lib/clock_in_page.dart` - Current broken version

---

## Next Steps

1. Update `lib/clock_in_page.dart` to use `get_document_statuses.php`
2. Update parsing logic to handle Map format response
3. Test with learner 21568
4. Rebuild APK
5. Deploy

---

## Lesson Learned

**When changing endpoints, ensure the new endpoint returns ALL the data the old one did.**

The switch from `get_document_statuses.php` to `check_learner_documents.php` removed critical status information needed for validation.
