# Security Questions System - Complete Implementation Guide

## Date: September 25, 2026

## Overview
Replace ID number verification with a proper security question system where learners pre-register their answers and the system randomly verifies them during clock-in/out.

## Requirements
✅ Database tables created (SQL file ready)
✅ PHP API endpoints created (ready to deploy)
⏳ Flutter UI for setup (needs implementation)
⏳ Flutter verification during clock-in (needs update)

---

## Architecture

### Setup Phase (One-Time)
```
Learner Registration
    ↓
Select 3-5 Security Questions
    ↓
Enter Answers (hashed with SHA256)
    ↓
Save to Database
```

### Verification Phase (Every Clock-In/Out)
```
Clock-In/Out Initiated
    ↓
System Picks Random Question
    ↓
Learner Answers
    ↓
Hash Answer & Compare
    ↓
Grant/Deny Access
```

---

## Files Created

### 1. Database Schema ✅
**File:** `sql/create_security_questions_tables.sql`

**Tables:**
- `security_questions` - Predefined question bank (15 questions)
- `learner_security_answers` - Learner's answers (SHA256 hashed)
- `security_question_verification_log` - Audit trail

**Sample Questions:**
- What is your mother's maiden name?
- What is the name of your first pet?
- What is the name of the street you grew up on?
- What is your favorite color?
- In what city were you born?
- (10 more...)

### 2. PHP API ✅
**File:** `mobile/manage_security_questions.php`

**Endpoints:**
```php
?action=get_questions          // Get all available questions
?action=get_learner_questions  // Get learner's registered questions
?action=save_answers           // Save learner's answers (minimum 3)
?action=verify_answer          // Verify answer during clock-in
?action=check_setup            // Check if learner has questions set up
```

**Security Features:**
- Answers stored as SHA256 hashes (never plaintext)
- Case-insensitive comparison
- Rate limiting on verification attempts
- Audit logging

---

## Implementation Needed

### Phase 1: Setup UI (In LearnerDetailsPage or separate page)

**Location:** Add to `lib/LearnerDetailsPage.dart` OR create `lib/security_questions_setup_page.dart`

**Flow:**
```dart
1. Check if learner has security questions
2. If not, show "Setup Security Questions" button
3. User clicks → Navigate to setup page
4. Fetch available questions from API
5. User selects 3-5 questions
6. User enters answers (text fields)
7. Optionally add hints
8. Submit to API (answers get hashed server-side)
9. Success → Return to profile
```

**UI Mockup:**
```
╔══════════════════════════════════════╗
║  Setup Security Questions            ║
╠══════════════════════════════════════╣
║                                      ║
║  For added security, please answer   ║
║  at least 3 security questions.      ║
║                                      ║
║  ┌─ Question 1 ─────────────────┐   ║
║  │ [Dropdown: Select question]  │   ║
║  │ What is your mother's        │   ║
║  │ maiden name?                 │   ║
║  └──────────────────────────────┘   ║
║  Answer: [________________]          ║
║  Hint (opt): [________________]      ║
║                                      ║
║  ┌─ Question 2 ─────────────────┐   ║
║  │ [Dropdown: Select question]  │   ║
║  └──────────────────────────────┘   ║
║  Answer: [________________]          ║
║                                      ║
║  ┌─ Question 3 ─────────────────┐   ║
║  │ [Dropdown: Select question]  │   ║
║  └──────────────────────────────┘   ║
║  Answer: [________________]          ║
║                                      ║
║  [+ Add Another Question]            ║
║                                      ║
║  [Cancel]  [Save Answers]            ║
╚══════════════════════════════════════╝
```

### Phase 2: Update Verification in backup_clock_in_page.dart

**Current function:** `_verifyWithSecurityQuestions(String learnerId)`
**Line:** ~3498

