<?php
require_once 'connection.php';

// Get filter parameters
$filter_date_from = isset($_GET['date_from']) ? $_GET['date_from'] : date('Y-m-01');
$filter_date_to = isset($_GET['date_to']) ? $_GET['date_to'] : date('Y-m-d');
$filter_status = isset($_GET['status']) ? $_GET['status'] : 'all';
$filter_verification = isset($_GET['verification']) ? $_GET['verification'] : 'all';
$filter_project = isset($_GET['project_id']) ? intval($_GET['project_id']) : 0;
$filter_site = isset($_GET['site_id']) ? intval($_GET['site_id']) : 0;
$filter_class = isset($_GET['class_id']) ? intval($_GET['class_id']) : 0;

// Build WHERE clause
$whereConditions = ["lce.clock_date BETWEEN '$filter_date_from' AND '$filter_date_to'"];

if ($filter_status == 'clocked_in') {
    $whereConditions[] = "lce.clock_in_timestamp IS NOT NULL AND lce.clock_out_timestamp IS NULL";
} elseif ($filter_status == 'clocked_out') {
    $whereConditions[] = "lce.clock_in_timestamp IS NOT NULL AND lce.clock_out_timestamp IS NOT NULL";
} elseif ($filter_status == 'incomplete') {
    $whereConditions[] = "lce.clock_in_timestamp IS NOT NULL AND lce.clock_out_timestamp IS NULL";
}

