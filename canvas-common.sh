#!/bin/bash
# Shared by the "push-components"/"pull-components" DDEV host commands and
# ./dev.sh. Not meant to be run directly.

# The Canvas CLI and Workbench run on the host, not in the DDEV container
# (./dev.sh works with no DDEV at all), so Node has to be installed on the
# host itself. Vite (used by Workbench) needs ^20.19 || >=22.12; 22 is the
# simplest floor to state.
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

# Ensures canvas_components/.env has CANVAS_SITE_URL and working
# CANVAS_CLIENT_ID/CANVAS_CLIENT_SECRET for the "canvas" client-credentials
# consumer (see .ddev/commands/web/site-install), and exports them into the
# current shell. $1 is the site URL to fill in when there's no .env yet. Run
# from the project root; changes directory into canvas_components/ as a side
# effect.
ensure_canvas_env() {
  local site_url="$1"
  ensure_canvas_components "$site_url"

  cd canvas_components

  if [ ! -f .env ]; then
    echo "CANVAS_SITE_URL=$site_url" > .env
  fi
  set -a
  source .env
  set +a

  if ! canvas_credentials_work; then
    canvas_provision_credentials
  fi
}

# True if the stored client ID/secret can get an access token from the site.
canvas_credentials_work() {
  [ "$CANVAS_CLIENT_ID" = "canvas" ] && [ -n "$CANVAS_CLIENT_SECRET" ] || return 1
  local code
  code=$(curl -ks -o /dev/null -w '%{http_code}' -X POST "$CANVAS_SITE_URL/oauth/token" \
    --data-urlencode grant_type=client_credentials \
    --data-urlencode client_id="$CANVAS_CLIENT_ID" \
    --data-urlencode client_secret="$CANVAS_CLIENT_SECRET" \
    --data-urlencode scope=canvas:js_component)
  [ "$code" = "200" ]
}

# Gives the "canvas" consumer a fresh secret and stores it in .env. The site
# only keeps a hash of the secret, so it can't be read back -- rotating it is
# how a new machine, or a site that was just reinstalled, gets working
# credentials without anyone opening a browser.
canvas_provision_credentials() {
  echo "Provisioning Canvas CLI credentials ..."
  local secret
  secret=$(openssl rand -hex 32)
  ddev drush php:eval "
    \$c = \Drupal::entityTypeManager()->getStorage('consumer')->loadByProperties(['client_id' => 'canvas']);
    if (!\$c) { fwrite(STDERR, \"No 'canvas' consumer found. Run 'ddev site-install' first.\n\"); exit(1); }
    \$c = reset(\$c);
    \$c->set('secret', '$secret');
    \$c->save();
  "
  grep -v -E '^CANVAS_CLIENT_ID=|^CANVAS_CLIENT_SECRET=' .env > .env.tmp || true
  mv .env.tmp .env
  printf 'CANVAS_CLIENT_ID=canvas\nCANVAS_CLIENT_SECRET=%s\n' "$secret" >> .env
  export CANVAS_CLIENT_ID=canvas CANVAS_CLIENT_SECRET="$secret"
}

# `canvas reconcile-media` rewrites external image URLs in pages/regions/
# content templates into references to Drupal media IDs, keeping the
# original URL in `_provenance`. Those IDs only exist in the database they
# were uploaded to, so on a teammate's fresh install (or after
# `ddev site-install`) the push fails with "NULL value found". Revert any
# reference to a media ID this site doesn't have back to its source URL, so
# the following reconcile-media uploads it again. Run from canvas_components/.
canvas_restore_missing_media() {
  local media_ids
  media_ids=$(ddev drush sql:query "SELECT mid FROM media" | tr '\n' ' ')
  MEDIA_IDS="$media_ids" node - <<'JS'
const fs = require("fs");
const path = require("path");
const config = JSON.parse(fs.readFileSync("canvas.config.json", "utf8"));
const existing = new Set(process.env.MEDIA_IDS.split(/\s+/).filter(Boolean).map(Number));
const dirs = [config.pagesDir, config.regionsDir, config.contentTemplatesDir].filter(Boolean);
for (const dir of dirs) {
  if (!fs.existsSync(dir)) continue;
  for (const name of fs.readdirSync(dir).filter((f) => f.endsWith(".json"))) {
    const file = path.join(dir, name);
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    let changed = 0;
    for (const element of Object.values(data.elements ?? {})) {
      for (const [prop, source] of Object.entries(element._provenance ?? {})) {
        if (!source?.source_url || existing.has(Number(source.target_id))) continue;
        element.props[prop] = { src: source.source_url };
        delete element._provenance[prop];
        changed++;
      }
      if (element._provenance && !Object.keys(element._provenance).length) delete element._provenance;
    }
    if (changed) {
      fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
      console.log(`Re-queued ${changed} image(s) in ${file} for upload (media missing on this site).`);
    }
  }
}
JS
}

# Runs a Canvas CLI command against canvas_components/ without prompting.
# Run this after ensure_canvas_env, so the credentials are exported.
canvas_run() {
  npx canvas "$@" --yes
}
