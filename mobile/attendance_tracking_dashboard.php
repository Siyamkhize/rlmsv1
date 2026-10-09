<?php
header('Content-Type: text/html; charset=UTF-8');
header('Cache-Control: no-cache, must-revalidate');

// Include database configuration
require_once 'config.php';

// Enable error reporting for debugging
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Set timezone
date_default_timezone_set('Africa/Johannesburg');

// Database connection
$conn = new mysqli($servername, $username, $password, $dbname);

if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}

// Get filter parameters
$filter_type = $_GET['filter_type'] ?? 'day';
$date_filter = $_GET['date_filter'] ?? date('Y-m-d');
$project_id = $_GET['project_id'] ?? '';
$pathway_id = $_GET['pathway_id'] ?? '';
$site_id = $_GET['site_id'] ?? '';
$class_id = $_GET['class_id'] ?? '';
$user_type = $_GET['user_type'] ?? 'all'; // all, learners, facilitators

// Get dropdown data for filters
function getProjects($conn) {
    $sql = "SELECT DISTINCT projectID, projectName FROM project ORDER BY projectName";
    $result = $conn->query($sql);
    $projects = [];
    if ($result && $result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            $projects[] = $row;
        }
    }
    return $projects;
}
function getPathways($conn) {
    $sql = "SELECT DISTINCT learningPathwayId, learningPathwayName FROM learningpathway ORDER BY learningPathwayName";
    $result = $conn->query($sql);
    $pathways = [];
    if ($result && $result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            $pathways[] = $row;
        }
    }
    return $pathways;
}

function getSites($conn) {
    $sql = "SELECT DISTINCT siteID, siteName FROM sites ORDER BY siteName";
    $result = $conn->query($sql);
    $sites = [];
    if ($result && $result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            $sites[] = $row;
        }
    }
    return $sites;
}

function getClasses($conn) {
    $sql = "SELECT DISTINCT classID, className FROM classes ORDER BY className";
    $result = $conn->query($sql);
    $classes = [];
    if ($result && $result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            $classes[] = $row;
        }
    }
    return $classes;
}
// Get date range based on filter type
function getDateRange($filter_type, $date_filter) {
    $start_date = $date_filter;
    $end_date = $date_filter;
    
    switch ($filter_type) {
        case 'week':
            $start_date = date('Y-m-d', strtotime('monday this week', strtotime($date_filter)));
            $end_date = date('Y-m-d', strtotime('sunday this week', strtotime($date_filter)));
            break;
        case 'month':
            $start_date = date('Y-m-01', strtotime($date_filter));
            $end_date = date('Y-m-t', strtotime($date_filter));
            break;
        case 'day':
        default:
            $start_date = $end_date = $date_filter;
            break;
    }
    
    return [$start_date, $end_date];
}

