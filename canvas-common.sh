#!/bin/bash
# Shared by the "push-components"/"pull-components" DDEV host commands and
# ./dev.sh. Not meant to be run directly.

# Scaffolds canvas_components/ on first run and installs its npm deps. Pass a
# site URL to pre-fill it into the generated .env; omit it for a pure
# frontend workflow that doesn't need ddev running at all.
ensure_canvas_components() {
  if [ ! -d canvas_components ]; then
    echo "Scaffolding canvas_components/ ..."
    if [ -n "$1" ]; then
      npx @drupal-canvas/create@latest canvas_components --site-url "$1"
    else
      npx @drupal-canvas/create@latest canvas_components
    fi
    # The scaffolder git-inits canvas_components/ itself. Strip that so its
    # files are tracked by this project's own repo instead of becoming an
    # invisible embedded repository.
    rm -rf canvas_components/.git
  fi
  (cd canvas_components && npm i)
}

# Ensures canvas_components/.env has CANVAS_SITE_URL/CANVAS_CLIENT_ID, and
# exports them into the current shell. $1 is the site URL to fill in when
# there's no .env yet. Run from the project root; changes directory into
# canvas_components/ as a side effect.
#
# The scaffolder's .env.example ships placeholder
# CANVAS_CLIENT_ID=cli/CANVAS_CLIENT_SECRET=secret values (for its generic
# client-credentials docs), which don't match the "canvas" consumer this
# starter actually provisions (see .ddev/commands/web/site-install). So
# CANVAS_CLIENT_ID is forced here rather than left alone if already set, and
# the bogus secret is dropped — this starter's consumer is a public PKCE
# client with no secret.
ensure_canvas_env() {
  local site_url="$1"
  ensure_canvas_components "$site_url"

  cd canvas_components

  if [ ! -f .env ]; then
    echo "CANVAS_SITE_URL=$site_url" > .env
  fi
  grep -v -E '^CANVAS_CLIENT_ID=|^CANVAS_CLIENT_SECRET=' .env > .env.tmp
  mv .env.tmp .env
  echo "CANVAS_CLIENT_ID=canvas" >> .env

  set -a
  source .env
  set +a
}

# Runs a Canvas CLI command against canvas_components/, logging in first if
# there's no stored token yet for this site. Run this after ensure_canvas_env,
# so CANVAS_SITE_URL/CANVAS_CLIENT_ID are set.
#
# `canvas login` caches tokens in ~/.config/drupal-canvas/oauth.json (keyed
# by site URL) and `push`/`pull` reuse -- and silently refresh -- them
# automatically, so this only opens a browser once per machine per site, not
# on every day-to-day run. It's a proactive check rather than "try push,
# login on failure": without a stored token, `canvas push`/`pull` itself
# blocks on an interactive "Enter your client secret" prompt (irrelevant for
# our PKCE-only, secret-less consumer) instead of just failing, so a reactive
# retry never gets the chance to run.
canvas_run() {
  local token_file="$HOME/.config/drupal-canvas/oauth.json"
  if [ ! -f "$token_file" ] || ! grep -qF "$CANVAS_SITE_URL" "$token_file"; then
    npx canvas login --site-url "$CANVAS_SITE_URL" --client-id "$CANVAS_CLIENT_ID"
  fi
  npx canvas "$@"
}
