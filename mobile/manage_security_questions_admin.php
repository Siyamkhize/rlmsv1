<?php
/**
 * Admin UI for Managing Security Questions
 * Use this to add, edit, or delete security questions
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once __DIR__ . '/connection.php';

// Handle form submissions
$message = '';
$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    
    switch ($action) {
        case 'add':
            $question_text = trim($_POST['question_text'] ?? '');
            $active = isset($_POST['active']) ? 1 : 0;
            
            if (empty($question_text)) {
                $error = 'Question text cannot be empty';
            } else {
                $stmt = $conn->prepare("INSERT INTO security_questions (question_text, active) VALUES (?, ?)");
                $stmt->bind_param('si', $question_text, $active);
                
                if ($stmt->execute()) {
                    $message = "Question added successfully (ID: {$stmt->insert_id})";
                } else {
                    $error = "Failed to add question: " . $stmt->error;
                }
            }
            break;
            
        case 'toggle':
            $id = intval($_POST['id'] ?? 0);
            $active = intval($_POST['active'] ?? 0);
            
            $stmt = $conn->prepare("UPDATE security_questions SET active = ? WHERE id = ?");
            $stmt->bind_param('ii', $active, $id);
            
            if ($stmt->execute()) {
                $message = "Question status updated";
            } else {
                $error = "Failed to update: " . $stmt->error;
            }
            break;
            
        case 'delete':
            $id = intval($_POST['id'] ?? 0);
            
            $stmt = $conn->prepare("DELETE FROM security_questions WHERE id = ?");
            $stmt->bind_param('i', $id);
            
            if ($stmt->execute()) {
                $message = "Question deleted successfully";
            } else {
                $error = "Failed to delete: " . $stmt->error;
            }
            break;
    }
}

// Fetch all questions
$result = $conn->query("SELECT id, question_text, active, created_at FROM security_questions ORDER BY id");
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Manage Security Questions</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 1200px;
            margin: 20px auto;
            padding: 0 20px;
        }
        h1 {
            color: #333;
        }
        .message {
            padding: 10px;
            margin: 10px 0;
            border-radius: 4px;
        }
        .success {
            background-color: #d4edda;
            border: 1px solid #c3e6cb;
            color: #155724;
        }
        .error {
            background-color: #f8d7da;
            border: 1px solid #f5c6cb;
            color: #721c24;
        }
        .add-form {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .add-form input[type="text"] {
            width: 70%;
            padding: 8px;
            margin-right: 10px;
        }
        .add-form button {
            padding: 8px 20px;
            background: #007bff;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
        }
        .add-form button:hover {
            background: #0056b3;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #007bff;
            color: white;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .btn {
            padding: 5px 10px;
            margin: 0 2px;
            border: none;
            border-radius: 3px;
            cursor: pointer;
            font-size: 12px;
        }
        .btn-toggle {
            background: #28a745;
            color: white;
        }
        .btn-delete {
            background: #dc3545;
            color: white;
        }
        .inactive {
            opacity: 0.5;
        }
        .status {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 12px;
            font-weight: bold;
        }
        .status-active {
            background: #d4edda;
            color: #155724;
        }
        .status-inactive {
            background: #f8d7da;
            color: #721c24;
        }
    </style>
</head>
<body>
    <h1>Manage Security Questions</h1>
    
    <?php if ($message): ?>
        <div class="message success"><?php echo htmlspecialchars($message); ?></div>
    <?php endif; ?>
    
    <?php if ($error): ?>
        <div class="message error"><?php echo htmlspecialchars($error); ?></div>
    <?php endif; ?>
    
    <div class="add-form">
        <h2>Add New Security Question</h2>
        <form method="POST">
            <input type="hidden" name="action" value="add">
            <input type="text" name="question_text" placeholder="Enter security question..." required>
            <label>
                <input type="checkbox" name="active" checked> Active
            </label>
            <button type="submit">Add Question</button>
        </form>
    </div>
    
    <h2>Existing Questions (<?php echo $result->num_rows; ?>)</h2>
    
    <?php if ($result->num_rows > 0): ?>
        <table>
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Question</th>
                    <th>Status</th>
                    <th>Created</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <?php while ($row = $result->fetch_assoc()): ?>
                    <tr class="<?php echo $row['active'] ? '' : 'inactive'; ?>">
                        <td><?php echo $row['id']; ?></td>
                        <td><?php echo htmlspecialchars($row['question_text']); ?></td>
                        <td>
                            <span class="status status-<?php echo $row['active'] ? 'active' : 'inactive'; ?>">
                                <?php echo $row['active'] ? 'Active' : 'Inactive'; ?>
                            </span>
                        </td>
                        <td><?php echo $row['created_at']; ?></td>
                        <td>
                            <form method="POST" style="display: inline;">
                                <input type="hidden" name="action" value="toggle">
                                <input type="hidden" name="id" value="<?php echo $row['id']; ?>">
                                <input type="hidden" name="active" value="<?php echo $row['active'] ? 0 : 1; ?>">
                                <button type="submit" class="btn btn-toggle">
                                    <?php echo $row['active'] ? 'Deactivate' : 'Activate'; ?>
                                </button>
                            </form>
                            
                            <form method="POST" style="display: inline;" onsubmit="return confirm('Delete this question?');">
                                <input type="hidden" name="action" value="delete">
                                <input type="hidden" name="id" value="<?php echo $row['id']; ?>">
                                <button type="submit" class="btn btn-delete">Delete</button>
                            </form>
                        </td>
                    </tr>
                <?php endwhile; ?>
            </tbody>
        </table>
    <?php else: ?>
        <p>No security questions found. Add some using the form above.</p>
    <?php endif; ?>
    
    <?php $conn->close(); ?>
</body>
</html>
