# Security Guidelines for RLMS Project

## 🔒 Security Standards

All code MUST pass security checks before deployment. This document outlines mandatory security practices.

---

## 1. SQL Injection Prevention

### ❌ NEVER DO THIS:
```php
// UNSAFE - Direct variable in SQL query
$sql = "SELECT * FROM users WHERE id = $_GET['id']";
$sql = "SELECT * FROM users WHERE email = '$email'";
$sql = "INSERT INTO learners VALUES ('$name', '$id')";
```

### ✅ ALWAYS DO THIS:
```php
// SAFE - Use prepared statements
$stmt = $conn->prepare("SELECT * FROM users WHERE id = ?");
$stmt->bind_param("i", $user_id);
$stmt->execute();

// Or with PDO
$stmt = $pdo->prepare("SELECT * FROM users WHERE email = :email");
$stmt->execute(['email' => $email]);
```

### Mandatory Rules:
1. **ALWAYS** use prepared statements with parameterized queries
2. **NEVER** concatenate user input directly into SQL
3. Use `bind_param()` or PDO placeholders for ALL user inputs
4. Validate and sanitize input BEFORE using in queries
5. Use `intval()` for numeric IDs, `filter_var()` for other types

---

## 2. XSS (Cross-Site Scripting) Prevention

### ❌ NEVER DO THIS:
```php
// UNSAFE - Direct output
echo $_GET['message'];
echo $user_input;
```

### ✅ ALWAYS DO THIS:
```php
// SAFE - Escaped output
echo htmlspecialchars($_GET['message'], ENT_QUOTES, 'UTF-8');
echo htmlentities($user_input, ENT_QUOTES, 'UTF-8');
```

### Mandatory Rules:
1. **ALWAYS** escape output with `htmlspecialchars()` or `htmlentities()`
2. Use `ENT_QUOTES` flag to escape both single and double quotes
3. Specify `UTF-8` encoding
4. Never trust user input - escape everything

---

## 3. Authentication & Authorization

### Password Security

❌ **NEVER** use MD5 or SHA1 for passwords:
```php
// INSECURE
$hash = md5($password);
$hash = sha1($password);
```

✅ **ALWAYS** use `password_hash()`:
```php
// SECURE
$hash = password_hash($password, PASSWORD_DEFAULT);

// Verify
if (password_verify($input_password, $stored_hash)) {
    // Password correct
}
```

### Session Security

```php
// Start session securely
session_start([
    'cookie_httponly' => true,
    'cookie_secure' => true,  // HTTPS only
    'cookie_samesite' => 'Strict'
]);

// Regenerate session ID on login
session_regenerate_id(true);
```

### Mandatory Rules:
1. Use `password_hash()` and `password_verify()` for passwords
2. Regenerate session ID on authentication state changes
3. Set secure session cookie flags
4. Implement session timeout
5. Check authentication on EVERY protected endpoint

---

## 4. File Upload Security

### ❌ NEVER DO THIS:
```php
// UNSAFE - No validation
move_uploaded_file($_FILES['file']['tmp_name'], 'uploads/' . $_FILES['file']['name']);
```

### ✅ ALWAYS DO THIS:
```php
// SAFE - Validate type, size, and sanitize name
$allowed_types = ['image/jpeg', 'image/png', 'application/pdf'];
$max_size = 5 * 1024 * 1024; // 5MB

if (!in_array($_FILES['file']['type'], $allowed_types)) {
    die('Invalid file type');
}

if ($_FILES['file']['size'] > $max_size) {
    die('File too large');
}

// Use secure filename
$extension = pathinfo($_FILES['file']['name'], PATHINFO_EXTENSION);
$filename = uniqid('upload_', true) . '.' . $extension;
$destination = 'uploads/' . $filename;

move_uploaded_file($_FILES['file']['tmp_name'], $destination);
```

