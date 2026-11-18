# SQL Injection Fix Guide - CRITICAL SECURITY
## rlmssv1 PHP API Security Hardening

**Priority:** 🚨 **CRITICAL - BLOCKING DEPLOYMENT**  
**Estimated Effort:** 6-8 hours  
**Risk Level:** HIGH - Data breach possible

---

## VULNERABLE FILES INVENTORY

### Priority 1: CRITICAL (Fix Immediately)

#### 1. bulk_down_register.php
**Lines:** 468, 578  
**Vulnerability:**
```php
// VULNERABLE CODE
$siteQuery .= " WHERE District = '" . $conn->real_escape_string($_GET['district']) . "'";
$whereClauses[] = "ld.IDNumber = '" . $conn->real_escape_string($_GET['id_search']) . "'";
```

**Fix:**
```php
// SECURE CODE
$stmt = $conn->prepare("SELECT * FROM sites WHERE District = ?");
$stmt->bind_param("s", $_GET['district']);
$stmt->execute();
$result = $stmt->get_result();

// For multiple WHERE clauses
$stmt = $conn->prepare("SELECT * FROM learnerdetails ld WHERE ld.IDNumber = ?");
$stmt->bind_param("s", $_GET['id_search']);
```

#### 2. cached_search_learners.php
**Lines:** 75-79  
**Vulnerable Parameters:** classID, search, page, limit

**Current Code:**
```php
$classID = $_GET['classID'] ?? $_POST['classID'] ?? null;
$searchQuery = trim($_GET['search'] ?? $_POST['search'] ?? '');
```

**Secure Fix:**
```php
// Validate inputs
$classID = filter_var($_GET['classID'] ?? $_POST['classID'] ?? null, FILTER_VALIDATE_INT);
if ($classID === false) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid class ID']);
    exit;
}

$searchQuery = trim($_GET['search'] ?? $_POST['search'] ?? '');
$searchQuery = htmlspecialchars($searchQuery, ENT_QUOTES, 'UTF-8');

// Use prepared statement for query
$stmt = $conn->prepare("SELECT * FROM learners WHERE classID = ? AND (name LIKE ? OR idnumber LIKE ?)");
$searchParam = "%$searchQuery%";
$stmt->bind_param("iss", $classID, $searchParam, $searchParam);
```

---

### Priority 2: HIGH (Fix Before Production)

#### 3. approve_pending_documents.php
**Line:** 7  
**Issue:** Partial protection with intval()

**Current:**
```php
$learner_id = isset($_GET['learner_id']) ? intval($_GET['learner_id']) : null;
```

**Better Fix:**
```php
$learner_id = filter_var($_GET['learner_id'] ?? null, FILTER_VALIDATE_INT);
if ($learner_id === false || $learner_id === null) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid learner ID']);
    exit;
}

// Use prepared statement
$stmt = $conn->prepare("SELECT * FROM learnerdetails WHERE LearnerID = ?");
$stmt->bind_param("i", $learner_id);
```

#### 4. bulk_export_api.php
**Multiple $_POST accesses without validation**

**Fix Pattern:**
```php
// Validate ALL inputs
$input = $_POST;

// Validate learner IDs
if (isset($input['learner_ids'])) {
    $learnerIds = json_decode($input['learner_ids'], true);
    if (!is_array($learnerIds)) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid learner IDs format']);
        exit;
    }
    
    // Validate each ID is numeric
    $learnerIds = array_filter($learnerIds, function($id) {
        return filter_var($id, FILTER_VALIDATE_INT) !== false;
    });
}

// Use prepared statements with IN clause
$placeholders = implode(',', array_fill(0, count($learnerIds), '?'));
$stmt = $conn->prepare("SELECT * FROM learners WHERE LearnerID IN ($placeholders)");
$types = str_repeat('i', count($learnerIds));
$stmt->bind_param($types, ...$learnerIds);
```

#### 5. bulk_export_background.php
**Lines:** 17-21

**Current:**
```php
$jobId = $_POST['job_id'] ?? uniqid('job_');
$learnerIds = isset($_POST['learner_ids']) ? json_decode($_POST['learner_ids'], true) : [];
$startDate = $_POST['start_date'] ?? date('Y-m-01');
```

**Secure:**
```php
// Validate job ID format
$jobId = $_POST['job_id'] ?? uniqid('job_');
if (!preg_match('/^[a-zA-Z0-9_-]+$/', $jobId)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid job ID']);
    exit;
}

// Validate learner IDs
$learnerIds = isset($_POST['learner_ids']) ? json_decode($_POST['learner_ids'], true) : [];
if (!is_array($learnerIds) || empty($learnerIds)) {
    http_response_code(400);
    echo json_encode(['error' => 'Learner IDs required']);
    exit;
}

// Validate dates
$startDate = $_POST['start_date'] ?? date('Y-m-01');
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $startDate)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid date format']);
    exit;
}
```

