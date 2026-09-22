<?php
/**
 * View Evidence Save Log
 * 
 * This displays the last 100 lines of the evidence save log file
 */

$log_file = __DIR__ . '/../logs/evidence_save.log';

?>
<!DOCTYPE html>
<html>
<head>
    <title>Evidence Save Log</title>
    <style>
        body {
            font-family: 'Courier New', monospace;
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 20px;
        }
        h1 {
            color: #4ec9b0;
        }
        .log-container {
            background: #252526;
            padding: 20px;
            border-radius: 5px;
            white-space: pre-wrap;
            word-wrap: break-word;
            max-height: 80vh;
            overflow-y: auto;
        }
        .error {
            color: #f48771;
            font-weight: bold;
        }
        .success {
            color: #4ec9b0;
            font-weight: bold;
        }
        .warning {
            color: #dcdcaa;
        }
        .info {
            color: #569cd6;
        }
        .refresh-btn {
            background: #0e639c;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 3px;
            cursor: pointer;
            margin-bottom: 20px;
        }
        .refresh-btn:hover {
            background: #1177bb;
        }
        .clear-btn {
            background: #a1260d;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 3px;
            cursor: pointer;
            margin-bottom: 20px;
            margin-left: 10px;
        }
        .clear-btn:hover {
            background: #c72e0d;
        }
    </style>
    <script>
        function refreshLog() {
            location.reload();
        }
        
        function clearLog() {
            if (confirm('Are you sure you want to clear the log file?')) {
                fetch('view_evidence_log.php?action=clear')
                    .then(() => location.reload());
            }
        }
        
        // Auto-refresh every 5 seconds
        setTimeout(refreshLog, 5000);
    </script>
</head>
<body>
    <h1>📋 Evidence Save Log</h1>
    <button class="refresh-btn" onclick="refreshLog()">🔄 Refresh Now</button>
    <button class="clear-btn" onclick="clearLog()">🗑️ Clear Log</button>
    <div class="log-container">
<?php

// Handle clear action
if (isset($_GET['action']) && $_GET['action'] === 'clear') {
    if (file_exists($log_file)) {
        file_put_contents($log_file, '');
        echo "Log cleared at " . date('Y-m-d H:i:s') . "\n";
    }
    exit;
}

// Check if log file exists
if (!file_exists($log_file)) {
    echo "No log file found yet. The log will be created when the first evidence save request is made.\n";
    echo "Log file path: $log_file\n";
} else {
    // Get file size
    $file_size = filesize($log_file);
    echo "Log file size: " . number_format($file_size) . " bytes\n";
    echo "Last modified: " . date('Y-m-d H:i:s', filemtime($log_file)) . "\n";
    echo str_repeat('=', 80) . "\n\n";
    
    // Read last 100 lines
    $lines = file($log_file);
    $total_lines = count($lines);
    
    echo "Showing last 100 lines (total: $total_lines lines)\n";
    echo str_repeat('=', 80) . "\n\n";
    
    $start = max(0, $total_lines - 100);
    $recent_lines = array_slice($lines, $start);
    
    foreach ($recent_lines as $line) {
        // Colorize output
        $line = htmlspecialchars($line);
        
        if (strpos($line, 'ERROR') !== false || strpos($line, 'EXCEPTION') !== false) {
            echo '<span class="error">' . $line . '</span>';
        } elseif (strpos($line, 'SUCCESS') !== false) {
            echo '<span class="success">' . $line . '</span>';
        } elseif (strpos($line, 'WARNING') !== false || strpos($line, 'NULL') !== false) {
            echo '<span class="warning">' . $line . '</span>';
        } elseif (strpos($line, 'NEW REQUEST') !== false || strpos($line, 'END REQUEST') !== false) {
            echo '<span class="info">' . $line . '</span>';
        } else {
            echo $line;
        }
    }
}

?>
    </div>
    <p style="color: #888; margin-top: 20px;">Auto-refreshing every 5 seconds...</p>
</body>
</html>
