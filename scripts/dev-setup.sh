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
#   - Node.js 18+ & Yarn (npm install -g yarn)
#   - Python 3.9+ (for challenge import)
#   - The techfest challenge repo cloned alongside this repo
#
# Expected directory layout (clone both repos into the same folder):
#   workspace/
#     techfest/               ← challenge content repo
#     techfest-CTFd/          ← this repo (CTFd platform)
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CTFD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
THEME_DIR="$CTFD_DIR/CTFd/themes/arcade"

# Auto-detect challenge repo — check sibling directory first, then legacy nested path
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

step() {
  echo -e "\n${CYAN}▸${NC} ${GREEN}$1${NC}"
}

warn() {
  echo -e "  ${YELLOW}⚠ $1${NC}"
}

fail() {
  echo -e "  ${RED}✗ $1${NC}"
  exit 1
}

ok() {
  echo -e "  ${GREEN}✓ $1${NC}"
}

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

command -v node >/dev/null 2>&1 || fail "Node.js is not installed. Install from https://nodejs.org (v18+)"
NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
[ "$NODE_VER" -ge 18 ] 2>/dev/null || warn "Node.js v18+ recommended (found v$NODE_VER)"
ok "Node.js $(node -v)"

command -v yarn >/dev/null 2>&1 || {
  warn "Yarn not found, installing..."
  npm install -g yarn
}
ok "Yarn $(yarn -v)"

command -v python3 >/dev/null 2>&1 || warn "Python 3 not found — challenge import will be skipped"
ok "Python3 found"

# ---- Build arcade theme ----
step "Building arcade theme assets..."
cd "$THEME_DIR"
yarn install --frozen-lockfile 2>/dev/null || yarn install
yarn build
ok "Theme compiled (Vite)"

# ---- Start Docker services ----
step "Starting CTFd platform (Docker Compose)..."
cd "$CTFD_DIR"

if docker compose ps --status running 2>/dev/null | grep -q ctfd; then
  warn "CTFd containers already running. Restarting to pick up theme..."
  docker compose restart ctfd
else
  docker compose up -d --build
  echo "  Waiting for CTFd to initialize..."
  for i in $(seq 1 30); do
    if curl -sf http://localhost:8000/ >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
fi

curl -sf http://localhost:8000/ >/dev/null 2>&1 || fail "CTFd failed to start. Check: docker compose logs ctfd"
ok "CTFd running at http://localhost:8000"

