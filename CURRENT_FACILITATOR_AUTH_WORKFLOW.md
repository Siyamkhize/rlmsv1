# Current Facilitator Authentication Workflow - Complete Analysis

**Document Date:** October 14, 2026  
**System:** RLMSS (Rural Learner Management System)  
**Scope:** Facilitator Authentication Flow (Mobile App + PHP Backend)

---

## Executive Summary

The RLMSS facilitator authentication system supports **multiple user roles** with a sophisticated **online/offline hybrid login** mechanism. The system handles 9 different user types with role-specific navigation, automatic data synchronization, and offline-first functionality for rural connectivity.

---

## 1. Authentication Architecture

### 1.1 Components
- **Frontend:** Flutter mobile app (`lib/main.dart` - LoginPage)
- **Backend:** PHP REST API (`mobile/login.php`)
- **Database:** MySQL (online) + SQLite (offline)
- **Security:** Bcrypt password hashing, auth tokens (SHA-256), rate limiting

### 1.2 Supported User Roles

| Role | User Type | Database Table | Navigation Destination |
|------|-----------|----------------|------------------------|
| `facilitator` | Training facilitator | `facilitator` | Dashboard → Learner List |
| `assessor` | Skills assessor | `facilitator` | AssessorPage |
| `arpl_assessor` | ARPL trade assessor | `facilitator` | ArplAssessorPage |
| `arpl_moderator` | ARPL moderator | `facilitator` | ModeratorPage |
| `Moderator` | General moderator | `facilitator` | ModeratorPage |
| `sdp` | Skills Development Provider | `sdp` | SdpProjectsPage (hierarchical view) |
| `finance` | Finance officer | `account_user` | FinanceDashboard |
| `logistics` | Logistics coordinator | `account_user` | LogisticsDashboard |
| `Site Admin` | Site administrator | `account_user` | Site Admin Dashboard |
| `admin` | System administrator | `account_user` | Admin Dashboard |
| `tqa` | Training Quality Assurance | `account_user` | TQA Dashboard |
| `Executive` | Executive viewer | `account_user` | Executive Dashboard |
| `client` | Client viewer | `client` | Client Dashboard |

---

## 2. Login Flow - Step by Step

### 2.1 Application Launch

```
┌─────────────────────────┐
│   User Opens App        │
│   (LoginPage loads)     │
└──────────┬──────────────┘
           │
           ├─→ Check Connectivity (WiFi/Mobile Data)
           ├─→ Check SQLite Database Connection
           ├─→ Initialize RandomPromptService
           └─→ Seed Essential Offline Data
```

**Code Location:** `lib/main.dart` lines 320-350  
**Actions:**
1. Check network connectivity using `Connectivity()` package
2. Verify SQLite database is accessible
3. Run `ensureEssentialDataExists()` to seed offline lookup data
4. Display connection status to user

---

### 2.2 User Enters Credentials

```
┌─────────────────────────┐
│  User Fills Form        │
│  - Email/Username       │
│  - Password             │
│  - Clicks Login         │
└──────────┬──────────────┘
           │
           ▼
    ┌─────────────┐
    │  Validate   │
    │  Form       │
    └──────┬──────┘
           │
           ▼
    Network Available?
           │
       ┌───┴───┐
       │       │
      YES     NO
       │       │
       ▼       ▼
   Online  Offline
   Login   Login
```

**Decision Point:** `_handleLogin()` method (line ~680)
- If **offline** → Show confirmation dialog → Proceed to offline login
- If **online** → Attempt online login → Fallback to offline if fails

---

### 2.3 ONLINE LOGIN PATH

#### Step 1: Backend Authentication Request

**Frontend Request:**
```dart
POST http://your-server.com/mobile/login.php
Body: {
  'email': username,
  'password': password
}
Timeout: 15 seconds
```

**Code:** `lib/main.dart` lines 408-434 (`_attemptLogin()`)

#### Step 2: PHP Backend Processing

**Security Checks (PHP):**
```
┌──────────────────────────────┐
│  Rate Limiting Check         │
│  (10 attempts/min per IP)    │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│  Query Priority Order:       │
│  1. sdp table               │
│  2. client table            │
│  3. facilitator table       │
│  4. account_user table      │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│  Password Verification       │
│  - Bcrypt (password_verify)  │
│  - Generate Auth Token       │
│  - SHA-256 hash for storage  │
└──────────────────────────────┘
```

