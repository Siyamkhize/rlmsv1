<?php
require_once 'connection.php';

// Get filter parameters
$filter_date_from = isset($_GET['date_from']) ? $_GET['date_from'] : date('Y-m-01');
$filter_date_to = isset($_GET['date_to']) ? $_GET['date_to'] : date('Y-m-d');
$filter_project = isset($_GET['project_id']) ? intval($_GET['project_id']) : 0;
$filter_site = isset($_GET['site_id']) ? intval($_GET['site_id']) : 0;
$filter_class = isset($_GET['class_id']) ? intval($_GET['class_id']) : 0;
$filter_evidence_type = isset($_GET['evidence_type']) ? $_GET['evidence_type'] : 'all';

// Build WHERE clause
$whereConditions = ["mce.clock_date BETWEEN '$filter_date_from' AND '$filter_date_to'"];

if ($filter_evidence_type == 'signature_only') {
    $whereConditions[] = "(mce.signature_in IS NOT NULL OR mce.signature_out IS NOT NULL) AND (mce.face_in IS NULL AND mce.face_out IS NULL)";
} elseif ($filter_evidence_type == 'face_only') {
    $whereConditions[] = "(mce.face_in IS NOT NULL OR mce.face_out IS NOT NULL) AND (mce.signature_in IS NULL AND mce.signature_out IS NULL)";
} elseif ($filter_evidence_type == 'both') {
    $whereConditions[] = "(mce.signature_in IS NOT NULL OR mce.signature_out IS NOT NULL) AND (mce.face_in IS NOT NULL OR mce.face_out IS NOT NULL)";
} elseif ($filter_evidence_type == 'incomplete') {
    $whereConditions[] = "(mce.signature_in IS NOT NULL OR mce.face_in IS NOT NULL) AND (mce.signature_out IS NULL AND mce.face_out IS NULL)";
}

if ($filter_project > 0) {
    $whereConditions[] = "s.project_id = $filter_project";
}

if ($filter_site > 0) {
    $whereConditions[] = "c.siteID = $filter_site";
}

if ($filter_class > 0) {
    $whereConditions[] = "ld.classID = $filter_class";
}

$whereClause = implode(' AND ', $whereConditions);

// Get summary statistics
$statsQuery = "
    SELECT 
        COUNT(*) as total_records,
        COUNT(DISTINCT mce.LearnerID) as unique_learners,
        SUM(CASE WHEN (mce.signature_in IS NOT NULL OR mce.face_in IS NOT NULL) AND (mce.signature_out IS NULL AND mce.face_out IS NULL) THEN 1 ELSE 0 END) as incomplete_evidence,
        SUM(CASE WHEN (mce.signature_in IS NOT NULL OR mce.face_in IS NOT NULL) AND (mce.signature_out IS NOT NULL OR mce.face_out IS NOT NULL) THEN 1 ELSE 0 END) as complete_evidence,
        SUM(CASE WHEN mce.signature_in IS NOT NULL OR mce.signature_out IS NOT NULL THEN 1 ELSE 0 END) as signature_evidence,
        SUM(CASE WHEN mce.face_in IS NOT NULL OR mce.face_out IS NOT NULL THEN 1 ELSE 0 END) as face_evidence,
        COUNT(CASE WHEN DATE(mce.created_at) = CURDATE() THEN 1 END) as today_submissions
    FROM manual_clocking_evidence mce
    INNER JOIN learnerdetails ld ON mce.LearnerID = ld.LearnerID
    LEFT JOIN class c ON ld.classID = c.classID
    LEFT JOIN sites s ON c.siteID = s.siteID
    WHERE $whereClause
";

$statsResult = $conn->query($statsQuery);
$stats = $statsResult->fetch_assoc();

// Get filter dropdown data
$projectsQuery = "SELECT DISTINCT project_id, project_name FROM project WHERE project_id IS NOT NULL ORDER BY project_name";
$projectsResult = $conn->query($projectsQuery);

