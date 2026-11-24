# Docker Build Script - RLMSS Flutter App
Write-Host "Docker Build - All Flavors" -ForegroundColor Cyan

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Docker not installed" -ForegroundColor Red
    exit 1
}

Write-Host "Building Docker image..." -ForegroundColor Green
docker build -t rlmss-flutter-builder .

$flavors = @("local", "staging", "production")
$results = @()

foreach ($flavor in $flavors) {
    Write-Host "`nBuilding $flavor..." -ForegroundColor Yellow
    $start = Get-Date
    
    docker run --rm -e FLAVOR=$flavor -v "${PWD}/build:/app/build" rlmss-flutter-builder
    
    $duration = (Get-Date) - $start
    $apk = "build/app/outputs/flutter-apk/app-$flavor-release.apk"
    
    if (Test-Path $apk) {
        $size = [math]::Round((Get-Item $apk).Length/1MB, 2)
        Write-Host "SUCCESS: $size MB" -ForegroundColor Green
        $results += @{Flavor=$flavor; Status="OK"; Size="$size MB"; Time=$duration.ToString('mm\:ss')}
    } else {
        Write-Host "FAILED" -ForegroundColor Red
        $results += @{Flavor=$flavor; Status="FAIL"; Size="N/A"; Time=$duration.ToString('mm\:ss')}
    }
}

Write-Host "`nBuild Summary:" -ForegroundColor Cyan
$results | ForEach-Object { [PSCustomObject]$_ } | Format-Table -AutoSize