**Code Location:** `mobile/login.php` lines 45-550

#### Step 3: Role-Specific Data Retrieval

**For FACILITATOR role:**
```sql
SELECT 
    ld.LearnerID, ld.Title, ld.Name, ld.Surname, 
    ld.Email, lc.clock_in_time, lc.clock_out_time, 
    lc.contact_time
FROM learnerdetails ld
LEFT JOIN learner_clocking lc 
    ON ld.LearnerID = lc.LearnerID 
    AND lc.clock_date = CURDATE()
WHERE ld.classID = ?
```

**Response:**
```json
{
  "success": true,
  "role": "facilitator",
  "classID": "12345",
  "learners": [...],
  "facilitator_id": "678",
  "auth_token": "abc123..."
}
```

**For ASSESSOR/ARPL_ASSESSOR/MODERATOR roles:**
```sql
SELECT s.project_id, s.Project_pathway, c.* 
FROM class c
JOIN sites s ON s.siteID = c.siteID
JOIN facilitator f ON FIND_IN_SET(c.classID, f.classID) > 0
WHERE f.facilitator_id = ?
```

**Response:**
```json
{
  "success": true,
  "role": "arpl_assessor",
  "facilitator_id": "678",
  "classes": [...],
  "auth_token": "abc123..."
}
```

**For SDP role:**
```sql
-- Step 1: Get all projects for SDP
SELECT DISTINCT p.*, ...
FROM project p
WHERE p.sdp_name = ? OR p.project_id IN (
    SELECT DISTINCT s.project_id 
    FROM sites s WHERE s.sdp_id = ?
)

-- Step 2: For each project, parse Project_pathway JSON
-- Step 3: For each pathway, get sites
SELECT s.siteID, s.siteName, ...
FROM sites s
WHERE s.project_id = ? 
  AND s.sdp_id = ?
  AND TRIM(LOWER(s.Project_pathway)) = TRIM(LOWER(?))
```

**Response (Hierarchical):**
```json
{
  "success": true,
  "role": "sdp",
  "sdp_id": "123",
  "sdp_name": "ABC Training Provider",
  "projects": [
    {
      "project_id": "P001",
      "Project_name": "Skills Development 2026",
      "pathways": [
        {
          "pathway_name": "Bricklaying",
          "sites": [
            {"siteID": "S001", "siteName": "Site A", ...},
            {"siteID": "S002", "siteName": "Site B", ...}
          ]
        }
      ]
    }
  ],
  "auth_token": "xyz789..."
}
```

#### Step 4: Save Data Locally

**Flutter saves to SQLite:**
```dart
// Save facilitator details
await dbHelper.saveFacilitatorDetailsOffline(classID, {
  'firstName': data['firstName'],
  'lastName': data['lastName'],
  'email': username,
  'role': role,
  'facilitator_id': facilitatorId,
  ...
});

// Save class data
await dbHelper.ensureClassDataExists(classID,
  facilitatorEmail: username
);

// Sync learners
await dbHelper.syncLearnersFromServer(classID);
```

**Code:** `lib/main.dart` lines 493-534

#### Step 5: Background Sync (Non-Blocking)

```dart
// Triggered immediately after login, runs in background
_performBackgroundSync() {
  await syncService.syncDataToServer();
  await syncService.syncAllPOERecords();
  await syncService.syncLearnerDetails();
  await syncService.syncMaterialFormsWithServer();
  await syncService.syncAcknowledgmentOfReceiptToServer();
  await syncService.sync_inductionClocking();
}
```

**Code:** `lib/main.dart` lines 473-489

---

### 2.4 OFFLINE LOGIN PATH

#### Step 1: Local Database Queries

**Priority Order (Same as online):**
```
1. Check SDP table
   ↓ (not found)
2. Check Facilitator table
   ↓ (not found)
3. Return error
```

**Code:** `lib/main.dart` lines 600-670 (`_loginOffline()`)

#### Step 2: Password Verification

```dart
// Password stored in SQLite is PLAIN TEXT (synced from server)
Map<String, dynamic>? sdpEntry = 
    await dbHelper.getSdp(username, password);

Map<String, dynamic>? facilitator = 
    await dbHelper.getFacilitator(username, password);
```