// Get learner clocking data with manual evidence
function getLearnerClockingData($conn, $start_date, $end_date, $project_id, $pathway_id, $site_id, $class_id) {
    $where_conditions = [];
    $params = [];
    $param_types = '';
    
    // Date range
    $where_conditions[] = "a.clock_in_time >= ? AND a.clock_in_time <= ?";
    $params[] = $start_date . ' 00:00:00';
    $params[] = $end_date . ' 23:59:59';
    $param_types .= 'ss';
    
    // Filters
    if (!empty($project_id)) {
        $where_conditions[] = "ld.projectID = ?";
        $params[] = $project_id;
        $param_types .= 's';
    }
    
    if (!empty($pathway_id)) {
        $where_conditions[] = "ld.learningPathwayId = ?";
        $params[] = $pathway_id;
        $param_types .= 's';
    }
    
    if (!empty($site_id)) {
        $where_conditions[] = "ld.siteID = ?";
        $params[] = $site_id;
        $param_types .= 's';
    }
    
    if (!empty($class_id)) {
        $where_conditions[] = "ld.classID = ?";
        $params[] = $class_id;
        $param_types .= 's';
    }
    $where_clause = !empty($where_conditions) ? 'WHERE ' . implode(' AND ', $where_conditions) : '';
    
    $sql = "SELECT 
                ld.learnerID,
                ld.firstName,
                ld.lastName,
                ld.idNumber,
                ld.classID,
                c.className,
                p.projectName,
                lp.learningPathwayName,
                s.siteName,
                a.clock_in_time,
                a.clock_out_time,
                a.contact_time,
                CASE 
                    WHEN mce.id IS NOT NULL THEN 'Manual Evidence'
                    ELSE 'Standard Clocking'
                END as clocking_method,
                mce.evidence_type,
                mce.created_at as evidence_created
            FROM attendance a
            INNER JOIN learnerdetails ld ON a.learnerID = ld.learnerID
            LEFT JOIN classes c ON ld.classID = c.classID
            LEFT JOIN project p ON ld.projectID = p.projectID
            LEFT JOIN learningpathway lp ON ld.learningPathwayId = lp.learningPathwayId
            LEFT JOIN sites s ON ld.siteID = s.siteID
            LEFT JOIN manual_clocking_evidence mce ON a.learnerID = mce.learner_id 
                AND DATE(a.clock_in_time) = DATE(mce.created_at)
            $where_clause
            ORDER BY a.clock_in_time DESC";
    
    $stmt = $conn->prepare($sql);
    if (!empty($params)) {
        $stmt->bind_param($param_types, ...$params);
    }
    
    $stmt->execute();
    $result = $stmt->get_result();
    
    $data = [];
    while ($row = $result->fetch_assoc()) {
        $data[] = $row;
    }
    
    return $data;
}
// Get facilitator clocking data
function getFacilitatorClockingData($conn, $start_date, $end_date, $project_id, $pathway_id, $site_id, $class_id) {
    $where_conditions = [];
    $params = [];
    $param_types = '';
    
    // Date range
    $where_conditions[] = "fc.clock_date >= ? AND fc.clock_date <= ?";
    $params[] = $start_date;
    $params[] = $end_date;
    $param_types .= 'ss';
    
    // Filters (facilitators are linked to classes, which are linked to projects/pathways/sites)
    if (!empty($project_id)) {
        $where_conditions[] = "c.projectID = ?";
        $params[] = $project_id;
        $param_types .= 's';
    }
    
    if (!empty($pathway_id)) {
        $where_conditions[] = "c.learningPathwayId = ?";
        $params[] = $pathway_id;
        $param_types .= 's';
    }
    
    if (!empty($site_id)) {
        $where_conditions[] = "c.siteID = ?";
        $params[] = $site_id;
        $param_types .= 's';
    }
    
    if (!empty($class_id)) {
        $where_conditions[] = "f.classID = ?";
        $params[] = $class_id;
        $param_types .= 's';
    }
    
    $where_clause = !empty($where_conditions) ? 'WHERE ' . implode(' AND ', $where_conditions) : '';
    
    $sql = "SELECT 
                f.facilitator_id,
                f.firstName,
                f.lastName,
                f.email,
                f.classID,
                c.className,
                p.projectName,
                lp.learningPathwayName,
                s.siteName,
                fc.clock_date,
                fc.clock_in_time,
                fc.clock_out_time,
                fc.contact_time,
                CASE 
                    WHEN fce.id IS NOT NULL THEN 'Face Recognition'
                    ELSE 'Standard Method'
                END as clocking_method,
                fce.clock_in_verification_method,
                fce.clock_out_verification_method
            FROM facilitator_clocking fc
            INNER JOIN facilitator f ON fc.facilitator_id = f.facilitator_id
            LEFT JOIN classes c ON f.classID = c.classID
            LEFT JOIN project p ON c.projectID = p.projectID
            LEFT JOIN learningpathway lp ON c.learningPathwayId = lp.learningPathwayId
            LEFT JOIN sites s ON c.siteID = s.siteID
            LEFT JOIN facilitator_clocking_evidence fce ON fc.facilitator_id = fce.facilitator_id 
                AND fc.clock_date = fce.clock_date
            $where_clause
            ORDER BY fc.clock_date DESC, fc.clock_in_time DESC";
    
    $stmt = $conn->prepare($sql);
    if (!empty($params)) {
        $stmt->bind_param($param_types, ...$params);
    }
    
    $stmt->execute();
    $result = $stmt->get_result();
    
    $data = [];
    while ($row = $result->fetch_assoc()) {
        $data[] = $row;
    }
    
    return $data;
}
// Get data based on filters
$projects = getProjects($conn);
$pathways = getPathways($conn);
$sites = getSites($conn);
$classes = getClasses($conn);