// Sites query - filtered by project if selected
if ($filter_project > 0) {
    $stmt = $conn->prepare("SELECT DISTINCT siteID, SiteName FROM sites WHERE project_id = ? ORDER BY SiteName");
    $stmt->bind_param("i", $filter_project);
    $stmt->execute();
    $sitesResult = $stmt->get_result();
} else {
    $sitesQuery = "SELECT DISTINCT siteID, SiteName FROM sites WHERE siteID IS NOT NULL ORDER BY SiteName";
    $sitesResult = $conn->query($sitesQuery);
}

// Classes query - filtered by site if selected, otherwise by project if selected
if ($filter_site > 0) {
    $stmt = $conn->prepare("SELECT DISTINCT classID, ClassName FROM class WHERE siteID = ? ORDER BY ClassName");
    $stmt->bind_param("i", $filter_site);
    $stmt->execute();
    $classesResult = $stmt->get_result();
} elseif ($filter_project > 0) {
    $stmt = $conn->prepare("SELECT DISTINCT c.classID, c.ClassName FROM class c INNER JOIN sites s ON c.siteID = s.siteID WHERE s.project_id = ? ORDER BY c.ClassName");
    $stmt->bind_param("i", $filter_project);
    $stmt->execute();
    $classesResult = $stmt->get_result();
} else {
    $classesQuery = "SELECT DISTINCT classID, ClassName FROM class WHERE classID IS NOT NULL ORDER BY ClassName";
    $classesResult = $conn->query($classesQuery);
}

// All projects for JS
$allProjectsQuery = "SELECT project_id, project_name FROM project WHERE project_id IS NOT NULL ORDER BY project_name";
$allProjectsResult = $conn->query($allProjectsQuery);
$allProjectsData = [];
if ($allProjectsResult) {
    while ($row = $allProjectsResult->fetch_assoc()) {
        $allProjectsData[] = ['id' => (int)$row['project_id'], 'name' => $row['project_name']];
    }
}

// All sites for JS
$allSitesQuery = "SELECT siteID, SiteName, project_id FROM sites WHERE siteID IS NOT NULL ORDER BY SiteName";
$allSitesResult = $conn->query($allSitesQuery);
$allSitesData = [];
if ($allSitesResult) {
    while ($row = $allSitesResult->fetch_assoc()) {
        $allSitesData[] = ['id' => (int)$row['siteID'], 'name' => $row['SiteName'], 'project_id' => (int)$row['project_id']];
    }
}

