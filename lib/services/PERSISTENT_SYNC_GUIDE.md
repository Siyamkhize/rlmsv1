# Persistent Sync Service - Enhanced Features Guide

## Overview
The enhanced `PersistentSyncService` now includes advanced features for robust offline-first data synchronization.

## New Features

### 1. **Progress Tracking**
Monitor sync progress in real-time with detailed phase information.

```dart
final syncService = PersistentSyncService();

// Listen to sync progress
syncService.progressStream.listen((progress) {
  print('Phase: ${progress.phase}');
  print('Progress: ${(progress.progress * 100).toStringAsFixed(1)}%');
  print('Message: ${progress.message}');
  
  if (progress.phase == SyncPhase.completed) {
    print('Sync completed: ${progress.result}');
  }
});

// Start sync with progress reporting
await syncService.syncAllData(reportProgress: true);
```

### 2. **Retry Mechanisms with Exponential Backoff**
Automatically retry failed operations with intelligent backoff.

```dart
// Configure retry behavior
syncService.configureRetry(
  maxRetries: 5,
  initialDelay: Duration(seconds: 2),
);

// Tasks will automatically retry with exponential backoff:
// Attempt 1: immediate
// Attempt 2: ~2 seconds
// Attempt 3: ~4 seconds
// Attempt 4: ~8 seconds
// Attempt 5: ~16 seconds
```

### 3. **Conflict Resolution Strategies**
Choose how to handle data conflicts between local and server data.

```dart
// Server data wins (default)
await syncService.syncAllData(
  conflictStrategy: SyncConflictStrategy.serverWins,
);

// Local data wins
await syncService.syncAllData(
  conflictStrategy: SyncConflictStrategy.clientWins,
);

// Merge data, prefer local non-empty values
await syncService.syncAllData(
  conflictStrategy: SyncConflictStrategy.mergePreserveLocal,
);

// Merge data, prefer server non-empty values
await syncService.syncAllData(
  conflictStrategy: SyncConflictStrategy.mergePreserveServer,
);
```

### 4. **Priority-Based Sync Queue**
Queue sync tasks with priorities for important operations.

```dart
// Add high-priority sync task
await syncService.queueSync(SyncTask(
  name: 'urgent_clocking_sync',
  priority: 10, // Higher = more important
  execute: () async {
    // Your sync logic here
    await DatabaseHelper().syncUnsyncedFingerprints();
  },
));

// Add normal priority task
await syncService.queueSync(SyncTask(
  name: 'background_learner_sync',
  priority: 1,
  execute: () async {
    await DatabaseHelper().syncLearnerDetails();
  },
));
```

### 5. **Comprehensive Statistics**
Track sync performance and diagnose issues.

```dart
final stats = syncService.statistics;

print('Total syncs: ${stats.totalSyncs}');
print('Success rate: ${(stats.successRate * 100).toStringAsFixed(1)}%');
print('Total learners synced: ${stats.totalLearnersSynced}');
print('Total clocking records: ${stats.totalClockingRecordsSynced}');
print('Average sync time: ${stats.averageSyncTime.inSeconds}s');
print('Last successful sync: ${stats.lastSuccessfulSync}');

// Get detailed JSON for logging/debugging
print(jsonEncode(stats.toJson()));

// Reset statistics
stats.reset();
```

### 6. **Data Validation**
Automatic integrity checks after sync.

```dart
// Validation runs automatically and reports:
// - Orphaned clocking records (clocking without learner)
// - Duplicate learner entries
// - Other integrity issues

final result = await syncService.syncAllData();

if (result.warnings.isNotEmpty) {
  print('Warnings found:');
  for (var warning in result.warnings) {
    print('  - $warning');
  }
}
```

## Sync Phases

The sync process goes through these phases:

1. **Starting** (0-10%) - Initialization and connectivity check
2. **Learners** (10-50%) - Syncing learner data for all classes
3. **Clocking Records** (50-80%) - Syncing offline clocking records
4. **Other Data** (80-90%) - Syncing POE, documents, etc.
5. **Validation** (90-100%) - Data integrity checks
6. **Completed** (100%) - Sync finished successfully
7. **Failed** - Sync encountered an error