### Mandatory Rules:
1. Validate file type (MIME type AND extension)
2. Limit file size
3. Generate secure filenames (never use user-provided names)
4. Store uploads outside web root when possible
5. Scan for malware if handling PDFs/documents

---

## 5. Path Traversal Prevention

### ❌ NEVER DO THIS:
```php
// UNSAFE - Direct user input in file operations
$file = $_GET['file'];
include('pages/' . $file);
$content = file_get_contents('docs/' . $_GET['doc']);
```

### ✅ ALWAYS DO THIS:
```php
// SAFE - Validate and sanitize
$allowed_files = ['home.php', 'about.php', 'contact.php'];
$file = basename($_GET['file']); // Remove directory traversal
if (!in_array($file, $allowed_files)) {
    die('Invalid file');
}
include('pages/' . $file);

// Or use realpath() to resolve and validate
$base_dir = realpath('/var/www/docs');
$requested = realpath($base_dir . '/' . $_GET['doc']);
if (strpos($requested, $base_dir) !== 0) {
    die('Invalid path');
}
```

### Mandatory Rules:
1. Use `basename()` to strip directory components
2. Validate against whitelist of allowed files
3. Use `realpath()` to resolve and check paths
4. Never directly use user input in `include`, `require`, `fopen`, etc.

---

## 6. Command Injection Prevention

### ❌ NEVER DO THIS:
```php
// UNSAFE - User input in system commands
exec("convert " . $_GET['file'] . " output.pdf");
system("ping " . $_POST['host']);
```

### ✅ ALWAYS DO THIS:
```php
// SAFE - Escape arguments
$file = escapeshellarg($_GET['file']);
exec("convert $file output.pdf");

// Better - avoid shell execution altogether
// Use PHP libraries instead of shell commands
```

### Mandatory Rules:
1. **AVOID** shell commands when possible - use PHP functions/libraries
2. If shell commands required, use `escapeshellarg()` for arguments
3. Use `escapeshellcmd()` for command names
4. Validate input against whitelist
5. Never use `eval()` with user input

---

## 7. HTTPS & Secure Communication

### Mandatory Rules:
1. **ALL** production traffic MUST use HTTPS
2. Enforce HTTPS redirects
3. Use HSTS headers
4. Validate SSL certificates (never disable in production)

```php
// PHP - Enforce HTTPS
if (!isset($_SERVER['HTTPS']) || $_SERVER['HTTPS'] !== 'on') {
    header('Location: https://' . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
    exit;
}
```

```dart
// Flutter - NO certificate bypass in production
// ❌ NEVER DO THIS:
HttpClient client = HttpClient()
  ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);

// ✅ Default is secure - just don't override
```

---

## 8. CSRF Protection

### Implementation:
```php
// Generate token
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

// In forms
echo '<input type="hidden" name="csrf_token" value="' . $_SESSION['csrf_token'] . '">';

// Validate
if (!hash_equals($_SESSION['csrf_token'], $_POST['csrf_token'])) {
    die('CSRF token validation failed');
}
```

### Mandatory Rules:
1. Generate unique CSRF token per session
2. Include token in ALL forms
3. Validate token on ALL POST/PUT/DELETE requests
4. Use `hash_equals()` for comparison (timing-attack safe)

---

## 9. Information Disclosure Prevention

### Production Settings:
```php
// NEVER display errors in production
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

// Remove debug info
// ❌ NEVER leave these in production:
// phpinfo();
// var_dump($sensitive_data);
// print_r($_SERVER);
```

### Mandatory Rules:
1. Disable error display in production
2. Log errors to files, not browser
3. Remove all debug code before deployment
4. Never expose stack traces to users
5. Remove `phpinfo()` and debugging functions

---

## 10. Input Validation

