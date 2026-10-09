<?php
header('Content-Type: text/html; charset=UTF-8');
require_once 'config.php';

// Database connection
$conn = new mysqli($servername, $username, $password, $dbname);

if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}

// Get table parameter
$table = $_GET['table'] ?? 'learnerdetails';
$limit = $_GET['limit'] ?? 50;
$classID = $_GET['classID'] ?? '';

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Database Browser - Last Insert/Update Check</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        .table-container { max-height: 600px; overflow-y: auto; }
        .timestamp { color: #28a745; font-weight: bold; }
        .old-data { color: #dc3545; }
        .recent-data { color: #28a745; }
    </style>
</head>
<body>
    <div class="container mt-4">
        <h1>📊 Database Browser - Last Insert/Update Check</h1>
        <p class="text-muted">Check when data was last inserted or updated (not deleted)</p>

        <!-- Table Selection -->
        <div class="row mb-4">
            <div class="col-md-4">
                <label class="form-label">Select Table:</label>
                <select class="form-select" onchange="location.href='?table=' + this.value + '&classID=<?php echo $classID; ?>'">
                    <option value="learnerdetails" <?php echo $table === 'learnerdetails' ? 'selected' : ''; ?>>learnerdetails</option>
                    <option value="learner_clocking" <?php echo $table === 'learner_clocking' ? 'selected' : ''; ?>>learner_clocking</option>
                    <option value="attendance" <?php echo $table === 'attendance' ? 'selected' : ''; ?>>attendance</option>
                    <option value="facilitator" <?php echo $table === 'facilitator' ? 'selected' : ''; ?>>facilitator</option>
                    <option value="facilitator_clocking" <?php echo $table === 'facilitator_clocking' ? 'selected' : ''; ?>>facilitator_clocking</option>
                    <option value="classes" <?php echo $table === 'classes' ? 'selected' : ''; ?>>classes</option>
                    <option value="sites" <?php echo $table === 'sites' ? 'selected' : ''; ?>>sites</option>
                    <option value="project" <?php echo $table === 'project' ? 'selected' : ''; ?>>project</option>
                </select>
            </div>
            <div class="col-md-3">
                <label class="form-label">Class ID Filter:</label>
                <input type="text" class="form-control" value="<?php echo htmlspecialchars($classID); ?>" 
                       onchange="location.href='?table=<?php echo $table; ?>&classID=' + this.value">
            </div>
            <div class="col-md-2">
                <label class="form-label">Limit:</label>
                <select class="form-select" onchange="location.href='?table=<?php echo $table; ?>&limit=' + this.value + '&classID=<?php echo $classID; ?>'">
                    <option value="50" <?php echo $limit == 50 ? 'selected' : ''; ?>>50</option>
                    <option value="100" <?php echo $limit == 100 ? 'selected' : ''; ?>>100</option>
                    <option value="200" <?php echo $limit == 200 ? 'selected' : ''; ?>>200</option>
                    <option value="500" <?php echo $limit == 500 ? 'selected' : ''; ?>>500</option>
                </select>
            </div>
            <div class="col-md-3 d-flex align-items-end">
                <button class="btn btn-success" onclick="location.reload()">🔄 Refresh</button>
            </div>
        </div>

        <?php
        // Get table info and recent data
        try {
            // Get table structure
            $structure = $conn->query("DESCRIBE $table");
            $columns = [];
            $hasTimestamp = false;
            $timestampColumn = '';
            
            while ($row = $structure->fetch_assoc()) {
                $columns[] = $row['Field'];
                if (in_array(strtolower($row['Field']), ['created_at', 'updated_at', 'timestamp', 'date_created', 'last_updated'])) {
                    $hasTimestamp = true;
                    $timestampColumn = $row['Field'];
                }
            }

            // Build query with class filter if applicable
            $whereClause = '';
            $params = [];
            
            if (!empty($classID) && in_array('classID', $columns)) {
                $whereClause = "WHERE classID = ?";
                $params[] = $classID;
            }
            
            // Order by timestamp if available, otherwise by primary key
            $orderBy = $hasTimestamp ? "ORDER BY $timestampColumn DESC" : 
                      (in_array('id', $columns) ? "ORDER BY id DESC" : 
                       (in_array('LearnerID', $columns) ? "ORDER BY LearnerID DESC" : ""));

            $sql = "SELECT * FROM $table $whereClause $orderBy LIMIT $limit";
            
            $stmt = $conn->prepare($sql);
            if (!empty($params)) {
                $stmt->bind_param(str_repeat('s', count($params)), ...$params);
            }
            $stmt->execute();
            $result = $stmt->get_result();

            // Get total count
            $countSql = "SELECT COUNT(*) as total FROM $table $whereClause";
            $countStmt = $conn->prepare($countSql);
            if (!empty($params)) {
                $countStmt->bind_param(str_repeat('s', count($params)), ...$params);
            }
            $countStmt->execute();
            $countResult = $countStmt->get_result();
            $totalCount = $countResult->fetch_assoc()['total'];

            echo "<div class='alert alert-info'>";
            echo "<h5>📋 Table: <strong>$table</strong></h5>";
            echo "<p>Total Records: <strong>$totalCount</strong> | Showing: <strong>$limit</strong></p>";
            if (!empty($classID)) {
                echo "<p>Filtered by Class ID: <strong>$classID</strong></p>";
            }
            if ($hasTimestamp) {
                echo "<p>Timestamp Column: <strong>$timestampColumn</strong></p>";
            }
            echo "</div>";

            if ($result->num_rows > 0) {
                echo "<div class='table-container'>";
                echo "<table class='table table-striped table-hover'>";
                echo "<thead class='table-dark'><tr>";
                
                $row = $result->fetch_assoc();
                foreach ($row as $key => $value) {
                    echo "<th>" . htmlspecialchars($key) . "</th>";
                }
                echo "</tr></thead><tbody>";

                // Reset result pointer and display data
                $result->data_seek(0);
                while ($row = $result->fetch_assoc()) {
                    echo "<tr>";
                    foreach ($row as $key => $value) {
                        $class = '';
                        
                        // Highlight timestamps and check if data is recent
                        if (in_array(strtolower($key), ['created_at', 'updated_at', 'timestamp', 'date_created', 'last_updated']) && !empty($value)) {
                            $timestamp = strtotime($value);
                            $now = time();
                            $daysDiff = ($now - $timestamp) / (60 * 60 * 24);
                            
                            if ($daysDiff <= 1) {
                                $class = 'recent-data timestamp';
                            } elseif ($daysDiff <= 7) {
                                $class = 'timestamp';
                            } else {
                                $class = 'old-data';
                            }
                        }
                        
                        // Format the value
                        if (is_null($value)) {
                            $displayValue = '<span class="text-muted">NULL</span>';
                        } elseif (strlen($value) > 50) {
                            $displayValue = htmlspecialchars(substr($value, 0, 50)) . '...';
                        } else {
                            $displayValue = htmlspecialchars($value);
                        }
                        
                        echo "<td class='$class'>$displayValue</td>";
                    }
                    echo "</tr>";
                }
                echo "</tbody></table>";
                echo "</div>";

                // Show last update info if timestamp column exists
                if ($hasTimestamp) {
                    $lastUpdateSql = "SELECT MAX($timestampColumn) as last_update FROM $table $whereClause";
                    $lastUpdateStmt = $conn->prepare($lastUpdateSql);
                    if (!empty($params)) {
                        $lastUpdateStmt->bind_param(str_repeat('s', count($params)), ...$params);
                    }
                    $lastUpdateStmt->execute();
                    $lastUpdateResult = $lastUpdateStmt->get_result();
                    $lastUpdate = $lastUpdateResult->fetch_assoc()['last_update'];

                    if ($lastUpdate) {
                        $timestamp = strtotime($lastUpdate);
                        $now = time();
                        $timeDiff = $now - $timestamp;
                        $daysDiff = $timeDiff / (60 * 60 * 24);
                        
                        $color = $daysDiff <= 1 ? 'success' : ($daysDiff <= 7 ? 'warning' : 'danger');
                        
                        echo "<div class='alert alert-$color'>";
                        echo "<h5>⏰ Last Update Information</h5>";
                        echo "<p><strong>Last Update:</strong> $lastUpdate</p>";
                        echo "<p><strong>Time Ago:</strong> " . formatTimeAgo($timeDiff) . "</p>";
                        echo "</div>";
                    }
                }

            } else {
                echo "<div class='alert alert-warning'>No records found in table '$table'";
                if (!empty($classID)) {
                    echo " for Class ID '$classID'";
                }
                echo "</div>";
            }

        } catch (Exception $e) {
            echo "<div class='alert alert-danger'>Error: " . htmlspecialchars($e->getMessage()) . "</div>";
        }

        function formatTimeAgo($seconds) {
            if ($seconds < 60) return "Just now";
            if ($seconds < 3600) return floor($seconds/60) . " minutes ago";
            if ($seconds < 86400) return floor($seconds/3600) . " hours ago";
            return floor($seconds/86400) . " days ago";
        }
        ?>

        <!-- Quick Stats -->
        <div class="row mt-4">
            <div class="col-12">
                <h5>🔍 Quick Database Stats</h5>
                <div class="row">
                    <?php
                    $quickTables = ['learnerdetails', 'learner_clocking', 'attendance', 'facilitator_clocking'];
                    foreach ($quickTables as $qtable) {
                        try {
                            $count = $conn->query("SELECT COUNT(*) as count FROM $qtable")->fetch_assoc()['count'];
                            echo "<div class='col-md-3'>";
                            echo "<div class='card'>";
                            echo "<div class='card-body text-center'>";
                            echo "<h6>$qtable</h6>";
                            echo "<h4 class='text-primary'>$count</h4>";
                            echo "<a href='?table=$qtable' class='btn btn-sm btn-outline-primary'>Browse</a>";
                            echo "</div></div></div>";
                        } catch (Exception $e) {
                            // Table might not exist, skip
                        }
                    }
                    ?>
                </div>
            </div>
        </div>

        <div class="mt-4">
            <small class="text-muted">
                🟢 Recent (≤1 day) | 🟡 Week old | 🔴 Older data<br>
                This tool helps verify that your local database has recent data and hasn't been accidentally cleared.
            </small>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>

<?php $conn->close(); ?>