## UI Integration Example

```dart
class SyncStatusWidget extends StatefulWidget {
  @override
  _SyncStatusWidgetState createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  final _syncService = PersistentSyncService();
  SyncProgress? _currentProgress;
  StreamSubscription<SyncProgress>? _subscription;
  
  @override
  void initState() {
    super.initState();
    _subscription = _syncService.progressStream.listen((progress) {
      setState(() {
        _currentProgress = progress;
      });
    });
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_currentProgress == null) {
      return SizedBox.shrink();
    }
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: _currentProgress!.progress,
            ),
            SizedBox(height: 8),
            Text(_currentProgress!.message),
            Text(
              '${(_currentProgress!.progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _startSync() async {
    await _syncService.syncAllData(
      reportProgress: true,
      conflictStrategy: SyncConflictStrategy.mergePreserveLocal,
    );
  }
}
```

## Best Practices

### 1. **Configure on App Start**
```dart
void main() {
  final syncService = PersistentSyncService();
  
  // Configure retry behavior
  syncService.configureRetry(maxRetries: 3);
  
  // Start auto-sync
  syncService.startAutoSync();
  
  runApp(MyApp());
}
```

### 2. **Handle Progress in Background**
```dart
// Don't block UI during sync
syncService.progressStream.listen((progress) {
  // Update notification or background indicator
  if (progress.phase == SyncPhase.completed) {
    showNotification('Sync completed successfully');
  } else if (progress.phase == SyncPhase.failed) {
    showNotification('Sync failed: ${progress.message}');
  }
});
```

### 3. **Monitor Statistics**
```dart
// Periodically check sync health
Timer.periodic(Duration(hours: 1), (_) {
  final stats = syncService.statistics;
  
  if (stats.successRate < 0.8) {
    logWarning('Low sync success rate: ${stats.successRate}');
  }
  
  if (stats.failedSyncs > 10) {
    logError('Many failed syncs: ${stats.failedSyncs}');
  }
});
```

### 4. **Priority Queue for Critical Data**
```dart
// High priority for user-initiated actions
await syncService.queueSync(SyncTask(
  name: 'user_clocking',
  priority: 100,
  execute: () async {
    await syncUserClockingNow();
  },
));

// Low priority for background maintenance
await syncService.queueSync(SyncTask(
  name: 'cleanup_old_data',
  priority: 1,
  execute: () async {
    await cleanupOldRecords();
  },
));
```

## Error Handling

```dart
try {
  final result = await syncService.syncAllData();
  
  if (!result.success) {
    print('Sync failed: ${result.message}');
    
    // Check specific errors
    for (var error in result.errors) {
      print('Error: $error');
    }
  }
  
  // Check warnings even on success
  if (result.warnings.isNotEmpty) {
    for (var warning in result.warnings) {
      print('Warning: $warning');
    }
  }
  
} catch (e) {
  print('Unexpected error: $e');
}
```

## Performance Tips

1. **Use appropriate conflict strategies**: `serverWins` is fastest, `merge` strategies take longer
2. **Monitor progress** only when needed: `reportProgress: false` for background syncs
3. **Queue batched operations**: Group related syncs into single tasks
4. **Check statistics** to identify bottlenecks
5. **Configure retry delays** based on your network conditions

## Troubleshooting

### High Failure Rate
```dart
final stats = syncService.statistics;
print(jsonEncode(stats.toJson())); // See detailed error history
```

### Slow Syncs
```dart
print('Average sync time: ${stats.averageSyncTime.inSeconds}s');
// If too high, consider:
// - Reducing batch sizes
// - Using serverWins strategy
// - Checking network conditions
```

### Memory Issues
```dart
// Reset statistics periodically
stats.reset();

// Don't keep too many items in queue
if (_syncQueue.length > 100) {
  print('Warning: Sync queue is too large');
}
```

## Migration from Old API

### Before:
```dart
await syncService.syncAllData();
```

### After:
```dart
await syncService.syncAllData(
  reportProgress: true,
  conflictStrategy: SyncConflictStrategy.serverWins,
);
```

The old API still works with default parameters for backward compatibility.