**⚠️ SECURITY NOTE:** Offline passwords are plain text in SQLite. This is a **known limitation** for offline-first functionality in rural areas with no connectivity.

#### Step 3: Sync Attempt (Optional)

Even in offline mode, the system attempts to sync learner data:

```dart
try {
  await dbHelper.syncLearnersFromServer(classID);
  print('Successfully synced learners for classID: $classID');
} catch (e) {
  print('Failed to sync learners: $e');
  // CONTINUES WITH LOCAL DATA - Does NOT block login
}
```

---

### 2.5 Role-Based Navigation

**After successful authentication, navigation is determined by role:**

```dart
void _navigateBasedOnRole(
  String role, String classID, String sdp, 
  List classData, List learners, String facilitatorId, 
  List classes, Map<String, dynamic> data
) {
  final normalizedRole = role.toLowerCase().trim();

  switch(normalizedRole) {
    case 'sdp':
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => SdpProjectsPage(
          sdpIdentifier: sdp,
          projects: data['projects']
        )
      ));
      break;

    case 'finance':
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => FinanceDashboard(
          financeId: facilitatorId
        )
      ));
      break;

    case 'assessor':
      await _handleFacilitatorLoginByClassID(
        classID: classID,
        facilitatorId: facilitatorId,
        onSuccess: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => AssessorPage(
              facilitator_id: facilitatorId
            )
          ));
        }
      );
      break;

    case 'arpl_assessor':
      // SPECIAL: Requires fingerprint enrollment + daily clock-in
      await _handleFacilitatorLoginByClassID(
        classID: classID,
        facilitatorId: facilitatorId,
        onSuccess: () async {
          // Check fingerprint enrollment (one-time)
          if (!hasFingerprints) {
            // Navigate to enrollment page
            await Navigator.push(context, MaterialPageRoute(
              builder: (context) => FacilitatorFingerprintPage(
                isFirstTimeSetup: true
              )
            ));
          }

          // Check daily clock-in
          if (!clockedInToday) {
            // Navigate to clock-in page
            await Navigator.push(context, MaterialPageRoute(
              builder: (context) => FacilitatorFingerprintPage(
                requireClockIn: true
              )
            ));
          }

          // Finally navigate to dashboard
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => ArplAssessorPage(
              facilitator_id: facilitatorId
            )
          ));
        }
      );
      break;

    case 'facilitator':
    default:
      // Similar pattern for standard facilitators
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => DashboardPage(
          classID: classID
        )
      ));
      break;
  }
}
```

**Code:** `lib/main.dart` lines 702-900

---

## 3. Special Requirements by Role

### 3.1 ARPL Assessor Workflow

**ARPL Assessors have MANDATORY steps after authentication:**

```
┌──────────────────────────┐
│  Login Success           │
│  Role: arpl_assessor     │
└──────────┬───────────────┘
           │
           ▼
    ┌──────────────────┐
    │ Fingerprints     │   NO  ┌─────────────────────┐
    │ Enrolled?        ├──────→│ Navigate to         │
    └──────┬───────────┘       │ Fingerprint Enroll  │
          YES                  │ (BLOCKING)          │
           │                   └──────────┬──────────┘
           ▼                              │
    ┌──────────────────┐                 │
    │ Clocked In       │   NO            │
    │ Today?           ├─────────────────┘
    └──────┬───────────┘
          YES
           │
           ▼
    ┌──────────────────┐
    │ Navigate to      │
    │ ArplAssessorPage │
    └──────────────────┘
```

**Enforced at:** `lib/main.dart` lines 805-895

**Database Checks:**
```dart
// One-time check
bool hasFingerprints = 
    await dbHelper.facilitatorHasFingerprints(facilitatorId);

// Daily check
bool clockedInToday = 
    await dbHelper.facilitatorClockedInToday(facilitatorId);
```

### 3.2 Regular Facilitator Workflow

**Standard facilitators follow similar pattern:**
1. Fingerprint enrollment check (one-time)
2. Daily clock-in check
3. Navigate to Dashboard

**Difference:** Less strict enforcement - may allow bypass in some scenarios.

---

## 4. Security Features

### 4.1 Rate Limiting (PHP Backend)