**Replace with:**
```dart
Future<bool> _verifyWithSecurityQuestions(String learnerId) async {
  print('[SECURITY] Starting security questions verification');
  
  try {
    // 1. Check if learner has security questions set up
    final checkResponse = await http.get(
      Uri.parse(AppConfig.buildUrl(
        'manage_security_questions.php?action=check_setup&learner_id=$learnerId'
      )),
    ).timeout(Duration(seconds: 10));
    
    if (checkResponse.statusCode != 200) {
      throw Exception('Failed to check security setup');
    }
    
    final checkData = json.decode(checkResponse.body);
    
    if (checkData['has_security_questions'] != true) {
      // No security questions set up - prompt user to set up
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please set up security questions in your profile first'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }
    
    // 2. Get learner's registered questions
    final questionsResponse = await http.get(
      Uri.parse(AppConfig.buildUrl(
        'manage_security_questions.php?action=get_learner_questions&learner_id=$learnerId'
      )),
    ).timeout(Duration(seconds: 10));
    
    if (questionsResponse.statusCode != 200) {
      throw Exception('Failed to fetch questions');
    }
    
    final questionsData = json.decode(questionsResponse.body);
    final questions = questionsData['questions'] as List;
    
    if (questions.isEmpty) {
      throw Exception('No security questions found');
    }
    
    // 3. Pick a random question
    final random = Random();
    final randomQuestion = questions[random.nextInt(questions.length)];
    final questionId = randomQuestion['question_id'];
    final questionText = randomQuestion['question'];
    final hint = randomQuestion['hint'];
    
    // 4. Show dialog and get answer
    final TextEditingController answerController = TextEditingController();
    
    final answered = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.security, color: Colors.blue),
              SizedBox(width: 12),
              Expanded(child: Text('Security Verification')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please answer this security question to verify your identity:',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  questionText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hint != null && hint.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  'Hint: $hint',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              SizedBox(height: 16),
              TextField(
                controller: answerController,
                decoration: InputDecoration(
                  labelText: 'Your Answer',
                  border: OutlineInputBorder(),
                  hintText: 'Type your answer here',
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (answerController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text('Please enter an answer'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } else {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: Text('Submit'),
            ),
          ],
        );
      },
    );
    
    if (answered != true) {
      return false; // User cancelled
    }
    
    final answer = answerController.text.trim();
    
    // 5. Verify answer with API
    final verifyResponse = await http.post(
      Uri.parse(AppConfig.buildUrl('manage_security_questions.php?action=verify_answer')),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'learner_id': int.parse(learnerId),
        'question_id': questionId,
        'answer': answer,
        'verification_type': 'clock_in', // or 'clock_out'
      }),
    ).timeout(Duration(seconds: 10));
    
    if (verifyResponse.statusCode != 200) {
      throw Exception('Verification request failed');
    }
    
    final verifyData = json.decode(verifyResponse.body);
    
    if (verifyData['verified'] == true) {
      // Correct answer!
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Identity verified successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } else {
      // Wrong answer
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✗ Incorrect answer. Identity verification failed.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
    
  } catch (e) {
    print('[SECURITY] Error during verification: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Security verification error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  }
}
```

---

## Testing Checklist

### Setup Phase
- [ ] Deploy SQL schema to database (local + server)
- [ ] Deploy PHP endpoint to server
- [ ] Create setup UI in Flutter
- [ ] Test selecting questions
- [ ] Test saving answers
- [ ] Verify answers are hashed in database
- [ ] Test minimum 3 questions requirement

### Verification Phase
- [ ] Update `_verifyWithSecurityQuestions` in backup_clock_in_page.dart
- [ ] Test random question selection
- [ ] Test correct answer (should pass)
- [ ] Test incorrect answer (should fail)
- [ ] Test case-insensitive matching ("Blue" = "blue")
- [ ] Test whitespace handling (" Blue " = "Blue")
- [ ] Verify audit log records attempts

### Integration
- [ ] Test full clock-in flow with face failure → security questions
- [ ] Test clock-out flow with face failure → security questions
- [ ] Test offline support (optional - can be done later)

---

## Database Deployment

### Step 1: Run SQL on MySQL Server
```bash
mysql -u your_user -p your_database < sql/create_security_questions_tables.sql
```

### Step 2: Run SQL on Local SQLite
Add migration to `database_helper.dart`:
```dart
// In _onCreate or _onUpgrade
await db.execute('''
  CREATE TABLE IF NOT EXISTS security_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_text TEXT NOT NULL UNIQUE,
    active INTEGER DEFAULT 1,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  )
''');

await db.execute('''
  CREATE TABLE IF NOT EXISTS learner_security_answers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    LearnerID INTEGER NOT NULL,
    question_id INTEGER NOT NULL,
    answer_hash TEXT NOT NULL,
    answer_hint TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(LearnerID, question_id)
  )
''');

// Insert default questions...
```

---

## Security Benefits

1. **No more ID number dependency** - Works even if ID is invalid/missing
2. **Personalized verification** - Only learner knows their answers
3. **Unpredictable** - Random question each time
4. **Hashed storage** - Answers never stored in plaintext
5. **Audit trail** - All verification attempts logged
6. **Flexible** - Can add more questions easily

---

## Status

| Component | Status |
|-----------|--------|
| Database Schema | ✅ Ready |
| PHP API | ✅ Ready |
| Flutter Setup UI | ⏳ To be implemented |
| Flutter Verification | ⏳ To be updated |
| Testing | ⏳ Pending |
| Documentation | ✅ Complete |

---

## Next Steps

1. Deploy SQL to database (both MySQL and SQLite)
2. Deploy `manage_security_questions.php` to server
3. Create security questions setup UI in Flutter
4. Update `_verifyWithSecurityQuestions` function
5. Test end-to-end flow
6. Roll out to production

**Priority:** High - This replaces removed ID verification system
