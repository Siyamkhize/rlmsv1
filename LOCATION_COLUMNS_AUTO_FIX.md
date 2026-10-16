# Location Columns Auto-Migration Fix

**Date:** October 15, 2026  
**Issue:** Province, District, Municipality columns keep needing manual addition

## Problem
Users who installed the app before location columns were added to `learnerdetails` table still have the old schema without these columns. This causes:
- Dropdown fields to fail
- Need to manually run `ALTER TABLE` commands
- Data sync issues between online MySQL and offline SQLite

## Solution Applied

### Database Migration v19
Added automatic migration that checks if location columns exist and adds them if missing.

**File Modified:** `lib/database_helper.dart`

**Changes:**
1. Bumped database version from 18 to 19
2. Added migration check for Province, District, Municipality columns
3. Auto-creates missing columns on app upgrade

```dart
if (oldVersion < 19) {
  // Check if columns exist
  final columns = await db.rawQuery("PRAGMA table_info('learnerdetails')");
  final existingColumns =
      columns.map((c) => c['name']?.toString().toLowerCase()).toSet();

  // Add Province if missing
  if (!existingColumns.contains('province')) {
    await db.execute(
        'ALTER TABLE learnerdetails ADD COLUMN Province VARCHAR(100) NULL');
  }

  // Add District if missing
  if (!existingColumns.contains('district')) {
    await db.execute(
        'ALTER TABLE learnerdetails ADD COLUMN District VARCHAR(100) NULL');
  }

  // Add Municipality if missing
  if (!existingColumns.contains('municipality')) {
    await db.execute(
        'ALTER TABLE learnerdetails ADD COLUMN Municipality VARCHAR(100) NULL');
  }
}
```

## How It Works

1. **Fresh Install:** New users get all columns from the start (defined in `onCreate`)
2. **Existing Users:** Migration runs on first launch after update
3. **Already Has Columns:** Migration safely skips if columns already exist

## Testing

After rebuilding and installing the new APK:
1. Location dropdowns should work immediately
2. No manual SQL commands needed
3. Data syncs properly between online/offline

## Next Steps

**Build new APK:**
```bash
flutter clean
flutter build apk --release
```

**Install on device:**
```bash
adb -s RZ8X306F7TZ install -r app-release.apk
```

**Verify:**
1. Open app
2. Check debug console for migration logs: `[DB] ✅ v19 migration...`
3. Try adding/editing learner with location fields
4. Verify dropdowns populate correctly

## Status

✅ Migration code added  
⏳ Needs rebuild and test  
⏳ Verify on device RZ8X306F7TZ

---

**Note:** Please share the "actual error" you mentioned so I can fix that too!
