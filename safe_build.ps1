# Safe Flutter Build Script - Prevents Gradle Lock Issues
# For RLMSS Flutter App on 4GB RAM Systems

param(
    [string]$BuildType = "debug",
    [switch]$Clean = $false
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  SAFE FLUTTER BUILD - GRADLE LOCK PREVENTION" -ForegroundColor Yellow
Write-Host "  Build Type: $BuildType" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check system resources
Write-Host "[1/8] Checking system resources..." -ForegroundColor Green
$memory = Get-WmiObject -Class Win32_OperatingSystem
$freeMemoryMB = [math]::Round($memory.FreePhysicalMemory / 1KB)
$totalMemoryMB = [math]::Round($memory.TotalVisibleMemorySize / 1KB)
$memoryUsagePercent = [math]::Round((($totalMemoryMB - $freeMemoryMB) / $totalMemoryMB) * 100)

Write-Host "Memory Usage: $memoryUsagePercent% ($freeMemoryMB MB free of $totalMemoryMB MB)" -ForegroundColor White

if ($memoryUsagePercent -gt 80) {
    Write-Host "⚠ WARNING: High memory usage detected!" -ForegroundColor Yellow
    Write-Host "Consider closing other applications before building." -ForegroundColor Yellow
}

# Step 2: Kill existing processes
Write-Host "[2/8] Terminating Java and Gradle processes..." -ForegroundColor Green
Get-Process -Name "*java*" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Killing Java process PID $($_.Id)" -ForegroundColor Gray
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Get-Process -Name "*gradle*" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Killing Gradle process PID $($_.Id)" -ForegroundColor Gray
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# Step 3: Clean Gradle locks
Write-Host "[3/8] Removing Gradle locks and caches..." -ForegroundColor Green
$gradleHome = "$env:USERPROFILE\.gradle"
if (Test-Path "$gradleHome\daemon") {
    Remove-Item "$gradleHome\daemon" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✓ Gradle daemon removed" -ForegroundColor Gray
}
if (Test-Path "$gradleHome\caches\journal-1") {
    Remove-Item "$gradleHome\caches\journal-1" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✓ Journal cache removed" -ForegroundColor Gray
}

# Step 4: Clean project cache
Write-Host "[4/8] Cleaning project cache..." -ForegroundColor Green
if (Test-Path "android\.gradle") {
    Remove-Item "android\.gradle" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✓ Project gradle cache removed" -ForegroundColor Gray
}

# Step 5: Flutter clean
Write-Host "[5/8] Running flutter clean..." -ForegroundColor Green
flutter clean | Out-Null
Write-Host "✓ Flutter clean completed" -ForegroundColor Gray

# Step 6: Set environment variables for low memory
Write-Host "[6/8] Setting build environment..." -ForegroundColor Green
$env:GRADLE_OPTS = "-Xmx320m -XX:MaxMetaspaceSize=64m -XX:+UseSerialGC -XX:+UseStringDeduplication"
$env:JAVA_OPTS = "-Xmx320m -XX:MaxMetaspaceSize=64m"
Write-Host "✓ Memory limits set to 320MB" -ForegroundColor Gray

# Step 7: Get dependencies
Write-Host "[7/8] Getting dependencies..." -ForegroundColor Green
flutter pub get | Out-Null
Write-Host "✓ Dependencies resolved" -ForegroundColor Gray

# Step 8: Build APK
Write-Host "[8/8] Building APK..." -ForegroundColor Green
$buildStartTime = Get-Date

if ($BuildType -eq "debug") {
    Write-Host "Starting DEBUG build for ARM64..." -ForegroundColor Cyan
    flutter build apk --debug --target-platform android-arm64
} elseif ($BuildType -eq "release") {
    Write-Host "Starting RELEASE build for ARM64..." -ForegroundColor Cyan
    Write-Host "WARNING: This may take 15-30 minutes on 4GB RAM!" -ForegroundColor Yellow
    flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons
} else {
    Write-Host "Invalid build type: $BuildType. Use 'debug' or 'release'" -ForegroundColor Red
    exit 1
}

$buildEndTime = Get-Date
$buildDuration = $buildEndTime - $buildStartTime

# Check results
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  BUILD COMPLETE" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan

if ($BuildType -eq "debug") {
    $apkPath = "build\app\outputs\flutter-apk\app-arm64-v8a-debug.apk"
} else {
    $apkPath = "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
}

if (Test-Path $apkPath) {
    $apkSize = (Get-Item $apkPath).Length / 1MB
    Write-Host "✅ SUCCESS!" -ForegroundColor Green
    Write-Host ""
    Write-Host "APK Details:" -ForegroundColor White
    Write-Host "  Location: $apkPath" -ForegroundColor Cyan
    Write-Host "  Size: $([math]::Round($apkSize, 2)) MB" -ForegroundColor Cyan
    Write-Host "  Build Time: $($buildDuration.ToString('mm\:ss'))" -ForegroundColor Cyan
    Write-Host "  Type: $BuildType" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Ready for installation on Android devices!" -ForegroundColor Green
} else {
    Write-Host "❌ BUILD FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Check available memory (need >1.5GB free)" -ForegroundColor White
    Write-Host "2. Close other applications" -ForegroundColor White
    Write-Host "3. Try debug build instead of release" -ForegroundColor White
    Write-Host "4. Run: .\safe_build.ps1 -BuildType debug" -ForegroundColor White
}

Write-Host ""