```php
// 10 login attempts per minute per IP address
$rate_check = check_rate_limit($conn, $ip, 'login', 10, 60);

if (!$rate_check['allowed']) {
    http_response_code(429);
    echo json_encode([
        'success' => false,
        'message' => $rate_check['message'],
        'retry_after' => $rate_check['retry_after'],
        'error_code' => 'RATE_LIMIT_EXCEEDED'
    ]);
    exit;
}
```

**Code:** `mobile/login.php` lines 48-65

### 4.2 Auth Token System

**Token Generation:**
```php
function generateSecureToken($length = 64) {
    return bin2hex(random_bytes($length / 2));
}

function createAuthToken($conn, $user_id, $user_role, $expires_hours = 168) {
    $token = generateSecureToken();
    $token_hash = hash('sha256', $token);
    $expires_at = date('Y-m-d H:i:s', time() + ($expires_hours * 3600));
    
    // Delete old tokens
    DELETE FROM auth_tokens WHERE user_id = ? AND user_role = ?
    
    // Insert new token
    INSERT INTO auth_tokens (user_id, user_role, token_hash, expires_at)
    VALUES (?, ?, ?, ?)
    
    return $token; // Raw token sent to client
}
```

**Token Lifespan:** 7 days (168 hours)  
**Storage:** SHA-256 hash in MySQL, raw token sent to client  
**Usage:** Included in subsequent API requests for authentication  

**Code:** `mobile/login.php` lines 16-42

### 4.3 Password Security

**Online (MySQL):**
- ✅ Bcrypt hashing (`password_verify()`)
- ✅ No plain text storage
- ✅ Salt automatically managed by PHP

**Offline (SQLite):**
- ⚠️ Plain text passwords (synced from server)
- **Justification:** Required for offline-first in rural areas
- **Mitigation:** SQLite database is app-sandboxed on Android

### 4.4 Security Logging

```php
log_security_event('login_success', 'Successful account login', [
    'ip' => $ip,
    'email' => $email,
    'account_id' => $row['account_id'],
    'role' => $row['role']
]);

log_security_event('login_failed', 'Invalid credentials', [
    'ip' => $ip,
    'email' => $email
]);
```

**Logged Events:**
- Login success
- Login failure
- Rate limit exceeded
- Invalid password attempts

**Code:** `mobile/login.php` lines 398, 423, 447, 558-563

---

## 5. Data Synchronization

### 5.1 Post-Login Sync (Background)

**Triggered:** Immediately after successful online login  
**Blocking:** NO - runs in background, does not delay navigation  

**Sync Operations:**
```dart
1. syncDataToServer()           // Push local changes
2. syncAllPOERecords()          // Portfolio of Evidence
3. syncLearnerDetails()         // Pull learner updates
4. syncMaterialFormsWithServer() // Learning materials
5. syncAcknowledgmentOfReceiptToServer() // Signatures
6. sync_inductionClocking()     // Attendance records
```

**Code:** `lib/main.dart` lines 473-489

### 5.2 Learner Data Sync

**When:** After login for facilitators with classID  
**Blocking:** NO - continues with local data if fails  

```dart
if (classID.isNotEmpty) {
  try {
    await dbHelper.ensureClassDataExists(classID, ...);
    await dbHelper.syncLearnersFromServer(classID);
  } catch (e) {
    // Log error and continue
    print('Failed to sync learners: $e');
  }
}
```

---

## 6. Error Handling

### 6.1 Network Errors

```dart
Future<Map<String, dynamic>?> _attemptLogin(...) async {
  try {
    final response = await http.post(...)
        .timeout(const Duration(seconds: 15));
    
    if (response.statusCode == 200) {
      // Parse JSON
    }
  } catch (e) {
    print('Error during login: $e');
    return null; // Triggers offline fallback
  }
}
```

**Timeout:** 15 seconds  
**Fallback:** User can choose offline login  

### 6.2 JSON Parsing Errors

```dart
// Clean response by removing HTML tags
String cleaned = response.body
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .trim();

// Extract JSON object
final start = cleaned.indexOf('{');
final end = cleaned.lastIndexOf('}');
if (start != -1 && end != -1 && end >= start) {
  cleaned = cleaned.substring(start, end + 1);
}

try {
  final data = json.decode(cleaned);
  return data;
} catch (e) {
  debugPrint('[LOGIN] JSON parsing error: $e');
  return null;
}
```