---

### Priority 3: MEDIUM (Review and Fix)

#### 6-8. add_supplemental_learners*.php (3 files)
- add_supplemental_learners.php
- add_supplemental_learners_fast.php
- add_supplemental_learners_from_existing.php

**Common Pattern:**
```php
$moderatorId = $data['moderator_id'] ?? $_GET['moderator_id'] ?? '';
$targetCount = $data['target_count'] ?? $_GET['target_count'] ?? 402;
```

**Secure:**
```php
// Validate moderator ID
$moderatorId = $data['moderator_id'] ?? $_GET['moderator_id'] ?? '';
if (empty($moderatorId) || !preg_match('/^[0-9]+$/', $moderatorId)) {
    http_response_code(400);
    echo json_encode(['error' => 'Valid moderator ID required']);
    exit;
}

// Validate target count
$targetCount = filter_var(
    $data['target_count'] ?? $_GET['target_count'] ?? 402,
    FILTER_VALIDATE_INT,
    ['options' => ['min_range' => 1, 'max_range' => 10000]]
);

if ($targetCount === false) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid target count']);
    exit;
}

// Use prepared statement
$stmt = $conn->prepare("SELECT * FROM moderators WHERE id = ?");
$stmt->bind_param("i", $moderatorId);
```

---

## COMPREHENSIVE FIX TEMPLATE

### Standard Prepared Statement Pattern:

```php
<?php
// 1. INPUT VALIDATION
function validateInput($input, $type = 'string', $required = true) {
    if ($required && (empty($input) && $input !== '0')) {
        throw new InvalidArgumentException('Required field missing');
    }
    
    switch ($type) {
        case 'int':
            $validated = filter_var($input, FILTER_VALIDATE_INT);
            if ($validated === false) {
                throw new InvalidArgumentException('Invalid integer');
            }
            return $validated;
            
        case 'email':
            $validated = filter_var($input, FILTER_VALIDATE_EMAIL);
            if ($validated === false) {
                throw new InvalidArgumentException('Invalid email');
            }
            return $validated;
            
        case 'date':
            if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $input)) {
                throw new InvalidArgumentException('Invalid date format');
            }
            return $input;
            
        case 'string':
        default:
            return htmlspecialchars(trim($input), ENT_QUOTES, 'UTF-8');
    }
}

// 2. PREPARED STATEMENT EXECUTION
try {
    // Validate inputs
    $learnerId = validateInput($_GET['learner_id'] ?? null, 'int', true);
    $status = validateInput($_GET['status'] ?? 'active', 'string', false);
    
    // Prepare statement
    $stmt = $conn->prepare("
        SELECT l.*, c.className 
        FROM learners l 
        JOIN classes c ON l.classID = c.id 
        WHERE l.LearnerID = ? AND l.status = ?
    ");
    
    if (!$stmt) {
        throw new Exception('Prepare failed: ' . $conn->error);
    }
    
    // Bind parameters
    $stmt->bind_param("is", $learnerId, $status);
    
    // Execute
    if (!$stmt->execute()) {
        throw new Exception('Execute failed: ' . $stmt->error);
    }
    
    // Get results
    $result = $stmt->get_result();
    $data = $result->fetch_all(MYSQLI_ASSOC);
    
    // Close statement
    $stmt->close();
    
    // Return JSON
    header('Content-Type: application/json');
    echo json_encode([
        'success' => true,
        'data' => $data
    ]);
    
} catch (InvalidArgumentException $e) {
    http_response_code(400);
    echo json_encode(['error' => $e->getMessage()]);
    
} catch (Exception $e) {
    error_log('Database error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['error' => 'Internal server error']);
}
?>
```

---

## VALIDATION FUNCTIONS LIBRARY

Create a shared validation file: `includes/validation.php`

