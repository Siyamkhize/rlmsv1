# 🔒 Secure Database Configuration

## Overview
Database credentials are stored in `.env` files that are **NEVER** committed to git.

## Setup Instructions

### 1. Create Your Environment File

```bash
# Copy the example file
cp db.env.example db.env

# Edit with your actual credentials
nano db.env  # or use any text editor
```

### 2. Configure Credentials

Edit `db.env` and replace with your actual values:

```env
DB_HOST=localhost
DB_USERNAME=your_actual_username
DB_PASSWORD=your_actual_password
DB_NAME=your_actual_database
DB_TABLE=sdp
DB_CHARSET=utf8mb4
DB_TIMEZONE=+02:00

APP_ENV=production
APP_DEBUG=false
```

### 3. Secure File Permissions (Linux/Mac)

```bash
# Make file readable only by owner
chmod 600 config/db.env
```

### 4. Verify Setup

The connection files will automatically load from `config/db.env`:
- `mobile/connection.php`
- `php/connection.php`

## Multiple Environments

### Production
```bash
cp db.env.example db.env
# Configure production credentials
```

### Staging
```bash
cp db.env.example db.env.staging
# Configure staging credentials
export APP_ENV=staging
```

### Local Development
```bash
cp db.env.example db.env.development
# Configure local credentials
export APP_ENV=development
```

## Security Best Practices

✅ **DO:**
- Keep `.env` files outside web root
- Use strong, unique passwords
- Set restrictive file permissions (600)
- Use different credentials per environment
- Rotate passwords regularly

❌ **DON'T:**
- Commit `.env` files to git
- Share credentials via email/chat
- Use production credentials locally
- Hardcode credentials in PHP files

## Git Protection

The `.gitignore` is configured to block:
- `config/db.env`
- `config/db.env.*`
- `.env`
- `*.env`

**Exception:** `*.env.example` files ARE committed (templates only, no real credentials)

## Troubleshooting

### "config/db.env not found"
```bash
cp config/db.env.example config/db.env
# Edit config/db.env with your credentials
```

### "Failed to parse config/db.env"
Check file format - must be:
```
KEY=value
# Comments start with #
```

### "Database connection failed"
1. Verify credentials in `config/db.env`
2. Check database server is running
3. Test connection: `mysql -u username -p database_name`

## Support

For issues, check:
1. File exists: `config/db.env`
2. File permissions: `ls -la config/db.env`
3. PHP can read file: `php -r "print_r(parse_ini_file('config/db.env'));"`
4. Database server: `mysql -u username -p`
