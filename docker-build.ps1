# Docker Build Script for RLMSS Flutter App
# Builds all 3 flavors (local, staging, production) using Docker

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Docker Build - RLMSS Flutter App" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Check if Docker is installed
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Docker is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    exit 1
}

# Check if Docker is running
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker is not running" -ForegroundColor Red
    Write-Host "Please start Docker Desktop and try again" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Building Docker image..." -ForegroundColor Green
docker build -t rlmss-flutter-builder .

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker image build failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Building All Flavors" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

$flavors = @("local", "staging", "production")
$results = @()

foreach ($flavor in $flavors) {
    Write-Host ""
    Write-Host "Building $flavor flavor..." -ForegroundColor Yellow
    $startTime = Get-Date
    
    docker run --rm `
        -e FLAVOR=$flavor `
        -v "${PWD}/build:/app/build" `
        rlmss-flutter-builder
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    $apkPath = "build/app/outputs/flutter-apk/app-${flavor}-release.apk"
    
    if (Test-Path $apkPath) {
        $size = [math]::Round((Get-Item $apkPath).Length / 1MB, 2)
        Write-Host "SUCCESS: $flavor APK built" -ForegroundColor Green
        Write-Host "  Size: $size MB" -ForegroundColor Cyan
        Write-Host "  Time: $($duration.ToString('mm\:ss'))" -ForegroundColor Cyan
        
        $results += [PSCustomObject]@{
            Flavor = $flavor
            Status = "SUCCESS"
            Size = "$size MB"
            Time = $duration.ToString('mm\:ss')
            APK = $apkPath
        }
    } else {
        Write-Host "FAILED: $flavor APK not found" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Flavor = $flavor
            Status = "FAILED"
            Size = "N/A"
            Time = $duration.ToString('mm\:ss')
            APK = "Not found"
        }
    }
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Build Summary" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$successCount = ($results | Where-Object { $_.Status -eq "SUCCESS" }).Count
Write-Host "Results: $successCount/3 builds succeeded" -ForegroundColor $(if ($successCount -eq 3) { "Green" } else { "Yellow" })

if ($successCount -lt 3) {
    Write-Host "Some builds failed. Check the output above." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "All APKs ready for deployment!" -ForegroundColor Green
