# ─────────────────────────────────────────────────────────────
# portfolio.zsh — deploy commands for matthewjgonzalez.me
#
# Install: append to ~/.zshrc (and DELETE the old
# `alias deploy=...` line), then `source ~/.zshrc`.
#
# Model:
#   You always work on the `dev` branch locally.
#   deploy-dev   pushes dev  -> dev.matthewjgonzalez.me
#   deploy       promotes dev -> main -> matthewjgonzalez.me
#
# The pi pulls both branches once a minute, so either command
# is live within ~60 seconds.
# ─────────────────────────────────────────────────────────────

export PORTFOLIO_DIR="$HOME/Documents/Bootstrap Studio/Portfolio Site Files"

# If an older `alias deploy=...` is still live in this shell, zsh will try to
# expand it while parsing the function definition below and fail with
# "parse error near ()". Clear it first.
unalias deploy      2>/dev/null
unalias deploy-dev  2>/dev/null

# Push local work to the staging site.
# Optional argument becomes the commit message.
deploy-dev() {
  cd "$PORTFOLIO_DIR" || { echo "Can't find the site folder."; return 1; }

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$branch" != "dev" ]]; then
    echo "You're on '$branch', not 'dev'. Switching."
    git checkout dev || return 1
  fi

  # One unescaped character in projects.json takes down the entire project
  # list, and the browser reports it as "Project not found" — which sends you
  # hunting for the wrong bug. Catch it here instead of on the staging site.
  if [[ -f projects.json ]] && ! python3 -m json.tool projects.json > /dev/null 2>&1; then
    echo ""
    echo "projects.json is not valid JSON — NOTHING was deployed."
    echo ""
    python3 -m json.tool projects.json 2>&1 | tail -2
    echo ""
    echo "Most common cause: a straight \" inside a caption (e.g. 1/2\" drill bit)."
    echo "Escape it as \\\" or use the word 'inch'."
    return 1
  fi

  # If this fails (stale .git/index.lock is the usual cause) we must stop.
  # Continuing would report a successful deploy while shipping nothing.
  if ! git add -A; then
    echo ""
    echo "git add failed — NOTHING was deployed."
    echo "If the error above mentions index.lock, no other git process is"
    echo "running; it's a stale file. Remove it and try again:"
    echo "  rm -f \"\$PORTFOLIO_DIR/.git/index.lock\""
    return 1
  fi

  if git diff --cached --quiet; then
    echo "Nothing new to commit — pushing anyway in case the last push failed."
  else
    git commit -m "${1:-update}" || return 1
  fi

  git push origin dev || return 1
  echo "→ dev.matthewjgonzalez.me updates within ~60s."
}

# Promote whatever is on dev to the live site.
deploy() {
  cd "$PORTFOLIO_DIR" || { echo "Can't find the site folder."; return 1; }

  # Refuse to promote work that isn't committed — otherwise you'd
  # ship something you never actually saw on staging.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "You have uncommitted changes. Run deploy-dev first, check staging, then promote."
    return 1
  fi

  git checkout dev || return 1
  git push origin dev || return 1

  echo -n "Promote dev -> live (matthewjgonzalez.me)? [y/N] "
  local answer
  read -r answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Aborted. Nothing shipped."
    return 1
  fi

  git checkout main || return 1

  # --ff-only makes this a literal "copy dev to live". If it fails,
  # someone committed straight to main and the two have diverged —
  # better to stop loudly than to auto-merge the live site.
  if ! git merge --ff-only dev; then
    echo "main has diverged from dev. Resolve by hand, then retry."
    git checkout dev
    return 1
  fi

  git push origin main || { git checkout dev; return 1; }
  git checkout dev

  echo "→ matthewjgonzalez.me updates within ~60s."
}

# Roll the live site back one commit. Staging is untouched.
deploy-rollback() {
  cd "$PORTFOLIO_DIR" || return 1
  git checkout main || return 1
  echo "About to revert this commit on live:"
  git log --oneline -1
  echo -n "Continue? [y/N] "
  local answer
  read -r answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Aborted."
    git checkout dev
    return 1
  fi
  git revert --no-edit HEAD && git push origin main
  git checkout dev
}
