# TechFest CTF 2026 — Platform (CTFd Fork)

> **For AI sessions:** This file is your entry point. Read it, then read the project's
> active backlog at [`../../techfest/techfest/TASKS.md`](../../techfest/techfest/TASKS.md)
> before making changes — it tracks open work and recently-completed items so you don't
> redo or duplicate effort.
> **For human devs:** See also [`CONTRIBUTING.md`](./CONTRIBUTING.md) for workflow,
> debugging tips, and the upstream CTFd contributing guide.
>
> **Three living documents — keep them accurate:**
> 1. **`CLAUDE.md`** (this file) — what's customized in this fork vs. stock CTFd
> 2. **`CONTRIBUTING.md`** — developer workflow, debugging, conventions
> 3. **`TASKS.md`** in the challenge repo — running project-wide backlog. **Check items
>    off when complete (don't delete); add new tasks as you discover them.**
>
> If you change Docker compose, the init pipeline, the arcade theme architecture, or
> add new gotchas, update CLAUDE.md and CONTRIBUTING.md in the same commit. If you
> complete or discover a task, update `../../techfest/techfest/TASKS.md` in the same commit.

## Project Purpose
This is a forked CTFd with a heavily customized `arcade` theme for TechFest CTF 2026.
Challenge content lives in a separate repo at `../../techfest/techfest/`.

## ⚠️ Directory Layout
```
workspace/
  techfest/
    techfest/           ← challenge repo
  techfest-ctfd/
    techfest-CTFd/      ← THIS repo (platform)
```
The nested structure affects `CHALLENGE_REPO` relative paths — from here the challenge
repo is at `../../techfest/techfest`.

---

## Key Customizations in This Fork

### 1. Arcade Theme (`CTFd/themes/arcade/`)
- Cyberpunk neon aesthetic: pink/cyan/green/orange palette
- Custom landing page with Pac-Man maze category selector (`assets/js/challenges.js`)
- Pac-Man maze is **responsive** (see `_syncOverlay()` method) — letterboxing + HTML
  overlay sync was a known issue, now fixed
- Glitch text effects, data-rain canvas, scan-line sweeps on every page
- 15 easter eggs embedded in the theme (console art, cookies, Konami code, CSS art
  gallery, etc.) — referenced as challenges in the `easter-eggs` category

### 2. Arcade Cabinet Chassis (`base.html` + `main.scss`)
- Body class `cabinet-mode` (default on) wraps every page in an arcade cabinet frame:
  glowing marquee (top), side rails, bottom control deck with joystick + 6 buttons
- Toggle at top-right persists to `localStorage` (`techfest-cabinet` key)
- Chassis only renders on screens ≥1400px — mobile/tablet gets clean UI
- **Attract mode** — 30s idle on landing page → full-screen demo overlay cycles through
  4 slides (title, zones, stats, insert coin). Any click/keypress dismisses.

### 3. Registration Rules Acceptance
- `register.html` has a required checkbox linking to `/rules`
- Submit button stays `disabled` until checkbox ticked (JS-enforced)
- Footer on every page has `/rules` link

### 4. Init Container (`scripts/docker-init.py`)
- Waits for CTFd to be ready
- Runs initial CTFd setup if DB is empty
- Fetches an admin API token
- Calls `convert-to-ctfd.py` in the mounted challenge repo, imports every challenge
- **Uploads challenge files** via multipart POST to `/api/v1/files` (added this round —
  previously files were silently discarded)
- Creates/updates the landing page and rules page from `pages/rules.md`
- Idempotent — safe to re-run

### 5. Docker Compose Changes (`docker-compose.yml`)
- All volumes are **named volumes**, not bind mounts. `docker compose down -v` actually
  wipes data now (bind mounts don't honor `-v`).
- `init` service mounts the challenge repo at `/challenges` via `CHALLENGE_REPO` env var

---

## Running Locally

```bash
# Fresh start
docker compose down -v
docker compose build init ctfd

# CHALLENGE_REPO path is relative to docker-compose.yml
CHALLENGE_REPO=../../techfest/techfest docker compose up -d

# Watch init
docker compose logs init -f
```

Expected init output:
- `✓ Import complete — 94 new, 0 updated, 0 skipped, 0 failed`
- `✓ Uploaded 92 challenge file(s) total`
- `✓ Rules page created at /rules`

**Admin:** `admin` / `admin` at `http://localhost:8000/admin`

---

## After Editing Theme Files

The arcade theme's SCSS is compiled during the CTFd docker image build (`theme-build`
stage in the Dockerfile). After editing anything in `CTFd/themes/arcade/`:

```bash
docker compose build --no-cache ctfd
docker compose up -d ctfd
```

**Gotcha:** CTFd's asset manifest is read at app startup. A simple restart sometimes keeps
serving a stale CSS hash. If you see 404s on the new hash, do a full `docker compose down`
then `up -d` to reload.

---

## Key File Paths

```
CTFd/themes/arcade/
├── templates/
│   ├── base.html              ← Arcade cabinet HTML, attract mode, easter eggs
│   ├── register.html          ← Required rules checkbox
│   └── login.html
├── assets/
│   ├── scss/main.scss         ← All arcade styling, cabinet chassis, attract mode
│   └── js/challenges.js       ← Pac-Man maze + responsive overlay sync

scripts/
└── docker-init.py             ← Challenge import + file upload pipeline

docker-compose.yml              ← Named volumes, init service with challenge repo mount
docker-compose.dev.yml          ← Source mount for hot-reload dev (rarely needed)
```

---

## Current State (as of this writing)
- ✅ Full pipeline working: 94 challenges + 92 files import cleanly
- ✅ Rules acceptance enforced on registration
- ✅ Arcade cabinet chassis + attract mode live
- ✅ Pac-Man maze responsive across screen sizes
- 🚧 Service-based challenges (Web Warfare, AI Arena, most of Secure Fortress) — source
  code is available as downloads, but live services aren't deployed. **This is the biggest
  remaining gap.**
- 🚧 Solve verification (walk through 94 challenges end-to-end) not yet done
- 🚧 Easter Egg verification against current theme state not yet done
- 🚧 POC placeholders in challenge repo's `pages/rules.md` need real addresses
