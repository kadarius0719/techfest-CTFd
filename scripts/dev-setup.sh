#!/usr/bin/env bash
# ================================================================
# TechFest CTF 2026 — Developer Setup
# ================================================================
# One-command setup for local development.
#
# Usage:
#   ./scripts/dev-setup.sh                     # Full setup
#   ./scripts/dev-setup.sh --skip-challenges   # Platform only (no challenge import)
#   ./scripts/dev-setup.sh --rebuild-theme     # Just rebuild the arcade theme
#
# Prerequisites:
#   - Docker & Docker Compose
#   - Node.js 18+ & Yarn (for local theme development only)
#   - The techfest challenge repo cloned alongside this repo
#
# NOTE: On a fresh machine with only Docker installed, you can skip
# this script entirely and just run:
#   CHALLENGE_REPO=../techfest docker compose up -d --build
#
# That builds the theme inside Docker and auto-configures everything.
# This script is for developers who want live code reload.
#
# Expected directory layout:
#   workspace/
#     techfest/               ← challenge content repo
#     techfest-CTFd/          ← this repo (CTFd platform)
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CTFD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
THEME_DIR="$CTFD_DIR/CTFd/themes/arcade"

# Auto-detect challenge repo
CHALLENGE_REPO=""
for candidate in "$CTFD_DIR/../techfest" "$CTFD_DIR/../../techfest/techfest" "$CTFD_DIR/../techfest-challenges"; do
  if [ -d "$candidate/categories" ] && [ -f "$candidate/scripts/convert-to-ctfd.py" ]; then
    CHALLENGE_REPO="$(cd "$candidate" && pwd)"
    break
  fi
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PINK='\033[0;35m'
NC='\033[0m'

banner() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${PINK}TECHFEST CTF 2026${NC} — Dev Setup            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${GREEN}Cyberpunk Arcade Edition${NC}                 ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
  echo ""
}

step() { echo -e "\n${CYAN}▸${NC} ${GREEN}$1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; exit 1; }
ok()   { echo -e "  ${GREEN}✓ $1${NC}"; }

# ---- Parse args ----
SKIP_CHALLENGES=false
REBUILD_ONLY=false

for arg in "$@"; do
  case $arg in
    --skip-challenges) SKIP_CHALLENGES=true ;;
    --rebuild-theme)   REBUILD_ONLY=true ;;
  esac
done

banner

# ---- Rebuild theme only mode ----
if [ "$REBUILD_ONLY" = true ]; then
  step "Rebuilding arcade theme..."
  cd "$THEME_DIR"
  yarn install --frozen-lockfile 2>/dev/null || yarn install
  yarn build
  ok "Theme built"
  step "Restarting CTFd to pick up new assets..."
  cd "$CTFD_DIR"
  docker compose restart ctfd
  ok "Done! Hard refresh your browser (Cmd+Shift+R)"
  exit 0
fi

# ---- Check prerequisites ----
step "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || fail "Docker is not installed. Install from https://docker.com"
ok "Docker found"

docker compose version >/dev/null 2>&1 || fail "Docker Compose is not available. Update Docker Desktop."
ok "Docker Compose found"

HAS_NODE=false
if command -v node >/dev/null 2>&1; then
  HAS_NODE=true
  ok "Node.js $(node -v) (theme will build locally for live dev)"
else
  warn "Node.js not found — theme will build inside Docker (no live reload)"
fi

command -v python3 >/dev/null 2>&1 || warn "Python 3 not found — challenge import requires Python"
ok "Python3 found"

# ---- Build theme locally if Node available (for live dev) ----
if [ "$HAS_NODE" = true ]; then
  step "Building arcade theme assets locally..."
  cd "$THEME_DIR"

  if ! command -v yarn >/dev/null 2>&1; then
    warn "Yarn not found, installing..."
    npm install -g yarn
  fi

  yarn install --frozen-lockfile 2>/dev/null || yarn install
  yarn build
  ok "Theme compiled (Vite)"
fi

# ---- Start Docker services ----
step "Starting CTFd platform..."
cd "$CTFD_DIR"

# Use dev override for source mounting if Node is available (live dev)
if [ "$HAS_NODE" = true ]; then
  COMPOSE_CMD="docker compose -f docker-compose.yml -f docker-compose.dev.yml"
else
  COMPOSE_CMD="docker compose"
fi

# Set challenge repo for init container
export CHALLENGE_REPO="${CHALLENGE_REPO:-./challenges}"

if $COMPOSE_CMD ps --status running 2>/dev/null | grep -q ctfd; then
  warn "CTFd containers already running. Restarting to pick up changes..."
  $COMPOSE_CMD restart ctfd
  # Re-run init container
  $COMPOSE_CMD rm -f init 2>/dev/null || true
  $COMPOSE_CMD up -d init
else
  $COMPOSE_CMD up -d --build
fi

# Wait for CTFd to be healthy
echo "  Waiting for CTFd to initialize..."
for i in $(seq 1 60); do
  if curl -sf http://localhost:8000/ >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

curl -sf http://localhost:8000/ >/dev/null 2>&1 || fail "CTFd failed to start. Check: docker compose logs ctfd"
ok "CTFd running at http://localhost:8000"

# Wait for init container to finish
step "Waiting for init container to complete setup..."
for i in $(seq 1 60); do
  STATUS=$($COMPOSE_CMD ps init --format '{{.State}}' 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "exited" ] || [ "$STATUS" = "unknown" ]; then
    break
  fi
  sleep 2
done

# Show init container output
$COMPOSE_CMD logs init 2>/dev/null || true

ok "Setup complete"

# ---- Done ----
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo ""
echo -e "  ${CYAN}Platform:${NC}  http://localhost:8000"
echo -e "  ${CYAN}Admin:${NC}     admin / admin"
echo -e "  ${CYAN}Theme:${NC}     arcade (cyberpunk)"
echo -e "  ${CYAN}Mode:${NC}      teams (max 10 per team)"
echo ""
echo -e "  ${YELLOW}Quick commands:${NC}"
if [ "$HAS_NODE" = true ]; then
  echo -e "  ${NC}Rebuild theme:${NC}  ./scripts/dev-setup.sh --rebuild-theme"
fi
echo -e "  ${NC}View logs:${NC}      docker compose logs -f ctfd"
echo -e "  ${NC}Init logs:${NC}      docker compose logs init"
echo -e "  ${NC}Stop:${NC}           docker compose down"
echo -e "  ${NC}Full reset:${NC}     docker compose down -v && docker compose up -d --build"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""
