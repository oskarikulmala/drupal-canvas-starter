#!/bin/bash
# Shared by the "push-components"/"pull-components" DDEV host commands and
# ./dev.sh. Not meant to be run directly.

# The Canvas CLI and Workbench run on the host, not in the DDEV container:
# `canvas login` has to open a browser and receive its OAuth callback on
# localhost:4444. So Node has to be installed on the host itself. Vite (used
# by Workbench) needs ^20.19 || >=22.12; 22 is the simplest floor to state.
require_node() {
  if ! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then
    echo "Node.js 22+ is required on your machine (not just inside DDEV)." >&2
    echo "Install it from https://nodejs.org, or with 'brew install node' / 'nvm install 22'." >&2
    exit 1
  fi
  local major
  major=$(node -p 'process.versions.node.split(".")[0]')
  if [ "$major" -lt 22 ]; then
    echo "Node.js 22+ is required, but $(node -v) is installed." >&2
    exit 1
  fi
}

# Scaffolds canvas_components/ on first run and installs its npm deps. Pass a
# site URL to pre-fill it into the generated .env; omit it for a pure
# frontend workflow that doesn't need ddev running at all.
ensure_canvas_components() {
  require_node
  if [ ! -d canvas_components ]; then
    echo "Scaffolding canvas_components/ ..."
    if [ -n "$1" ]; then
      npx -y @drupal-canvas/create@latest canvas_components --site-url "$1"
    else
      npx -y @drupal-canvas/create@latest canvas_components
    fi
    # The scaffolder git-inits canvas_components/ itself. Strip that so its
    # files are tracked by this project's own repo instead of becoming an
    # invisible embedded repository. Its initial commit can leave a detached
    # `git gc --auto` running that re-creates parts of .git/ (info/refs,
    # objects/info/packs) after it's deleted, so keep deleting until it
    # stays gone.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      rm -rf canvas_components/.git 2>/dev/null || true
      sleep 1
      [ -e canvas_components/.git ] || break
    done
    if [ -e canvas_components/.git ]; then
      echo "Could not remove canvas_components/.git; delete it manually and re-run." >&2
      exit 1
    fi
    # The Nebula template ships its starter components, pages and regions in
    # examples/ and leaves the synced directories empty, so a first push
    # would otherwise report "Nothing to push". Seed them once.
    (
      cd canvas_components
      mkdir -p src/components pages regions
      [ -d examples/components ] && cp -R examples/components/. src/components/
      [ -d examples/pages ] && cp -R examples/pages/. pages/
      [ -d examples/regions ] && cp -R examples/regions/. regions/
      # Region files are named after theme regions. The example targets a
      # "footer" region, but Olivero (the standard profile's theme) only has
      # footer_top/footer_bottom.
      [ -f regions/footer.json ] && mv regions/footer.json regions/footer_bottom.json
    )
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

# Prints the state of the cached CLI login for $CANVAS_SITE_URL:
#   missing     - never logged in to this site on this machine
#   valid       - access token accepted by the site
#   refreshable - access token expired, but a refresh token is stored (the
#                 CLI refreshes it by itself)
#   dead        - expired with no refresh token, or rejected by the site
#                 (e.g. after `ddev site-install` wiped the database)
canvas_token_state() {
  local token_file="$HOME/.config/drupal-canvas/oauth.json"
  local state
  state=$(TOKEN_FILE="$token_file" node -e '
    const fs = require("fs");
    let entry;
    try { entry = JSON.parse(fs.readFileSync(process.env.TOKEN_FILE, "utf8"))[process.env.CANVAS_SITE_URL]; } catch {}
    if (!entry || !entry.accessToken) { console.log("missing"); process.exit(); }
    if (entry.expiresAt && entry.expiresAt < Date.now() + 30000) {
      console.log(entry.refreshToken ? "refreshable" : "dead"); process.exit();
    }
    console.log("check " + entry.accessToken);
  ')
  if [ "${state%% *}" != "check" ]; then
    echo "$state"
    return
  fi
  local code
  code=$(curl -ks -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${state#check }" \
    "$CANVAS_SITE_URL/canvas/api/v0/config/js_component")
  if [ "$code" = "401" ] || [ "$code" = "403" ]; then
    echo dead
  else
    echo valid
  fi
}

canvas_login() {
  npx canvas logout --site-url "$CANVAS_SITE_URL" >/dev/null 2>&1 || true
  npx canvas login --site-url "$CANVAS_SITE_URL" --client-id "$CANVAS_CLIENT_ID"
}

# Runs a Canvas CLI command against canvas_components/, logging in first if
# there's no usable stored token for this site. Run this after
# ensure_canvas_env, so CANVAS_SITE_URL/CANVAS_CLIENT_ID are set.
#
# `canvas login` caches tokens in ~/.config/drupal-canvas/oauth.json (keyed
# by site URL) and `push`/`pull` reuse -- and silently refresh -- them, so
# this only opens a browser once per machine per site (or after a reinstall),
# not on every run. It's a proactive check rather than "try push, login on
# failure": without a stored token, `canvas push`/`pull` itself blocks on an
# interactive "Enter your client secret" prompt (irrelevant for our
# PKCE-only, secret-less consumer) instead of just failing.
canvas_run() {
  case "$(canvas_token_state)" in
    missing|dead) canvas_login ;;
  esac
  if ! npx canvas "$@"; then
    # A stored refresh token can still be dead (site reinstalled since): a
    # successful refresh would have bumped expiresAt, so a token still
    # "refreshable" here means the refresh itself was rejected. Log in again
    # and retry once in that case only; real push/pull errors fall through.
    case "$(canvas_token_state)" in
      missing|dead|refreshable)
        canvas_login
        npx canvas "$@"
        ;;
      *) return 1 ;;
    esac
  fi
}
