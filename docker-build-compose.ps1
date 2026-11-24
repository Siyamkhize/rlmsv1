# Docker Compose Build Script
# Builds all 3 flavors in parallel using docker-compose

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Docker Compose Build - All Flavors" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Check if Docker Compose is installed
if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Docker Compose is not installed" -ForegroundColor Red
    Write-Host "Install with: docker-compose comes with Docker Desktop" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Building and running all services..." -ForegroundColor Green
docker-compose up --build

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Checking APKs" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

$flavors = @("local", "staging", "production")
foreach ($flavor in $flavors) {
    $apkPath = "build/app/outputs/flutter-apk/app-${flavor}-release.apk"
    if (Test-Path $apkPath) {
        $size = [math]::Round((Get-Item $apkPath).Length / 1MB, 2)
        Write-Host "SUCCESS: $flavor - $size MB - $apkPath" -ForegroundColor Green
    } else {
        Write-Host "FAILED: $flavor - APK not found" -ForegroundColor Red
    }
}
