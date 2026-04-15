# TechFest CTF 2026 — Platform

Custom CTFd platform for TechFest CTF 2026, featuring a cyberpunk arcade theme with a Pac-Man maze overworld, hidden Easter Egg challenges, and team-based competition.

Built on [CTFd 3.8.3](https://github.com/CTFd/CTFd).

## Quick Start (Docker Only)

The only prerequisite is **Docker**. The theme, admin account, challenges, and landing page are all configured automatically.

```bash
# Clone both repos side by side
mkdir techfest-workspace && cd techfest-workspace
git clone <platform-repo-url> techfest-CTFd
git clone <challenges-repo-url> techfest

# Start everything
cd techfest-CTFd
CHALLENGE_REPO=../techfest docker compose up -d --build
```

Wait ~60 seconds for the init container to finish, then open:

- **Platform:** http://localhost:8000
- **Admin panel:** http://localhost:8000/admin
- **Credentials:** admin / admin

Watch setup progress with:

```bash
docker compose logs -f init
```

### What Happens Automatically

The `init` container runs once after CTFd is healthy and:

1. Creates the admin account (admin/admin, teams mode, max 10/team)
2. Sets the theme to `arcade`
3. Imports all challenges from the mounted challenge repo
4. Configures the TechFest landing page
5. Exits

The Easter Eggs plugin automatically hides the 15 Easter Egg challenges from the public API on startup.

## Developer Setup (Live Reload)

For local development with live code changes, you'll need Node.js 18+ on the host:

```bash
# Install yarn if needed
npm install -g yarn

# Full dev setup (builds theme locally, mounts source into container)
./scripts/dev-setup.sh
```

This uses `docker-compose.dev.yml` to mount the source directory into the container for live reload. After editing theme files:

```bash
# Rebuild theme and restart
./scripts/dev-setup.sh --rebuild-theme
```

## Project Structure

```
techfest-CTFd/
  CTFd/
    plugins/
      easter_eggs/            Easter Egg plugin (hidden challenges, secure API)
    themes/
      arcade/                 Cyberpunk arcade theme
        assets/               Source files (JS, SCSS)
        static/               Compiled output (Vite)
        templates/            Jinja2 templates
  scripts/
    dev-setup.sh              Developer setup script
    docker-init.py            Docker init container script
    import-challenges.sh      Standalone challenge import
  docker-compose.yml          Production compose (self-contained)
  docker-compose.dev.yml      Dev override (source mount for live reload)
  Dockerfile                  Multi-stage: Node theme build + Python runtime
```

## Architecture

### Arcade Theme

A custom CTFd theme built with Alpine.js and Vite:

- **Maze overworld** — 9 category zones arranged as a Pac-Man maze
- **Zone view** — Click a category node to enter its challenge list
- **Boss challenges** — Special gated challenges at the end of each zone
- **Easter Egg zone** — Hidden `?` node with 15 secret challenges
- **Scoreboard** — Neon-styled leaderboard with egg flair badges
- **Team profiles** — Trophy case showing discovered Easter Eggs

### Easter Eggs Plugin

Located at `CTFd/plugins/easter_eggs/`:

- Registers 6 in-platform Easter Eggs (robots.txt, response headers, sitemap, hidden API, teapot, IDDQD)
- Auto-hides Easter Egg challenges from `/api/v1/challenges` (sets `state=hidden`)
- Provides secure endpoints:
  - `GET /api/v1/egg-status` — Minimal egg data for the `?` zone UI (auth required)
  - `GET /api/v1/egg-solves` — Per-team solve counts for scoreboard flair
- Server-side trophy map prevents leaking challenge names to the client

### Docker Setup

The Dockerfile uses a 3-stage build:

1. **theme-build** (Node 18) — Runs `yarn install && yarn build` to compile the arcade theme
2. **build** (Python 3.11) — Installs Python dependencies
3. **release** (Python 3.11 slim) — Final image with compiled theme + Python runtime

The `init` service in docker-compose.yml handles first-time setup and challenge import.

## Common Commands

```bash
# Start platform (Docker only, no other dependencies)
CHALLENGE_REPO=../techfest docker compose up -d --build

# View logs
docker compose logs -f ctfd      # Platform logs
docker compose logs init          # Init/setup logs

# Restart after config changes
docker compose restart ctfd

# Re-run init (reimport challenges, reset config)
docker compose rm -f init && docker compose up -d init

# Full reset (wipe database and start fresh)
docker compose down -v
CHALLENGE_REPO=../techfest docker compose up -d --build

# Dev: rebuild theme after editing SCSS/JS
./scripts/dev-setup.sh --rebuild-theme

# Standalone challenge import
./scripts/import-challenges.sh ../techfest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CHALLENGE_REPO` | `./challenges` | Path to challenge repo (for init container) |
| `DATABASE_URL` | `mysql+pymysql://ctfd:ctfd@db/ctfd` | Database connection string |
| `REDIS_URL` | `redis://cache:6379` | Redis connection string |
| `UPLOAD_FOLDER` | `/var/uploads` | File upload directory |
| `WORKERS` | `1` | Gunicorn worker count |

## Credits

- Platform: [CTFd](https://github.com/CTFd/CTFd) by [CTFd LLC](https://ctfd.io/)
- Arcade theme and Easter Eggs plugin: TechFest 2026 team