// All classes for JS
$allClassesQuery = "SELECT classID, ClassName, siteID FROM class WHERE classID IS NOT NULL ORDER BY ClassName";
$allClassesResult = $conn->query($allClassesQuery);
$allClassesData = [];
if ($allClassesResult) {
    while ($row = $allClassesResult->fetch_assoc()) {
        $allClassesData[] = ['id' => (int)$row['classID'], 'name' => $row['ClassName'], 'site_id' => (int)$row['siteID']];
    }
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Manual Clocking Evidence Dashboard | RLMS</title>
    <link href="css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="https://cdn.datatables.net/1.11.5/css/dataTables.bootstrap5.min.css" rel="stylesheet">
    <style>
        /* Modern Color Palette */
        :root {
            --primary-gradient: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            --success-gradient: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            --warning-gradient: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            --info-gradient: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            --dark-gradient: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
        }
        
        body {
            background: linear-gradient(120deg, #f8f9fa 0%, #e9ecef 100%);
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            min-height: 100vh;
        }
        
        /* Modern Navigation */
        .navbar {
            background: var(--dark-gradient) !important;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
            padding: 1rem 0;
        }
        
        .navbar-brand {
            font-weight: 700;
            font-size: 1.3rem;
            letter-spacing: 0.5px;
        }
        
        .nav-link {
            font-weight: 500;
            transition: all 0.3s ease;
            margin: 0 0.25rem;
            border-radius: 8px;
            padding: 0.5rem 1rem !important;
        }
        
        .nav-link:hover {
            background: rgba(255, 255, 255, 0.1);
            transform: translateY(-2px);
        }
        
        /* Page Header */
        .page-header {
            background: white;
            padding: 2rem;
            border-radius: 15px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
            margin-bottom: 2rem;
        }
        
        .page-header h2 {
            color: #2c3e50;
            font-weight: 700;
            margin-bottom: 0.5rem;
        }
        
        .page-header p {
            color: #6c757d;
            font-size: 1.05rem;
            margin: 0;
        }
        
        /* Enhanced Stat Cards */
        .stat-card {
            border: none;
            border-radius: 15px;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            overflow: hidden;
            position: relative;
            background: white;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
        }
        
        .stat-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 4px;
            background: var(--gradient);
        }
        
        .stat-card:hover {
            transform: translateY(-8px);
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.15);
        }
        
        .stat-card.primary::before { background: var(--primary-gradient); }
        .stat-card.success::before { background: var(--success-gradient); }
        .stat-card.warning::before { background: var(--warning-gradient); }
        .stat-card.info::before { background: var(--info-gradient); }
        
        .stat-card .card-body {
            padding: 1.75rem;
        }
        
        .stat-card h6 {
            color: #6c757d;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.75rem;
            letter-spacing: 0.5px;
            margin-bottom: 0.75rem;
        }
        
        .stat-card h3 {
            color: #2c3e50;
            font-weight: 700;
            font-size: 2rem;
        }
        
        .stat-card .fs-1 {
            opacity: 0.15;
            font-size: 3.5rem !important;
        }
        
        /* Enhanced Status Badges */
        .status-badge {
            padding: 0.35rem 1rem;
            border-radius: 50px;
            font-size: 0.8rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            display: inline-block;
        }
        
        .status-complete {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            color: white;
            box-shadow: 0 2px 10px rgba(56, 239, 125, 0.3);
        }
        
        .status-incomplete {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
            box-shadow: 0 2px 10px rgba(245, 87, 108, 0.3);
        }
        
        /* Evidence Badges */
        .evidence-badge {
            padding: 0.3rem 0.75rem;
            border-radius: 50px;
            font-size: 0.75rem;
            font-weight: 600;
            display: inline-flex;
            align-items: center;
            gap: 0.4rem;
            margin: 0.2rem;
        }
        
        .evidence-signature {
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            color: white;
            box-shadow: 0 2px 8px rgba(79, 172, 254, 0.3);
        }
        
        .evidence-face {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            box-shadow: 0 2px 8px rgba(102, 126, 234, 0.3);
        }
        
        /* Modern Filter Section */
        .filter-section {
            background: white;
            padding: 2rem;
            border-radius: 15px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
            margin-bottom: 2rem;
        }
        
        .filter-section .form-label {
            font-weight: 600;
            color: #2c3e50;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 0.5rem;
        }
        
        .filter-section .form-control,
        .filter-section .form-select {
            border: 2px solid #e9ecef;
            border-radius: 10px;
            padding: 0.65rem 1rem;
            transition: all 0.3s ease;
            font-size: 0.95rem;
        }
        
        .filter-section .form-control:focus,
        .filter-section .form-select:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.15);
        }
        
        /* Modern Buttons */
        .btn {
            padding: 0.65rem 1.5rem;
            border-radius: 10px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            font-size: 0.85rem;
            transition: all 0.3s ease;
            border: none;
        }
        
        .btn-primary {
            background: var(--primary-gradient);
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.4);
        }
        
        .btn-success {
            background: var(--success-gradient);
            box-shadow: 0 4px 15px rgba(56, 239, 125, 0.3);
        }
        
        .btn-success:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(56, 239, 125, 0.4);
        }
        
        .btn-warning {
            background: var(--warning-gradient);
            color: white;
            box-shadow: 0 4px 15px rgba(245, 87, 108, 0.3);
        }
        
        .btn-warning:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(245, 87, 108, 0.4);
        }
        
        .btn-info {
            background: var(--info-gradient);
            box-shadow: 0 4px 15px rgba(79, 172, 254, 0.3);
        }
        
        .btn-info:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(79, 172, 254, 0.4);
        }
        
        .btn-secondary {
            background: linear-gradient(135deg, #757f9a 0%, #d7dde8 100%);
            color: #2c3e50;
        }
        
        .btn-secondary:hover {
            transform: translateY(-2px);
        }
        
        /* Enhanced Cards */
        .card {
            border: none;
            border-radius: 15px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
            transition: all 0.3s ease;
            background: white;
        }
        
        .card:hover {
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.12);
        }
        
        .card-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 15px 15px 0 0 !important;
            padding: 1.25rem 1.5rem;
            font-weight: 700;
        }
        
        .card-header h5 {
            margin: 0;
            font-size: 1.1rem;
            letter-spacing: 0.5px;
        }
        
        .card-body {
            padding: 1.5rem;
        }
        
        /* Enhanced Table */
        .table {
            margin: 0;
        }
        
        .table thead th {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            color: #2c3e50;
            font-weight: 700;
            text-transform: uppercase;
            font-size: 0.75rem;
            letter-spacing: 0.5px;
            border: none;
            padding: 1rem;
        }
        
        .table tbody tr {
            transition: all 0.2s ease;
        }
        
        .table tbody tr:hover {
            background: #f8f9fa;
            transform: scale(1.01);
        }
        
        .table tbody td {
            vertical-align: middle;
            padding: 1rem;
            border-color: #f1f3f5;
        }
        
        /* Evidence Thumbnail */
        .evidence-thumbnail {
            width: 60px;
            height: 60px;
            object-fit: cover;
            border-radius: 10px;
            cursor: pointer;
            transition: all 0.3s ease;
            border: 3px solid #e9ecef;
        }
        
        .evidence-thumbnail:hover {
            transform: scale(1.1);
            border-color: #667eea;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
        }
        
        /* Modal Enhancements */
        .modal-content {
            border-radius: 15px;
            border: none;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
        }
        
        .modal-header {
            background: var(--primary-gradient);
            color: white;
            border-radius: 15px 15px 0 0;
            padding: 1.5rem;
        }
        
        .modal-title {
            font-weight: 700;
            letter-spacing: 0.5px;
        }
        
        .btn-close {
            filter: brightness(0) invert(1);
        }
        
        /* DataTables Enhancements */
        .dataTables_wrapper .dataTables_filter input {
            border: 2px solid #e9ecef;
            border-radius: 10px;
            padding: 0.5rem 1rem;
            transition: all 0.3s ease;
        }
        
        .dataTables_wrapper .dataTables_filter input:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.15);
        }
        
        .dataTables_wrapper .dataTables_length select {
            border: 2px solid #e9ecef;
            border-radius: 10px;
            padding: 0.5rem;
        }
        
        /* Small text improvements */
        small.text-muted {
            color: #6c757d !important;
            font-size: 0.8rem;
        }
        
        /* Icon improvements */
        .fa-calendar, .fa-filter, .fa-shield-alt, .fa-project-diagram, 
        .fa-map-marker-alt, .fa-chalkboard {
            margin-right: 0.4rem;
            opacity: 0.7;
        }
    </style>