### Comprehensive Validation:
```php
// Validate email
$email = filter_var($_POST['email'], FILTER_VALIDATE_EMAIL);
if (!$email) {
    die('Invalid email');
}

// Validate integer
$id = filter_var($_POST['id'], FILTER_VALIDATE_INT);
if ($id === false) {
    die('Invalid ID');
}

// Validate URL
$url = filter_var($_POST['url'], FILTER_VALIDATE_URL);

// Custom validation
if (!preg_match('/^[a-zA-Z0-9_]{3,20}$/', $_POST['username'])) {
    die('Invalid username format');
}
```

### Mandatory Rules:
1. Validate ALL user inputs
2. Use `filter_var()` for standard types
3. Use regex for custom formats
4. Validate on server side (never trust client)
5. Fail closed - reject if validation uncertain

---

## 11. Flutter/Dart Security

### Secure Storage:
```dart
// ❌ NEVER store sensitive data in SharedPreferences
SharedPreferences prefs = await SharedPreferences.getInstance();
prefs.setString('password', password); // INSECURE!

// ✅ Use flutter_secure_storage
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage();
await storage.write(key: 'auth_token', value: token);
String? token = await storage.read(key: 'auth_token');
```

### API Communication:
```dart
// ✅ Always use HTTPS
final url = Uri.parse('https://api.rlms.co.za/endpoint');

// ✅ Add timeout
final response = await http.get(url).timeout(Duration(seconds: 30));

// ✅ Validate response
if (response.statusCode == 200) {
    // Process data
} else {
    // Handle error
}
```

### Mandatory Rules:
1. Use `flutter_secure_storage` for sensitive data
2. Never disable SSL validation
3. Always use HTTPS in production
4. Implement request timeouts
5. Validate all API responses

---

## 12. Database Security

### Connection Security:
```php
// ✅ Use environment variables for credentials
$host = getenv('DB_HOST');
$user = getenv('DB_USER');
$pass = getenv('DB_PASS');
$db = getenv('DB_NAME');

// ✅ Use mysqli or PDO
$conn = new mysqli($host, $user, $pass, $db);

// ✅ Set charset
$conn->set_charset("utf8mb4");
```

### Mandatory Rules:
1. Store credentials in environment variables (never in code)
2. Use least-privilege database accounts
3. Set `utf8mb4` charset to prevent encoding attacks
4. Enable SSL for database connections
5. Regular security audits and updates

---

## Security Checklist Before Deployment

- [ ] All SQL queries use prepared statements
- [ ] All output is escaped with htmlspecialchars()
- [ ] Passwords use password_hash() and password_verify()
- [ ] CSRF tokens on all forms
- [ ] File uploads validate type and size
- [ ] No hardcoded credentials or API keys
- [ ] HTTPS enforced everywhere
- [ ] Error display disabled in production
- [ ] Session security configured
- [ ] All user inputs validated
- [ ] Security audit script passes
- [ ] Snyk scan passes (no HIGH/CRITICAL)
- [ ] SonarQube quality gate passes
- [ ] Code review completed

---

## CI/CD Security Gates

The following MUST pass before deployment:

1. **Flutter Analysis** - No errors allowed
2. **Custom Security Audit** - No CRITICAL issues
3. **Snyk Scan** - No HIGH/CRITICAL vulnerabilities  
4. **SonarQube** - Quality gate MUST pass
5. **Unit Tests** - 100% pass rate
6. **Code Coverage** - Minimum 70%
7. **Manual Code Review** - Required for sensitive changes

**If any gate fails, deployment is BLOCKED automatically.**

---

## Reporting Security Issues

If you discover a security vulnerability:

1. **DO NOT** create a public issue
2. Email: security@rlms.co.za (if available) or contact DevOps team
3. Include detailed description and steps to reproduce
4. Wait for confirmation before disclosing

---

## Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [PHP Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/PHP_Configuration_Cheat_Sheet.html)
- [Flutter Security](https://flutter.dev/docs/deployment/security)
- [SQL Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)

---

**Last Updated:** November 2026  
**Version:** 1.0  
**Status:** MANDATORY - All developers must follow
