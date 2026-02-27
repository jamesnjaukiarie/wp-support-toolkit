#!/usr/bin/env bash
# =============================================================================
# diagnose-502.sh
# WordPress 502 Bad Gateway — PHP-FPM / NGINX Upstream Diagnostic
#
# Usage:  ./diagnose-502.sh
# Output: PHP-FPM status, upstream errors from NGINX log, resource state.
#
# A 502 means NGINX received no valid response from the PHP-FPM upstream.
# Root causes in order of frequency:
#   1. PHP-FPM process has crashed or is not running
#   2. PHP-FPM worker pool exhausted (too many requests, too few workers)
#   3. PHP execution timeout (slow query or loop blocking a worker)
#   4. Resource exhaustion (OOM kill of PHP-FPM by the kernel)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

FINDINGS=0

header() { echo ""; echo -e "${CYAN}${BOLD}── $1 ──${RESET}"; }
found()  { echo -e "  ${RED}[FOUND]${RESET}  $1"; FINDINGS=$((FINDINGS + 1)); }
ok()     { echo -e "  ${GREEN}[OK]${RESET}     $1"; }
warn()   { echo -e "  ${YELLOW}[WARN]${RESET}   $1"; }
recommend() { echo -e "  ${BOLD}→ Action:${RESET} $1"; }

echo ""
echo -e "${BOLD}wp-support-toolkit / diagnose-502.sh${RESET}"
echo -e "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "────────────────────────────────────────────────────────────────"

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 1: PHP-FPM Service Status
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 1: PHP-FPM Service Status"

# Detect installed PHP-FPM version
PHP_FPM_SERVICE=""
for ver in php8.2-fpm php8.1-fpm php8.0-fpm php7.4-fpm php-fpm; do
    if systemctl list-units --type=service 2>/dev/null | grep -q "$ver"; then
        PHP_FPM_SERVICE="$ver"
        break
    fi
done

if [[ -z "$PHP_FPM_SERVICE" ]]; then
    warn "Could not auto-detect PHP-FPM service name."
    recommend "Run: systemctl list-units | grep fpm  — to find the correct service name."
else
    STATUS=$(systemctl is-active "$PHP_FPM_SERVICE" 2>/dev/null || echo "unknown")

    if [[ "$STATUS" == "active" ]]; then
        ok "PHP-FPM service ($PHP_FPM_SERVICE) is running."
    elif [[ "$STATUS" == "failed" ]]; then
        found "PHP-FPM service ($PHP_FPM_SERVICE) has FAILED."
        recommend "Restart immediately: sudo systemctl restart $PHP_FPM_SERVICE"
        recommend "Then check why it failed: sudo journalctl -u $PHP_FPM_SERVICE -n 50"
    else
        found "PHP-FPM service ($PHP_FPM_SERVICE) is NOT active (status: $STATUS)."
        recommend "Start the service: sudo systemctl start $PHP_FPM_SERVICE"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 2: NGINX Error Log — Upstream Failures
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 2: NGINX Error Log — Upstream Errors"

NGINX_LOG="/var/log/nginx/error.log"

if [[ -f "$NGINX_LOG" && -r "$NGINX_LOG" ]]; then
    ok "NGINX error log found: $NGINX_LOG"
    echo ""

    # Extract upstream-related errors from the last 200 lines
    UPSTREAM_ERRORS=$(grep -i -E "(upstream|connect() failed|Connection refused|no live upstreams|timed out)" \
        "$NGINX_LOG" 2>/dev/null | tail -20 || true)

    if [[ -n "$UPSTREAM_ERRORS" ]]; then
        found "Upstream errors found in NGINX error log:"
        echo ""
        echo "$UPSTREAM_ERRORS" | while IFS= read -r line; do
            echo "  $line"
        done
        echo ""
        recommend "These errors confirm PHP-FPM is not responding. Restart PHP-FPM and investigate the cause."
    else
        ok "No upstream connection errors in recent NGINX log entries."
    fi

    # Check for timeout patterns specifically
    TIMEOUTS=$(grep -i "upstream timed out" "$NGINX_LOG" 2>/dev/null | tail -5 || true)
    if [[ -n "$TIMEOUTS" ]]; then
        found "PHP-FPM timeout errors detected — PHP is taking too long to respond."
        recommend "Check for slow MySQL queries or infinite loops in plugin code."
        recommend "Increase fastcgi_read_timeout in NGINX config if queries are legitimately slow."
    fi
else
    warn "NGINX error log not found at $NGINX_LOG or not readable."
    recommend "Check NGINX config for error_log path: nginx -T | grep error_log"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 3: PHP-FPM Pool Configuration
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 3: PHP-FPM Pool Configuration"

FPM_CONF_PATHS=(
    "/etc/php/8.2/fpm/pool.d/www.conf"
    "/etc/php/8.1/fpm/pool.d/www.conf"
    "/etc/php/8.0/fpm/pool.d/www.conf"
    "/etc/php/7.4/fpm/pool.d/www.conf"
    "/etc/php-fpm.d/www.conf"
)