[$start_date, $end_date] = getDateRange($filter_type, $date_filter);

$learner_data = [];
$facilitator_data = [];

if ($user_type === 'all' || $user_type === 'learners') {
    $learner_data = getLearnerClockingData($conn, $start_date, $end_date, $project_id, $pathway_id, $site_id, $class_id);
}

if ($user_type === 'all' || $user_type === 'facilitators') {
    $facilitator_data = getFacilitatorClockingData($conn, $start_date, $end_date, $project_id, $pathway_id, $site_id, $class_id);
}

// Get summary statistics
$total_learners_clocked = count($learner_data);
$total_facilitators_clocked = count($facilitator_data);
$manual_evidence_count = count(array_filter($learner_data, function($row) {
    return $row['clocking_method'] === 'Manual Evidence';
}));
$face_clocking_count = count(array_filter($facilitator_data, function($row) {
    return $row['clocking_method'] === 'Face Recognition';
}));

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Attendance Tracking Dashboard</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <link href="https://cdn.datatables.net/1.13.4/css/dataTables.bootstrap5.min.css" rel="stylesheet">
    <style>
        .dashboard-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem 0;
            margin-bottom: 2rem;
        }
        
        .stat-card {
            border: none;
            border-radius: 15px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            transition: transform 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
        }
        
        .stat-icon {
            font-size: 2.5rem;
            opacity: 0.8;
        }
        
        .filter-section {
            background: #f8f9fa;
            border-radius: 15px;
            padding: 1.5rem;
            margin-bottom: 2rem;
        }
        
        .table-container {
            background: white;
            border-radius: 15px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
            overflow: hidden;
        }
        
        .nav-pills .nav-link.active {
            background: #667eea;
        }
        
        .badge-manual {
            background: #ff6b6b;
        }
        
        .badge-face {
            background: #51cf66;
        }
        
        .badge-standard {
            background: #748ffc;
        }
    </style>
