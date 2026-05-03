# Contributing to TechFest CTF 2026 — Platform

This is a forked CTFd with a heavily customized `arcade` theme and an automated
challenge-import pipeline. Challenge content lives in a sibling repo.

> Looking to contribute upstream to CTFd itself (not this fork)? See the
> [Upstream CTFd Contributing Guide](#upstream-ctfd-contributing-guide) at the bottom
> of this document.

---

## 1. Repo Layout

```
workspace/
├── techfest/techfest/           ← Challenge content
└── techfest-ctfd/techfest-CTFd/ ← THIS repo
```

`CHALLENGE_REPO` env var is passed to `docker-compose.yml` as a relative path from
this directory. The expected value is `../../techfest/techfest`.

---

## 2. First-Time Setup

**Prereqs:** Docker Desktop. Nothing else needs to be installed on the host.

```bash
docker compose down -v
docker compose build init ctfd

CHALLENGE_REPO=../../techfest/techfest docker compose up -d
docker compose logs init -f
```

Open `http://localhost:8000` → `admin` / `admin`.

Expected init log highlights:
- `✓ Import complete — 94 new, 0 updated, 0 skipped, 0 failed`
- `✓ Uploaded 92 challenge file(s) total`
- `✓ Rules page created at /rules`

---

## 3. What's Custom Here (vs. stock CTFd)

### Arcade theme (`CTFd/themes/arcade/`)
- Full cyberpunk/arcade visual overhaul — neon palette, glitch effects, data-rain canvas
- Pac-Man maze category selector on `/challenges` (responsive — see `_syncOverlay()`
  in `assets/js/challenges.js`)
- Arcade cabinet chassis wraps every page on screens ≥1400px (marquee, side rails,
  control deck with joystick + 6 buttons)
- Attract mode overlay on the landing page (30s idle → full-screen demo)
- 15 easter eggs embedded in the theme — these are real challenges (category `easter-eggs`
  in the challenge repo)

### Rules Acceptance
- `/rules` page is synced from challenge repo's `pages/rules.md`
- `register.html` has a required checkbox + disabled submit until it's ticked
- Footer on every page has a `/rules` link

### Init Container (`scripts/docker-init.py`)
- Runs once at stack startup
- Waits for CTFd health → runs CTFd initial setup if DB is empty → creates admin API
  token → runs challenge import → creates/updates rules page + landing page
- **Uploads challenge files** via multipart `POST /api/v1/files` (stdlib-only, no
  `requests` dependency)
- Idempotent — safe to re-run (update instead of duplicate, skip already-uploaded files)

### Docker Compose
- **All volumes are named volumes.** Bind mounts don't honor `docker compose down -v`,
  which is why we switched.
- `init` service mounts the challenge repo at `/challenges` via `CHALLENGE_REPO`

---

## 4. Making Changes

### Editing templates or SCSS
1. Edit under `CTFd/themes/arcade/`
2. Rebuild: `docker compose build --no-cache ctfd`
3. Restart: `docker compose up -d ctfd`
4. **If the browser still serves the old CSS hash:** CTFd caches its asset manifest at
   startup. Do a full `docker compose down && docker compose up -d` to reload.

### Editing `docker-init.py`
1. Edit the script
2. Rebuild the init image: `docker compose build init`
3. Re-run init: `docker compose up -d --force-recreate init`

### Adding a new Jinja template route
The arcade theme extends CTFd's template resolution. New `.html` files in
`CTFd/themes/arcade/templates/` override their stock counterparts automatically.

### Commit conventions
- First line: imperative, under 72 chars
- Body: explain *why*, not just *what*
- Claude-authored commits include a `Co-Authored-By` trailer — leave it in

---

## 5. Key File Paths

| What | Where |
|---|---|
| Arcade cabinet chassis HTML | `CTFd/themes/arcade/templates/base.html` (look for `cabinet-controls`) |
| Arcade cabinet + attract mode CSS | `CTFd/themes/arcade/assets/scss/main.scss` |
| Rules checkbox on registration | `CTFd/themes/arcade/templates/register.html` |
| Pac-Man maze logic | `CTFd/themes/arcade/assets/js/challenges.js` |
| Challenge import + file upload | `scripts/docker-init.py` |
| Named-volume config | `docker-compose.yml` |

---

## 6. Debugging Tips

**"Import complete — 0 new, 0 updated, 94 skipped"**
Means CTFd thinks these challenges already exist but the PATCH path isn't firing.
Check that `docker compose down -v` actually wiped the DB volume (it should — they're
named volumes now).

**"File not found" warnings in init logs**
The `CHALLENGE_REPO` bind mount path is wrong, OR the challenge repo doesn't have the
files in the expected `categories/<cat>/<chal>/files/` location. Check
`docker compose exec init ls /challenges/categories/` to verify the mount.

**New theme changes not showing up**
Two likely causes:
1. Build cache — use `docker compose build --no-cache ctfd`
2. Asset manifest cache — use `docker compose down && docker compose up -d`

**500 error on `/rules`**
The init container failed to create the page. Check `docker compose logs init` for a
warning line, and confirm `pages/rules.md` exists in the challenge repo.

---

## 7. Updating These Docs

**Three living documents — keep them accurate:**

1. **[`CLAUDE.md`](./CLAUDE.md)** — what's customized in this fork, key file paths
2. **`CONTRIBUTING.md`** (this file) — workflow, debugging, conventions
3. **`TASKS.md`** in the challenge repo at
   [`../../techfest/techfest/TASKS.md`](../../techfest/techfest/TASKS.md) — running
   project-wide backlog

If you make a change that affects how people run, build, or debug the platform, update
CLAUDE.md and CONTRIBUTING.md in the same commit.

If you complete a task — even a small one — **check it off in `TASKS.md` in the same
commit that finishes it**. Never delete a completed task; we keep the [x] history so
future sessions can see what's been done. If you discover new work that needs doing,
add it to TASKS.md immediately, don't rely on memory.

Common triggers to update CLAUDE.md / CONTRIBUTING.md:
- Changes to `docker-compose.yml` (ports, volumes, services)
- Changes to the init pipeline
- New theme features or arcade components
- URL / route additions (e.g. a new page route)
- Any new "gotcha" worth warning future devs about

Any Claude session working on this repo should keep these files accurate.

---

---

# Upstream CTFd Contributing Guide

*(Preserved from the CTFd fork base — applies if you want to contribute back to
upstream CTFd itself, not to this TechFest fork.)*

## How to contribute to CTFd

#### **Did you find a bug?**

- **Do not open up a GitHub issue if the bug is a security vulnerability in CTFd**. Instead [email the details to us at support@ctfd.io](mailto:support@ctfd.io).

- **Ensure the bug was not already reported** by searching on GitHub under [Issues](https://github.com/CTFd/CTFd/issues).

- If you're unable to find an open issue addressing the problem, [open a new one](https://github.com/CTFd/CTFd/issues/new). Be sure to fill out the issue template with a **title and clear description**, and as much relevant information as possible (e.g. deployment setup, browser version, etc).

#### **Did you write a patch that fixes a bug or implements a new feature?**

- Open a new pull request with the patch.

- Ensure the PR description clearly describes the problem and solution. Include the relevant issue number if applicable.

- Ensure all status checks pass. PR's with test failures will not be merged. PR's with insufficient coverage may be merged depending on the situation.

#### **Did you fix whitespace, format code, or make a purely cosmetic patch?**

Changes that are cosmetic in nature and do not add anything substantial to the stability, functionality, or testability of CTFd will generally not be accepted.
