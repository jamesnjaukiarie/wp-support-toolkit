#!/usr/bin/env bash
# =============================================================================
# migration-fix.sh
# WordPress Post-Migration URL and Configuration Repair
#
# Usage:
#   ./migration-fix.sh /path/to/wordpress https://olddomain.com https://newdomain.com
#
# What it does:
#   1. Audits siteurl and home values in wp_options
#   2. Checks wp-config.php for hardcoded old domain references
#   3. Optionally runs wp search-replace across all tables
#   4. Flushes rewrite rules and all caches
#   5. Verifies the fix by re-reading siteurl from the database
#
# Prerequisites: WP-CLI must be installed (wp-cli.org)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

header()    { echo ""; echo -e "${CYAN}${BOLD}── $1 ──${RESET}"; }
found()     { echo -e "  ${RED}[FOUND]${RESET}  $1"; }
ok()        { echo -e "  ${GREEN}[OK]${RESET}     $1"; }
warn()      { echo -e "  ${YELLOW}[WARN]${RESET}   $1"; }
info()      { echo -e "  ${CYAN}[INFO]${RESET}   $1"; }
recommend() { echo -e "  ${BOLD}→ Action:${RESET} $1"; }
success()   { echo -e "  ${GREEN}${BOLD}[DONE]${RESET}   $1"; }

