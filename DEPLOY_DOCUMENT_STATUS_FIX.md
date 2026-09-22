# 🚀 DEPLOY: Document Status Fix for Learner 21568

**Fix Applied:** September 22, 2026  
**Issue:** Learner 21568 cannot clock in despite having approved documents  
**Root Cause:** Server endpoint returning ALL documents instead of APPROVED only

---

## ⚡ Quick Deploy (Server-Side Only)

### Upload Fixed File

```bash
scp c:\projects\rlmss\mobile\check_learner_documents.php user@yourserver:/path/to/rlmss/mobile/
```

**That's it! No app rebuild needed.**

---

## ✅ What Was Fixed

### File Changed
- `mobile/check_learner_documents.php`

### Change Summary
```sql
-- BEFORE (broken):
SELECT documentName FROM learner_document WHERE learner_id = ?

-- AFTER (fixed):
SELECT documentName, status 
FROM learner_document 
WHERE learner_id = ? 
AND LOWER(status) = 'approved'
```

### Impact
- ✅ Only APPROVED documents count for clock-in
- ❌ Pending documents excluded
- ❌ Declined documents excluded
- ❌ NULL status documents excluded

---

## 🧪 Test After Deploy

### 1. Test Endpoint Directly

```bash
curl -X POST https://yourserver.com/rlmss/mobile/check_learner_documents.php \
  -d "learner_id=21568"
```

**Expected Response:**
```json
{
  "success": true,
  "documents": [
    {
      "documentName": "ID Document",
      "status": "Approved"
    },
    {
      "documentName": "Qualifications",
      "status": "Approved"
    },
    {
      "documentName": "Proof of Residence",
      "status": "Approved"
    }
  ]
}
```

### 2. Test on Mobile Device

**Steps:**
1. Open RLMSS app (existing APK, no rebuild needed)
2. Go to Clock-In page
3. Enter learner ID: 21568
4. Should proceed without document upload prompt
5. Complete clock-in successfully

---

## 📋 Diagnostic Script (Optional)

To check any learner's document status:

```bash
php c:\projects\rlmss\check_learner_21568_documents.php
```

This shows:
- All documents in database
- Their status
- What the endpoint returns
- What's missing for clock-in

---

## 🎯 The 3 Required Documents

For clock-in, learners need these 3 documents **APPROVED**:

1. ID Document
2. Qualifications
3. Proof of Residence

*(Professional Indemnity is NOT required for learners)*

---

## ✅ Verification Checklist

After deploying the fix:

- [ ] Uploaded `check_learner_documents.php` to server
- [ ] Tested endpoint returns only approved documents
- [ ] Tested learner 21568 can clock in on mobile app
- [ ] Verified no document upload prompt shown
- [ ] Clock-in completes successfully

---

## 📞 If Issue Persists

### Check 1: Document Names Match
Run this SQL to see exact document names:

```sql
SELECT learner_id, documentName, status 
FROM learner_document 
WHERE learner_id = '21568';
```

Document names must match exactly (case-insensitive):
- ✅ "ID Document"
- ✅ "Qualifications"
- ✅ "Proof of Residence"

### Check 2: Status is 'Approved'
```sql
SELECT documentName, status 
FROM learner_document 
WHERE learner_id = '21568' 
AND LOWER(status) = 'approved';
```

Should return 3 rows (one for each required document).

### Check 3: Cache Issues
If mobile app still shows old behavior:
1. Force close app
2. Clear app cache (Settings → Apps → RLMSS → Clear Cache)
3. Reopen and try again

---

## 🎉 Success Criteria

After this fix:

✅ Learners with 3 approved documents can clock in immediately  
✅ Pending/declined documents don't count  
✅ No unnecessary document upload prompts  
✅ Clock-in flow is smooth and fast

---

**Deploy the file and test with learner 21568 immediately!**
