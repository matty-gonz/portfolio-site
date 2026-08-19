#!/bin/bash
# ─────────────────────────────────────────────────────────────
# stats-refresh.sh — regenerate the private GoAccess report.
#
# Install to /usr/local/bin/stats-refresh (mode 755, root-owned) and
# run from root's crontab every 30 minutes:
#   */30 * * * * /usr/local/bin/stats-refresh
#
# HOW THE 1-YEAR WINDOW WORKS
# There is no database to prune. Every run reparses whatever log files
# logrotate has kept, and logrotate is configured to keep 365 days. So
# the retention window and the report window are the same thing, and
# they can never drift apart. Old data disappears from the report on
# exactly the day the log file is deleted.
#
# The cost is that we reparse the full year on every run. GoAccess is C
# and reads ~100k lines/sec, so at portfolio-site traffic this is a
# sub-second job. If the site ever gets genuinely popular and this
# starts taking real time, switch to GoAccess's incremental mode
# (--persist / --restore / --db-path) — but don't do it before then,
# because incremental mode reintroduces the pruning problem this
# design avoids.
# ─────────────────────────────────────────────────────────────

set -euo pipefail

LOG_DIR="/var/log/nginx"
LOG_BASE="portfolio.access.log"
OUT_DIR="/var/www/stats"
OUT="$OUT_DIR/index.html"          # plain-English summary (the landing page)
DASH="$OUT_DIR/dashboard.html"     # full GoAccess dashboard
SUMMARY_BIN="/usr/local/bin/stats-summary"

log() { echo "[stats-refresh] $*" >&2; }

# ── Only one run at a time ────────────────────────────────────
# Cron will happily start a second copy if the first is slow. flock
# makes the extra copy exit immediately instead of two processes
# writing the same file.
exec 9>/var/lock/stats-refresh.lock
if ! flock -n 9; then
    log "another run is in progress; exiting"
    exit 0
fi

command -v goaccess >/dev/null || { log "goaccess is not installed"; exit 1; }
mkdir -p "$OUT_DIR"

# ── Collect logs oldest → newest ──────────────────────────────
# logrotate names them: portfolio.access.log (today),
# portfolio.access.log.1 (yesterday), portfolio.access.log.2.gz, ...
# so the HIGHEST number is the OLDEST. Reverse version-sort therefore
# yields chronological order, which keeps GoAccess's time-series
# panels sane.
mapfile -t LOGS < <(ls -1 "$LOG_DIR/$LOG_BASE"* 2>/dev/null | sort -V -r || true)

if [ "${#LOGS[@]}" -eq 0 ]; then
    log "no logs matching $LOG_DIR/$LOG_BASE* — has nginx been configured to write it?"
    exit 1
fi

ARGS=(
    -                                   # read the log from stdin
    --log-format=COMBINED
    --no-progress                       # cron has no terminal to draw on

    # Drop requests from user agents that identify themselves as bots.
    # This is why the numbers here will be lower than Cloudflare's
    # "requests" figure, and closer to reality.
    --ignore-crawlers

    # Anything whose OS *and* browser can't be identified is almost
    # never a person — real browsers announce themselves. Counting
    # these as crawlers too closes the gap left by bots that don't
    # politely put "bot" in their user agent.
    --unknowns-as-crawlers

    # The Referrers panel is OFF by default in GoAccess. It's the one
    # that answers "did that LinkedIn post actually send anyone here",
    # so it's the last thing we'd want silently missing.
    --enable-panel=REFERRERS

    # Hide panels that are meaningful for a busy application server and
    # pure noise for a portfolio. Every one of these was answering a
    # question you will never ask, while making the ones you do ask
    # harder to find.
    --ignore-panel=REQUESTS_STATIC   # every font and image, individually
    --ignore-panel=KEYPHRASES        # dead: Google stopped sending these
    --ignore-panel=REMOTE_USER       # you have no HTTP auth
    --ignore-panel=CACHE_STATUS      # not logged in our format
    --ignore-panel=MIME_TYPE         # not logged in our format
    --ignore-panel=TLS_TYPE          # not logged; TLS terminates at Cloudflare
    --ignore-panel=VIRTUAL_HOSTS     # one host per log file already

    # Second layer. nginx already truncates addresses before writing
    # them (see pi/nginx-log-anon.conf), so by the time we get here the
    # last octet is a zero and this flag has nothing left to do.
    #
    # Kept deliberately: if the log-anon config were ever removed,
    # overwritten by a package update, or if a log file from before
    # that change got mixed in, this still prevents complete addresses
    # from reaching the report. The two protections fail independently,
    # which is the point of having both.
    --anonymize-ip

    # Belt and braces on the retention window. logrotate should already
    # prevent older data from reaching us; this guarantees it even if
    # the logrotate config gets edited or reset by a package update.
    # Set to match `rotate` in pi/logrotate-nginx (260 weeks = 5 years).
    --keep-last=1825

    --real-os
    --html-report-title="matthewjgonzalez.me — rolling 12 months"
)

