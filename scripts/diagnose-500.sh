#!/usr/bin/env bash
# =============================================================================
# diagnose-500.sh
# WordPress HTTP 500 Internal Server Error — Root Cause Diagnostic
#
# Usage:  ./diagnose-500.sh /path/to/wordpress
# Output: Colour-coded findings with a recommended first action for each issue.
#
# What it checks (in order of most common cause):
#   1. PHP error log for fatal errors
#   2. WordPress debug log (if WP_DEBUG_LOG is enabled)
#   3. Memory limit in wp-config.php
#   4. .htaccess for corruption patterns
#   5. Recently modified plugin files (potential conflict source)
# =============================================================================

set -euo pipefail

# ── Colour codes ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Argument validation ───────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Usage: $0 /path/to/wordpress${RESET}"
    exit 1
fi

WP_ROOT="${1%/}"   # strip trailing slash

if [[ ! -f "$WP_ROOT/wp-config.php" ]]; then
    echo -e "${RED}ERROR: wp-config.php not found at $WP_ROOT${RESET}"
    echo "Make sure you are passing the WordPress root directory."
    exit 1
fi

FINDINGS=0

# ── Helper functions ──────────────────────────────────────────────────────────
header() {
    echo ""
    echo -e "${CYAN}${BOLD}── $1 ──${RESET}"
}

found() {
    echo -e "  ${RED}[FOUND]${RESET}  $1"
    FINDINGS=$((FINDINGS + 1))
}

ok() {
    echo -e "  ${GREEN}[OK]${RESET}     $1"
}

warn() {
    echo -e "  ${YELLOW}[WARN]${RESET}   $1"
}

recommend() {
    echo -e "  ${BOLD}→ Action:${RESET} $1"
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}wp-support-toolkit / diagnose-500.sh${RESET}"
echo -e "WordPress root: ${CYAN}$WP_ROOT${RESET}"
echo -e "Timestamp:      $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "────────────────────────────────────────────────────────────────"

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 1: PHP Error Log
# Common locations for NGINX + PHP-FPM stacks (adjust for your server layout)
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 1: PHP Error Log"

PHP_LOG_PATHS=(
    "/var/log/nginx/error.log"
    "/var/log/php-fpm/error.log"
    "/var/log/php/error.log"
    "/var/log/apache2/error.log"
    "$WP_ROOT/error_log"
    "/tmp/php_errors.log"
)

PHP_LOG_FOUND=""
for log in "${PHP_LOG_PATHS[@]}"; do
    if [[ -f "$log" && -r "$log" ]]; then
        PHP_LOG_FOUND="$log"
        break
    fi
done

if [[ -n "$PHP_LOG_FOUND" ]]; then
    ok "Log file found: $PHP_LOG_FOUND"
    echo ""
    echo -e "  ${BOLD}Last 30 lines containing errors:${RESET}"
    echo "  ─────────────────────────────────"

    # Extract PHP fatal/warning lines, deduplicate, show last 30
    ERRORS=$(grep -i -E "PHP (Fatal|Error|Warning|Parse)" "$PHP_LOG_FOUND" 2>/dev/null | tail -30 || true)

    if [[ -n "$ERRORS" ]]; then
        found "PHP errors detected in $PHP_LOG_FOUND"
        echo "$ERRORS" | while IFS= read -r line; do
            echo "  $line"
        done
        recommend "Fix the PHP Fatal error shown above. The file path and line number are in the log."
    else
        ok "No PHP Fatal errors in last 30 log entries."
    fi
else
    warn "No readable PHP error log found at standard paths."
    recommend "Run: php -i | grep error_log  — to find where PHP is writing errors on this server."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 2: WordPress Debug Log
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 2: WordPress Debug Log (wp-content/debug.log)"

DEBUG_LOG="$WP_ROOT/wp-content/debug.log"

if [[ -f "$DEBUG_LOG" ]]; then
    LOG_SIZE=$(du -sh "$DEBUG_LOG" 2>/dev/null | cut -f1)
    ok "debug.log exists (size: $LOG_SIZE)"
    echo ""
    echo -e "  ${BOLD}Last 20 entries:${RESET}"
    echo "  ─────────────────────────────────"
    tail -20 "$DEBUG_LOG" | while IFS= read -r line; do
        echo "  $line"
    done
    found "Active debug.log — review errors above."
    recommend "Identify the plugin or theme causing the error from the file path in the log."
