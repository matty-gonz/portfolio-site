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
OUT="$OUT_DIR/index.html"

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

    # Store only the first three octets of each address (1.2.3.0). You
    # still get accurate unique-visitor counts and correct geolocation,
    # but the report stops being a list of people's home IP addresses —
    # so if it ever leaked, it would leak almost nothing. Remove this
    # if you ever need to identify one specific visitor.
    --anonymize-ip

    # Belt and braces on the 1-year window. logrotate should already
    # prevent older data from reaching us; this guarantees it even if
    # the logrotate config gets edited or reset by a package update.
    --keep-last=365

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
TMP="$OUT_DIR/.index.html.tmp.$$"
trap 'rm -f "$TMP"' EXIT

if ! zcat -f -- "${LOGS[@]}" | goaccess "${ARGS[@]}" -o "$TMP"; then
    log "goaccess failed; keeping the previous report"
    exit 1
fi

[ -s "$TMP" ] || { log "goaccess produced an empty file; keeping previous report"; exit 1; }

chown www-data:www-data "$TMP"
chmod 640 "$TMP"
mv -f "$TMP" "$OUT"
trap - EXIT

log "wrote $OUT from ${#LOGS[@]} log file(s)"
