# Canvas Drupal starter

A reusable kickstart for a Drupal 11 site built around
[Drupal Canvas](https://project.pages.drupalcode.org/canvas/) code components,
running locally on [DDEV](https://ddev.com), with the Canvas CLI
(`npx canvas push`) wired up.

## Prerequisites

- [DDEV](https://ddev.com/get-started/) 1.24+ with a Docker provider
  (Docker Desktop, OrbStack, Colima or Rancher Desktop).
- **Node.js 22+ on your own machine** (`node -v`), not just inside DDEV.
  The Canvas CLI and Workbench run on the host. Install Node from
  [nodejs.org](https://nodejs.org), or with `brew install node` or
  `nvm install 22`.
- Port `5173` free on the host for Workbench.

## What's in here

- `composer.json` — Drupal 11 + `drupal/canvas`, `drupal/ai`, `drupal/ai_agents`,
  `drupal/ai_provider_openai`, `drupal/pathauto`, `drupal/simple_oauth`.
- `.ddev/config.yaml` — PHP 8.4, Node 24 with Corepack enabled (needed for
  `npx`/`npm` inside the web container).
- `.ddev/commands/web/site-install` — fresh install: composer install, OAuth
  key generation, `drush site-install`, applies the recipe below, then
  configures the Simple OAuth key paths and creates the `canvas` consumer
  (Client Credentials, acting as user 1, allowed every `canvas:*` scope), so
  `npx canvas push` works with no browser login and no manual UI steps. It's
  safe to re-run, and it finishes with `drush config:export`. **That
  consumer is for local development only.** Don't deploy it.
- `.ddev/commands/web/build-local` — day-to-day rebuild after pulling changes.
- `recipes/canvas_starter/` — a Drupal recipe that installs Canvas (plus its
  `canvas_ai`, `canvas_dev_ai`, `canvas_dev_mode`, `canvas_oauth` submodules),
  the AI modules, Pathauto, and Simple OAuth in one shot. It ships no config
  of its own, but it does `config: import` each module's default config
  (OAuth scopes, text formats, image styles, AI agent definitions): a recipe
  otherwise installs only a module's *simple* config and silently skips its
  config entities. It also makes core's **Stark** the default front-end
  theme (Claro stays the admin theme). Canvas pages render inside the
  front-end theme, and Olivero's grid and typography squeeze the Tailwind
  components into narrow columns. Stark adds almost no CSS and has the
  plain `header`/`footer` regions that the Nebula layout targets.
  Content-specific config (content types, view modes, Pathauto patterns) is
  left for each project to define.
- `config/sync/` — exported site config (committed). `ddev site-install`
  writes the initial export; `ddev build-local` imports it.
- `.ddev/mutagen/mutagen.yml` — DDEV's default, plus `/canvas_components`
  excluded from the sync. The container never uses it, and syncing it
  copies 300+ MB of `node_modules` into the container.
- `canvas-common.sh` — shared by the commands below: checks for Node 22+,
  scaffolds `canvas_components/` and its `.env` on first run (seeding it
  with the template's example components, pages and regions), and keeps
  working `CANVAS_CLIENT_ID`/`CANVAS_CLIENT_SECRET` values in
  `canvas_components/.env` (gitignored). The site stores only a hash of the
  secret. So when there's no secret yet, or the site rejects it (for example
  after a reinstall), the script sets a new one on the `canvas` consumer
  through `ddev drush`.
- `.ddev/commands/host/push-components` / `pull-components` — `ddev
  push-components` pushes component/page/content-template/region changes to
  the Drupal site; `ddev pull-components` pulls edits made in the Drupal UI
  back into the codebase. Both run on the host, read the site URL straight
  from DDEV's `$DDEV_PRIMARY_URL`, and don't prompt: they pass `--yes`.
- `dev.sh` — runs Canvas Workbench for local component
  preview/development. **Needs no Drupal site and no `ddev` running at
  all** — it never touches `.env` or OAuth, so component work can start
  before the backend even exists. It's a plain script rather than a `ddev`
  command specifically to keep that independence obvious.

`canvas_components/` itself is **not** part of this template — it's generated
fresh per project by the official scaffolder (see below), so it always starts
from the current version of that tooling.

## Kickstarting a new project

1. Copy this directory to your new project folder and `cd` into it, then
   `git init` (or clone this repo and re-point `origin`).
2. `ddev start`
3. `ddev site-install`
   - Installs Composer dependencies, generates an RSA key pair into `keys/`,
     runs `drush site-install standard`, applies `recipes/canvas_starter`,
     configures the Simple OAuth key paths, creates a `canvas`
     client-credentials consumer and exports config to `config/sync/`, with
     no manual UI steps. Commit `config/sync/`.
4. `ddev push-components` — scaffolds `canvas_components/` (React + Tailwind +
   the Canvas CLI/Workbench, from Acquia's "Nebula" starter) with its `.env`
   pre-filled on first run, copies the template's `examples/` components,
   pages and regions into place, installs npm deps, provisions the CLI's
   client secret, uploads the example pages' external images as Drupal
   media, and pushes everything to the site. There's no browser login and
   nothing to confirm.
5. `./dev.sh` to run Canvas Workbench for local component development.
   This scaffolds `canvas_components/` too if you haven't run `ddev
   push-components` yet. **No Drupal site or `ddev` required** — if you just
   want to build components, `./dev.sh` can be your entire step 1, skipping
   steps 2–4 completely until you're ready to wire up the backend.

## Day to day

- `ddev build-local` — rebuild after pulling code/config changes.
- `./dev.sh` — local component preview/dev server. **Works with `ddev`
  stopped and no Drupal site installed** — nothing else here does.
- `ddev push-components` — push component changes to the Drupal site, then
  export config to `config/sync/`, because pushed components are Drupal
  config. Commit both. Images the site doesn't have yet (for example on a
  teammate's fresh install) are re-uploaded from their original URLs
  automatically.
- `ddev pull-components` — pull page, content template, or region edits made
  in the Drupal UI back into the codebase.

## Troubleshooting

- **`Node.js 22+ is required on your machine`**: the Canvas tooling runs on
  the host. See [Prerequisites](#prerequisites).
- **`No 'canvas' consumer found`**: the site was installed without this
  starter's `site-install`. Run `ddev site-install`.
- **Push fails with 401/403 right after changing OAuth settings**: delete the
  `CANVAS_CLIENT_SECRET` line from `canvas_components/.env` and re-run. A
  new secret is provisioned automatically.
- **`ddev build-local` says config/sync/ is empty**: run `ddev drush cex -y`
  on a working site and commit `config/sync/`.
- **npm warns that install scripts were blocked (esbuild, fsevents)**: this
  is harmless with npm 12+. Workbench and builds use esbuild's prebuilt
  platform binary.