FPM_CONF=""
for conf in "${FPM_CONF_PATHS[@]}"; do
    if [[ -f "$conf" ]]; then
        FPM_CONF="$conf"
        break
    fi
done

if [[ -n "$FPM_CONF" ]]; then
    ok "PHP-FPM pool config found: $FPM_CONF"

    MAX_CHILDREN=$(grep "^pm.max_children" "$FPM_CONF" 2>/dev/null | awk '{print $3}' || echo "not set")
    PM_MODE=$(grep "^pm " "$FPM_CONF" 2>/dev/null | awk '{print $3}' || echo "not set")
    REQUEST_TIMEOUT=$(grep "^request_terminate_timeout" "$FPM_CONF" 2>/dev/null | awk '{print $3}' || echo "not set")

    echo -e "  pm (process manager):        ${BOLD}$PM_MODE${RESET}"
    echo -e "  pm.max_children:             ${BOLD}$MAX_CHILDREN${RESET}"
    echo -e "  request_terminate_timeout:   ${BOLD}$REQUEST_TIMEOUT${RESET}"

    # Low max_children is a common 502 cause under load
    if [[ "$MAX_CHILDREN" =~ ^[0-9]+$ && "$MAX_CHILDREN" -lt 5 ]]; then
        found "pm.max_children is very low ($MAX_CHILDREN). Pool may be exhausted under normal load."
        recommend "Increase pm.max_children based on available RAM. Rule of thumb: RAM_MB / 50 = max_children."
        recommend "After editing, reload: sudo systemctl reload $PHP_FPM_SERVICE"
    fi
else
    warn "PHP-FPM pool config not found at standard paths."
    recommend "Locate config manually: find /etc -name 'www.conf' 2>/dev/null"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 4: System Resource State
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 4: System Resource State"

# Memory
TOTAL_MEM=$(free -m 2>/dev/null | awk 'NR==2{print $2}' || echo "unknown")
USED_MEM=$(free -m 2>/dev/null | awk 'NR==2{print $3}' || echo "unknown")
FREE_MEM=$(free -m 2>/dev/null | awk 'NR==2{print $4}' || echo "unknown")

echo -e "  Memory (MB):  total=$TOTAL_MEM  used=$USED_MEM  free=$FREE_MEM"

if [[ "$FREE_MEM" =~ ^[0-9]+$ && "$FREE_MEM" -lt 50 ]]; then
    found "Very low free memory ($FREE_MEM MB). Kernel may be killing PHP-FPM workers (OOM kill)."
    recommend "Check OOM kills: dmesg | grep -i 'oom\|killed process' | tail -10"
fi

# CPU Load
LOAD=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | sed 's/^ //' || echo "unknown")
echo -e "  Load average: $LOAD"

# Disk space
DISK=$(df -h / 2>/dev/null | awk 'NR==2{print "used="$3" available="$4" percent="$5}' || echo "unknown")
echo -e "  Disk (/):     $DISK"

DISK_PCT=$(df / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%' || echo "0")
if [[ "$DISK_PCT" =~ ^[0-9]+$ && "$DISK_PCT" -gt 90 ]]; then
    found "Disk usage is at ${DISK_PCT}% — a full disk will crash PHP-FPM and cause 502 errors."
    recommend "Free disk space: clear logs, WordPress cache, and old backups."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 5: OOM Kill History
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 5: OOM Kill History"

OOM=$(dmesg 2>/dev/null | grep -i "oom\|killed process" | tail -5 || true)
if [[ -n "$OOM" ]]; then
    found "Kernel OOM kills detected in dmesg:"
    echo "$OOM" | while IFS= read -r line; do echo "  $line"; done
    recommend "PHP-FPM was killed by the OS due to memory pressure. Increase server RAM or reduce pm.max_children."
else
    ok "No OOM kills found in dmesg."
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo -e "${BOLD}Quick Recovery Commands:${RESET}"
echo ""
echo "  Restart PHP-FPM (most common fix):"

if [[ -n "$PHP_FPM_SERVICE" ]]; then
    echo "    sudo systemctl restart $PHP_FPM_SERVICE"
else
    echo "    sudo systemctl restart php8.1-fpm   # adjust version number"
fi

echo ""
echo "  Reload NGINX (if config was changed):"
echo "    sudo systemctl reload nginx"
echo ""
echo "  Monitor PHP-FPM logs live:"
echo "    sudo journalctl -u ${PHP_FPM_SERVICE:-php-fpm} -f"
echo ""

if [[ $FINDINGS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}No definitive causes identified.${RESET}"
    echo "If the 502 is intermittent, it is likely a worker pool capacity issue under load."
    echo "Consider increasing pm.max_children in the FPM pool config."
else
    echo -e "${RED}${BOLD}$FINDINGS finding(s) identified.${RESET} Follow recommended actions above."
fi
echo "════════════════════════════════════════════════════════════════"
echo ""