if ($filter_verification != 'all') {
    $whereConditions[] = "lce.clock_in_verification_method = '$filter_verification'";
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
        COUNT(DISTINCT lce.LearnerID) as unique_learners,
        SUM(CASE WHEN lce.clock_in_timestamp IS NOT NULL AND lce.clock_out_timestamp IS NULL THEN 1 ELSE 0 END) as currently_clocked_in,
        SUM(CASE WHEN lce.clock_in_timestamp IS NOT NULL AND lce.clock_out_timestamp IS NOT NULL THEN 1 ELSE 0 END) as completed_sessions,
        SUM(CASE WHEN lce.clock_in_verification_method = 'face' THEN 1 ELSE 0 END) as face_verifications,
        SUM(CASE WHEN lce.clock_in_verification_method = 'signature' THEN 1 ELSE 0 END) as signature_verifications,
        COUNT(CASE WHEN DATE(lce.clock_in_timestamp) = CURDATE() THEN 1 END) as today_clockings
    FROM learner_clocking_evidence lce
    INNER JOIN learnerdetails ld ON lce.LearnerID = ld.LearnerID
    LEFT JOIN class c ON ld.classID = c.classID
    LEFT JOIN sites s ON c.siteID = s.siteID
    WHERE $whereClause
";

$statsResult = $conn->query($statsQuery);
$stats = $statsResult->fetch_assoc();

// Get filter dropdown data
$projectsQuery = "SELECT DISTINCT project_id, project_name FROM project WHERE project_id IS NOT NULL ORDER BY project_name";
$projectsResult = $conn->query($projectsQuery);

$sitesQuery = "SELECT DISTINCT siteID, SiteName FROM sites WHERE siteID IS NOT NULL ORDER BY SiteName";
$sitesResult = $conn->query($sitesQuery);

$classesQuery = "SELECT DISTINCT classID, ClassName FROM class WHERE classID IS NOT NULL ORDER BY ClassName";
$classesResult = $conn->query($classesQuery);

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Learner Clocking Dashboard | RLMS</title>
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
        
        .status-clocked-in {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            color: white;
            box-shadow: 0 2px 10px rgba(56, 239, 125, 0.3);
        }
        
        .status-clocked-out {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            box-shadow: 0 2px 10px rgba(118, 75, 162, 0.3);
        }
        
        /* Verification Badges */
        .verification-badge {
            padding: 0.3rem 0.75rem;
            border-radius: 50px;
            font-size: 0.75rem;
            font-weight: 600;
            display: inline-flex;
            align-items: center;
            gap: 0.4rem;
        }
        
        .verification-face {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            box-shadow: 0 2px 8px rgba(102, 126, 234, 0.3);
        }
        
        .verification-signature {
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            color: white;
            box-shadow: 0 2px 8px rgba(79, 172, 254, 0.3);
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
        
        /* Photo Thumbnail */
        .photo-thumbnail {
            width: 50px;
            height: 50px;
            object-fit: cover;
            border-radius: 10px;
            cursor: pointer;
            transition: all 0.3s ease;
            border: 3px solid #e9ecef;
        }
        
        .photo-thumbnail:hover {
            transform: scale(1.1);
            border-color: #667eea;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
        }
        
        /* Time Duration */
        .time-duration {
            font-weight: 700;
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            font-size: 1rem;
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
                <i class="fas fa-clock"></i> Learner Clocking System
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
                            <i class="fas fa-chart-line"></i> Dashboard
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="clocking_realtime.php">
                            <i class="fas fa-satellite-dish"></i> Real-Time
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="clocking_analytics.php">
                            <i class="fas fa-chart-pie"></i> Analytics
                        </a>
                    </li>
                </ul>
            </div>
        </div>
    </nav>
    
    <div class="container-fluid mt-4">
        <!-- Page Header -->
        <div class="page-header">
            <h2><i class="fas fa-clock"></i> Learner Clocking Dashboard</h2>
            <p>Monitor learner attendance using facial recognition and signature verification</p>
        </div>
        
        <!-- Statistics Cards -->
        <div class="row mb-4">
            <div class="col-md-3">
                <div class="card stat-card primary">
                    <div class="card-body">
                        <div class="d-flex justify-content-between align-items-center">
                            <div>
                                <h6 class="text-muted mb-1">Total Records</h6>
                                <h3 class="mb-0"><?php echo number_format($stats['total_records']); ?></h3>
                            </div>
                            <div class="fs-1 text-primary">
                                <i class="fas fa-clipboard-list"></i>
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
                                <h6 class="text-muted mb-1">Currently Clocked In</h6>
                                <h3 class="mb-0"><?php echo number_format($stats['currently_clocked_in']); ?></h3>
                            </div>
                            <div class="fs-1 text-success">
                                <i class="fas fa-user-clock"></i>
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
                                <h6 class="text-muted mb-1">Completed Sessions</h6>
                                <h3 class="mb-0"><?php echo number_format($stats['completed_sessions']); ?></h3>
                            </div>
                            <div class="fs-1 text-info">
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
                                <h6 class="text-muted mb-1">Today's Clockings</h6>
                                <h3 class="mb-0"><?php echo number_format($stats['today_clockings']); ?></h3>
                            </div>
                            <div class="fs-1 text-warning">
                                <i class="fas fa-calendar-day"></i>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Verification Method Stats -->
        <div class="row mb-4">
            <div class="col-md-6">
                <div class="card">
                    <div class="card-body">
                        <h5 class="card-title"><i class="fas fa-chart-pie"></i> Verification Methods</h5>
                        <div class="row text-center mt-3">
                            <div class="col-6">
                                <div class="p-3 border rounded">
                                    <i class="fas fa-face-smile fs-1 text-primary mb-2"></i>
                                    <h4><?php echo number_format($stats['face_verifications']); ?></h4>
                                    <p class="text-muted mb-0">Face Recognition</p>
                                </div>
                            </div>
                            <div class="col-6">
                                <div class="p-3 border rounded">
                                    <i class="fas fa-signature fs-1 text-info mb-2"></i>
                                    <h4><?php echo number_format($stats['signature_verifications']); ?></h4>
                                    <p class="text-muted mb-0">Signature</p>
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
                            <p class="text-muted">Active learners in selected period</p>
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
                        <label class="form-label"><i class="fas fa-filter"></i> Status</label>
                        <select name="status" class="form-select">
                            <option value="all" <?php echo $filter_status == 'all' ? 'selected' : ''; ?>>All</option>
                            <option value="clocked_in" <?php echo $filter_status == 'clocked_in' ? 'selected' : ''; ?>>Clocked In</option>
                            <option value="clocked_out" <?php echo $filter_status == 'clocked_out' ? 'selected' : ''; ?>>Clocked Out</option>
                            <option value="incomplete" <?php echo $filter_status == 'incomplete' ? 'selected' : ''; ?>>Incomplete</option>
                        </select>
                    </div>
                    
                    <div class="col-md-2">
                        <label class="form-label"><i class="fas fa-shield-alt"></i> Verification</label>
                        <select name="verification" class="form-select">
                            <option value="all" <?php echo $filter_verification == 'all' ? 'selected' : ''; ?>>All</option>
                            <option value="face" <?php echo $filter_verification == 'face' ? 'selected' : ''; ?>>Face Recognition</option>
                            <option value="signature" <?php echo $filter_verification == 'signature' ? 'selected' : ''; ?>>Signature</option>
                        </select>
                    </div>
                    
                    <div class="col-md-2">
                        <label class="form-label"><i class="fas fa-project-diagram"></i> Project</label>
                        <select name="project_id" class="form-select">
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
                        <select name="site_id" class="form-select">
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
                </div>
                
                <div class="row mt-3">
                    <div class="col-md-3">
                        <label class="form-label"><i class="fas fa-chalkboard"></i> Class</label>
                        <select name="class_id" class="form-select">
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
                    
                    <div class="col-md-2">
                        <label class="form-label">&nbsp;</label>
                        <div>
                            <button type="submit" class="btn btn-primary w-100">
                                <i class="fas fa-search"></i> Filter
                            </button>
                        </div>
                    </div>
                    
                    <div class="col-md-7 text-end">
                        <label class="form-label">&nbsp;</label>
                        <div>
                            <a href="clocking_dashboard.php" class="btn btn-secondary">
                                <i class="fas fa-redo"></i> Reset Filters
                            </a>
                            <a href="clocking_export.php?<?php echo http_build_query($_GET); ?>" class="btn btn-success">
                                <i class="fas fa-file-excel"></i> Export to Excel
                            </a>
                            <a href="clocking_analytics.php" class="btn btn-warning">
                                <i class="fas fa-chart-pie"></i> Analytics
                            </a>
                            <a href="clocking_realtime.php" class="btn btn-info">
                                <i class="fas fa-sync-alt"></i> Real-Time View
                            </a>
                        </div>
                    </div>
                </div>
            </form>
        </div>
        
        <!-- Clocking Records Table -->
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0"><i class="fas fa-table"></i> Clocking Records</h5>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table id="clockingTable" class="table table-striped table-hover">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Learner Name</th>
                                <th>Project</th>
                                <th>Site</th>
                                <th>Class</th>
                                <th>Date</th>
                                <th>Clock In</th>
                                <th>Clock Out</th>
                                <th>Duration</th>
                                <th>Verification</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php
                            $recordsQuery = "
                                SELECT 
                                    lce.*,
                                    CONCAT(ld.Name, ' ', ld.Surname) as learner_name,
                                    ld.IDNumber,
                                    p.project_name as ProjectName,
                                    s.siteName as SiteName,
                                    c.className as ClassName,
                                    s.project_id,
                                    c.siteID,
                                    ld.classID,
                                    TIMESTAMPDIFF(HOUR, lce.clock_in_timestamp, lce.clock_out_timestamp) as hours_worked,
                                    TIMESTAMPDIFF(MINUTE, lce.clock_in_timestamp, lce.clock_out_timestamp) as minutes_worked
                                FROM learner_clocking_evidence lce
                                INNER JOIN learnerdetails ld ON lce.LearnerID = ld.LearnerID
                                LEFT JOIN class c ON ld.classID = c.classID
                                LEFT JOIN sites s ON c.siteID = s.siteID
                                LEFT JOIN project p ON s.project_id = p.project_id
                                WHERE $whereClause
                                ORDER BY lce.clock_date DESC, lce.clock_in_timestamp DESC
                                LIMIT 1000
                            ";
                            
                            $recordsResult = $conn->query($recordsQuery);
                            
                            if ($recordsResult) {
                                while ($row = $recordsResult->fetch_assoc()) {
                                    $clockInTime = $row['clock_in_timestamp'] ? date('H:i', strtotime($row['clock_in_timestamp'])) : '-';
                                    $clockOutTime = $row['clock_out_timestamp'] ? date('H:i', strtotime($row['clock_out_timestamp'])) : '-';
                                    
                                    $duration = '-';
                                    if ($row['clock_out_timestamp']) {
                                        $hours = floor($row['minutes_worked'] / 60);
                                        $minutes = $row['minutes_worked'] % 60;
                                        $duration = sprintf('%dh %dm', $hours, $minutes);
                                    }
                                    
                                    $status = $row['clock_out_timestamp'] ? 'clocked-out' : 'clocked-in';
                                    $statusText = $row['clock_out_timestamp'] ? 'Clocked Out' : 'Clocked In';
                                    $statusClass = $row['clock_out_timestamp'] ? 'status-clocked-out' : 'status-clocked-in';
                                    
                                    $verificationMethod = ucfirst($row['clock_in_verification_method']);
                                    $verificationClass = $row['clock_in_verification_method'] == 'face' ? 'verification-face' : 'verification-signature';
                                    
                                    echo "<tr>";
                                    echo "<td>" . htmlspecialchars($row['id']) . "</td>";
                                    echo "<td><strong>" . htmlspecialchars($row['learner_name']) . "</strong><br><small class='text-muted'>ID: " . htmlspecialchars($row['IDNumber']) . "</small></td>";
                                    echo "<td><small>" . htmlspecialchars($row['ProjectName'] ?? 'N/A') . "</small></td>";
                                    echo "<td><small>" . htmlspecialchars($row['SiteName'] ?? 'N/A') . "</small></td>";
                                    echo "<td><small>" . htmlspecialchars($row['ClassName'] ?? 'N/A') . "</small></td>";
                                    echo "<td>" . date('d M Y', strtotime($row['clock_date'])) . "</td>";
                                    echo "<td>" . $clockInTime . "</td>";
                                    echo "<td>" . $clockOutTime . "</td>";
                                    echo "<td><span class='time-duration'>" . $duration . "</span></td>";
                                    echo "<td><span class='verification-badge " . $verificationClass . "'><i class='fas fa-" . ($row['clock_in_verification_method'] == 'face' ? 'face-smile' : 'signature') . "'></i> " . $verificationMethod . "</span></td>";
                                    echo "<td><span class='status-badge " . $statusClass . "'>" . $statusText . "</span></td>";
                                    echo "<td>
                                        <a href='clocking_details.php?id=" . $row['id'] . "' class='btn btn-sm btn-info' title='View Details'>
                                            <i class='fas fa-eye'></i>
                                        </a>
                                    </td>";
                                    echo "</tr>";
                                }
                            } else {
                                echo "<tr><td colspan='12' class='text-center'>No records found</td></tr>";
                            }
                            ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Photo Modal -->
    <div class="modal fade" id="photoModal" tabindex="-1">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Clocking Photo</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body text-center">
                    <img id="modalPhoto" src="" class="img-fluid" alt="Clocking Photo">
                </div>
            </div>
        </div>
    </div>
    
    <script src="js/jquery-3.6.0.min.js"></script>
    <script src="js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.11.5/js/dataTables.bootstrap5.min.js"></script>
    
    <script>
        $(document).ready(function() {
            // Initialize DataTable
            $('#clockingTable').DataTable({
                pageLength: 25,
                order: [[2, 'desc']],
                language: {
                    search: "Search records:"
                }
            });
            
            // Photo modal
            $('#photoModal').on('show.bs.modal', function(event) {
                var button = $(event.relatedTarget);
                var photo = button.data('photo');
                $('#modalPhoto').attr('src', 'uploads/clocking_photos/' + photo);
            });
        });
    </script>
</body>
</html>