# NOTE ON TIMEZONES
# GoAccess's --tz flag only works correctly alongside an explicit
# --datetime-format, because the COMBINED preset discards the timezone
# offset in the log line. Rather than hand-rolling a format string, the
# pi's own clock is set to Eastern (see STATS-SETUP.md step 3) so nginx
# writes local time and no conversion is needed. Fixing the clock is
# more robust than correcting for it afterwards.

# Uncomment and set to skip your own visits. Only useful if you have a
# static IP — on a home connection this changes periodically.
# ARGS+=(--exclude-ip=203.0.113.45)

# Country/city breakdown, only if the free GeoLite2 database is present.
# Entirely optional; see STATS-SETUP.md step 8.
for db in /var/lib/GeoIP/GeoLite2-City.mmdb /var/lib/GeoIP/GeoLite2-Country.mmdb; do
    [ -r "$db" ] && { ARGS+=(--geoip-database="$db"); break; }
done

# ── Generate ──────────────────────────────────────────────────
# Written to a temp file in the SAME directory, then moved into place.
# mv within one filesystem is atomic, so a browser refreshing mid-run
# sees either the old report or the new one — never a half-written file.
# Names MUST end in .html/.json — GoAccess picks its output format from
# the extension and hard-fails on anything else ("Invalid filename
# extension"). So the PID goes in the middle, not on the end. Leading
# dot keeps them hidden, and nginx-stats.conf denies dotfiles anyway.
TMP_HTML="$OUT_DIR/.stats-tmp.$$.html"
TMP_JSON="$OUT_DIR/.stats-tmp.$$.json"
TMP_SUM="$OUT_DIR/.stats-sum.$$.html"
trap 'rm -f "$TMP_HTML" "$TMP_JSON" "$TMP_SUM"' EXIT

# One pass, two outputs. The HTML is the full dashboard; the JSON is the
# same data in a form the summary generator can read. Running GoAccess
# once rather than twice means the two can never disagree.
if ! zcat -f -- "${LOGS[@]}" | goaccess "${ARGS[@]}" -o "$TMP_HTML" -o "$TMP_JSON"; then
    log "goaccess failed; keeping the previous report"
    exit 1
fi

[ -s "$TMP_HTML" ] || { log "goaccess produced an empty report; keeping previous"; exit 1; }

install_file() {   # $1 = temp file, $2 = destination
    chown www-data:www-data "$1"
    chmod 640 "$1"
    mv -f "$1" "$2"
}

# The full dashboard always gets published.
install_file "$TMP_HTML" "$DASH"

# The plain-English summary is a nice-to-have layered on top. If it
# fails we say so and keep the previous one rather than taking the
# whole report down with it — a broken summary shouldn't cost you the
# dashboard that was working fine a second ago.
if [ -s "$TMP_JSON" ] && [ -x "$SUMMARY_BIN" ]; then
    if "$SUMMARY_BIN" "$TMP_JSON" "$TMP_SUM" 2>&1 | sed 's/^/[summary] /' >&2; then
        [ -s "$TMP_SUM" ] && install_file "$TMP_SUM" "$OUT"
    else
        log "summary generation failed; dashboard updated, summary left as-is"
    fi
elif [ ! -x "$SUMMARY_BIN" ]; then
    log "note: $SUMMARY_BIN not installed — publishing dashboard only"
    [ -f "$OUT" ] || { cp "$DASH" "$OUT"; chown www-data:www-data "$OUT"; }
fi

trap - EXIT

log "wrote $OUT + $DASH from ${#LOGS[@]} log file(s)"