</head>
<body>
    <div class="dashboard-header">
        <div class="container">
            <div class="row align-items-center">
                <div class="col">
                    <h1><i class="fas fa-chart-line me-3"></i>Attendance Tracking Dashboard</h1>
                    <p class="mb-0">Monitor learner and facilitator attendance with advanced filtering</p>
                </div>
                <div class="col-auto">
                    <div class="text-end">
                        <div class="fs-5">
                            <?php 
                            echo ucfirst($filter_type) . ': ';
                            if ($filter_type === 'day') {
                                echo date('M d, Y', strtotime($date_filter));
                            } elseif ($filter_type === 'week') {
                                echo date('M d', strtotime($start_date)) . ' - ' . date('M d, Y', strtotime($end_date));
                            } elseif ($filter_type === 'month') {
                                echo date('F Y', strtotime($date_filter));
                            }
                            ?>
                        </div>
                        <small>Last updated: <?php echo date('H:i:s'); ?></small>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="container">
        <!-- Statistics Cards -->
        <div class="row mb-4">
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-primary">
                    <div class="card-body text-center">
                        <i class="fas fa-users stat-icon text-primary"></i>
                        <h3 class="mt-2"><?php echo $total_learners_clocked; ?></h3>
                        <p class="text-muted mb-0">Learners Clocked</p>
                    </div>
                </div>
            </div>
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-success">
                    <div class="card-body text-center">
                        <i class="fas fa-chalkboard-teacher stat-icon text-success"></i>
                        <h3 class="mt-2"><?php echo $total_facilitators_clocked; ?></h3>
                        <p class="text-muted mb-0">Facilitators Clocked</p>
                    </div>
                </div>
            </div>
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-warning">
                    <div class="card-body text-center">
                        <i class="fas fa-camera stat-icon text-warning"></i>
                        <h3 class="mt-2"><?php echo $manual_evidence_count; ?></h3>
                        <p class="text-muted mb-0">Manual Evidence</p>
                    </div>
                </div>
            </div>
            <div class="col-md-3 mb-3">
                <div class="card stat-card border-info">
                    <div class="card-body text-center">
                        <i class="fas fa-user-check stat-icon text-info"></i>
                        <h3 class="mt-2"><?php echo $face_clocking_count; ?></h3>
                        <p class="text-muted mb-0">Face Recognition</p>
                    </div>
                </div>
            </div>
        </div>
        <!-- Filters -->
        <div class="filter-section">
            <form method="GET" class="row g-3">
                <div class="col-md-2">
                    <label class="form-label">Time Period</label>
                    <select name="filter_type" class="form-select" onchange="this.form.submit()">
                        <option value="day" <?php echo $filter_type === 'day' ? 'selected' : ''; ?>>Daily</option>
                        <option value="week" <?php echo $filter_type === 'week' ? 'selected' : ''; ?>>Weekly</option>
                        <option value="month" <?php echo $filter_type === 'month' ? 'selected' : ''; ?>>Monthly</option>
                    </select>
                </div>
                
                <div class="col-md-2">
                    <label class="form-label">Date</label>
                    <input type="date" name="date_filter" class="form-select" value="<?php echo $date_filter; ?>" onchange="this.form.submit()">
                </div>
                
                <div class="col-md-2">
                    <label class="form-label">User Type</label>
                    <select name="user_type" class="form-select" onchange="this.form.submit()">
                        <option value="all" <?php echo $user_type === 'all' ? 'selected' : ''; ?>>All Users</option>
                        <option value="learners" <?php echo $user_type === 'learners' ? 'selected' : ''; ?>>Learners Only</option>
                        <option value="facilitators" <?php echo $user_type === 'facilitators' ? 'selected' : ''; ?>>Facilitators Only</option>
                    </select>
                </div>
                
                <div class="col-md-2">
                    <label class="form-label">Project</label>
                    <select name="project_id" class="form-select" onchange="this.form.submit()">
                        <option value="">All Projects</option>
                        <?php foreach ($projects as $project): ?>
                            <option value="<?php echo htmlspecialchars($project['projectID']); ?>" 
                                    <?php echo $project_id == $project['projectID'] ? 'selected' : ''; ?>>
                                <?php echo htmlspecialchars($project['projectName']); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                
                <div class="col-md-2">
                    <label class="form-label">Learning Pathway</label>
                    <select name="pathway_id" class="form-select" onchange="this.form.submit()">
                        <option value="">All Pathways</option>
                        <?php foreach ($pathways as $pathway): ?>
                            <option value="<?php echo htmlspecialchars($pathway['learningPathwayId']); ?>" 
                                    <?php echo $pathway_id == $pathway['learningPathwayId'] ? 'selected' : ''; ?>>
                                <?php echo htmlspecialchars($pathway['learningPathwayName']); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                
                <div class="col-md-2">
                    <label class="form-label">Site</label>
                    <select name="site_id" class="form-select" onchange="this.form.submit()">
                        <option value="">All Sites</option>
                        <?php foreach ($sites as $site): ?>
                            <option value="<?php echo htmlspecialchars($site['siteID']); ?>" 
                                    <?php echo $site_id == $site['siteID'] ? 'selected' : ''; ?>>
                                <?php echo htmlspecialchars($site['siteName']); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                
                <div class="col-md-2">
                    <label class="form-label">Class</label>
                    <select name="class_id" class="form-select" onchange="this.form.submit()">
                        <option value="">All Classes</option>
                        <?php foreach ($classes as $class): ?>
                            <option value="<?php echo htmlspecialchars($class['classID']); ?>" 
                                    <?php echo $class_id == $class['classID'] ? 'selected' : ''; ?>>
                                <?php echo htmlspecialchars($class['className']); ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>
                
                <div class="col-md-4 d-flex align-items-end">
                    <button type="button" class="btn btn-secondary me-2" onclick="clearFilters()">
                        <i class="fas fa-times"></i> Clear Filters
                    </button>
                    <button type="button" class="btn btn-success" onclick="exportData()">
                        <i class="fas fa-download"></i> Export
                    </button>
                </div>
            </form>
        </div>
        <!-- Tabs for Learners and Facilitators -->
        <ul class="nav nav-pills mb-3" id="attendanceTabs" role="tablist">
            <?php if ($user_type === 'all' || $user_type === 'learners'): ?>
            <li class="nav-item" role="presentation">
                <button class="nav-link <?php echo ($user_type !== 'facilitators') ? 'active' : ''; ?>" 
                        id="learners-tab" data-bs-toggle="pill" data-bs-target="#learners" 
                        type="button" role="tab">
                    <i class="fas fa-users me-2"></i>Learners (<?php echo $total_learners_clocked; ?>)
                </button>
            </li>
            <?php endif; ?>
            
            <?php if ($user_type === 'all' || $user_type === 'facilitators'): ?>
            <li class="nav-item" role="presentation">
                <button class="nav-link <?php echo ($user_type === 'facilitators') ? 'active' : ''; ?>" 
                        id="facilitators-tab" data-bs-toggle="pill" data-bs-target="#facilitators" 
                        type="button" role="tab">
                    <i class="fas fa-chalkboard-teacher me-2"></i>Facilitators (<?php echo $total_facilitators_clocked; ?>)
                </button>
            </li>
            <?php endif; ?>
        </ul>
        
        <div class="tab-content" id="attendanceTabContent">
            <!-- Learners Tab -->
            <?php if ($user_type === 'all' || $user_type === 'learners'): ?>
            <div class="tab-pane fade <?php echo ($user_type !== 'facilitators') ? 'show active' : ''; ?>" 
                 id="learners" role="tabpanel">
                <div class="table-container">
                    <div class="p-3 border-bottom">
                        <h5 class="mb-0"><i class="fas fa-users text-primary me-2"></i>Learner Attendance</h5>
                    </div>
                    <div class="table-responsive">
                        <table id="learnersTable" class="table table-hover mb-0">
                            <thead class="table-dark">
                                <tr>
                                    <th>ID</th>
                                    <th>Name</th>
                                    <th>ID Number</th>
                                    <th>Class</th>
                                    <th>Project</th>
                                    <th>Pathway</th>
                                    <th>Site</th>
                                    <th>Clock In</th>
                                    <th>Clock Out</th>
                                    <th>Method</th>
                                    <th>Evidence</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach ($learner_data as $row): ?>
                                <tr>
                                    <td><strong><?php echo htmlspecialchars($row['learnerID']); ?></strong></td>
                                    <td><?php echo htmlspecialchars($row['firstName'] . ' ' . $row['lastName']); ?></td>
                                    <td><?php echo htmlspecialchars($row['idNumber']); ?></td>
                                    <td><?php echo htmlspecialchars($row['className'] ?? '-'); ?></td>
                                    <td><?php echo htmlspecialchars($row['projectName'] ?? '-'); ?></td>
                                    <td><?php echo htmlspecialchars($row['learningPathwayName'] ?? '-'); ?></td>
                                    <td><?php echo htmlspecialchars($row['siteName'] ?? '-'); ?></td>
                                    <td>
                                        <?php if ($row['clock_in_time']): ?>
                                            <span class="text-success">
                                                <i class="fas fa-clock me-1"></i>
                                                <?php echo date('H:i', strtotime($row['clock_in_time'])); ?>
                                            </span>
                                        <?php else: ?>
                                            <span class="text-muted">-</span>
                                        <?php endif; ?>
                                    </td>
                                    <td>
                                        <?php if ($row['clock_out_time']): ?>
                                            <span class="text-danger">
                                                <i class="fas fa-clock me-1"></i>
                                                <?php echo date('H:i', strtotime($row['clock_out_time'])); ?>
                                            </span>
                                        <?php else: ?>
                                            <span class="text-muted">-</span>
                                        <?php endif; ?>
                                    </td>
                                    <td>
                                        <?php if ($row['clocking_method'] === 'Manual Evidence'): ?>
                                            <span class="badge badge-manual">Manual</span>
                                        <?php else: ?>
                                            <span class="badge badge-standard">Standard</span>
                                        <?php endif; ?>
                                    </td>
                                    <td>
                                        <?php if ($row['evidence_type']): ?>
                                            <span class="badge bg-info"><?php echo htmlspecialchars($row['evidence_type']); ?></span>
                                        <?php else: ?>
                                            <span class="text-muted">-</span>
                                        <?php endif; ?>
                                    </td>
                                </tr>
                                <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
            <?php endif; ?>
            <!-- Facilitators Tab -->
            <?php if ($user_type === 'all' || $user_type === 'facilitators'): ?>
            <div class="tab-pane fade <?php echo ($user_type === 'facilitators') ? 'show active' : ''; ?>" 
                 id="facilitators" role="tabpanel">
                <div class="table-container">
                    <div class="p-3 border-bottom">
                        <h5 class="mb-0"><i class="fas fa-chalkboard-teacher text-success me-2"></i>Facilitator Attendance</h5>
                    </div>
                    <div class="table-responsive">
                        <table id="facilitatorsTable" class="table table-hover mb-0">
                            <thead class="table-dark">
                                <tr>
                                    <th>ID</th>
                                    <th>Name</th>
                                    <th>Email</th>
                                    <th>Class</th>
                                    <th>Project</th>
                                    <th>Pathway</th>
                                    <th>Site</th>
                                    <th>Date</th>
                                    <th>Clock In</th>
                                    <th>Clock Out</th>
                                    <th>Method</th>
                                    <th>Verification</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach ($facilitator_data as $row): ?>
                                <tr>
                                    <td><strong><?php echo htmlspecialchars($row['facilitator_id']); ?></strong></td>
                                    <td><?php echo htmlspecialchars($row['firstName'] . ' ' . $row['lastName']); ?></td>
                                    <td><?php echo htmlspecialchars($row['email']); ?></td>
                                    <td><?php echo htmlspecialchars($row['className'] ?? '-'); ?></td>
                                    <td><?php echo htmlspecialchars($row['projectName'] ?? '-'); ?></td>
                                    <td><?php echo htmlspecialchars($row['learningPathwayName'] ?? '-'); ?></td>
                                    <td><?php echo htmlspecialchars($row['siteName'] ?? '-'); ?></td>
                                    <td>
                                        <span class="text-primary">
                                            <i class="fas fa-calendar me-1"></i>
                                            <?php echo date('M d', strtotime($row['clock_date'])); ?>
                                        </span>
                                    </td>
                                    <td>
                                        <?php if ($row['clock_in_time']): ?>
                                            <span class="text-success">
                                                <i class="fas fa-clock me-1"></i>
                                                <?php echo date('H:i', strtotime($row['clock_in_time'])); ?>
                                            </span>
                                        <?php else: ?>
                                            <span class="text-muted">-</span>
                                        <?php endif; ?>
                                    </td>
                                    <td>
                                        <?php if ($row['clock_out_time']): ?>
                                            <span class="text-danger">
                                                <i class="fas fa-clock me-1"></i>
                                                <?php echo date('H:i', strtotime($row['clock_out_time'])); ?>
                                            </span>
                                        <?php else: ?>
                                            <span class="text-muted">-</span>
                                        <?php endif; ?>
                                    </td>
                                    <td>
                                        <?php if ($row['clocking_method'] === 'Face Recognition'): ?>
                                            <span class="badge badge-face">Face</span>
                                        <?php else: ?>
                                            <span class="badge badge-standard">Standard</span>
                                        <?php endif; ?>
                                    </td>
                                    <td>
                                        <div class="d-flex flex-column">
                                            <?php if ($row['clock_in_verification_method']): ?>
                                                <small class="text-success">In: <?php echo htmlspecialchars($row['clock_in_verification_method']); ?></small>
                                            <?php endif; ?>
                                            <?php if ($row['clock_out_verification_method']): ?>
                                                <small class="text-danger">Out: <?php echo htmlspecialchars($row['clock_out_verification_method']); ?></small>
                                            <?php endif; ?>
                                        </div>
                                    </td>
                                </tr>
                                <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
            <?php endif; ?>
        </div>
    </div>

    <!-- Scripts -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.4/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.4/js/dataTables.bootstrap5.min.js"></script>
    <script>
        $(document).ready(function() {
            // Initialize DataTables
            $('#learnersTable, #facilitatorsTable').DataTable({
                responsive: true,
                pageLength: 25,
                order: [[7, 'desc']], // Sort by clock in time descending
                columnDefs: [
                    { targets: [9, 10], orderable: false } // Method and Evidence columns
                ],
                language: {
                    search: "Search records:",
                    lengthMenu: "Show _MENU_ records per page",
                    info: "Showing _START_ to _END_ of _TOTAL_ records",
                    paginate: {
                        previous: "<i class='fas fa-chevron-left'></i>",
                        next: "<i class='fas fa-chevron-right'></i>"
                    }
                }
            });
            
            // Auto-refresh every 30 seconds
            setInterval(function() {
                location.reload();
            }, 30000);
        });
        
        function clearFilters() {
            const url = new URL(window.location);
            url.searchParams.delete('project_id');
            url.searchParams.delete('pathway_id');
            url.searchParams.delete('site_id');
            url.searchParams.delete('class_id');
            url.searchParams.set('user_type', 'all');
            window.location.href = url.toString();
        }
        
        function exportData() {
            const params = new URLSearchParams(window.location.search);
            params.set('export', 'csv');
            window.open('?' + params.toString(), '_blank');
        }
    </script>

