#!/bin/bash
# ─────────────────────────────────────────────────────────────
# stats-exclude — manage which addresses are left out of the report.
#
# Install to /usr/local/bin/stats-exclude (mode 755).
#
#   sudo stats-exclude me        detect your current network, exclude it
#   sudo stats-exclude add <ip>  exclude a specific address
#   sudo stats-exclude list      show the list and whether it's active
#   sudo stats-exclude off       keep the list, stop applying it
#   sudo stats-exclude on        apply it again
#   sudo stats-exclude clear     empty the list
#
# THE TRICK BEHIND "me"
# Your Mac and the pi sit behind the same home router, so they share one
# public IP. The pi asking "what's my public address?" therefore returns
# YOUR address too — no need to look it up on your Mac and copy it over.
#
# THE CAVEAT, WHICH MATTERS
# Logs store truncated addresses (203.0.113.45 is written as
# 203.0.113.0), so exclusions are necessarily /24-wide. At home that
# means you and, at most, a handful of neighbours on the same ISP block.
#
# Do NOT run `me` while on campus wifi. UCF's network would resolve to a
# range shared by thousands of people, and you'd silently delete real
# visitors from your own stats. If you do it by accident: `clear`.
#
# Changes apply on the next refresh, or immediately with:
#   sudo /usr/local/bin/stats-refresh
# ─────────────────────────────────────────────────────────────

set -euo pipefail

CONF="/etc/stats-exclude.conf"

die() { echo "stats-exclude: $*" >&2; exit 1; }

ensure_conf() {
    [ -f "$CONF" ] && return
    cat > "$CONF" <<'EOF'
# Addresses excluded from the stats report, one per line.
# Written by `stats-exclude`; safe to edit by hand.
#
# enabled=1 applies the list. enabled=0 keeps it but counts everyone,
# which is the toggle — no need to delete anything to compare.
enabled=1
EOF
    chmod 644 "$CONF"
}

# Truncate to /24 to match how the logs are actually written. Excluding
# 203.0.113.45 would never match anything, because that address was
# already stored as 203.0.113.0 before it ever reached a file.
to_network() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.[0-9]{1,3}$ ]]; then
        echo "${BASH_REMATCH[1]}.0"
    elif [[ "$ip" =~ ^([0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){3}): ]]; then
        echo "${BASH_REMATCH[1]}::"
    else
        return 1
    fi
}

detect_ip() {
    # Cloudflare's trace endpoint: tiny, no JSON to parse, and you're
    # already routing through them.
    local ip
    ip=$(curl -fsS --max-time 8 https://cloudflare.com/cdn-cgi/trace 2>/dev/null \
         | sed -n 's/^ip=//p' | tr -d '[:space:]') || true
    [ -n "$ip" ] || ip=$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null \
         | tr -d '[:space:]') || true
    [ -n "$ip" ] || die "could not determine public IP (no network?)"
    echo "$ip"
}

add_entry() {
    local net="$1"
    ensure_conf
    if grep -qxF "$net" "$CONF"; then
        echo "already excluded: $net"
        return
    fi
    echo "$net" >> "$CONF"
    echo "excluded: $net"
}

set_enabled() {
    ensure_conf
    if grep -q '^enabled=' "$CONF"; then
        sed -i "s/^enabled=.*/enabled=$1/" "$CONF"
    else
        sed -i "1i enabled=$1" "$CONF"
    fi
}

case "${1:-}" in
    me)
        raw=$(detect_ip)
        net=$(to_network "$raw") || die "unrecognised address: $raw"
        echo "this network appears as: $raw  ->  logged as $net"
        add_entry "$net"
        set_enabled 1
        echo
        echo "Reminder: this excludes the whole $net block, not just you."
        echo "If you ran this on campus wifi, undo it with: sudo stats-exclude clear"
        ;;
    add)
        [ $# -eq 2 ] || die "usage: stats-exclude add <ip>"
        net=$(to_network "$2") || die "unrecognised address: $2"
        add_entry "$net"
        ;;
    list)
        [ -f "$CONF" ] || { echo "no exclusions configured"; exit 0; }
        state=$(sed -n 's/^enabled=//p' "$CONF" | tail -1)
        echo "status: $([ "${state:-1}" = "1" ] && echo ACTIVE || echo "off (list kept)")"
        echo "entries:"
        grep -vE '^\s*(#|enabled=|$)' "$CONF" | sed 's/^/  /' || echo "  (none)"
        ;;
    off) set_enabled 0; echo "exclusions off — everyone is counted again" ;;
    on)  set_enabled 1; echo "exclusions on" ;;
    clear)
        ensure_conf
        tmp=$(mktemp)
        grep -E '^\s*(#|enabled=)' "$CONF" > "$tmp" || true
        mv "$tmp" "$CONF"; chmod 644 "$CONF"
        echo "exclusion list emptied"
        ;;
    *)
        sed -n '3,30p' "$0" | sed 's/^# \?//'
        exit 1
        ;;
esac
