# TechFest CTF 2026 — Developer Guide

## Quick Start (One Command)

```bash
./scripts/dev-setup.sh
```

This will:
1. Install theme dependencies and build the arcade theme (Vite)
2. Start CTFd + MariaDB + Redis + Nginx via Docker Compose
3. Run initial CTFd setup (admin/admin, teams mode, 10 max per team)
4. Import all challenges from the challenge repo (if found)
5. Configure the landing page

**Platform:** http://localhost:8000  
**Admin:** admin / admin

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker Desktop | Latest | https://docker.com |
| Node.js | 18+ | https://nodejs.org |
| Yarn | 1.x | `npm install -g yarn` |
| Python | 3.9+ | https://python.org |

## Repository Layout

Clone both repos into the same parent folder:

```bash
mkdir techfest-workspace && cd techfest-workspace
git clone <platform-repo-url> techfest-CTFd
git clone <challenges-repo-url> techfest
```

```
techfest-workspace/
  techfest-CTFd/              ← Platform repo (forked CTFd + arcade theme)
    CTFd/themes/arcade/       ← Custom theme
      assets/                 ← Source files (SCSS, JS) — edit these
        scss/main.scss        ← All styles
        js/challenges.js      ← Maze, zone view, challenge logic
      static/                 ← Compiled output (Vite) — don't edit
      templates/              ← Jinja2 templates
    docker-compose.yml        ← Platform services
    scripts/
      dev-setup.sh            ← Full setup script
      import-challenges.sh    ← Challenge import only
    DEV-GUIDE.md              ← This file

  techfest/                   ← Challenge content repo
    categories/               ← 9 category folders with challenges
    scripts/
      convert-to-ctfd.py      ← Converts challenge.json → CTFd API format
      validate-challenges.py  ← Validates challenge structure
    docker-compose.yml        ← Challenge Docker services (web challenges)
```

## Theme Development

### Edit → Build → Refresh cycle

```bash
# 1. Edit source files
#    CSS:  CTFd/themes/arcade/assets/scss/main.scss
#    JS:   CTFd/themes/arcade/assets/js/challenges.js
#    HTML: CTFd/themes/arcade/templates/

# 2. Build with Vite
cd CTFd/themes/arcade && yarn build

# 3. Restart CTFd to clear manifest cache
docker compose restart ctfd

# 4. Hard refresh browser (Cmd+Shift+R / Ctrl+Shift+R)
```

Or use the shortcut:
```bash
./scripts/dev-setup.sh --rebuild-theme
```

### Key SCSS Variables

```scss
$cyber-bg:      #06060e;   // Background
$cyber-panel:   #0c0c1d;   // Panel backgrounds
$cyber-surface: #12122a;   // Card surfaces
$cyber-cyan:    #00f0ff;   // Primary accent
$cyber-pink:    #e100ff;   // Secondary accent
$cyber-green:   #39ff14;   // Success / cleared
$cyber-orange:  #ff6b35;   // Points / warnings
$cyber-red:     #ff003c;   // Danger / boss
$cyber-purple:  #7b2fff;   // Expert difficulty
```

### Key Fonts
- **Press Start 2P** — Titles, hero text
- **Orbitron** — Labels, buttons, category names
- **VT323** — Body text, stats, terminal-style content

---

## Architecture Overview

### Overworld (Pac-Man Maze)
- 3×3 grid of category nodes connected by corridors
- Waypoint nodes (J_TL, J_TR, etc.) for L-shaped pathfinding
- BFS pathfinding through `_mazeGraph` adjacency
- Pac-Man avatar animates between nodes, eats pellets

### Zone View (Split Panel)
- Left panel: vertical timeline of challenges with status dots
- Right panel: challenge detail (description, hints, flag input)
- Replaces the default CTFd modal for in-zone challenge viewing

### Challenge States
| State | Dot | Card Border | Badge |
|-------|-----|-------------|-------|
| Default | Numbered, dim | Dark border | — |
| Next | Cyan, pulsing | Cyan glow | NEXT |
| Cleared | Green ✓ | Green accent | CLEARED |
| Boss | Red ★, pulsing | Red accent | BOSS FIGHT |
| Selected | White glow | Cyan highlight | — |

---

## Managing Challenges

### Import challenges
```bash
# Auto-detect challenge repo location
./scripts/import-challenges.sh

# Or specify path explicitly
./scripts/import-challenges.sh /path/to/techfest/repo
```

### Add a new challenge
1. Create in the challenge repo: `categories/<category>/<slug>/challenge.json`
2. Re-run import: `./scripts/import-challenges.sh`
3. Already-existing challenges are skipped (safe to re-run)

### Category ↔ Maze mapping
The maze layout is hardcoded in `challenges.js` (`_nodePositions`, `_mazeGraph`, `_categoryMeta`). If you add/rename categories, update those objects.

| Category | Maze Position | Icon | Color |
|----------|---------------|------|-------|
| Tutorial Zone | Top-left | ▶ | Green |
| Cipher Quest | Top-center | ◆ | Pink |
| Web Warfare | Top-right | ◎ | Cyan |
| Data Dungeon | Mid-left | ▦ | Purple |
| Secure Fortress | Mid-center | ⬡ | Orange |
| AI Arena | Mid-right | ⬢ | Pink |
| Packet Arena | Bot-left | ◈ | Cyan |
| Code Breakers | Bot-center | ⚡ | Yellow |
| Bonus Stage | Bot-right | ★ | Orange |

---

## Docker Services

| Service | Port | Purpose |
|---------|------|---------|
| ctfd | 8000 | CTFd platform |
| nginx | 80 | Reverse proxy |
| db | 3306 (internal) | MariaDB |
| cache | 6379 (internal) | Redis |

```bash
docker compose up -d          # Start all
docker compose down            # Stop all
docker compose restart ctfd    # Restart CTFd only
docker compose logs -f ctfd    # Stream CTFd logs
```

---

## Troubleshooting

### CSS not loading / old styles showing
CTFd caches the Vite manifest in memory. After `yarn build`:
```bash
docker compose restart ctfd    # Clear server cache
# Then Cmd+Shift+R in browser   # Clear browser cache
```

If that doesn't work:
```bash
docker compose down && docker compose up -d   # Full restart
```

### Scoreboard shows no data
Admin accounts are hidden by default. Create a regular user account and team to see scores on the leaderboard.

### Challenge modal opens instead of side panel
The side panel only activates in the zone view (after clicking a category). From the overworld, challenges aren't directly accessible — navigate to a zone first.

### Port 8000 already in use
```bash
lsof -i :8000                  # Find what's using it
docker compose down            # Stop CTFd containers
```