# ── Argument validation ───────────────────────────────────────────────────────
if [[ $# -lt 3 ]]; then
    echo -e "${RED}Usage: $0 /path/to/wordpress https://olddomain.com https://newdomain.com${RESET}"
    echo ""
    echo "Example:"
    echo "  ./migration-fix.sh /var/www/html https://staging.mysite.com https://mysite.com"
    exit 1
fi

WP_ROOT="${1%/}"
OLD_DOMAIN="${2%/}"    # strip trailing slash
NEW_DOMAIN="${3%/}"

# Validate WP root
if [[ ! -f "$WP_ROOT/wp-config.php" ]]; then
    echo -e "${RED}ERROR: wp-config.php not found at $WP_ROOT${RESET}"
    exit 1
fi

# Validate WP-CLI availability
if ! command -v wp &>/dev/null; then
    echo -e "${RED}ERROR: WP-CLI (wp) not found in PATH.${RESET}"
    echo "Install from: https://wp-cli.org/#installing"
    exit 1
fi

echo ""
echo -e "${BOLD}wp-support-toolkit / migration-fix.sh${RESET}"
echo -e "WordPress root: ${CYAN}$WP_ROOT${RESET}"
echo -e "Old domain:     ${CYAN}$OLD_DOMAIN${RESET}"
echo -e "New domain:     ${CYAN}$NEW_DOMAIN${RESET}"
echo -e "Timestamp:      $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "────────────────────────────────────────────────────────────────"
echo ""
echo -e "${YELLOW}${BOLD}WARNING: This script will modify your WordPress database.${RESET}"
echo -e "${YELLOW}Ensure you have a recent backup before proceeding.${RESET}"
echo ""

# Prompt for confirmation
read -rp "Continue? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted. No changes made."
    exit 0
fi

WP="wp --path=$WP_ROOT --allow-root"

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 1: Current siteurl and home values
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 1: Current siteurl and home in wp_options"

CURRENT_SITEURL=$($WP option get siteurl 2>/dev/null || echo "ERROR")
CURRENT_HOME=$($WP option get home 2>/dev/null || echo "ERROR")

echo -e "  siteurl: ${BOLD}$CURRENT_SITEURL${RESET}"
echo -e "  home:    ${BOLD}$CURRENT_HOME${RESET}"

NEEDS_URL_FIX=false

if [[ "$CURRENT_SITEURL" == *"$OLD_DOMAIN"* ]]; then
    found "siteurl still references old domain: $CURRENT_SITEURL"
    NEEDS_URL_FIX=true
else
    ok "siteurl does not reference old domain."
fi

if [[ "$CURRENT_HOME" == *"$OLD_DOMAIN"* ]]; then
    found "home still references old domain: $CURRENT_HOME"
    NEEDS_URL_FIX=true
else
    ok "home does not reference old domain."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 2: wp-config.php hardcoded URLs
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 2: Hardcoded URLs in wp-config.php"

WP_CONFIG_REFS=$(grep -n "$OLD_DOMAIN" "$WP_ROOT/wp-config.php" 2>/dev/null || true)

if [[ -n "$WP_CONFIG_REFS" ]]; then
    found "Old domain found hardcoded in wp-config.php:"
    echo "$WP_CONFIG_REFS" | while IFS= read -r line; do
        echo "  Line $line"
    done
    recommend "Edit wp-config.php and replace $OLD_DOMAIN with $NEW_DOMAIN in lines shown above."
    recommend "If WP_HOME or WP_SITEURL are defined there, they override the database — fix them first."
else
    ok "No hardcoded references to old domain in wp-config.php."
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 3: HTTPS / HTTP mismatch
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 3: HTTP / HTTPS Consistency"

if [[ "$OLD_DOMAIN" == http://* && "$NEW_DOMAIN" == https://* ]]; then
    info "Migration includes HTTP → HTTPS upgrade."
    info "search-replace will also update all http:// asset URLs to https://."
elif [[ "$OLD_DOMAIN" == https://* && "$NEW_DOMAIN" == http://* ]]; then
    warn "You are downgrading from HTTPS to HTTP. This is unusual — confirm this is intentional."
fi

# ─────────────────────────────────────────────────────────────────────────────
# FIX 1: Update siteurl and home directly
# ─────────────────────────────────────────────────────────────────────────────
header "FIX 1: Update siteurl and home"

if [[ "$NEEDS_URL_FIX" == true ]]; then
    NEW_SITEURL="${CURRENT_SITEURL/$OLD_DOMAIN/$NEW_DOMAIN}"
    NEW_HOME="${CURRENT_HOME/$OLD_DOMAIN/$NEW_DOMAIN}"

    $WP option update siteurl "$NEW_SITEURL" 2>/dev/null
    success "siteurl updated to: $NEW_SITEURL"

    $WP option update home "$NEW_HOME" 2>/dev/null
    success "home updated to: $NEW_HOME"
else
    ok "siteurl and home already correct. Skipping direct update."
fi

# ─────────────────────────────────────────────────────────────────────────────
# FIX 2: Search-Replace across all tables
# ─────────────────────────────────────────────────────────────────────────────
header "FIX 2: Search-Replace Across All Tables"

echo ""
echo "  This will replace all occurrences of:"
echo -e "    ${RED}$OLD_DOMAIN${RESET}  →  ${GREEN}$NEW_DOMAIN${RESET}"
echo "  across every table in the WordPress database."
echo ""
read -rp "  Run search-replace now? [y/N] " RUN_SR

if [[ "$RUN_SR" =~ ^[Yy]$ ]]; then
    echo ""
    $WP search-replace "$OLD_DOMAIN" "$NEW_DOMAIN" --all-tables --report-changed-only 2>&1 | \
        while IFS= read -r line; do echo "  $line"; done
    success "search-replace completed."

    # If upgrading HTTP to HTTPS, also replace any remaining http:// references
    if [[ "$OLD_DOMAIN" == http://* ]]; then
        OLD_BARE="${OLD_DOMAIN#http://}"
        NEW_BARE="${NEW_DOMAIN#https://}"

        if [[ "$OLD_BARE" != "$NEW_BARE" ]]; then
            # Domain itself changed — the above search-replace already covered it
            ok "Domain change covered by the search-replace above."
        else
            # Same domain, just protocol upgrade — handle http:// → https:// separately
            $WP search-replace "http://$OLD_BARE" "https://$NEW_BARE" --all-tables --report-changed-only 2>&1 | \
                while IFS= read -r line; do echo "  $line"; done
            success "HTTP → HTTPS URL upgrade completed."
        fi
    fi
else
    warn "Skipped. Run manually if needed:"
    echo "  wp search-replace '$OLD_DOMAIN' '$NEW_DOMAIN' --all-tables --path=$WP_ROOT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# FIX 3: Flush rewrite rules and all caches
# ─────────────────────────────────────────────────────────────────────────────
header "FIX 3: Flush Rewrite Rules and Cache"

$WP rewrite flush --hard --path="$WP_ROOT" 2>/dev/null && success "Rewrite rules flushed."
$WP cache flush --path="$WP_ROOT" 2>/dev/null && success "Object cache flushed."
$WP transient delete --all --path="$WP_ROOT" 2>/dev/null && success "Transients cleared."

# ─────────────────────────────────────────────────────────────────────────────
# VERIFICATION
# ─────────────────────────────────────────────────────────────────────────────
header "Verification"

VERIFY_SITEURL=$($WP option get siteurl 2>/dev/null || echo "ERROR")
VERIFY_HOME=$($WP option get home 2>/dev/null || echo "ERROR")

echo -e "  siteurl: ${BOLD}$VERIFY_SITEURL${RESET}"
echo -e "  home:    ${BOLD}$VERIFY_HOME${RESET}"

if [[ "$VERIFY_SITEURL" == *"$OLD_DOMAIN"* ]] || [[ "$VERIFY_HOME" == *"$OLD_DOMAIN"* ]]; then
    found "Old domain still present after fix. Check for WP_SITEURL / WP_HOME constants in wp-config.php — these override the database."
else
    success "Database URLs are now pointing to $NEW_DOMAIN"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo -e "${BOLD}Next steps after migration:${RESET}"
echo "  1. Clear any server-level page cache (WP Rocket, Cloudflare, or hosting cache)"
echo "  2. Test checkout / forms / login — these commonly have hardcoded URLs"
echo "  3. Check browser console for remaining mixed content warnings"
echo "  4. Verify SSL certificate is active for $NEW_DOMAIN"
echo "  5. Update Cloudflare DNS A records if the server IP also changed"
echo "════════════════════════════════════════════════════════════════"
echo ""
