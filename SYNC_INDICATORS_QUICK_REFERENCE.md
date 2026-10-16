# Sync Status Indicators - Quick Reference

## Icon Colors & Meanings

### 🟢 GREEN = Synced to Server
- **Avatar**: Green circle with cloud_done icon ☁️✓
- **Text**: "In: 10:46:02 ☁️✓ Synced"
- **Meaning**: Data successfully saved on MySQL server
- **Action**: None required

### 🟠 ORANGE = Needs Sync (Offline)
- **Avatar**: Orange circle with cloud_off icon ☁️❌
- **Text**: "In: 10:46:02 🔄 Needs sync"
- **Meaning**: Data saved locally (SQLite), not yet on server
- **Action**: Will auto-sync when online

### ⚪ GREY = Clocked Out
- **Avatar**: Grey circle with check_circle icon ✓
- **Text**: "In: 10:46:02 / Out: 16:30:00"
- **Meaning**: Both clock-in and clock-out complete
- **Action**: Record complete

## How It Works

### Online Clock-In Flow
```
1. User clicks "Clock In" (online)
2. Data → Server immediately
3. Server response: success
4. Icon → GREEN 🟢
5. Badge: "Synced"
```

### Offline Clock-In Flow
```
1. User clicks "Clock In" (offline)
2. Data → Local DB (synced=0)
3. Save successful
4. Icon → ORANGE 🟠
5. Badge: "Needs sync"
6. [When online] → Auto-sync
7. Icon → GREEN 🟢
```

## Visual Examples

```
┌─────────────────────────────────────────┐
│ 🟢  Siyabonga Mkhize               ⋮│
│     ID: 9502195714080                  │
│     📷 Photo  ✍️ Signature             │
│     In: 10:46:02 ☁️✓ Synced           │
└─────────────────────────────────────────┘
        ↑ GREEN = Data on server
        
┌─────────────────────────────────────────┐
│ 🟠  John Doe                       ⋮│
│     ID: 9501011234567                  │
│     📷 Photo  ✍️ Signature             │
│     In: 09:30:15 🔄 Needs sync        │
└─────────────────────────────────────────┘
        ↑ ORANGE = Offline, needs sync
        
┌─────────────────────────────────────────┐
│ ⚪  Jane Smith                     ⋮│
│     ID: 9502201234567                  │
│     📷 Photo  ✍️ Signature             │
│     In: 08:00:00 / Out: 16:30:00       │
│     Duration: 8h 30m                    │
└─────────────────────────────────────────┘
        ↑ GREY = Completed (clocked out)
```

## When You See Orange 🟠

**Don't worry!** The data is safe in local storage.

**What happens:**
1. Data saved locally on device
2. App will auto-sync when network returns
3. You can continue working offline
4. Icon will turn green after sync

**Manual sync:**
Pull down to refresh when online

## Troubleshooting

### All Icons Orange
- **Cause**: Device offline or server down
- **Fix**: Check network, wait for connection
- **Data**: Safe in local DB

### Some Orange, Some Green
- **Normal**: Mixed sync states
- **Cause**: Those learners clocked in while offline
- **Fix**: Will sync automatically

### Icon Stays Orange
- **Cause**: Sync failed or blocked
- **Check**: Network, server, sync logs
- **Manual**: Pull to refresh

## Technical Reference

```dart
// Check unsynced count
SELECT COUNT(*) FROM manual_clocking 
WHERE clock_date = 'TODAY' AND synced = 0;

// View unsynced learners
SELECT LearnerID, Name, clock_in_time 
FROM manual_clocking mc
JOIN learnerdetails ld ON mc.LearnerID = ld.LearnerID
WHERE mc.clock_date = 'TODAY' AND mc.synced = 0;
```

## User Actions

| Indicator | User Should |
|-----------|-------------|
| 🟢 Green  | Continue normally |
| 🟠 Orange | Wait for auto-sync or manually refresh |
| ⚪ Grey   | Record complete, no action needed |

---
**Remember**: Orange doesn't mean error - it means "waiting for sync"
