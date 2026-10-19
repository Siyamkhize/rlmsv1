# Manual Clocking Evidence Dashboard - Deployment Guide

## Server File Structure

The manual clocking evidence system has a specific file structure on the server:

```
/public_html/
  ├── manual_clocking_evidence_details.php (ROOT level)
  ├── manual_clocking_evidence_dashboard.php (ROOT level)
  └── mobile/
      └── manual_clocking_evidence/ (Evidence folder)
          ├── signatures/
          │   ├── signature_in_12345_2026-10-19.png
          │   └── signature_out_12345_2026-10-19.png
          └── faces/
              ├── face_in_12345_2026-10-19.png
              └── face_out_12345_2026-10-19.png
```

## Deployment Steps

### 1. Copy PHP Files to ROOT Level

The PHP dashboard files should be copied to the **ROOT** level (`/public_html/`), NOT inside the mobile folder:

```bash
# From your local repo /mobile/ folder
cp mobile/manual_clocking_evidence_details.php /server/public_html/
cp mobile/manual_clocking_evidence_dashboard.php /server/public_html/
```

### 2. Verify Evidence Folder Exists

The evidence folder structure should exist inside the mobile folder:

```bash
/public_html/mobile/manual_clocking_evidence/
/public_html/mobile/manual_clocking_evidence/signatures/
/public_html/mobile/manual_clocking_evidence/faces/
```

### 3. Set Folder Permissions

```bash
chmod 755 /public_html/mobile/manual_clocking_evidence/
chmod 755 /public_html/mobile/manual_clocking_evidence/signatures/
chmod 755 /public_html/mobile/manual_clocking_evidence/faces/
chmod 644 /public_html/mobile/manual_clocking_evidence/signatures/*.png
chmod 644 /public_html/mobile/manual_clocking_evidence/faces/*.png
```

## Path Configuration

The PHP files use these paths (already configured correctly):

```php
// Evidence base path - for file existence checks
$evidenceBasePath = __DIR__ . '/mobile/manual_clocking_evidence/';

// Evidence base URL - for browser image loading
$evidenceBaseUrl = 'mobile/manual_clocking_evidence/';
```

## URLs

- **Dashboard**: `https://yourdomain.com/manual_clocking_evidence_dashboard.php`
- **Details**: `https://yourdomain.com/manual_clocking_evidence_details.php?id=123`
- **Images**: `https://yourdomain.com/mobile/manual_clocking_evidence/signatures/signature_in_123.png`

## Troubleshooting

### Images Not Showing

1. Check folder exists: `/public_html/mobile/manual_clocking_evidence/`
2. Check files exist in subfolders: `signatures/` and `faces/`
3. Check permissions: `755` for folders, `644` for files
4. Check database records have correct filenames stored

### "No Data" Message

1. Check if database table `manual_clocking_evidence` has records
2. Run diagnostic: `https://yourdomain.com/mobile/check_manual_clocking_data.php`
3. Check if learners have actually clocked in using manual clocking feature
4. Check if sync has completed from mobile app to server

### File Not Found Errors

If you see "File not found" errors:
- Verify PHP files are at ROOT level: `/public_html/`
- Verify evidence folder is at: `/public_html/mobile/manual_clocking_evidence/`
- Check `__DIR__` in PHP resolves to `/public_html/`

## Database Query

To check if you have evidence records:

```sql
SELECT 
    evidence_id,
    LearnerID,
    clock_date,
    signature_in,
    signature_out,
    face_in,
    face_out,
    created_at
FROM manual_clocking_evidence
ORDER BY created_at DESC
LIMIT 10;
```

## Mobile App Endpoints

The mobile app saves evidence using these endpoints:

- `save_manual_clockin.php` - Saves clock-in with signature and face
- `save_manual_clockout.php` - Saves clock-out with signature and face  
- `save_manual_clocking_images.php` - Uploads images first, returns filenames
- `sync_manual_clocking_evidence.php` - Syncs offline records

All these endpoints save images to: `mobile/manual_clocking_evidence/signatures/` and `mobile/manual_clocking_evidence/faces/`
