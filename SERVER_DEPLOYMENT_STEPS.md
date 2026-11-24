# 🚀 SERVER DEPLOYMENT STEPS - URGENT

## ⚠️ IMPORTANT: Your server needs ONE file to work

The database credentials are NO LONGER in `mobile/connection.php`. They must be in `config/db.env`.

## 📋 Steps to Deploy on Server

### 1. SSH to Your Server
```bash
ssh user@rlms.rlms.co.za
```

### 2. Navigate to Project
```bash
cd /path/to/your/rlmssv1
# Or wherever your mobile folder is located
```

### 3. Pull Latest Code
```bash
git pull origin main
```

### 4. Create config Directory (if it doesn't exist)
```bash
mkdir -p config
```

### 5. Create config/db.env File
```bash
nano config/db.env
```

### 6. Paste This Content
```env
# Database Configuration - PRODUCTION
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

**Save and exit:** Press `Ctrl+X`, then `Y`, then `Enter`

### 7. Secure the File
```bash
chmod 600 config/db.env
chown www-data:www-data config/db.env
```

### 8. Test Connection
```bash
php -r "include 'mobile/connection.php'; echo 'Connected: ' . \$conn->ping() . PHP_EOL;"
```

Should output: `Connected: 1`

### 9. Restart Web Server
```bash
# For Apache
sudo systemctl restart apache2

# Or for Nginx + PHP-FPM
sudo systemctl restart nginx
sudo systemctl restart php-fpm
```

### 10. Test Your App
Open your app and test login/data loading.

## 🔍 Troubleshooting

### Error: "config/db.env not found"
```bash
# Check if file exists
ls -la config/db.env

# If not, create it (see step 5-6 above)
```

### Error: "Failed to parse config/db.env"
```bash
# Check file contents
cat config/db.env

# Should be KEY=value format
# No spaces around =
# No special characters except in password
```

### Error: "Permission denied"
```bash
# Fix permissions
chmod 600 config/db.env
chown www-data:www-data config/db.env

# Check web server user
ps aux | grep apache2
# or
ps aux | grep nginx
```

### App Still Not Working
```bash
# Check PHP error log
tail -f /var/log/apache2/error.log
# or
tail -f /var/log/nginx/error.log

# Check if PHP can read the file
sudo -u www-data php -r "print_r(parse_ini_file('/full/path/to/config/db.env'));"
```

## 📂 File Locations

**PRODUCTION SERVER:**
- Config file: `/path/to/rlmssv1/config/db.env`
- Connection: `/path/to/rlmssv1/mobile/connection.php`
- API endpoints: `/path/to/rlmssv1/mobile/*.php`

**STAGING SERVER (if different):**
- Config file: `/path/to/rlmssv1/config/db.env.staging`
- Set: `export APP_ENV=staging`

## ✅ Verification Checklist

After deployment, verify:

- [ ] `config/db.env` exists on server
- [ ] File has correct credentials
- [ ] File permissions are 600
- [ ] PHP can read the file
- [ ] Database connection works
- [ ] App can login
- [ ] App can load data
- [ ] No errors in logs

## 🔐 Security Notes

**What Changed:**
- OLD: Credentials hardcoded in `mobile/connection.php`
- NEW: Credentials in `config/db.env` (not in git)

**Benefits:**
- ✅ Credentials never committed to git
- ✅ Different credentials per environment
- ✅ Easy to rotate passwords
- ✅ Secure file permissions

**NEVER:**
- ❌ Commit `config/db.env` to git
- ❌ Share credentials via email
- ❌ Use same password for staging/production
- ❌ Make file world-readable

## 📞 Need Help?

1. Check `DEPLOYMENT_SECURITY.md` for detailed guide
2. Check `config/README.md` for setup instructions
3. Test locally first with `php/connection.php`
4. Check server error logs

## 🎯 Quick Reference

```bash
# Create file
nano config/db.env

# Secure file  
chmod 600 config/db.env

# Test connection
php -r "include 'mobile/connection.php';"

# Check logs
tail -f /var/log/apache2/error.log
```
