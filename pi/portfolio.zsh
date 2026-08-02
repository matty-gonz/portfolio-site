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

  git add -A
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
