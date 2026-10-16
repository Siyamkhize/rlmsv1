# NOT NULL constraint fix for learner sync operations

**Watch for:** Incomplete fix in persistent sync service — data sanitization bypassed, potential silent data corruption with '1900-01-01' dates in age calculations, missing error handling for remaining NOT NULL columns.

**Verdict**: NEEDS_CHANGES

## High-level view

The sync_service.dart fix correctly routes learner data through the sanitization layer by switching from direct database insertion to upsertLearner calls. The database_helper.dart sanitization methods provide reasonable defaults for Title ('') and DateOfBirth ('1900-01-01') while preserving data integrity for required fields like Name, Surname, and IDNumber with 'Unknown' fallbacks. However, the persistent_sync_service.dart implementation still performs manual string coercion without proper sanitization, potentially allowing empty strings to violate NOT NULL constraints and bypassing the established data quality controls.

<details>
<summary>Issues (4)</summary>

1. **Persistent sync bypasses sanitization** — persistent_sync_service.dart uses manual string coercion (learner['Title']?.toString() ?? '') instead of the established _sanitizeLearnerData method, allowing constraint violations to persist.
2. **Age calculation data corruption risk** — _sanitizeDate returns '1900-01-01' for null dates which will produce incorrect ages (124 years old), potentially breaking business logic that depends on learner age.
3. **Incomplete NOT NULL coverage** — AddressLine2, AddressLine3 columns are marked NOT NULL in schema but only get empty string defaults, missing from sanitization method coverage check.
4. **Silent failure potential** — persistent sync lacks try-catch blocks around database operations, so NOT NULL violations would crash the sync process rather than continuing with other records.

</details>

<details>
<summary>Details</summary>

## Sync service sanitization integration

The sync_service.dart fix correctly addresses the root cause by replacing direct database insertion with sanitized upsert operations. The change from `db.insert('learnerdetails', learnerData)` to `await _dbHelper.upsertLearner(learnerData)` ensures all server data passes through the _sanitizeLearnerData pipeline before database insertion. The error handling specifically catches NOT NULL constraint failures and continues processing other learners, preventing batch sync operations from failing completely due to individual record issues.

```dart
// Before: Direct insertion vulnerable to constraint violations
await db.insert('learnerdetails', learnerData, conflictAlgorithm: ConflictAlgorithm.replace);

// After: Sanitized upsert with proper defaults
await _dbHelper.upsertLearner(learnerData);
```

The logging enhancement provides visibility into data quality issues by printing the raw learner data when constraint failures occur, enabling diagnosis of server-side data problems.

## Sanitization strategy and data integrity

The _sanitizeLearnerData method provides a comprehensive approach to handling null server data. Required fields like Name, Surname, and IDNumber receive meaningful defaults ('Unknown') through _sanitizeRequiredString, while optional string fields get empty strings via _sanitizeString. The Title field correctly receives an empty string default, which satisfies the NOT NULL constraint while indicating missing data.

However, the DateOfBirth handling introduces a potential data corruption issue. The _sanitizeDate method returns '1900-01-01' for null dates, which will cause age calculations to show learners as 124+ years old. While this prevents constraint violations, it creates misleading data that could break business logic expecting realistic ages.

```dart
String _sanitizeDate(dynamic value) {
  if (value == null) return '1900-01-01'; // Creates 124-year-old learners
  // ... validation logic
}
```

A more appropriate default might be null for optional date fields or a clearly invalid placeholder that age calculations can detect and handle gracefully.

## Persistent sync service gap

The persistent_sync_service.dart implementation still performs manual data preparation without utilizing the established sanitization infrastructure. Lines 195-210 manually coerce server data using null-safe operators:

```dart
final learnerData = {
  'Title': learner['Title']?.toString() ?? '',
  'DateOfBirth': learner['DateOfBirth']?.toString() ?? '',
  // ... other fields
};
```

This approach bypasses _sanitizeLearnerData entirely, meaning constraint violations can still occur in persistent sync operations. The manual coercion also lacks the data validation present in _sanitizeDate (DateTime.parse validation) and _sanitizeRequiredString (meaningful defaults for critical fields).

The persistent sync should either call dbHelper.upsertLearner or apply the same sanitization logic to ensure consistency across all sync pathways.

## Schema and constraint coverage analysis

Examining the learnerdetails table schema reveals five NOT NULL constraints: Title, Name, Surname, IDNumber, and DateOfBirth. The sanitization correctly handles all five fields. However, reviewing the full schema shows AddressLine2 and AddressLine3 are also marked NOT NULL but receive only empty string defaults from _sanitizeString. While empty strings satisfy NOT NULL constraints, this creates an asymmetry where some required fields get meaningful defaults ('Unknown') while address fields get empty strings.

The fix addresses the immediate constraint violations reported in the error logs but doesn't provide comprehensive coverage for all potential NOT NULL fields that might be added or modified in the schema.

</details>

<details>
<summary>File map</summary>

- **lib/sync_service.dart** — replaced direct database insertion with sanitized upsert calls in _syncLearnerDetails
- **lib/database_helper.dart** — added comprehensive _sanitizeLearnerData with separate methods for strings, dates, and required fields
- **lib/services/persistent_sync_service.dart** — manual string coercion in _syncLearnersForClass (gap - not using sanitization)

[Full diff details](git diff main)

</details>