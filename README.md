# Canvas Drupal starter

A reusable kickstart for a Drupal 11 site built around
[Drupal Canvas](https://project.pages.drupalcode.org/canvas/) code components,
running locally on [DDEV](https://ddev.com), with the Canvas CLI
(`npx canvas push`) wired up.

## What's in here

- `composer.json` — Drupal 11 + `drupal/canvas`, `drupal/ai`, `drupal/ai_agents`,
  `drupal/ai_provider_openai`, `drupal/pathauto`, `drupal/simple_oauth`.
- `.ddev/config.yaml` — PHP 8.4, Node 24 with Corepack enabled (needed for
  `npx`/`npm` inside the web container).
- `.ddev/commands/web/site-install` — fresh install: composer install, OAuth
  key generation, `drush site-install`, applies the recipe below, then
  configures the Simple OAuth key paths and creates the `canvas` consumer
  (Authorization Code + PKCE, redirect `http://localhost:4444/callback`) so
  `npx canvas push` works with no manual UI steps.
- `.ddev/commands/web/build-local` — day-to-day rebuild after pulling changes.
- `recipes/canvas_starter/` — a Drupal recipe that installs Canvas (plus its
  `canvas_ai`, `canvas_dev_ai`, `canvas_dev_mode`, `canvas_oauth` submodules),
  the AI modules, Pathauto, and Simple OAuth in one shot. It intentionally
  contains no config — everything else (OAuth scopes, filter formats, page
  regions, AI agent definitions) ships as default config from those modules
  themselves; only content-specific config (content types, view modes,
  Pathauto patterns) is left for each project to define on its own.
- `canvas-common.sh` — shared by the commands below: scaffolds
  `canvas_components/` and its `.env` on first run, and logs in via PKCE only
  when there's no stored token yet (or the site rejects it), instead of on
  every run.
- `.ddev/commands/host/push-components` / `pull-components` — `ddev
  push-components` pushes component/page/content-template/region changes to
  the Drupal site; `ddev pull-components` pulls edits made in the Drupal UI
  back into the codebase. Both run on the host (so `npx canvas login`'s
  browser flow works) and read the site URL straight from DDEV's
  `$DDEV_PRIMARY_URL`.
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
     configures the Simple OAuth key paths, and creates a `canvas` consumer
     (Authorization Code grant, PKCE, redirect `http://localhost:4444/callback`)
     — no manual UI steps needed.
4. `ddev push-components` — scaffolds `canvas_components/` (React + Tailwind +
   the Canvas CLI/Workbench, from Acquia's "Nebula" starter) with its `.env`
   pre-filled on first run, installs npm deps, opens a browser to log in via
   PKCE (one time only — the token is cached in
   `~/.config/drupal-canvas/oauth.json` and reused after that), then pushes
   the starter components to the site.
5. `./dev.sh` to run Canvas Workbench for local component development.
   This scaffolds `canvas_components/` too if you haven't run `ddev
   push-components` yet. **No Drupal site or `ddev` required** — if you just
   want to build components, `./dev.sh` can be your entire step 1, skipping
   steps 2–4 completely until you're ready to wire up the backend.

## Day to day

- `ddev build-local` — rebuild after pulling code/config changes.
- `./dev.sh` — local component preview/dev server. **Works with `ddev`
  stopped and no Drupal site installed** — nothing else here does.
- `ddev push-components` — push component changes to the Drupal site.
- `ddev pull-components` — pull page, content template, or region edits made
  in the Drupal UI back into the codebase.
