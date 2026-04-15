#!/usr/bin/env bash
# ================================================================
# Import challenges from the techfest challenge repo into CTFd
# ================================================================
# Usage:
#   ./scripts/import-challenges.sh                          # Auto-detect challenge repo
#   ./scripts/import-challenges.sh /path/to/techfest/repo   # Explicit path
#
# Requires CTFd to be running at localhost:8000 with admin/admin credentials.
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CTFD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Find challenge repo
if [ -n "${1:-}" ]; then
  CHALLENGE_REPO="$1"
else
  # Auto-detect: sibling directory first, then legacy nested path
  CHALLENGE_REPO=""
  for candidate in "$CTFD_DIR/../techfest" "$CTFD_DIR/../../techfest/techfest" "$CTFD_DIR/../techfest-challenges"; do
    if [ -d "$candidate/categories" ] && [ -f "$candidate/scripts/convert-to-ctfd.py" ]; then
      CHALLENGE_REPO="$(cd "$candidate" && pwd)"
      break
    fi
  done

  if [ -z "$CHALLENGE_REPO" ]; then
    echo -e "${RED}✗ Challenge repo not found. Clone it alongside this repo or pass the path.${NC}"
    echo "  Expected layout:"
    echo "    workspace/"
    echo "      techfest/          ← challenge repo"
    echo "      techfest-CTFd/     ← this repo"
    echo ""
    echo "  Or specify path: $0 /path/to/techfest/repo"
    exit 1
  fi
fi

echo -e "${CYAN}▸${NC} Challenge repo: $CHALLENGE_REPO"

# Verify CTFd is running
curl -sf http://localhost:8000/ >/dev/null 2>&1 || {
  echo -e "${RED}✗ CTFd is not running at localhost:8000${NC}"
  echo "  Start it first: cd $CTFD_DIR && docker compose up -d"
  exit 1
}

# Login and get API token
echo -e "${CYAN}▸${NC} Authenticating..."
NONCE=$(curl -sf -c /tmp/ctfd_import_cookies.txt http://localhost:8000/login | sed -n 's/.*name="nonce"[^>]*value="\([^"]*\)".*/\1/p' | head -1)
if [ -z "$NONCE" ]; then
  echo -e "${RED}✗ Could not extract CSRF nonce from login page${NC}"
  echo "  Is CTFd running at http://localhost:8000 and showing the login page?"
  exit 1
fi

LOGIN_CODE=$(curl -s -o /dev/null -w "%{http_code}" -b /tmp/ctfd_import_cookies.txt -c /tmp/ctfd_import_cookies.txt \
  -X POST http://localhost:8000/login \
  -d "name=admin&password=admin&nonce=$NONCE&_submit=Submit" \
  -L 2>/dev/null)
echo -e "  Login response: $LOGIN_CODE"

SETTINGS_PAGE=$(curl -sf -b /tmp/ctfd_import_cookies.txt http://localhost:8000/settings 2>/dev/null || echo "")
if echo "$SETTINGS_PAGE" | grep -q "csrfNonce"; then
  CSRF=$(echo "$SETTINGS_PAGE" | sed -n "s/.*'csrfNonce':[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)
else
  echo -e "${RED}✗ Login failed — could not reach settings page${NC}"
  echo "  Check credentials: admin / admin"
  echo "  If you changed the admin password, edit this script or use the admin panel."
  rm -f /tmp/ctfd_import_cookies.txt
  exit 1
fi

TOKEN_RESP=$(curl -sf -b /tmp/ctfd_import_cookies.txt \
  -X POST http://localhost:8000/api/v1/tokens \
  -H "Content-Type: application/json" \
  -H "CSRF-Token: $CSRF" \
  -d '{"description":"import-script","expiration":null}' 2>/dev/null || echo "")
API_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['value'])" 2>/dev/null || echo "")

if [ -z "$API_TOKEN" ]; then
  echo -e "${RED}✗ Could not generate API token${NC}"
  echo "  CSRF token: ${CSRF:-empty}"
  echo "  Token response: ${TOKEN_RESP:-empty}"
  echo ""
  echo "  Try a clean restart:"
  echo "    docker compose down -v"
  echo "    ./scripts/dev-setup.sh"
  rm -f /tmp/ctfd_import_cookies.txt
  exit 1
fi

rm -f /tmp/ctfd_import_cookies.txt

echo -e "  ${GREEN}✓ Authenticated${NC}"

# Convert challenges
echo -e "${CYAN}▸${NC} Converting challenges..."
CHALLENGES_JSON=$(python3 "$CHALLENGE_REPO/scripts/convert-to-ctfd.py" --categories-dir "$CHALLENGE_REPO/categories" 2>/dev/null)
COUNT=$(echo "$CHALLENGES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
echo -e "  Found $COUNT challenges"

# Import
echo -e "${CYAN}▸${NC} Importing..."
echo "$CHALLENGES_JSON" | python3 -c "
import sys, json, urllib.request

token = '$API_TOKEN'
challenges = json.load(sys.stdin)
imported = 0
skipped = 0
failed = 0

for c in challenges:
    flags = c.pop('flags', [])
    tags = c.pop('tags', [])
    hints = c.pop('hints', [])
    files = c.pop('files', [])
    reqs = c.pop('requirements', None)

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

        for flag in flags:
            flag['challenge_id'] = cid
            freq = urllib.request.Request(
                'http://localhost:8000/api/v1/flags',
                data=json.dumps(flag).encode(),
                headers={'Content-Type': 'application/json', 'Authorization': f'Token {token}'},
                method='POST'
            )
            urllib.request.urlopen(freq)

        for tag in tags:
            treq = urllib.request.Request(
                'http://localhost:8000/api/v1/tags',
                data=json.dumps({'challenge_id': cid, 'value': tag}).encode(),
                headers={'Content-Type': 'application/json', 'Authorization': f'Token {token}'},
                method='POST'
            )
            urllib.request.urlopen(treq)

        for hint in hints:
            hint['challenge_id'] = cid
            hreq = urllib.request.Request(
                'http://localhost:8000/api/v1/hints',
                data=json.dumps(hint).encode(),
                headers={'Content-Type': 'application/json', 'Authorization': f'Token {token}'},
                method='POST'
            )
            urllib.request.urlopen(hreq)

        imported += 1
        print(f'  \033[0;32m✓\033[0m {c[\"name\"]} ({c[\"category\"]}, {c[\"value\"]} pts)', file=sys.stderr)

    except Exception as e:
        if '400' in str(e):
            skipped += 1
            print(f'  \033[1;33m-\033[0m {c[\"name\"]} (already exists)', file=sys.stderr)
        else:
            failed += 1
            print(f'  \033[0;31m✗\033[0m {c[\"name\"]}: {e}', file=sys.stderr)

print(f'\n  Imported: {imported}  Skipped: {skipped}  Failed: {failed}', file=sys.stderr)
" 2>&1

echo -e "\n${GREEN}Done!${NC}"