**Handles:** PHP warnings, HTML output before JSON, malformed responses

### 6.3 User-Friendly Messages

```dart
void _showError(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 3),
    ),
  );
}

// Usage:
_showError('Invalid email or password');
_showError('Unable to reach server. Please try again.');
_showError('Clock-in is required to access the dashboard');
```

---

## 7. Offline-First Design Principles

### 7.1 Essential Data Seeding

**On App Launch:**
```dart
await dbHelper.ensureEssentialDataExists();
```

**Seeds:**
- Province lookup data
- Municipality lookup data
- Qualification codes
- Trade/skill categories
- Default class structures

**Purpose:** Enable offline learner registration and data entry

### 7.2 Graceful Degradation

```
┌─────────────────────────┐
│  Network Available?     │
└──────────┬──────────────┘
           │
       ┌───┴───┐
       │       │
      YES     NO
       │       │
       ▼       ▼
   Online  Offline
    Mode    Mode
       │       │
       ├───────┤
       │
       ▼
   Full Sync  Local Data
   + Latest   + Last Sync
   + Push     + Queue Ops
```

**User Experience:**
- **Online:** Full sync, latest data, immediate push
- **Offline:** Local cache, queue operations, sync on reconnect
- **Transition:** Automatic detection, transparent to user

### 7.3 Sync Queue System

**Queued Operations:**
- Learner clocking (clock-in/out)
- POE document uploads
- Material issue forms
- Learner registrations
- Assessment submissions

**Auto-Sync Triggers:**
- Network reconnect
- App resume from background
- Manual sync button
- Background timer (every 15 minutes when connected)

---

## 8. Database Schema

### 8.1 Auth Tokens Table (MySQL)

```sql
CREATE TABLE auth_tokens (
    token_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL,
    user_role VARCHAR(50) NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    expires_at DATETIME NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user (user_id, user_role),
    INDEX idx_token (token_hash),
    INDEX idx_expiry (expires_at)
);
```

### 8.2 Facilitator Table

