# 🚀 Secure Deployment Guide

## Critical Security Changes

### ✅ What Changed

1. **Removed Hardcoded Credentials**
   - `mobile/connection.php` - No more passwords in code
   - `php/connection.php` - Now reads from secure .env file

2. **Added Environment Configuration**
   - `config/db.env` - Secure credential storage (NOT in git)
   - `config/db.env.example` - Template for setup
   - `config/db.env.staging` - Staging environment template

3. **Updated .gitignore**
   - Blocks all `.env` files from being committed
   - Protects `config/db.env*` files

## 🔐 Deployment Steps

### Step 1: On Your Server

```bash
# Navigate to project directory
cd /path/to/rlmssv1

# Create config directory if it doesn't exist
mkdir -p config

# Copy the example file
cp config/db.env.example config/db.env

# Edit with your PRODUCTION credentials
nano config/db.env
```

### Step 2: Configure Production Credentials

Edit `config/db.env`:

```env
DB_HOST=localhost
DB_USERNAME=rlmsrlmsco_ezxcmacd_rlms
DB_PASSWORD=aV~4RP=_G{Uxm-Mp
DB_NAME=rlmsrlmsco_ezxcmacd_rlms
DB_TABLE=sdp
DB_CHARSET=utf8mb4
DB_TIMEZONE=+02:00

APP_ENV=production
APP_DEBUG=false
```

### Step 3: Secure File Permissions

```bash
# Owner read/write only (600)
chmod 600 config/db.env

# Verify
ls -la config/db.env
# Should show: -rw------- (only owner can read/write)
```

### Step 4: Test Connection

```bash
# PHP syntax check
php -l mobile/connection.php
php -l php/connection.php

# Test database connection
php -r "include 'mobile/connection.php'; echo 'Connected: ' . $conn->ping() . PHP_EOL;"
```

### Step 5: Deploy Updates

```bash
# Pull latest code
git pull origin main

# DO NOT overwrite your config/db.env file!
# The .gitignore ensures it stays safe

# Restart web server
sudo systemctl restart apache2
# or
sudo systemctl restart nginx
```

## 🏗️ Staging Environment Setup

### Create Staging Database & User

```sql
CREATE DATABASE rlmss_staging;
CREATE USER 'rlmss_staging'@'localhost' IDENTIFIED BY 'secure_staging_password';
GRANT ALL PRIVILEGES ON rlmss_staging.* TO 'rlmss_staging'@'localhost';
FLUSH PRIVILEGES;
```

### Configure Staging Environment

```bash
# Create staging config
cp config/db.env.example config/db.env.staging

# Edit with staging credentials
nano config/db.env.staging

# Set environment variable
export APP_ENV=staging
```

## 🔒 Security Checklist

Before going live, verify:

- [ ] `config/db.env` exists on server
- [ ] File permissions are 600 (owner only)
- [ ] No credentials in git history
- [ ] `.gitignore` includes `config/db.env`
- [ ] Different passwords for prod/staging/dev
- [ ] Credentials not in any committed files
- [ ] Web server can read `config/db.env`
- [ ] Database connection successful

## 🚨 Emergency: Credentials Exposed

If credentials were committed to git:

### 1. Change Database Password Immediately

```sql
ALTER USER 'rlmsrlmsco_ezxcmacd_rlms'@'localhost' IDENTIFIED BY 'NEW_SECURE_PASSWORD';
FLUSH PRIVILEGES;
```

### 2. Update config/db.env

```bash
nano config/db.env
# Update DB_PASSWORD with new password
```

### 3. Remove from Git History

```bash
# Install BFG Repo-Cleaner
# Remove sensitive file from history
bfg --delete-files connection.php

# Force push (CAUTION!)
git push --force
```

### 4. Rotate All Credentials

Change:
- Database password
- API keys
- JWT secrets
- Any other exposed credentials

## 📊 Monitoring

### Check File Access

```bash
# See who accessed the file
sudo ausearch -f /path/to/config/db.env

# Monitor file changes
sudo auditctl -w /path/to/config/db.env -p wa -k db_config_changes
```

### Database Connection Logs

Check `error.log` and `debug_clockin.log` for connection issues

## 🆘 Support

### File Not Found Error

```
CRITICAL: config/db.env not found
```

**Solution:**
```bash
cp config/db.env.example config/db.env
nano config/db.env  # Add your credentials
chmod 600 config/db.env
```

### Parse Error

```
CRITICAL: Failed to parse config/db.env
```

**Solution:**
```bash
# Check file format
cat config/db.env

# Should be KEY=value format, no syntax errors
# Fix any malformed lines
```

### Connection Failed

```
Database connection failed
```

**Solution:**
```bash
# 1. Verify credentials
cat config/db.env

# 2. Test MySQL connection
mysql -u username -p database_name

# 3. Check PHP can read file
php -r "print_r(parse_ini_file('config/db.env'));"

# 4. Check file permissions
ls -la config/db.env
```

## 📝 Notes

- The old `connection.php` files have been updated to read from `config/db.env`
- No code changes needed in your app - just configure the .env file
- Multiple environments supported (production, staging, development)
- All credential changes happen in ONE file: `config/db.env`
