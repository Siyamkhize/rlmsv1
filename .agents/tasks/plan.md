# Implementation Plan: Learner Sync NOT NULL Constraint Failures

## Problem Analysis

The Flutter app is experiencing `DatabaseException(NOT NULL constraint failed)` errors during learner sync operations. From analyzing the error logs and codebase:

**Root Cause**: The SQLite `learnerdetails` table has NOT NULL constraints on `Title` and `DateOfBirth` columns, but the server API can return NULL values for these fields, causing INSERT OR REPLACE operations to fail.

**Key Findings**:
1. **NOT NULL Constraints**: `learnerdetails` table (line 1730 in database_helper.dart) has NOT NULL constraints on:
   - `Title VARCHAR(50) NOT NULL`
   - `Name VARCHAR(100) NOT NULL` 
   - `Surname VARCHAR(100) NOT NULL`
   - `IDNumber VARCHAR(20) NOT NULL`
   - `DateOfBirth DATE NOT NULL`

2. **Sync Methods**: Multiple methods perform INSERT OR REPLACE operations:
   - `upsertLearner()` at line 341 - uses `_sanitizeLearnerData()` which converts NULL to empty strings
   - `insertLearnerDetails()` at line 2895 - provides default values like 'N/A' for Title and '1900-01-01' for DateOfBirth
   - `_syncLearnerDetails()` in sync_service.dart - directly inserts server data without sanitization

3. **Server Data**: PHP endpoints (`sync_learnerdetails.php`, `get_learners.php`) can legitimately return NULL values for Title and DateOfBirth when data is incomplete.

4. **The Problem**: `_syncLearnerDetails()` in sync_service.dart uses direct `db.insert()` without calling the sanitization methods, causing constraint violations.

## Implementation Plan

- [ ] 1. **Fix the primary sync method in sync_service.dart**
      Replace direct database insertion with sanitized upsert calls in `_syncLearnerDetails()` method.
      Files: c:/projects/rlmss/lib/sync_service.dart (around line 540)
      Verify: Run sync operation and check logs for successful inserts without constraint errors.

- [ ] 2. **Fix persistent sync service method**
      Update `_syncLearnersForClass()` to use sanitized data insertion in persistent_sync_service.dart.
      Files: c:/projects/rlmss/lib/services/persistent_sync_service.dart (around line 120)
      Verify: Trigger offline sync and confirm no constraint violations in logs.

- [ ] 3. **Enhance sanitization to handle all NOT NULL fields**
      Update `_sanitizeLearnerData()` to provide non-empty defaults for Name, Surname, IDNumber fields.
      Files: c:/projects/rlmss/lib/database_helper.dart (around line 366)
      Verify: Unit test the sanitization with NULL inputs for all required fields.

- [ ] 4. **Add validation logging for data quality issues**
      Add logging in sync methods to identify and track when server returns incomplete data.
      Files: c:/projects/rlmss/lib/sync_service.dart, c:/projects/rlmss/lib/services/persistent_sync_service.dart
      Verify: Check logs during sync to see warnings for incomplete server data.

- [ ] 5. **Add error handling for constraint violations**
      Wrap all learner insertion operations in try-catch blocks with specific handling for constraint errors.
      Files: c:/projects/rlmss/lib/sync_service.dart, c:/projects/rlmss/lib/services/persistent_sync_service.dart
      Verify: Inject NULL data and confirm graceful error handling without app crashes.

## Recommended Fix Strategy

**Strategy B: Provide default/fallback values at insertion time**

**Rationale**: 
- Making Title and DateOfBirth nullable would require a schema migration and could break other parts of the app that expect these fields to have values
- The app already has sanitization logic in place (`_sanitizeLearnerData` and `insertLearnerDetails`)
- The issue is that some sync paths bypass this sanitization
- This approach maintains data integrity while handling incomplete server data gracefully

## Verification Steps

After implementation:
1. **Test with current error cases**: Use the specific IDNumbers from the error logs (8505030703086, 9807050956084, etc.) to verify they sync successfully
2. **Test edge cases**: Inject learner records with all NULL values to ensure sanitization works
3. **Monitor sync logs**: Check for successful completion of learner sync without constraint errors
4. **Verify data integrity**: Confirm that sanitized records display properly in the app UI

## Server-Side Considerations

The server PHP endpoints legitimately return NULL values when data is incomplete. This is correct behavior - the client should handle missing data gracefully rather than requiring the server to provide fake defaults.

The sync errors indicate a data quality issue where some learner records in the database are incomplete, which is a normal scenario in real-world data entry.