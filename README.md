# wp-support-toolkit

A practical collection of diagnostic scripts, WP-CLI references, and PHP configuration snippets for resolving common WordPress hosting issues at the server level.

Built for engineers who support WordPress on managed hosting infrastructure (NGINX + PHP-FPM + MySQL). Each tool is focused on a specific failure mode and designed to be run from an SSH session under time pressure.

---

## Contents

| Path | Purpose |
|------|---------|
| `scripts/diagnose-500.sh` | Isolate the root cause of HTTP 500 errors |
| `scripts/diagnose-502.sh` | Identify and recover from PHP-FPM / 502 Bad Gateway failures |
| `scripts/migration-fix.sh` | Fix URL mismatches and configuration issues after a site migration |
| `scripts/security-audit.sh` | Surface indicators of compromise on a WordPress installation |
| `php-snippets/debug-config.php` | Safe wp-config.php debug constants with environment guard |
| `wpcli/cheatsheet.md` | WP-CLI commands organised by support scenario |

---

## Diagnostic Scripts

### `diagnose-500.sh` — HTTP 500 Internal Server Error

A 500 error on WordPress almost always originates from one of four sources: a PHP fatal error, an exhausted memory limit, a corrupted `.htaccess` file, or a plugin conflict. This script checks all four in sequence and outputs a prioritised finding.

**What it checks:**
- PHP error log for fatal errors (last 50 lines)
- `wp-config.php` for `WP_MEMORY_LIMIT` value
- `.htaccess` for common corruption patterns
- Most recently modified plugin files (potential conflict source)
- WordPress debug log if `WP_DEBUG_LOG` is enabled

**Usage:**
```bash
chmod +x scripts/diagnose-500.sh
./scripts/diagnose-500.sh /var/www/html
```

**Output:** Colour-coded findings with a recommended first action for each issue found.

---

### `diagnose-502.sh` — 502 Bad Gateway

A 502 means NGINX received no valid response from the PHP-FPM upstream. The cause is almost always a crashed PHP-FPM process, an exhausted worker pool, or a timeout caused by a slow PHP execution. This script checks the live state of PHP-FPM and surfaces the cause from logs before you restart anything.

**What it checks:**
- PHP-FPM service status via `systemctl`
- NGINX error log for upstream connect failures
- PHP-FPM pool configuration (max children, timeout values)
- System memory and CPU to rule out resource exhaustion

**Usage:**
```bash
chmod +x scripts/diagnose-502.sh
./scripts/diagnose-502.sh
```

---

### `migration-fix.sh` — Post-Migration URL and Configuration Fix

The most common issues after migrating a WordPress site to a new host or domain are: wrong `siteurl`/`home` values in the database, hardcoded HTTP URLs causing mixed content, and `wp-config.php` still referencing the old database or domain. This script audits all three and optionally runs the fixes via WP-CLI.

**What it fixes:**
- Detects mismatched `siteurl` and `home` in `wp_options`
- Runs `wp search-replace` to update old domain references across all tables
- Checks `wp-config.php` for hardcoded old domain strings
- Flushes rewrite rules and all caches after correction

**Usage:**
```bash
chmod +x scripts/migration-fix.sh
./scripts/migration-fix.sh /var/www/html https://olddomain.com https://newdomain.com
```

---

### `security-audit.sh` — WordPress Compromise Indicators

When a customer reports their site has been hacked, the first priority is establishing the scope of compromise before touching anything. This script surfaces the most common indicators without modifying any files.

**What it checks:**
- Files modified in the last 7 days outside of core update patterns
- Unknown administrator accounts in `wp_users`
- Presence of PHP files in the uploads directory (common backdoor location)
- Known malicious patterns in active plugin files (`eval(base64_decode`, `system(`, `exec(`)
- `wp-config.php` for added malicious code blocks

**Usage:**
```bash
chmod +x scripts/security-audit.sh
./scripts/security-audit.sh /var/www/html
```

> **Note:** This script is read-only. It does not delete or modify any files. All findings are written to stdout and optionally to a log file.

---

## PHP Snippets

### `php-snippets/debug-config.php`

A safe, annotated block of `wp-config.php` debug constants for diagnosing PHP errors in WordPress. Includes an environment guard that prevents debug output from being exposed on production sites if accidentally left enabled.

**Constants covered:**

| Constant | Purpose |
|----------|---------|
| `WP_DEBUG` | Enables the WordPress debug mode |
| `WP_DEBUG_LOG` | Writes errors to `/wp-content/debug.log` |
| `WP_DEBUG_DISPLAY` | Controls whether errors render in the browser |
| `SCRIPT_DEBUG` | Forces WordPress to use unminified JS/CSS |
| `SAVEQUERIES` | Logs all database queries (use with Query Monitor) |

---

## WP-CLI Reference

### `wpcli/cheatsheet.md`

WP-CLI commands organised by the support scenario you are trying to resolve — not alphabetically. Covers: site down recovery, post-migration fixes, user and password management, cache management, database operations, and cron debugging.

---

## When to Use This Toolkit

| Symptom | Start Here |
|---------|-----------|
| White screen / blank page | `diagnose-500.sh` |
| 500 Internal Server Error | `diagnose-500.sh` |
| 502 Bad Gateway | `diagnose-502.sh` |
| Site loads but shows old domain | `migration-fix.sh` |
| "Not secure" warning after migration | `migration-fix.sh` then check SSL |
| Suspected hack or malware | `security-audit.sh` |
| Can't login / unknown admin accounts | `security-audit.sh` + `wpcli/cheatsheet.md` |

---

## Requirements

- Linux server with Bash 4+
- SSH access to the WordPress installation
- WP-CLI installed (`wp-cli.org`) for scripts that use WP-CLI commands
- PHP 7.4+ / MySQL 5.7+ (standard on modern managed hosting)

---

## Author

James N. Kiarie — WordPress Support Engineer  
[linkedin.com/in/james-kiarie-3098a2154](https://linkedin.com/in/james-kiarie-3098a2154) · [profiles.wordpress.org/jamesgreat](https://profiles.wordpress.org/jamesgreat)