</body>
</html>

<?php
// Handle CSV export
if (isset($_GET['export']) && $_GET['export'] === 'csv') {
    header('Content-Type: text/csv');
    header('Content-Disposition: attachment; filename="attendance_report_' . date('Y-m-d_H-i-s') . '.csv"');
    
    $output = fopen('php://output', 'w');
    
    // Learners data
    if (!empty($learner_data)) {
        fputcsv($output, ['Type', 'ID', 'Name', 'ID Number', 'Class', 'Project', 'Pathway', 'Site', 'Clock In', 'Clock Out', 'Method', 'Evidence']);
        foreach ($learner_data as $row) {
            fputcsv($output, [
                'Learner',
                $row['learnerID'],
                $row['firstName'] . ' ' . $row['lastName'],
                $row['idNumber'],
                $row['className'] ?? '-',
                $row['projectName'] ?? '-',
                $row['learningPathwayName'] ?? '-',
                $row['siteName'] ?? '-',
                $row['clock_in_time'] ? date('Y-m-d H:i:s', strtotime($row['clock_in_time'])) : '-',
                $row['clock_out_time'] ? date('Y-m-d H:i:s', strtotime($row['clock_out_time'])) : '-',
                $row['clocking_method'],
                $row['evidence_type'] ?? '-'
            ]);
        }
    }
    
    // Facilitators data
    if (!empty($facilitator_data)) {
        if (empty($learner_data)) {
            fputcsv($output, ['Type', 'ID', 'Name', 'Email', 'Class', 'Project', 'Pathway', 'Site', 'Date', 'Clock In', 'Clock Out', 'Method', 'In Verification', 'Out Verification']);
        } else {
            fputcsv($output, []); // Empty line separator
        }
        
        foreach ($facilitator_data as $row) {
            fputcsv($output, [
                'Facilitator',
                $row['facilitator_id'],
                $row['firstName'] . ' ' . $row['lastName'],
                $row['email'],
                $row['className'] ?? '-',
                $row['projectName'] ?? '-',
                $row['learningPathwayName'] ?? '-',
                $row['siteName'] ?? '-',
                $row['clock_date'],
                $row['clock_in_time'] ? date('Y-m-d H:i:s', strtotime($row['clock_in_time'])) : '-',
                $row['clock_out_time'] ? date('Y-m-d H:i:s', strtotime($row['clock_out_time'])) : '-',
                $row['clocking_method'],
                $row['clock_in_verification_method'] ?? '-',
                $row['clock_out_verification_method'] ?? '-'
            ]);
        }
    }
    
    fclose($output);
    exit;
}

$conn->close();
?>