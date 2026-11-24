# 🐳 Docker Build Guide - RLMSS Flutter App

## Overview

Build Flutter Android APKs using Docker containers for consistent, reproducible builds across different machines.

## ✨ Benefits of Docker Builds

- ✅ **Consistent environment** - Same build results everywhere
- ✅ **No local setup** - Android SDK, Java, Flutter all in container
- ✅ **Fast** - Cached dependencies, parallel builds
- ✅ **Clean** - No pollution of host system
- ✅ **CI/CD ready** - Same Dockerfile works locally and in GitHub Actions

## 📋 Prerequisites

### 1. Install Docker Desktop

**Windows:**
- Download: https://www.docker.com/products/docker-desktop
- Install Docker Desktop for Windows
- Enable WSL 2 backend (recommended)
- Start Docker Desktop

**Verify Installation:**
```powershell
docker --version
docker-compose --version
```

### 2. Configure Docker Resources

**Recommended Settings:**
- Memory: 8 GB minimum (12 GB recommended)
- CPUs: 4 cores minimum
- Disk: 20 GB free space

**To Configure:**
1. Open Docker Desktop
2. Settings → Resources
3. Adjust Memory and CPUs
4. Apply & Restart

## 🚀 Quick Start

### Method 1: Single Command Build (Sequential)

```powershell
# Build all 3 flavors using PowerShell script
.\docker-build.ps1
```

This will:
1. Build Docker image with Flutter, Android SDK, Java
2. Build local APK (~6 minutes)
3. Build staging APK (~5 minutes)
4. Build production APK (~5 minutes)
5. Output summary with APK sizes and locations

### Method 2: Docker Compose (Parallel)

```powershell
# Build all 3 flavors in parallel
.\docker-build-compose.ps1
```

Faster! Builds all 3 flavors simultaneously.

### Method 3: Manual Docker Commands

**Build specific flavor:**
```powershell
# Build Docker image
docker build -t rlmss-flutter-builder .

# Build production APK
docker run --rm -e FLAVOR=production -v "${PWD}/build:/app/build" rlmss-flutter-builder

# Build staging APK
docker run --rm -e FLAVOR=staging -v "${PWD}/build:/app/build" rlmss-flutter-builder

# Build local APK
docker run --rm -e FLAVOR=local -v "${PWD}/build:/app/build" rlmss-flutter-builder
```

## 📂 Output Locations

APKs are saved to:
```
build/app/outputs/flutter-apk/
├── app-local-release.apk      (~71 MB)
├── app-staging-release.apk    (~71 MB)
└── app-production-release.apk (~71 MB)
```

## 🔧 Docker Files Explained

### Dockerfile
Main build container with:
- Ubuntu 22.04 base
- Java 17 (OpenJDK)
- Android SDK (API 35)
- Flutter 3.24.0
- Build tools

### docker-compose.yml
Orchestrates parallel builds of all 3 flavors

### .dockerignore
Excludes unnecessary files from Docker context (faster builds)

## ⚡ Performance Tips

### 1. Use BuildKit (Faster Builds)
```powershell
$env:DOCKER_BUILDKIT=1
docker build -t rlmss-flutter-builder .
```

### 2. Cache Dependencies
The Docker image caches:
- Flutter SDK (~1.5 GB)
- Android SDK (~2 GB)
- Pub dependencies (~500 MB)

First build: ~15-20 minutes (downloads everything)
Subsequent builds: ~5-7 minutes per APK

### 3. Prune Unused Images
```powershell
# Clean up space
docker system prune -a
```

## 🐛 Troubleshooting

### "Docker is not running"
**Solution:** Start Docker Desktop

### "not enough space"
**Solution:**
```powershell
# Check Docker disk usage
docker system df

# Clean up
docker system prune -a --volumes
```

### "Cannot connect to Docker daemon"
**Solution:** Restart Docker Desktop

### Build fails with "out of memory"
**Solution:** Increase Docker Desktop memory:
1. Docker Desktop → Settings → Resources
2. Memory: Increase to 8 GB or more
3. Apply & Restart

### APK not found after build
**Solution:** Check build logs:
```powershell
docker logs <container-id>
```

## 🔄 Updating Docker Image

When you change dependencies (pubspec.yaml):

```powershell
# Rebuild image
docker build --no-cache -t rlmss-flutter-builder .

# Or using compose
docker-compose build --no-cache
```

## 📊 Build Time Comparison

| Method | Time | Pros | Cons |
|--------|------|------|------|
| **Local (Windows)** | 15-25 min | No Docker needed | Requires local setup, inconsistent |
| **Docker (Sequential)** | 15-20 min | Consistent, clean | Slower first time |
| **Docker (Parallel)** | 8-12 min | Fastest | Uses more resources |
| **GitHub Actions** | 30-40 min | Free, automated | Slower, requires git push |

## 🎯 CI/CD Integration

The same Dockerfile works in GitHub Actions:

```yaml
jobs:
  docker-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Docker image
        run: docker build -t rlmss-builder .
      
      - name: Build APK
        run: |
          docker run --rm \
            -e FLAVOR=production \
            -v $PWD/build:/app/build \
            rlmss-builder
      
      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: production-apk
          path: build/app/outputs/flutter-apk/*.apk
```

## 🔐 Security Notes

- ✅ Config files (`config/db.env`) are excluded via `.dockerignore`
- ✅ Credentials never baked into Docker image
- ✅ Build container runs as non-root by default
- ✅ No secrets in Dockerfile

## 📝 Advanced Usage

### Custom Build Arguments

```powershell
# Build with custom Flutter version
docker build --build-arg FLUTTER_VERSION=3.25.0 -t rlmss-builder .

# Build with custom Android API level
docker build --build-arg ANDROID_API=34 -t rlmss-builder .
```

### Interactive Debugging

```powershell
# Enter container for debugging
docker run -it --rm rlmss-flutter-builder /bin/bash

# Inside container
flutter doctor
flutter build apk --release --flavor production --verbose
```

### Multi-stage Builds (Smaller Images)

See `Dockerfile.optimized` for a smaller final image using multi-stage builds.

## 🆘 Support

**Common Commands:**
```powershell
# View running containers
docker ps

# View all containers
docker ps -a

# View logs
docker logs <container-name>

# Stop all containers
docker stop $(docker ps -q)

# Remove all containers
docker rm $(docker ps -aq)

# Remove all images
docker rmi $(docker images -q)

# Full cleanup
docker system prune -a --volumes
```

## 🎉 Summary

Docker provides a consistent, reliable build environment for your Flutter app. Use it for:
- ✅ Local development builds
- ✅ CI/CD pipelines  
- ✅ Team collaboration (same environment for everyone)
- ✅ Debugging build issues

**Recommended Workflow:**
1. Develop and test locally
2. Use `.\docker-build.ps1` to build APKs
3. Push to GitHub (CI/CD builds automatically)
4. Download APKs from GitHub Actions or use Docker builds

Happy building! 🚀