else
    warn "debug.log not found. WP_DEBUG_LOG may be disabled."
    recommend "Add to wp-config.php: define('WP_DEBUG', true); define('WP_DEBUG_LOG', true); define('WP_DEBUG_DISPLAY', false);"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 3: PHP Memory Limit
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 3: PHP Memory Limit (wp-config.php)"

WP_MEMORY=$(grep "WP_MEMORY_LIMIT" "$WP_ROOT/wp-config.php" 2>/dev/null || true)
MAX_MEMORY=$(grep "WP_MAX_MEMORY_LIMIT" "$WP_ROOT/wp-config.php" 2>/dev/null || true)

if [[ -n "$WP_MEMORY" ]]; then
    ok "WP_MEMORY_LIMIT defined: $WP_MEMORY"
else
    warn "WP_MEMORY_LIMIT not explicitly set in wp-config.php (WordPress default: 40M)."
    recommend "Add to wp-config.php: define('WP_MEMORY_LIMIT', '256M');"
fi

if [[ -n "$MAX_MEMORY" ]]; then
    ok "WP_MAX_MEMORY_LIMIT defined: $MAX_MEMORY"
fi

# Also check PHP's own memory_limit
PHP_MEM=$(php -r "echo ini_get('memory_limit');" 2>/dev/null || echo "unknown")
echo -e "  PHP memory_limit (server):  ${BOLD}$PHP_MEM${RESET}"

if [[ "$PHP_MEM" == "32M" || "$PHP_MEM" == "40M" || "$PHP_MEM" == "64M" ]]; then
    found "Low PHP memory limit ($PHP_MEM) — likely cause of 500 errors on resource-heavy sites."
    recommend "Increase memory_limit in php.ini or php-fpm pool config to 256M or higher."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 4: .htaccess Integrity
# (Only relevant on Apache; on NGINX this file is ignored)
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 4: .htaccess File"

HTACCESS="$WP_ROOT/.htaccess"

if [[ -f "$HTACCESS" ]]; then
    ok ".htaccess found."

    # Check for WordPress standard rewrite rules
    if grep -q "BEGIN WordPress" "$HTACCESS" 2>/dev/null; then
        ok "Standard WordPress rewrite block present."
    else
        found "WordPress rewrite block missing from .htaccess."
        recommend "Regenerate .htaccess: wp rewrite flush --hard"
    fi

    # Check for suspicious injected code (common after a hack)
    SUSPICIOUS=$(grep -i -E "(eval\(|base64_decode|gzinflate|rot13|exec\(|system\(|passthru)" "$HTACCESS" 2>/dev/null || true)
    if [[ -n "$SUSPICIOUS" ]]; then
        found "SUSPICIOUS CODE detected in .htaccess — possible compromise."
        echo "  $SUSPICIOUS"
        recommend "Immediately replace .htaccess with a clean WordPress default and run security-audit.sh"
    else
        ok "No suspicious patterns found in .htaccess."
    fi
else
    warn ".htaccess not found. If running Apache, WordPress permalinks may be broken."
    recommend "Regenerate: wp rewrite flush --hard"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 5: Recently Modified Plugin Files
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 5: Recently Modified Plugin Files (last 24h)"

PLUGINS_DIR="$WP_ROOT/wp-content/plugins"

if [[ -d "$PLUGINS_DIR" ]]; then
    RECENT=$(find "$PLUGINS_DIR" -name "*.php" -mtime -1 -type f 2>/dev/null | head -20 || true)

    if [[ -n "$RECENT" ]]; then
        warn "PHP files modified in the last 24 hours:"
        echo "$RECENT" | while IFS= read -r file; do
            echo "  $file"
        done
        found "Recent plugin file changes detected — potential conflict source."
        recommend "Identify which plugin was updated and deactivate it to test: wp plugin deactivate PLUGIN_SLUG"
    else
        ok "No plugin files modified in the last 24 hours."
    fi
else
    warn "wp-content/plugins directory not found at expected path."
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
if [[ $FINDINGS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}No definitive causes found.${RESET}"
    echo "Next steps:"
    echo "  1. Enable WP_DEBUG_LOG and reproduce the error to capture the stack trace."
    echo "  2. Deactivate all plugins via WP-CLI: wp plugin deactivate --all"
    echo "  3. Switch to a default theme: wp theme activate twentytwentyfour"
    echo "  4. Re-enable plugins one by one to isolate the conflict."
else
    echo -e "${RED}${BOLD}$FINDINGS finding(s) require attention.${RESET} Review recommended actions above."
fi
echo "════════════════════════════════════════════════════════════════"
echo ""