```sql
CREATE TABLE facilitator (
    facilitator_id INT PRIMARY KEY,
    firstName VARCHAR(100),
    lastName VARCHAR(100),
    email VARCHAR(255) UNIQUE,
    phoneNumber VARCHAR(20),
    f_IDNumber VARCHAR(20),
    assessorNo VARCHAR(50),
    f_signature TEXT,
    f_profile TEXT,
    role VARCHAR(50),  -- 'facilitator', 'assessor', 'arpl_assessor', etc.
    classID TEXT,      -- Comma-separated list
    password VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 8.3 SDP Table

```sql
CREATE TABLE sdp (
    sdp_id INT PRIMARY KEY,
    client_name VARCHAR(255),
    email VARCHAR(255),
    password VARCHAR(255),  -- Bcrypt hashed
    sdp_name VARCHAR(255),
    Reg_number VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 8.4 Account User Table

```sql
CREATE TABLE account_user (
    account_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(100) UNIQUE,
    email VARCHAR(255),
    password VARCHAR(255),  -- Bcrypt hashed
    role VARCHAR(50),       -- 'finance', 'logistics', 'admin', etc.
    account_name VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

## 9. Key Differences from Standard Web Login

### 9.1 Multi-Role Support

**Web applications** typically have:
- Single login page per role
- Separate URLs (e.g., `/admin`, `/facilitator`)

**RLMSS Mobile:**
- ✅ Single login page for ALL roles
- ✅ Dynamic navigation based on authenticated role
- ✅ Role-specific data fetching

### 9.2 Offline Capability

**Standard web apps:**
- Require constant internet connection
- Session expires quickly
- No offline data access

**RLMSS Mobile:**
- ✅ Offline login with SQLite
- ✅ 7-day token persistence
- ✅ Offline data entry with sync queue
- ✅ Automatic reconnect and sync

### 9.3 Biometric Integration

**ARPL Assessors & Facilitators:**
- ✅ Mandatory fingerprint enrollment
- ✅ Daily biometric clock-in
- ✅ Hardware fingerprint scanner support (Futronic/ZKTeco)

**Standard web login:**
- Typically username/password only

---

## 10. Known Issues & Considerations

### 10.1 Offline Password Security

**Issue:** SQLite stores passwords in plain text  
**Risk:** If device is rooted/compromised, passwords are exposed  
**Mitigation:**
- App uses Android sandboxing
- SQLite database is not world-readable
- User education on device security

**Future Enhancement:** Consider SQLCipher for encrypted SQLite

### 10.2 Role Case Sensitivity

**Issue:** Role strings have inconsistent casing in database
- `facilitator` vs `Facilitator`
- `arpl_assessor` vs `ARPL_Assessor`
- `Moderator` vs `moderator`

**Current Fix:** 
```dart
final normalizedRole = role.toLowerCase().trim();
```

**Recommendation:** Standardize database values to lowercase

### 10.3 ClassID Validation

**Issue:** Empty or invalid classID can cause navigation errors

**Current Fix:**
```dart
if (classID.isNotEmpty) {
  // Safe to proceed
}
```

**Recommendation:** Add server-side validation for classID assignment

### 10.4 Token Expiry Handling

**Current:** Tokens expire after 7 days  
**Gap:** No automatic refresh mechanism  
**Impact:** User must re-login after 7 days  

**Recommendation:** Implement token refresh endpoint

---

## 11. Testing Checklist

### 11.1 Online Login Tests

- [ ] Login as facilitator with valid credentials
- [ ] Login as assessor with valid credentials
- [ ] Login as ARPL assessor with valid credentials
- [ ] Login as SDP with valid credentials
- [ ] Login as finance user
- [ ] Login as logistics user
- [ ] Login with invalid credentials (should fail)
- [ ] Login with correct username but wrong password (should fail)
- [ ] Verify rate limiting (try 11+ attempts rapidly)
- [ ] Verify auth token is saved to SharedPreferences
- [ ] Verify background sync starts after login
- [ ] Verify learners are synced for facilitator role

### 11.2 Offline Login Tests

- [ ] Turn off WiFi and mobile data
- [ ] Login as facilitator (previously synced)
- [ ] Login as SDP (previously synced)
- [ ] Try login with never-synced user (should fail)
- [ ] Verify offline dialog appears
- [ ] Verify learner data loads from SQLite
- [ ] Verify sync queue operations are stored

### 11.3 Role Navigation Tests

- [ ] Facilitator → Dashboard → Learner List
- [ ] Assessor → AssessorPage → Class List
- [ ] ARPL Assessor → Fingerprint Check → Clock-in → ArplAssessorPage
- [ ] SDP → Projects → Pathways → Sites → Classes
- [ ] Finance → FinanceDashboard
- [ ] Logistics → LogisticsDashboard

### 11.4 Security Tests

- [ ] Verify bcrypt password hashing on server
- [ ] Verify auth token is SHA-256 hashed in database
- [ ] Verify rate limiting logs security events
- [ ] Verify failed login attempts are logged
- [ ] Test SQL injection in login fields (should be prevented by prepared statements)
- [ ] Test XSS in login response (should be sanitized)

### 11.5 Edge Cases

- [ ] Login during network interruption (timeout handling)
- [ ] Login with malformed JSON response
- [ ] Login with PHP warnings/errors in response
- [ ] Login when database is unreachable
- [ ] Login with expired auth token
- [ ] Login when fingerprint enrollment is incomplete (ARPL assessor)
- [ ] Login when not clocked in (ARPL assessor)

---

## 12. Workflow Diagrams

### 12.1 Complete Authentication Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    USER OPENS RLMSS APP                       │
└───────────────────────────────┬──────────────────────────────┘
                                │
                                ▼
                    ┌────────────────────────┐
                    │  LoginPage Initializes │
                    │  - Check Connectivity  │
                    │  - Check SQLite DB     │
                    │  - Seed Offline Data   │
                    └───────────┬────────────┘
                                │
                                ▼
                    ┌────────────────────────┐
                    │  User Enters Creds     │
                    │  - Email/Username      │
                    │  - Password            │
                    │  - Clicks LOGIN        │
                    └───────────┬────────────┘
                                │
                                ▼
                        Network Available?
                                │
                    ┌───────────┴────────────┐
                   YES                       NO
                    │                         │
                    ▼                         ▼
        ┌──────────────────────┐  ┌──────────────────────┐
        │   ONLINE LOGIN       │  │  Show Dialog:        │
        │                      │  │  "Proceed Offline?"  │
        │  POST to login.php   │  └──────────┬───────────┘
        │  - Timeout: 15s      │             │
        │  - Rate Limited      │         ┌───┴───┐
        └──────────┬───────────┘        YES     NO
                   │                      │      │
                   ▼                      │      └─→ Cancel
        ┌──────────────────────┐         │
        │  PHP Backend:        │         ▼
        │  1. Check sdp        │  ┌──────────────────────┐
        │  2. Check client     │  │   OFFLINE LOGIN      │
        │  3. Check facilitator│  │                      │
        │  4. Check account_usr│  │  Query SQLite:       │
        │                      │  │  1. Check sdp        │
        │  - Verify password   │  │  2. Check facilitator│
        │  - Generate token    │  └──────────┬───────────┘
        │  - Fetch role data   │             │
        └──────────┬───────────┘             │
                   │                         │
                   └────────────┬────────────┘
                                │
                                ▼
                    ┌────────────────────────┐
                    │  Authentication OK     │
                    │  - Save to SQLite      │
                    │  - Start Background    │
                    │    Sync (online only)  │
                    └───────────┬────────────┘
                                │
                                ▼
                        Determine Role
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐   ┌───────────────────┐   ┌─────────────────┐
│   SDP Role    │   │ ARPL Assessor     │   │ Other Roles     │
│               │   │                   │   │                 │
│ → Projects    │   │ → Check Prints?   │   │ → Finance       │
│   → Pathways  │   │   NO → Enroll     │   │ → Logistics     │
│     → Sites   │   │   YES ↓           │   │ → Assessor      │
│       → Classes│  │ → Clocked In?     │   │ → Moderator     │
└───────────────┘   │   NO → Clock-in   │   │ → Facilitator   │
                    │   YES → Dashboard │   │ → Admin         │
                    └───────────────────┘   └─────────────────┘
```

### 12.2 ARPL Assessor Specific Flow

```
┌───────────────────────────────────────────────────────────────┐
│           ARPL ASSESSOR AUTHENTICATION COMPLETE               │
└──────────────────────────────┬────────────────────────────────┘
                               │
                               ▼
                ┌──────────────────────────────┐
                │ Check: Fingerprints Enrolled?│
                └──────────┬───────────────────┘
                          │
                    ┌─────┴─────┐
                   NO           YES
                    │             │
                    ▼             ▼
    ┌──────────────────────────┐  │
    │ Navigate to:             │  │
    │ FacilitatorFingerprintPage│ │
    │ - isFirstTimeSetup: true │  │
    │ - Show enrollment UI     │  │
    │ - Scan 10 fingerprints  │  │
    │ - Save to SQLite         │  │
    └──────────┬───────────────┘  │
               │                  │
               │ ┌────────────────┘
               │ │
               ▼ ▼
    ┌──────────────────────────┐
    │ Check: Clocked In Today? │
    └──────────┬─────────────────┘
               │
         ┌─────┴─────┐
        NO           YES
         │             │
         ▼             ▼
┌──────────────────────────┐  │
│ Navigate to:             │  │
│ FacilitatorFingerprintPage│ │
│ - requireClockIn: true   │  │
│ - Show clock-in UI       │  │
│ - Verify fingerprint     │  │
│ - Record clock-in time   │  │
│ - Capture signature      │  │
│ - Take profile photo     │  │
└──────────┬───────────────┘  │
           │                  │
           │ ┌────────────────┘
           │ │
           ▼ ▼
┌──────────────────────────┐
│ Navigate to:             │
│ ArplAssessorPage         │
│ - Show class list        │
│ - Access learner data    │
│ - Record assessments     │
└──────────────────────────┘
```

---

## 13. API Endpoints Reference

### 13.1 Login Endpoint

**URL:** `https://your-server.com/mobile/login.php`  
**Method:** POST  
**Content-Type:** `application/x-www-form-urlencoded`  
**Rate Limit:** 10 requests per minute per IP  

**Request Body:**
```
email=user@example.com&password=SecurePass123
```

**Response Format:**

*Facilitator:*
```json
{
  "success": true,
  "role": "facilitator",
  "classID": "12345",
  "facilitator_id": "678",
  "learners": [
    {
      "LearnerID": "L001",
      "Title": "Mr",
      "Name": "John",
      "Surname": "Doe",
      "Email": "john@example.com",
      "clock_in_time": "08:30:00",
      "clock_out_time": null,
      "contact_time": "480"
    }
  ],
  "auth_token": "a1b2c3d4e5f6..."
}
```

*ARPL Assessor:*
```json
{
  "success": true,
  "role": "arpl_assessor",
  "facilitator_id": "678",
  "classes": [
    {
      "project_id": "P001",
      "Project_pathway": "Bricklaying",
      "classId": "C001",
      "className": "Bricklaying Class A",
      "siteID": "S001",
      "siteName": "Training Site 1"
    }
  ],
  "auth_token": "x9y8z7w6v5u4..."
}
```

*SDP:*
```json
{
  "success": true,
  "role": "sdp",
  "sdp_id": "123",
  "sdp_name": "ABC Training Provider",
  "projects": [
    {
      "project_id": "P001",
      "Project_name": "Skills Development 2026",
      "pathways": [
        {
          "pathway_name": "Bricklaying",
          "sites": [...]
        }
      ]
    }
  ],
  "auth_token": "p0o9i8u7y6t5..."
}
```

*Error Response:*
```json
{
  "success": false,
  "message": "Invalid credentials"
}
```

*Rate Limited:*
```json
{
  "success": false,
  "message": "Too many login attempts. Please try again later.",
  "retry_after": 45,
  "error_code": "RATE_LIMIT_EXCEEDED"
}
```

---

## 14. Recommendations for Improvement

### 14.1 High Priority

1. **Implement Token Refresh**
   - Add `/mobile/refresh_token.php` endpoint
   - Auto-refresh tokens before 7-day expiry
   - Reduce user re-login frequency

2. **Encrypt SQLite Database**
   - Use SQLCipher for offline database
   - Protect plain text passwords
   - Secure PII (learner data)

3. **Standardize Role Values**
   - Convert all database roles to lowercase
   - Update PHP and Dart to use consistent casing
   - Add database migration script

4. **Add Session Management UI**
   - Show "Logged in as: [Name]" in app header
   - Add "Logout" button (clear SQLite, tokens)
   - Display session expiry countdown

### 14.2 Medium Priority

5. **Biometric Authentication for All Roles**
   - Extend fingerprint requirement to all facilitators
   - Add device biometric option (FaceID, TouchID)
   - Implement "Remember Me" with biometric

6. **Enhanced Error Messages**
   - User-friendly explanations for errors
   - Suggest solutions (e.g., "Check your internet connection")
   - Add error code reference in documentation

7. **Login Analytics Dashboard**
   - Track login success/failure rates
   - Monitor offline vs online logins
   - Alert on suspicious patterns (multiple failed attempts)

### 14.3 Low Priority

8. **Multi-Factor Authentication (MFA)**
   - SMS OTP for sensitive roles (Finance, Admin)
   - Email verification for password reset
   - TOTP app support (Google Authenticator)

9. **Password Complexity Rules**
   - Enforce minimum 8 characters
   - Require uppercase, lowercase, number, symbol
   - Prevent common passwords

10. **Remember Username**
    - Save email/username (not password) locally
    - Auto-fill on app reopen
    - User preference toggle

---

## 15. Conclusion

The RLMSS facilitator authentication system is a **robust, multi-role, offline-first** solution designed for rural deployment. It successfully handles:

✅ **9+ different user roles** with dynamic navigation  
✅ **Hybrid online/offline login** with graceful degradation  
✅ **Biometric authentication** for assessors (fingerprint)  
✅ **Background data synchronization** for seamless UX  
✅ **Security features**: bcrypt, auth tokens, rate limiting, event logging  
✅ **Rural-optimized**: Offline data entry, sync queue, essential data seeding  

**Key Strengths:**
- Comprehensive role support
- Offline-first architecture
- Automatic sync and recovery
- User-friendly error handling

**Areas for Improvement:**
- SQLite encryption
- Token refresh mechanism
- Role standardization
- Session management UI

---

**Document Version:** 1.0  
**Last Updated:** October 14, 2026  
**Author:** AI Agent (Kiro)  
**Review Status:** ✅ Ready for comparison with specification document
