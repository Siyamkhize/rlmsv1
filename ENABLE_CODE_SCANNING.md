# Enable Code Scanning on GitHub

## Issue

SARIF uploads are failing with:
```
Code scanning is not enabled for this repository. 
Please enable code scanning in the repository settings.
```

## Solution: Enable Code Scanning (2 Minutes)

### Step 1: Go to Repository Settings

1. Visit: https://github.com/Siyamkhize/rlmsv1/settings
2. Click **Code security and analysis** (left sidebar)

### Step 2: Enable Code Scanning

Scroll down to **Code scanning** section and click:

**"Set up" → "Advanced"**

This will:
- ✅ Enable code scanning for the repository
- ✅ Allow SARIF file uploads from workflows
- ✅ Show security findings in the Security tab

### Step 3: Verify

After enabling, you should see:
- Security tab shows "Code scanning" section
- SARIF uploads will succeed in workflows

---

## Alternative: Visit Direct Link

**Quick Enable Link:**
```
https://github.com/Siyamkhize/rlmsv1/settings/security_analysis
```

Scroll to **Code scanning** → Click **Set up** → Choose **Advanced**

---

## What This Enables

Once code scanning is enabled:

✅ **Trivy** vulnerability reports  
✅ **Semgrep** security findings  
✅ **Checkov** IaC security issues  
✅ **CodeQL** analysis results  
✅ **Snyk** dependency vulnerabilities  

All will appear in:
```
https://github.com/Siyamkhize/rlmsv1/security/code-scanning
```

---

## If You Can't Enable It Right Now

The workflows will continue to work! SARIF uploads will just show warnings but won't block the pipeline.

All workflows have `continue-on-error: true` on SARIF upload steps, so:
- ✅ Core checks still pass
- ✅ Builds still succeed
- ⚠️ Security findings just won't appear in Security tab (yet)

You can enable it later and re-run the workflows to upload the findings.

---

## After Enabling

Re-run the failed workflows:
1. Go to: https://github.com/Siyamkhize/rlmsv1/actions
2. Click on a workflow run
3. Click "Re-run all jobs"

Or just push a new commit - workflows will run automatically!

---

## Summary

**Current:** Code scanning not enabled (SARIF uploads fail)  
**Fix:** Enable in Settings → Code security → Code scanning → Set up  
**Time:** 2 minutes  
**Impact:** Security findings will appear in Security tab  
**Urgency:** Low - workflows still pass, this is just for viewing findings  

---

*Last Updated: 2026-11-16*  
*Status: Waiting for user to enable code scanning feature*
