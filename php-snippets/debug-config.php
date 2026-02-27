<?php
/**
 * WordPress Debug Configuration
 * ==============================
 * Safe, annotated debug constants for wp-config.php.
 *
 * IMPORTANT: This block includes an environment guard that prevents
 * debug output from being exposed on production. If you are on a
 * managed host that sets WP_ENVIRONMENT_TYPE automatically (e.g. Kinsta,
 * WP Engine), this guard will prevent accidental debug exposure if these
 * constants are left enabled after troubleshooting.
 *
 * Usage:
 *   Add this block to wp-config.php ABOVE the line:
 *   "That's all, stop editing! Happy publishing."
 *
 *   To enable debugging:    set DEBUG_ACTIVE to true
 *   To disable debugging:   set DEBUG_ACTIVE to false (or remove the block)
 */

// ── Toggle this to enable or disable the entire debug block ──────────────────
define( 'DEBUG_ACTIVE', true );

if ( defined( 'DEBUG_ACTIVE' ) && DEBUG_ACTIVE ) {

    // Guard: never expose debug output on production environments.
    // WP_ENVIRONMENT_TYPE is set by Kinsta and other managed hosts automatically.
    $env = defined( 'WP_ENVIRONMENT_TYPE' ) ? WP_ENVIRONMENT_TYPE : 'production';

    if ( in_array( $env, [ 'local', 'development', 'staging' ], true ) || $env !== 'production' ) {

        /**
         * WP_DEBUG
         * --------
         * Master switch for WordPress debug mode.
         * When true, WordPress stores errors instead of suppressing them.
         * Required for all other debug constants to have effect.
         */
        define( 'WP_DEBUG', true );

        /**
         * WP_DEBUG_LOG
         * ------------
         * Writes all PHP errors, warnings, and notices to:
         *   wp-content/debug.log
         *
         * This is the primary tool for diagnosing White Screen of Death (WSOD),
         * plugin fatal errors, and any issue that produces no visible output.
         *
         * To read the log via WP-CLI:
         *   wp eval 'echo file_get_contents(WP_CONTENT_DIR . "/debug.log");' | tail -50
         *
         * Or directly:
         *   tail -f /var/www/html/wp-content/debug.log
         */
        define( 'WP_DEBUG_LOG', true );

        /**
         * WP_DEBUG_DISPLAY
         * ----------------
         * Controls whether errors are printed to the browser.
         *
         * Set to FALSE when using WP_DEBUG_LOG — you want errors written
         * to the log file, not rendered on screen (which breaks JSON/AJAX
         * responses and exposes sensitive stack traces to visitors).
         *
         * Set to TRUE only in a completely local environment where only
         * you can see the output.
         */
        define( 'WP_DEBUG_DISPLAY', false );

        /**
         * SCRIPT_DEBUG
         * ------------
         * Forces WordPress to load the unminified versions of all
         * registered JS and CSS files.
         *
         * Use this when debugging JavaScript errors in the browser console
         * to see meaningful function names instead of minified code.
         */
        define( 'SCRIPT_DEBUG', true );

        /**
         * SAVEQUERIES
         * -----------
         * Logs every database query to the $wpdb->queries array.
         *
         * USE WITH CAUTION on production — storing every query in memory
         * is a significant performance overhead.
         *
         * Best used alongside the Query Monitor plugin, which reads this
         * array and displays queries with execution times in the admin bar.
         *
         * To inspect queries manually:
         *   global $wpdb;
         *   var_dump( $wpdb->queries );
         */
        define( 'SAVEQUERIES', true );

    } else {
        // Production environment — disable all debug output silently.
        define( 'WP_DEBUG',         false );
        define( 'WP_DEBUG_LOG',     false );
        define( 'WP_DEBUG_DISPLAY', false );
    }
}

/**
 * Additional useful constants for managed hosting environments
 * ─────────────────────────────────────────────────────────────
 *
 * These are safe to leave enabled permanently.
 */

/**
 * WP_MEMORY_LIMIT
 * ---------------
 * Sets the PHP memory limit available to WordPress.
 * The default (40M) is too low for most modern plugin stacks.
 * 256M is a reasonable minimum; managed hosts like Kinsta typically
 * allow 256M–512M depending on the plan.
 */
if ( ! defined( 'WP_MEMORY_LIMIT' ) ) {
    define( 'WP_MEMORY_LIMIT', '256M' );
}

/**
 * DISALLOW_FILE_EDIT
 * ------------------
 * Removes the plugin/theme editor from the WordPress admin.
 * Recommended on all production sites — prevents code editing
 * through a compromised admin account.
 */
define( 'DISALLOW_FILE_EDIT', true );

/**
 * DISALLOW_FILE_MODS
 * ------------------
 * Prevents plugin and theme installation or updates through the admin.
 * Use on production sites where you want to enforce deployment via Git
 * or a staging workflow.
 *
 * Note: uncommenting this will also disable automatic updates.
 * Only enable if you have a deliberate deployment process in place.
 */
// define( 'DISALLOW_FILE_MODS', true );

/**
 * FORCE_SSL_ADMIN
 * ---------------
 * Forces all admin panel requests to use HTTPS.
 * Should be enabled on any site with a valid SSL certificate.
 */
define( 'FORCE_SSL_ADMIN', true );

/**
 * WP_POST_REVISIONS
 * -----------------
 * Controls how many post revisions WordPress stores per post.
 * Default is unlimited, which bloats the wp_posts table on active sites.
 * Setting to 5–10 keeps revision history useful without database overhead.
 */
define( 'WP_POST_REVISIONS', 5 );

/**
 * EMPTY_TRASH_DAYS
 * ----------------
 * Number of days before trashed posts are permanently deleted.
 * Default is 30. Setting to 7 reduces database clutter on active sites.
 */
define( 'EMPTY_TRASH_DAYS', 7 );
