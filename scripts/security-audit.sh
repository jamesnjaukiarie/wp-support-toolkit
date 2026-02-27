#!/usr/bin/env bash
# =============================================================================
# security-audit.sh
# WordPress Compromise Indicator Scan — Read-Only
#
# Usage:  ./security-audit.sh /path/to/wordpress [--log /path/to/output.log]
#
# This script is READ-ONLY. It does not delete, modify, or quarantine anything.
# All findings are written to stdout and optionally to a log file.
#
# What it checks:
#   1. PHP files modified in the last 7 days (outside of core update patterns)
#   2. PHP files in wp-content/uploads (no PHP should ever be there)
#   3. Unknown administrator accounts in wp_users
#   4. Known malicious code patterns in plugin/theme PHP files
#   5. wp-config.php for injected code blocks
#   6. .htaccess for redirect injections
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

FINDINGS=0
LOG_FILE=""

header()    { echo ""; echo -e "${CYAN}${BOLD}── $1 ──${RESET}"; [[ -n "$LOG_FILE" ]] && echo "── $1 ──" >> "$LOG_FILE"; }
found()     { echo -e "  ${RED}[FOUND]${RESET}  $1"; FINDINGS=$((FINDINGS + 1)); [[ -n "$LOG_FILE" ]] && echo "  [FOUND]  $1" >> "$LOG_FILE"; }
ok()        { echo -e "  ${GREEN}[OK]${RESET}     $1"; }
warn()      { echo -e "  ${YELLOW}[WARN]${RESET}   $1"; }
recommend() { echo -e "  ${BOLD}→ Action:${RESET} $1"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Usage: $0 /path/to/wordpress [--log /path/to/output.log]${RESET}"
    exit 1
fi

WP_ROOT="${1%/}"

if [[ "${2:-}" == "--log" && -n "${3:-}" ]]; then
    LOG_FILE="${3}"
    touch "$LOG_FILE"
fi

if [[ ! -f "$WP_ROOT/wp-config.php" ]]; then
    echo -e "${RED}ERROR: wp-config.php not found at $WP_ROOT${RESET}"
    exit 1
fi

echo ""
echo -e "${BOLD}wp-support-toolkit / security-audit.sh${RESET}"
echo -e "WordPress root: ${CYAN}$WP_ROOT${RESET}"
echo -e "Timestamp:      $(date '+%Y-%m-%d %H:%M:%S %Z')"
[[ -n "$LOG_FILE" ]] && echo -e "Log file:       ${CYAN}$LOG_FILE${RESET}"
echo -e "${YELLOW}This scan is read-only. No files will be modified.${RESET}"
echo "────────────────────────────────────────────────────────────────"

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 1: PHP Files Modified in the Last 7 Days
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 1: PHP Files Modified in Last 7 Days (excluding wp-admin, wp-includes)"

RECENT_MODIFIED=$(find "$WP_ROOT/wp-content" -name "*.php" -mtime -7 -type f 2>/dev/null \
    | grep -v "/cache/" \
    | sort || true)

COUNT=$(echo "$RECENT_MODIFIED" | grep -c "\.php" 2>/dev/null || echo 0)

if [[ "$COUNT" -gt 0 ]]; then
    warn "$COUNT PHP file(s) modified in the last 7 days:"
    echo ""
    echo "$RECENT_MODIFIED" | while IFS= read -r file; do
        MTIME=$(stat -c '%y' "$file" 2>/dev/null | cut -d. -f1 || echo "unknown")
        echo "  [$MTIME]  $file"
    done
    echo ""
    recommend "Cross-reference against any plugin/theme updates from the same period."
    recommend "Unexpected modifications to core theme files or plugins are a red flag."
    FINDINGS=$((FINDINGS + 1))
else
    ok "No PHP files modified in the last 7 days in wp-content."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 2: PHP Files in uploads Directory
# PHP files have NO legitimate reason to be in wp-content/uploads.
# Their presence is a near-certain indicator of a backdoor.
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 2: PHP Files in wp-content/uploads (Backdoor Indicator)"

UPLOADS_DIR="$WP_ROOT/wp-content/uploads"

if [[ -d "$UPLOADS_DIR" ]]; then
    PHP_IN_UPLOADS=$(find "$UPLOADS_DIR" -name "*.php" -type f 2>/dev/null || true)

    if [[ -n "$PHP_IN_UPLOADS" ]]; then
        found "PHP file(s) detected in uploads directory — LIKELY BACKDOOR:"
        echo ""
        echo "$PHP_IN_UPLOADS" | while IFS= read -r file; do
            echo -e "  ${RED}$file${RESET}"
        done
        echo ""
        recommend "Do NOT execute these files. Quarantine immediately."
        recommend "Delete each file and check its contents for shell/exec patterns."
        recommend "Then identify how it was uploaded (vulnerable plugin or theme)."
    else
        ok "No PHP files found in uploads directory."
    fi
else
    warn "Uploads directory not found at $UPLOADS_DIR"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 3: Malicious Code Patterns in Plugin and Theme Files
# These patterns are found in the vast majority of WordPress malware injections.
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 3: Malicious Code Patterns in Plugin/Theme PHP Files"

MALWARE_PATTERNS=(
    "eval(base64_decode"
    "eval(gzinflate"
    "eval(str_rot13"
    "assert(base64_decode"
    "\$_POST\['cmd'\]"
    "\$_GET\['cmd'\]"
    "passthru("
    "shell_exec("
    "system(\$_"
    "preg_replace.*\/e"
    "FilesMan"
    "WSO shell"
)

PLUGINS_THEMES_DIR="$WP_ROOT/wp-content"
MALWARE_FOUND=false

for pattern in "${MALWARE_PATTERNS[@]}"; do
    MATCHES=$(grep -rl "$pattern" "$PLUGINS_THEMES_DIR" \
        --include="*.php" 2>/dev/null \
        | grep -v "/cache/" || true)

    if [[ -n "$MATCHES" ]]; then
        found "Malicious pattern detected: ${BOLD}$pattern${RESET}"
        echo "$MATCHES" | while IFS= read -r file; do
            echo -e "    ${RED}$file${RESET}"
            # Show the matching line for context
            grep -n "$pattern" "$file" 2>/dev/null | head -3 | while IFS= read -r match_line; do
                echo "    Line: $match_line"
            done
        done
        MALWARE_FOUND=true
    fi
done

if [[ "$MALWARE_FOUND" == false ]]; then
    ok "No known malicious code patterns found in plugin/theme files."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 4: Unknown Admin Accounts
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 4: WordPress Administrator Accounts"

if command -v wp &>/dev/null; then
    echo ""
    echo -e "  ${BOLD}All administrator-level accounts:${RESET}"
    wp user list --role=administrator --fields=ID,user_login,user_email,user_registered \
        --path="$WP_ROOT" --allow-root 2>/dev/null \
        | while IFS= read -r line; do echo "  $line"; done

    ADMIN_COUNT=$(wp user list --role=administrator --path="$WP_ROOT" \
        --allow-root --format=count 2>/dev/null || echo "unknown")

    echo ""
    if [[ "$ADMIN_COUNT" =~ ^[0-9]+$ && "$ADMIN_COUNT" -gt 2 ]]; then
        warn "$ADMIN_COUNT administrator accounts found. Verify all are legitimate."
        recommend "Remove unknown admin accounts: wp user delete USER_ID --reassign=1 --path=$WP_ROOT"
        FINDINGS=$((FINDINGS + 1))
    else
        ok "$ADMIN_COUNT administrator account(s) found."
    fi
else
    warn "WP-CLI not available. Check administrator accounts manually via phpMyAdmin:"
    recommend "SELECT ID, user_login, user_email FROM wp_users u JOIN wp_usermeta m ON u.ID = m.user_id WHERE m.meta_key = 'wp_capabilities' AND m.meta_value LIKE '%administrator%';"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 5: wp-config.php Injected Code
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 5: wp-config.php Integrity"

# A standard wp-config.php should not contain base64, eval, or curl calls
WPCONFIG_SUSPICIOUS=$(grep -n -E "(base64_decode|eval\(|curl_exec|file_get_contents\(http)" \
    "$WP_ROOT/wp-config.php" 2>/dev/null || true)

if [[ -n "$WPCONFIG_SUSPICIOUS" ]]; then
    found "Suspicious code detected in wp-config.php:"
    echo "$WPCONFIG_SUSPICIOUS" | while IFS= read -r line; do
        echo -e "  ${RED}$line${RESET}"
    done
    recommend "Replace wp-config.php with a clean copy and restore only the DB credentials."
else
    ok "No suspicious patterns found in wp-config.php."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 6: .htaccess Redirect Injection
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 6: .htaccess Redirect Injection"

HTACCESS="$WP_ROOT/.htaccess"

if [[ -f "$HTACCESS" ]]; then
    # Look for redirect rules pointing to external domains
    REDIRECT_INJECT=$(grep -n -E "RewriteRule.*http[s]?://" "$HTACCESS" 2>/dev/null || true)

    if [[ -n "$REDIRECT_INJECT" ]]; then
        warn "External redirect rules found in .htaccess (review carefully):"
        echo "$REDIRECT_INJECT" | while IFS= read -r line; do
            echo "  $line"
        done
        recommend "Verify each redirect is intentional. Malicious redirects are a common SEO spam tactic."
        FINDINGS=$((FINDINGS + 1))
    else
        ok "No external redirect rules in .htaccess."
    fi

    # Look for eval/base64 injections
    HTACCESS_MALWARE=$(grep -n -E "(base64_decode|eval\()" "$HTACCESS" 2>/dev/null || true)
    if [[ -n "$HTACCESS_MALWARE" ]]; then
        found "Malicious code injected into .htaccess:"
        echo "$HTACCESS_MALWARE" | while IFS= read -r line; do
            echo -e "  ${RED}$line${RESET}"
        done
        recommend "Replace .htaccess with WordPress default and investigate the infection vector."
    fi
else
    warn ".htaccess not found at $WP_ROOT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"

if [[ $FINDINGS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}No compromise indicators found.${RESET}"
    echo "This scan covers common patterns but is not exhaustive."
    echo "For a thorough audit, run Wordfence or Sucuri in addition to this script."
else
    echo -e "${RED}${BOLD}$FINDINGS indicator(s) found.${RESET}"
    echo ""
    echo -e "${BOLD}Immediate actions if compromise is confirmed:${RESET}"
    echo "  1. Change all passwords: WP admin, FTP, database, hosting panel, Cloudflare"
    echo "  2. Restore from a clean backup taken before the infection date"
    echo "  3. Update ALL plugins, themes, and WordPress core"
    echo "  4. Remove any plugins/themes not actively in use"
    echo "  5. Implement 2FA on all admin accounts"
    echo "  6. Enable a WAF (Cloudflare or Wordfence) to block re-infection"
    [[ -n "$LOG_FILE" ]] && echo "" && echo "  Findings logged to: $LOG_FILE"
fi

echo "════════════════════════════════════════════════════════════════"
echo ""
