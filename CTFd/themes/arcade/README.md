# Arcade Theme — TechFest CTF 2026

Custom CTFd theme with a cyberpunk arcade aesthetic. Built on CTFd's core-beta theme structure using Alpine.js, Bootstrap 5, and Vite.

## Features

- **Pac-Man maze overworld** — 9 category zones arranged as an interactive maze
- **Zone view** — Click a category node to enter its challenge list
- **Boss challenges** — "BOSS FIGHT" badges with animated glow borders, gated by prerequisites
- **Easter Egg zone** — Hidden `?` node with 15 secret challenges
- **Scoreboard** — Neon-styled high-score leaderboard with egg flair badges
- **Team profiles** — Trophy case showing discovered Easter Eggs
- **CRT effects** — Scanlines overlay, neon glow text-shadows, pixel borders

## Visual Design

- **Fonts:** Press Start 2P (headers), VT323 (body)
- **Colors:** Dark backgrounds (#0a0a0a, #1a1a2e), neon accents (#ff00ff, #00ffff, #39ff14, #ff6b35)
- **Effects:** CRT scanlines (CSS overlay), neon glow text-shadows, pixel borders, hover animations

## Directory Structure

```
arcade/
  assets/               Source files (JS, SCSS) — editable
  static/               Compiled output (Vite) — do not edit directly
  templates/            Jinja2 templates
  package.json          Node dependencies
  vite.config.js        Vite build configuration
```

## Building

The theme is built automatically inside Docker during `docker compose up --build`. No host tools required.

### For local development (live reload)

If you want to iterate on the theme with faster rebuilds:

```bash
# Prerequisites: Node.js 18+ and Yarn
cd CTFd/themes/arcade
yarn install
yarn build          # One-time production build
yarn dev            # Watch mode (rebuilds on file change)
```

Then use the dev compose override to mount your local source into the container:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

Or use the dev setup script which handles this automatically:

```bash
./scripts/dev-setup.sh               # Full setup with local theme build
./scripts/dev-setup.sh --rebuild-theme  # Just rebuild theme + restart
```

After rebuilding, hard-refresh your browser (Cmd+Shift+R) to pick up new assets.

## How It Works

- **`assets/`** contains the source SCSS and JavaScript files you edit
- **Vite** compiles these into content-hashed files in `static/` (e.g., `main-abc123.js`)
- **`static/.vite/manifest.json`** maps source paths to hashed filenames
- CTFd's `Assets()` helper reads the manifest to resolve `{{ Assets("path") }}` in templates
- The Dockerfile runs `yarn build` in a Node stage, then copies `static/` into the final image

## Based On

[CTFd core-beta theme](https://github.com/CTFd/core-beta) — Bootstrap 5 + Alpine.js + Vite rewrite of the CTFd core theme.