# ---- Check if setup is needed ----
NEEDS_SETUP=false
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:8000/setup 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  NEEDS_SETUP=true
  step "Running initial CTFd setup..."

  # Get CSRF nonce from setup page
  NONCE=$(curl -sf -c /tmp/ctfd_cookies.txt http://localhost:8000/setup | grep -o 'name="nonce" value="[^"]*"' | grep -o 'value="[^"]*"' | cut -d'"' -f2)

  if [ -z "$NONCE" ]; then
    fail "Could not get setup CSRF nonce"
  fi

  # Submit setup form
  curl -sf -b /tmp/ctfd_cookies.txt \
    -X POST http://localhost:8000/setup \
    -d "ctf_name=TechFest+2026" \
    -d "ctf_description=Cyberpunk+Arcade+CTF" \
    -d "user_mode=teams" \
    -d "team_size=10" \
    -d "name=admin" \
    -d "email=admin@techfest.local" \
    -d "password=admin" \
    -d "ctf_logo=" \
    -d "ctf_banner=" \
    -d "ctf_small_icon=" \
    -d "ctf_theme=arcade" \
    -d "theme_color=" \
    -d "start=" \
    -d "end=" \
    -d "nonce=$NONCE" \
    -d "_submit=Submit" \
    -L -o /dev/null

  ok "CTFd initialized (admin/admin, teams mode, max 10/team)"
  rm -f /tmp/ctfd_cookies.txt
fi

# ---- Import challenges ----
if [ "$SKIP_CHALLENGES" = true ]; then
  warn "Skipping challenge import (--skip-challenges)"
elif [ -z "$CHALLENGE_REPO" ]; then
  warn "Challenge repo not found at expected path."
  warn "Expected: techfest/techfest/ alongside techfest-ctfd/"
  warn "You can import manually later with: ./scripts/import-challenges.sh"
else
  step "Importing challenges from $CHALLENGE_REPO..."

  if [ ! -f "$CHALLENGE_REPO/scripts/convert-to-ctfd.py" ]; then
    warn "convert-to-ctfd.py not found in challenge repo. Skipping import."
  else
    # Generate CTFd JSON
    CHALLENGES_JSON=$(python3 "$CHALLENGE_REPO/scripts/convert-to-ctfd.py" --categories-dir "$CHALLENGE_REPO/categories" 2>/dev/null)
    CHALLENGE_COUNT=$(echo "$CHALLENGES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

    if [ "$CHALLENGE_COUNT" -gt 0 ]; then
      # Get API token
      # Login first
      NONCE=$(curl -sf -c /tmp/ctfd_cookies.txt http://localhost:8000/login | sed -n 's/.*name="nonce"[^>]*value="\([^"]*\)".*/\1/p' | head -1)
      curl -sf -b /tmp/ctfd_cookies.txt -c /tmp/ctfd_cookies.txt \
        -X POST http://localhost:8000/login \
        -d "name=admin&password=admin&nonce=$NONCE&_submit=Submit" \
        -L -o /dev/null 2>/dev/null

      # Generate API token (with CSRF nonce)
      CSRF=$(curl -sf -b /tmp/ctfd_cookies.txt http://localhost:8000/settings 2>/dev/null | sed -n "s/.*'csrfNonce':[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)
      TOKEN_RESP=$(curl -sf -b /tmp/ctfd_cookies.txt \
        -X POST http://localhost:8000/api/v1/tokens \
        -H "Content-Type: application/json" \
        -H "CSRF-Token: $CSRF" \
        -d '{"description":"dev-setup","expiration":null}' 2>/dev/null)
      API_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['value'])" 2>/dev/null || echo "")

      if [ -z "$API_TOKEN" ]; then
        warn "Could not generate API token. Import challenges manually via admin panel."
      else
        # Import each challenge
        IMPORTED=0
        SKIPPED=0
        echo "$CHALLENGES_JSON" | python3 -c "
import sys, json, urllib.request

token = '$API_TOKEN'
challenges = json.load(sys.stdin)

for c in challenges:
    flags = c.pop('flags', [])
    tags = c.pop('tags', [])
    hints = c.pop('hints', [])
    files = c.pop('files', [])
    reqs = c.pop('requirements', None)

    # Create challenge
    req = urllib.request.Request(
        'http://localhost:8000/api/v1/challenges',
        data=json.dumps(c).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': f'Token {token}'},
        method='POST'
    )
    try:
        resp = urllib.request.urlopen(req)
        result = json.loads(resp.read())
        cid = result['data']['id']

        # Add flags
        for flag in flags:
            flag['challenge_id'] = cid
            freq = urllib.request.Request(
                'http://localhost:8000/api/v1/flags',
                data=json.dumps(flag).encode(),
                headers={'Content-Type': 'application/json', 'Authorization': f'Token {token}'},
                method='POST'
            )
            urllib.request.urlopen(freq)

        # Add tags
        for tag in tags:
            treq = urllib.request.Request(
                'http://localhost:8000/api/v1/tags',
                data=json.dumps({'challenge_id': cid, 'value': tag}).encode(),
                headers={'Content-Type': 'application/json', 'Authorization': f'Token {token}'},
                method='POST'
            )
            urllib.request.urlopen(treq)

        # Add hints
        for hint in hints:
            hint['challenge_id'] = cid
            hreq = urllib.request.Request(
                'http://localhost:8000/api/v1/hints',
                data=json.dumps(hint).encode(),
                headers={'Content-Type': 'application/json', 'Authorization': f'Token {token}'},
                method='POST'
            )
            urllib.request.urlopen(hreq)

        print(f'  ✓ {c[\"name\"]} ({c[\"category\"]}, {c[\"value\"]} pts)', file=sys.stderr)

    except Exception as e:
        if '400' in str(e) or 'already' in str(e).lower():
            print(f'  - {c[\"name\"]} (already exists)', file=sys.stderr)
        else:
            print(f'  ✗ {c[\"name\"]}: {e}', file=sys.stderr)
" 2>&1

        ok "Challenge import complete"
      fi
      rm -f /tmp/ctfd_cookies.txt
    else
      warn "No challenges found in $CHALLENGE_REPO/categories/"
    fi
  fi
fi

# ---- Ensure correct config (runs every time, not just first setup) ----
# Get API token if we don't already have one
if [ -z "${API_TOKEN:-}" ]; then
  step "Authenticating for config sync..."
  NONCE=$(curl -sf -c /tmp/ctfd_cookies.txt http://localhost:8000/login | sed -n 's/.*name="nonce"[^>]*value="\([^"]*\)".*/\1/p' | head -1)
  curl -sf -b /tmp/ctfd_cookies.txt -c /tmp/ctfd_cookies.txt \
    -X POST http://localhost:8000/login \
    -d "name=admin&password=admin&nonce=$NONCE&_submit=Submit" \
    -L -o /dev/null 2>/dev/null
  CSRF=$(curl -sf -b /tmp/ctfd_cookies.txt http://localhost:8000/settings 2>/dev/null | sed -n "s/.*'csrfNonce':[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)
  TOKEN_RESP=$(curl -sf -b /tmp/ctfd_cookies.txt \
    -X POST http://localhost:8000/api/v1/tokens \
    -H "Content-Type: application/json" \
    -H "CSRF-Token: $CSRF" \
    -d '{"description":"dev-setup-config","expiration":null}' 2>/dev/null)
  API_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['value'])" 2>/dev/null || echo "")
  rm -f /tmp/ctfd_cookies.txt
fi

if [ -n "${API_TOKEN:-}" ]; then
  step "Syncing platform config..."

  # Ensure theme is set to arcade
  curl -sf -X PATCH "http://localhost:8000/api/v1/configs/ctf_theme" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"value": "arcade"}' -o /dev/null 2>/dev/null
  ok "Theme: arcade"

  # Ensure CTF name is correct
  curl -sf -X PATCH "http://localhost:8000/api/v1/configs/ctf_name" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"value": "TechFest 2026"}' -o /dev/null 2>/dev/null
  ok "CTF name: TechFest 2026"

  # Always update landing page content
  step "Setting up landing page..."
  curl -sf -X PATCH "http://localhost:8000/api/v1/pages/1" \
    -H "Authorization: Token $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "content": "<div class=\"landing-hero\"><div class=\"hero-glitch\" data-text=\"TECHFEST CTF 2026\">TECHFEST CTF 2026</div><div class=\"hero-tagline typewriter\">CYBERPUNK ARCADE EDITION</div><div class=\"hero-cta\"><a href=\"/challenges\" class=\"hero-btn\">INSERT COIN</a><a href=\"/register\" class=\"hero-btn hero-btn-alt\">JOIN THE GRID</a></div><div class=\"hero-stats\"><div class=\"hero-stat\"><span class=\"hero-stat-num\">71</span><span class=\"hero-stat-label\">CHALLENGES</span></div><div class=\"hero-stat\"><span class=\"hero-stat-num\">9</span><span class=\"hero-stat-label\">ZONES</span></div><div class=\"hero-stat\"><span class=\"hero-stat-num\">10</span><span class=\"hero-stat-label\">MAX PARTY</span></div></div></div>"
    }' -o /dev/null
  ok "Landing page configured"
else
  warn "Could not get API token — landing page and config must be set manually via admin panel."
fi

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
echo -e "  ${NC}Rebuild theme:${NC}  ./scripts/dev-setup.sh --rebuild-theme"
echo -e "  ${NC}View logs:${NC}      docker compose logs -f ctfd"
echo -e "  ${NC}Stop:${NC}           docker compose down"
echo -e "  ${NC}Restart:${NC}        docker compose restart ctfd"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""
