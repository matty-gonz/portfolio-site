#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# site-pull — sync a document root to a git branch
#
# Replaces the old /var/www/html/deploy.sh. Two improvements
# over the original:
#
#   1. Only reloads nginx when HEAD actually moved. The old
#      script reloaded every single minute regardless.
#   2. Uses `reset --hard origin/<branch>` instead of `pull`,
#      so the doc root is always an exact mirror of the branch
#      and can never end up in a merge-conflict state.
#
# Usage:  site-pull <docroot> <branch>
# Cron:   * * * * * /usr/local/bin/site-pull /var/www/html main
# ─────────────────────────────────────────────────────────────

set -uo pipefail

ROOT="${1:?usage: site-pull <docroot> <branch>}"
BRANCH="${2:?usage: site-pull <docroot> <branch>}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $ROOT ($BRANCH) ${*:2}"; }

cd "$ROOT" 2>/dev/null || { log ERR "cannot cd to doc root"; exit 1; }

before=$(git rev-parse HEAD 2>/dev/null) || { log ERR "not a git repository"; exit 1; }

if ! git fetch --quiet origin "$BRANCH" 2>/dev/null; then
  log ERR "fetch failed"
  exit 1
fi

if ! git reset --hard --quiet "origin/$BRANCH" 2>/dev/null; then
  log ERR "reset failed"
  exit 1
fi

after=$(git rev-parse HEAD)

# Nothing changed — stay silent so the log only ever contains
# real deploys and real failures.
[ "$before" = "$after" ] && exit 0

chown -R www-data:www-data "$ROOT"
nginx -s reload

log OK "${before:0:7} -> ${after:0:7}"
