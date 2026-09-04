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
  key generation, `drush site-install`, then applies the recipe below.
- `.ddev/commands/web/build-local` — day-to-day rebuild after pulling changes.
- `recipes/canvas_starter/` — a Drupal recipe that installs Canvas (plus its
  `canvas_ai`, `canvas_dev_ai`, `canvas_dev_mode`, `canvas_oauth` submodules),
  the AI modules, Pathauto, and Simple OAuth in one shot. It intentionally
  contains no config — everything else (OAuth scopes, filter formats, page
  regions, AI agent definitions) ships as default config from those modules
  themselves; only content-specific config (content types, view modes,
  Pathauto patterns) is left for each project to define on its own.
- `push_components.sh` / `dev_theme.sh` — thin wrappers around the Canvas CLI
  and Canvas Workbench, reading the site URL/client ID from
  `canvas_components/.env` instead of hardcoding them.

`canvas_components/` itself is **not** part of this template — it's generated
fresh per project by the official scaffolder (see below), so it always starts
from the current version of that tooling.

## Kickstarting a new project

1. Copy this directory to your new project folder and `cd` into it, then
   `git init` (or clone this repo and re-point `origin`).
2. `ddev start`
3. `ddev site-install`
   - Installs Composer dependencies, generates an RSA key pair into `keys/`,
     runs `drush site-install standard`, and applies `recipes/canvas_starter`.
   - Prints two manual steps you still need to do once, in the UI:
     1. At `/admin/config/people/simple_oauth`, point the key paths at
        `keys/private.key` and `keys/public.key`.
     2. At `/admin/config/services/consumer`, create a consumer with the
        **Authorization Code** grant, **PKCE** enabled, **"Is Confidential?"**
        unchecked, and redirect URI `http://localhost:4444/callback`. Note its
        client ID.
4. Scaffold the component workspace:
   ```
   npx @drupal-canvas/create@latest
   ```
   This creates `canvas_components/` (React + Tailwind + the Canvas CLI/
   Workbench, from Acquia's "Nebula" starter) and a `canvas_components/.env.example`.
5. `cp canvas_components/.env.example canvas_components/.env` and fill in
   `CANVAS_SITE_URL` (your `*.ddev.site` URL) and `CANVAS_CLIENT_ID` (from
   step 3.2).
6. `./push_components.sh` — installs npm deps, opens a browser to log in via
   PKCE, then pushes the starter components to the site.
7. `./dev_theme.sh` to run Canvas Workbench for local component development.

## Day to day

- `ddev build-local` — rebuild after pulling code/config changes.
- `./dev_theme.sh` — local component preview/dev server.
- `./push_components.sh` — push component changes to the Drupal site.
