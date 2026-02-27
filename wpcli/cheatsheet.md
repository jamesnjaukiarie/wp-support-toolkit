# WP-CLI Support Cheatsheet

Commands organised by the support scenario you are trying to resolve — not alphabetically.

All commands assume you are in the WordPress root directory or using `--path=/var/www/html`.  
For server environments requiring root: append `--allow-root` to any command.

---

## Site Is Down / White Screen of Death

```bash
# Deactivate ALL plugins immediately (fastest WSOD isolation step)
wp plugin deactivate --all

# Reactivate plugins one at a time to find the conflict
wp plugin activate contact-form-7
wp plugin activate woocommerce

# Switch to a default WordPress theme
wp theme activate twentytwentyfour

# Check WordPress version and core integrity
wp core version
wp core verify-checksums          # detects modified or missing core files

# Re-download and replace corrupted core files (does not touch wp-config or content)
wp core download --force --skip-content

# Check for PHP errors in the WordPress debug log
wp eval 'error_log("test");'
tail -20 wp-content/debug.log
```

---

## Post-Migration URL Fix

```bash
# Check current siteurl and home values in the database
wp option get siteurl
wp option get home

# Update siteurl and home directly
wp option update siteurl 'https://newdomain.com'
wp option update home 'https://newdomain.com'

# Replace old domain across every table (the correct migration fix)
wp search-replace 'https://olddomain.com' 'https://newdomain.com' --all-tables

# Preview what will change before running (dry run)
wp search-replace 'https://olddomain.com' 'https://newdomain.com' --all-tables --dry-run

# If migrating from HTTP to HTTPS (same domain)
wp search-replace 'http://example.com' 'https://example.com' --all-tables

# Fix broken permalinks after migration
wp rewrite flush --hard
```

---

## Cache Management

```bash
# Flush the WordPress object cache (Redis, Memcached, or database cache)
wp cache flush

# Delete all transients stored in the database
wp transient delete --all

# Delete a specific transient by name
wp transient delete feed_cache

# List all transients (useful for diagnosing bloated wp_options)
wp transient list

# Flush rewrite rules (fixes 404 on posts after migration or permalink change)
wp rewrite flush --hard

# Run all due cron jobs immediately (useful for debugging stuck cron tasks)
wp cron event run --due-now

# List all scheduled cron events
wp cron event list
```

---

## Database Operations

```bash
# Export the full database
wp db export /tmp/backup-$(date +%Y%m%d).sql

# Export a specific table only
wp db export /tmp/wp_posts.sql --tables=wp_posts

# Import a database dump
wp db import /tmp/backup.sql

# Optimise all tables (reduces overhead after deleting many rows)
wp db optimize

# Check all tables for corruption
wp db check

# Repair corrupted tables
wp db repair

# Run a raw SQL query
wp db query "SELECT option_name, option_value FROM wp_options WHERE option_name IN ('siteurl','home');"

# Count total posts by status
wp db query "SELECT post_status, COUNT(*) as count FROM wp_posts GROUP BY post_status;"

# Find and delete all auto-draft posts (reduces table bloat)
wp db query "DELETE FROM wp_posts WHERE post_status = 'auto-draft';"

# Delete all post revisions (run with caution on production)
wp post delete $(wp post list --post_type=revision --fields=ID --format=ids) --force
```

---

## User and Password Management

```bash
# List all users with their roles
wp user list

# List only administrator accounts
wp user list --role=administrator

# Reset a user's password by ID
wp user update 1 --user_pass='NewSecurePassword123!'

# Create a new administrator (emergency access recovery)
wp user create recovery recovery@example.com --role=administrator --user_pass='TempPass123!'

# Delete a suspicious admin account (reassign content to user ID 1)
wp user delete 99 --reassign=1

# Get a user's details by login name
wp user get admin

# Check what capabilities a user has
wp user get admin --fields=ID,user_login,roles
```

---

## Performance Diagnostics

```bash
# Check if object cache is active
wp eval 'echo ( wp_using_ext_object_cache() ) ? "External cache active" : "No external cache";'

# Measure the time a specific WP-CLI command takes
time wp post list --post_type=post --posts_per_page=100 --format=count

# List all options in wp_options that are autoloaded (can cause slow queries)
wp db query "SELECT option_name, LENGTH(option_value) as size FROM wp_options WHERE autoload='yes' ORDER BY size DESC LIMIT 20;"

# Identify large autoloaded options (values over 10KB are candidates for review)
wp db query "SELECT option_name, LENGTH(option_value) as bytes FROM wp_options WHERE autoload='yes' AND LENGTH(option_value) > 10000 ORDER BY bytes DESC;"
```

---

## Security

```bash
# List all admin accounts (check for unknown users)
wp user list --role=administrator --fields=ID,user_login,user_email,user_registered

# Check for users with the 'administrator' capability set directly in usermeta
wp db query "SELECT user_id, meta_value FROM wp_usermeta WHERE meta_key='wp_capabilities' AND meta_value LIKE '%administrator%';"

# Update the WordPress secret keys in wp-config.php
# (Do this after a suspected compromise — invalidates all active sessions)
wp config shuffle-salts

# Check if file editing is disabled
wp config get DISALLOW_FILE_EDIT

# Verify WordPress core file integrity
wp core verify-checksums

# Verify plugin file integrity against WordPress.org checksums
wp plugin verify-checksums --all
```

---

## Plugin and Theme Management

```bash
# List all plugins with their status and version
wp plugin list

# List only active plugins
wp plugin list --status=active

# Update a specific plugin
wp plugin update woocommerce

# Update all plugins at once
wp plugin update --all

# Install a plugin from WordPress.org
wp plugin install query-monitor --activate

# Delete a plugin completely (not just deactivate)
wp plugin delete hello-dolly

# List all themes
wp theme list

# Get the currently active theme
wp theme list --status=active
```

---

## Multisite

```bash
# List all sites in a network
wp site list

# Create a new subsite
wp site create --slug=newsite --title='New Site' --email=admin@example.com

# Run a command across all sites in a network
wp site list --field=url | xargs -I % wp --url=% cache flush

# Export the database for a specific subsite
wp db export /tmp/subsite.sql --url=https://network.com/subsite
```

---

## Quick Reference: Most Used Commands

| Scenario | Command |
|----------|---------|
| Site down — isolate plugin | `wp plugin deactivate --all` |
| WSOD — check error log | `tail -50 wp-content/debug.log` |
| Migration — fix URLs | `wp search-replace 'old.com' 'new.com' --all-tables` |
| 404 errors after migration | `wp rewrite flush --hard` |
| Slow site — flush cache | `wp cache flush && wp transient delete --all` |
| Can't log in | `wp user update 1 --user_pass='NewPass'` |
| Check site URL | `wp option get siteurl` |
| Backup database | `wp db export /tmp/backup.sql` |
| Verify core files | `wp core verify-checksums` |
| Check for unknown admins | `wp user list --role=administrator` |