```php
<?php
class InputValidator {
    
    public static function validateInt($value, $min = null, $max = null) {
        $options = ['options' => []];
        if ($min !== null) $options['options']['min_range'] = $min;
        if ($max !== null) $options['options']['max_range'] = $max;
        
        $result = filter_var($value, FILTER_VALIDATE_INT, $options);
        if ($result === false) {
            throw new InvalidArgumentException('Invalid integer value');
        }
        return $result;
    }
    
    public static function validateEmail($email) {
        $result = filter_var($email, FILTER_VALIDATE_EMAIL);
        if ($result === false) {
            throw new InvalidArgumentException('Invalid email');
        }
        return $result;
    }
    
    public static function validateDate($date) {
        if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
            throw new InvalidArgumentException('Invalid date format (YYYY-MM-DD)');
        }
        $dt = DateTime::createFromFormat('Y-m-d', $date);
        if (!$dt || $dt->format('Y-m-d') !== $date) {
            throw new InvalidArgumentException('Invalid date');
        }
        return $date;
    }
    
    public static function validateEnum($value, array $allowed) {
        if (!in_array($value, $allowed, true)) {
            throw new InvalidArgumentException('Invalid value. Allowed: ' . implode(', ', $allowed));
        }
        return $value;
    }
    
    public static function sanitizeString($str, $maxLength = 255) {
        $str = trim($str);
        $str = substr($str, 0, $maxLength);
        return htmlspecialchars($str, ENT_QUOTES, 'UTF-8');
    }
    
    public static function validateIdNumber($idNumber) {
        // South African ID format: YYMMDDGSSSCAZ
        if (!preg_match('/^\d{13}$/', $idNumber)) {
            throw new InvalidArgumentException('Invalid ID number format');
        }
        return $idNumber;
    }
}
?>
```

---

## TESTING CHECKLIST

After implementing fixes, test each endpoint:

### Manual Testing:

```bash
# Test with valid input
curl -X POST "http://localhost/api/endpoint.php" \
  -d "learner_id=123&status=active"

# Test with SQL injection attempt
curl -X POST "http://localhost/api/endpoint.php" \
  -d "learner_id=123' OR '1'='1&status=active"

# Test with invalid input
curl -X POST "http://localhost/api/endpoint.php" \
  -d "learner_id=abc&status=active"

# Test with missing required fields
curl -X POST "http://localhost/api/endpoint.php" \
  -d "status=active"
```

### Expected Results:
- ✅ Valid input: Success (200)
- ✅ SQL injection attempt: Validation error (400)
- ✅ Invalid input: Validation error (400)
- ✅ Missing fields: Validation error (400)

### Automated Testing:

Create `tests/security_test.php`:

```php
<?php
function testSQLInjection($endpoint, $params) {
    $injectionPatterns = [
        "' OR '1'='1",
        "1' UNION SELECT NULL--",
        "'; DROP TABLE users--",
        "1' AND 1=1--",
    ];
    
    foreach ($injectionPatterns as $pattern) {
        $testParams = $params;
        $testParams['test'] = $pattern;
        
        $response = file_get_contents("$endpoint?" . http_build_query($testParams));
        $json = json_decode($response, true);
        
        if (!isset($json['error'])) {
            echo "❌ FAILED: Injection pattern not caught: $pattern\n";
            return false;
        }
    }
    
    echo "✅ PASSED: All injection patterns caught\n";
    return true;
}

// Test all endpoints
testSQLInjection('http://localhost/api/get_learner.php', ['learner_id' => '123']);
testSQLInjection('http://localhost/api/search.php', ['search' => 'test']);
// Add more endpoints...
?>
```

---

## DEPLOYMENT CHECKLIST

Before deploying security fixes:

- [ ] All prepared statements implemented
- [ ] All user inputs validated
- [ ] Error messages don't leak sensitive info
- [ ] Security testing completed
- [ ] Manual penetration testing done
- [ ] All API endpoints tested
- [ ] Logs reviewed for errors
- [ ] Backup database created
- [ ] Rollback plan documented

---

## PRIORITY QUEUE

Work through files in this order:

**Day 1 (3-4 hours):**
1. ✅ bulk_down_register.php (CRITICAL)
2. ✅ cached_search_learners.php (CRITICAL)
3. ✅ approve_pending_documents.php (HIGH)

**Day 2 (3-4 hours):**
4. ✅ bulk_export_api.php
5. ✅ bulk_export_background.php
6. ✅ bulk_export_with_documents.php
7. ✅ add_supplemental_learners*.php (3 files)

**Day 3 (Review & Test):**
8. ✅ Review all mobile/*.php files
9. ✅ Run security tests
10. ✅ Manual penetration testing

---

## CONCLUSION

**Current Status:** 🚨 **CRITICAL SECURITY VULNERABILITIES**

**Required Action:** Fix SQL injection in 20+ PHP files

**Effort:** 6-8 hours focused work

**Impact:** **BLOCKS PRODUCTION DEPLOYMENT**

**Next Step:** Start with bulk_down_register.php and cached_search_learners.php

---

**Document End**
**Created:** January 21, 2025
**Status:** Ready for implementation