</head>
<body>
    <!-- Simple Navigation -->
    <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
        <div class="container-fluid">
            <a class="navbar-brand" href="clocking_reports_menu.php">
                <i class="fas fa-camera"></i> Manual Clocking Evidence System
            </a>
            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav">
                <span class="navbar-toggler-icon"></span>
            </button>
            <div class="collapse navbar-collapse" id="navbarNav">
                <ul class="navbar-nav">
                    <li class="nav-item">
                        <a class="nav-link" href="clocking_reports_menu.php">
                            <i class="fas fa-home"></i> Home
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="clocking_dashboard.php">
                            <i class="fas fa-clock"></i> Learner Clocking
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link active" href="manual_clocking_evidence_dashboard.php">
                            <i class="fas fa-camera"></i> Manual Evidence
                        </a>
                    </li>
                </ul>
            </div>
        </div>
    </nav>
    
    <div class="container-fluid mt-4">
        <!-- Page Header -->
        <div class="page-header">
            <h2><i class="fas fa-camera"></i> Manual Clocking Evidence Dashboard</h2>
            <p>Monitor learner manual clocking evidence including signatures and face photos</p>
        </div>
        
        <!-- Statistics Cards -->
        <div class="row mb-4">
            <div class="col-md-3">
                <div class="card stat-card primary">
                    <div class="card-body">
                        <div class="d-flex justify-content-between align-items-center">
                            <div>
                                <h6 class="text-muted mb-1">Total Evidence Records</h6>
                                <h3 class="mb-0"><?php echo number_format($stats['total_records']); ?></h3>
                            </div>
                            <div class="fs-1 text-primary">
                                <i class="fas fa-file-image"></i>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3">
                <div class="card stat-card success">
                    <div class="card-body">
                        <div class="d-flex justify-content-between align-items-center">
                            <div>
                                <h6 class="text-muted mb-1">Complete Evidence</h6>
                                <h3 class="mb-0"><?php echo number_format($stats['complete_evidence']); ?></h3>
                            </div>
                            <div class="fs-1 text-success">
                                <i class="fas fa-check-circle"></i>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3">
                <div class="card stat-card warning">
                    <div class="card-body">
                        <div class="d-flex justify-content-between align-items-center">
                            <div>
                                <h6 class="text-muted mb-1">Incomplete Evidence</h6>
                                <h3 class="mb-0"><?php echo number_format($stats['incomplete_evidence']); ?></h3>
                            </div>
                            <div class="fs-1 text-warning">
                                <i class="fas fa-exclamation-triangle"></i>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="col-md-3">
                <div class="card stat-card info">
                    <div class="card-body">
                        <div class="d-flex justify-content-between align-items-center">
                            <div>
                                <h6 class="text-muted mb-1">Today's Submissions</h6>
                                <h3 class="mb-0"><?php echo number_format($stats['today_submissions']); ?></h3>
                            </div>
                            <div class="fs-1 text-info">
                                <i class="fas fa-calendar-day"></i>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Evidence Method Stats -->
        <div class="row mb-4">
            <div class="col-md-6">
                <div class="card">
                    <div class="card-body">
                        <h5 class="card-title"><i class="fas fa-chart-pie"></i> Evidence Types</h5>
                        <div class="row text-center mt-3">
                            <div class="col-6">
                                <div class="p-3 border rounded">
                                    <i class="fas fa-signature fs-1 text-primary mb-2"></i>
                                    <h4><?php echo number_format($stats['signature_evidence']); ?></h4>
                                    <p class="text-muted mb-0">Signature Evidence</p>
                                </div>
                            </div>
                            <div class="col-6">
                                <div class="p-3 border rounded">
                                    <i class="fas fa-face-smile fs-1 text-info mb-2"></i>
                                    <h4><?php echo number_format($stats['face_evidence']); ?></h4>
                                    <p class="text-muted mb-0">Face Evidence</p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="col-md-6">
                <div class="card">
                    <div class="card-body">
                        <h5 class="card-title"><i class="fas fa-users"></i> Unique Learners</h5>
                        <div class="text-center p-4">
                            <i class="fas fa-users fs-1 text-success mb-3"></i>
                            <h2 class="mb-0"><?php echo number_format($stats['unique_learners']); ?></h2>
                            <p class="text-muted">Learners with evidence in selected period</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Filters -->
        <div class="filter-section">
            <form method="GET" action="" id="filterForm">
                <div class="row">
                    <div class="col-md-2">
                        <label class="form-label"><i class="fas fa-calendar"></i> Date From</label>
                        <input type="date" name="date_from" class="form-control" value="<?php echo htmlspecialchars($filter_date_from); ?>">
                    </div>
                    
                    <div class="col-md-2">
                        <label class="form-label"><i class="fas fa-calendar"></i> Date To</label>
                        <input type="date" name="date_to" class="form-control" value="<?php echo htmlspecialchars($filter_date_to); ?>">
                    </div>
                    
                    <div class="col-md-2">
                        <label class="form-label"><i class="fas fa-filter"></i> Evidence Type</label>
                        <select name="evidence_type" class="form-select">
                            <option value="all" <?php echo $filter_evidence_type == 'all' ? 'selected' : ''; ?>>All Evidence</option>
                            <option value="signature_only" <?php echo $filter_evidence_type == 'signature_only' ? 'selected' : ''; ?>>Signature Only</option>
                            <option value="face_only" <?php echo $filter_evidence_type == 'face_only' ? 'selected' : ''; ?>>Face Only</option>
                            <option value="both" <?php echo $filter_evidence_type == 'both' ? 'selected' : ''; ?>>Both Types</option>
                            <option value="incomplete" <?php echo $filter_evidence_type == 'incomplete' ? 'selected' : ''; ?>>Incomplete</option>
                        </select>
                    </div>
                    
                    <div class="col-md-2">
                        <label class="form-label"><i class="fas fa-project-diagram"></i> Project</label>
                        <select name="project_id" id="project_select" class="form-select">
                            <option value="0">All Projects</option>
                            <?php 
                            if ($projectsResult) {
                                while ($project = $projectsResult->fetch_assoc()): 
                            ?>
                            <option value="<?php echo $project['project_id']; ?>" <?php echo $filter_project == $project['project_id'] ? 'selected' : ''; ?>>
                                <?php echo htmlspecialchars($project['project_name']); ?>
                            </option>
                            <?php 
                                endwhile;
                            }
                            ?>
                        </select>
                    </div>
                    
                    <div class="col-md-2">
                        <label class="form-label"><i class="fas fa-map-marker-alt"></i> Site</label>
                        <select name="site_id" id="site_select" class="form-select">
                            <option value="0">All Sites</option>
                            <?php 
                            if ($sitesResult) {
                                while ($site = $sitesResult->fetch_assoc()): 
                            ?>
                            <option value="<?php echo $site['siteID']; ?>" <?php echo $filter_site == $site['siteID'] ? 'selected' : ''; ?>>
                                <?php echo htmlspecialchars($site['SiteName']); ?>
                            </option>
                            <?php 
                                endwhile;
                            }
                            ?>
                        </select>
                    </div>
                    
                    <div class="col-md-2">
                        <label class="form-label"><i class="fas fa-chalkboard"></i> Class</label>
                        <select name="class_id" id="class_select" class="form-select">
                            <option value="0">All Classes</option>
                            <?php 
                            if ($classesResult) {
                                while ($class = $classesResult->fetch_assoc()): 
                            ?>
                            <option value="<?php echo $class['classID']; ?>" <?php echo $filter_class == $class['classID'] ? 'selected' : ''; ?>>
                                <?php echo htmlspecialchars($class['ClassName']); ?>
                            </option>
                            <?php 
                                endwhile;
                            }
                            ?>
                        </select>
                    </div>
                </div>
                
                <div class="row mt-3">
                    <div class="col-md-2">
                        <label class="form-label">&nbsp;</label>
                        <div>
                            <button type="submit" class="btn btn-primary w-100">
                                <i class="fas fa-search"></i> Filter
                            </button>
                        </div>
                    </div>
                    
                    <div class="col-md-10 text-end">
                        <label class="form-label">&nbsp;</label>
                        <div>
                            <a href="manual_clocking_evidence_dashboard.php" class="btn btn-secondary">
                                <i class="fas fa-redo"></i> Reset Filters
                            </a>
                            <a href="manual_clocking_evidence_export.php?<?php echo http_build_query($_GET); ?>" class="btn btn-success">
                                <i class="fas fa-file-excel"></i> Export to Excel
                            </a>
                        </div>
                    </div>
                </div>
            </form>
        </div>
        
        <!-- Evidence Records Table -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-table"></i> Manual Clocking Evidence Records</h5>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table id="evidenceTable" class="table table-striped table-hover">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Learner Name</th>
                                <th>Project</th>
                                <th>Site</th>
                                <th>Class</th>
                                <th>Date</th>
                                <th>Signature In</th>
                                <th>Signature Out</th>
                                <th>Face In</th>
                                <th>Face Out</th>
                                <th>Status</th>
                                <th>Created</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php
                            $recordsQuery = "
                                SELECT 
                                    mce.*,
                                    CONCAT(ld.Name, ' ', ld.Surname) as learner_name,
                                    ld.IDNumber,
                                    p.project_name as ProjectName,
                                    s.siteName as SiteName,
                                    c.className as ClassName,
                                    s.project_id,
                                    c.siteID,
                                    ld.classID
                                FROM manual_clocking_evidence mce
                                INNER JOIN learnerdetails ld ON mce.LearnerID = ld.LearnerID
                                LEFT JOIN class c ON ld.classID = c.classID
                                LEFT JOIN sites s ON c.siteID = s.siteID
                                LEFT JOIN project p ON s.project_id = p.project_id
                                WHERE $whereClause
                                ORDER BY mce.clock_date DESC, mce.created_at DESC
                                LIMIT 1000
                            ";
                            
                            $recordsResult = $conn->query($recordsQuery);
                            
                            if ($recordsResult) {
                                while ($row = $recordsResult->fetch_assoc()) {
                                    // Determine status based on evidence completeness
                                    $hasClockIn = ($row['signature_in'] || $row['face_in']);
                                    $hasClockOut = ($row['signature_out'] || $row['face_out']);
                                    
                                    if ($hasClockIn && $hasClockOut) {
                                        $status = 'complete';
                                        $statusText = 'Complete';
                                        $statusClass = 'status-complete';
                                    } elseif ($hasClockIn) {
                                        $status = 'incomplete';
                                        $statusText = 'Incomplete';
                                        $statusClass = 'status-incomplete';
                                    } else {
                                        $status = 'no_evidence';
                                        $statusText = 'No Evidence';
                                        $statusClass = 'status-incomplete';
                                    }
                                    
                                    echo "<tr>";
                                    echo "<td>" . htmlspecialchars($row['evidence_id']) . "</td>";
                                    echo "<td><strong>" . htmlspecialchars($row['learner_name']) . "</strong><br><small class='text-muted'>ID: " . htmlspecialchars($row['IDNumber']) . "</small></td>";
                                    echo "<td><small>" . htmlspecialchars($row['ProjectName'] ?? 'N/A') . "</small></td>";
                                    echo "<td><small>" . htmlspecialchars($row['SiteName'] ?? 'N/A') . "</small></td>";
                                    echo "<td><small>" . htmlspecialchars($row['ClassName'] ?? 'N/A') . "</small></td>";
                                    echo "<td>" . date('d M Y', strtotime($row['clock_date'])) . "</td>";
                                    
                                    // Signature In
                                    if ($row['signature_in']) {
                                        echo "<td><span class='evidence-badge evidence-signature'><i class='fas fa-signature'></i> Available</span></td>";
                                    } else {
                                        echo "<td><span class='text-muted'>-</span></td>";
                                    }
                                    
                                    // Signature Out
                                    if ($row['signature_out']) {
                                        echo "<td><span class='evidence-badge evidence-signature'><i class='fas fa-signature'></i> Available</span></td>";
                                    } else {
                                        echo "<td><span class='text-muted'>-</span></td>";
                                    }
                                    
                                    // Face In
                                    if ($row['face_in']) {
                                        echo "<td><span class='evidence-badge evidence-face'><i class='fas fa-face-smile'></i> Available</span></td>";
                                    } else {
                                        echo "<td><span class='text-muted'>-</span></td>";
                                    }
                                    
                                    // Face Out
                                    if ($row['face_out']) {
                                        echo "<td><span class='evidence-badge evidence-face'><i class='fas fa-face-smile'></i> Available</span></td>";
                                    } else {
                                        echo "<td><span class='text-muted'>-</span></td>";
                                    }
                                    
                                    echo "<td><span class='status-badge " . $statusClass . "'>" . $statusText . "</span></td>";
                                    echo "<td>" . date('d M Y H:i', strtotime($row['created_at'])) . "</td>";
                                    echo "<td>
                                        <a href='manual_clocking_evidence_details.php?id=" . $row['evidence_id'] . "' class='btn btn-sm btn-info' title='View Details'>
                                            <i class='fas fa-eye'></i>
                                        </a>
                                    </td>";
                                    echo "</tr>";
                                }
                            } else {
                                echo "<tr><td colspan='13' class='text-center'>No records found</td></tr>";
                            }
                            ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Evidence Modal -->
    <div class="modal fade" id="evidenceModal" tabindex="-1">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Evidence Image</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body text-center">
                    <img id="modalEvidence" src="" class="img-fluid" alt="Evidence Image">
                </div>
            </div>
        </div>
    </div>
    
    <script src="js/jquery-3.6.0.min.js"></script>
    <script src="js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/dataTables.bootstrap5.min.js"></script>
    
    <script>
        // Pre-loaded data from PHP
        var allSites = <?php echo json_encode($allSitesData); ?>;
        var allClasses = <?php echo json_encode($allClassesData); ?>;
        
        $(document).ready(function() {
            // Initialize DataTable
            $('#evidenceTable').DataTable({
                pageLength: 25,
                order: [[5, 'desc']],
                language: {
                    search: "Search records:"
                }
            });
            
            // Evidence modal
            $('#evidenceModal').on('show.bs.modal', function(event) {
                var button = $(event.relatedTarget);
                var evidence = button.data('evidence');
                $('#modalEvidence').attr('src', 'manual_clocking_evidence/' + evidence);
            });
            
            // Filter sites dropdown based on selected project
            function filterSites(projectId) {
                var siteSelect = document.getElementById('site_select');
                var currentSiteVal = siteSelect.value;
                
                // Rebuild site options
                siteSelect.innerHTML = '<option value="0">All Sites</option>';
                var sitesToShow = (projectId == 0) ? allSites : allSites.filter(function(s) { return s.project_id == projectId; });
                sitesToShow.forEach(function(site) {
                    var opt = document.createElement('option');
                    opt.value = site.id;
                    opt.textContent = site.name;
                    if (site.id == currentSiteVal) opt.selected = true;
                    siteSelect.appendChild(opt);
                });
                
                // If the previously selected site is no longer available, reset it
                if (siteSelect.value != currentSiteVal) {
                    siteSelect.value = '0';
                }
                
                // Now cascade to classes
                filterClasses(siteSelect.value, projectId);
            }

            // Filter classes dropdown based on selected site (and optionally project)
            function filterClasses(siteId, projectId) {
                var classSelect = document.getElementById('class_select');
                var currentClassVal = classSelect.value;
                
                classSelect.innerHTML = '<option value="0">All Classes</option>';
                
                var classesToShow;
                if (siteId > 0) {
                    classesToShow = allClasses.filter(function(c) { return c.site_id == siteId; });
                } else if (projectId > 0) {
                    // Get site IDs for this project first
                    var siteIds = allSites.filter(function(s) { return s.project_id == projectId; }).map(function(s) { return s.id; });
                    classesToShow = allClasses.filter(function(c) { return siteIds.indexOf(c.site_id) !== -1; });
                } else {
                    classesToShow = allClasses;
                }
                
                classesToShow.forEach(function(cls) {
                    var opt = document.createElement('option');
                    opt.value = cls.id;
                    opt.textContent = cls.name;
                    if (cls.id == currentClassVal) opt.selected = true;
                    classSelect.appendChild(opt);
                });
                
                if (classSelect.value != currentClassVal) {
                    classSelect.value = '0';
                }
            }

            // Wire up change events
            document.getElementById('project_select').addEventListener('change', function() {
                filterSites(parseInt(this.value) || 0);
            });

            document.getElementById('site_select').addEventListener('change', function() {
                var projectId = parseInt(document.getElementById('project_select').value) || 0;
                filterClasses(parseInt(this.value) || 0, projectId);
            });
        });
    </script>
</body>
</html>