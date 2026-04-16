#!/usr/bin/env python3
"""
TechFest CTF 2026 — Docker Init Script
========================================
Runs once after CTFd starts to:
  1. Complete initial setup (admin user, teams mode, arcade theme)
  2. Import challenges from the mounted challenge repo
  3. Configure landing page, CTF name, and theme

Usage (called by docker-compose init service):
  python3 /opt/CTFd/scripts/docker-init.py

Environment variables:
  CTFD_URL       — CTFd base URL (default: http://ctfd:8000)
  CHALLENGE_REPO — Path to challenge repo mount (default: /challenges)
"""

import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.cookiejar import CookieJar

CTFD_URL = os.environ.get("CTFD_URL", "http://ctfd:8000").rstrip("/")
CHALLENGE_REPO = os.environ.get("CHALLENGE_REPO", "/challenges")

# ANSI colors
GREEN = "\033[0;32m"
CYAN = "\033[0;36m"
YELLOW = "\033[1;33m"
RED = "\033[0;31m"
NC = "\033[0m"


def log(msg):
    print(f"{CYAN}▸{NC} {msg}", flush=True)


def ok(msg):
    print(f"  {GREEN}✓ {msg}{NC}", flush=True)


def warn(msg):
    print(f"  {YELLOW}⚠ {msg}{NC}", flush=True)


def fail(msg):
    print(f"  {RED}✗ {msg}{NC}", flush=True)
    sys.exit(1)


# ---------------------------------------------------------------------------
# HTTP helpers using stdlib (no requests dependency)
# ---------------------------------------------------------------------------

cookie_jar = CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))


def http_get(path, allow_redirects=True):
    """GET request, returns (status_code, body_text)."""
    url = f"{CTFD_URL}{path}"
    try:
        resp = opener.open(url)
        return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return 0, str(e)


def http_post_form(path, data):
    """POST form-encoded data, returns (status_code, body_text)."""
    url = f"{CTFD_URL}{path}"
    encoded = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=encoded, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        resp = opener.open(req)
        return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")


def http_post_json(path, data, token=None):
    """POST JSON, returns (status_code, parsed_json)."""
    url = f"{CTFD_URL}{path}"
    req = urllib.request.Request(
        url, data=json.dumps(data).encode(), method="POST"
    )
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Token {token}")
    try:
        resp = opener.open(req)
        return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read())
        except Exception:
            body = {"error": str(e)}
        return e.code, body


def http_get_json(path, token=None):
    """GET JSON, returns (status_code, parsed_json)."""
    url = f"{CTFD_URL}{path}"
    req = urllib.request.Request(url, method="GET")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Token {token}")
    try:
        resp = opener.open(req)
        return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read())
        except Exception:
            body = {"error": str(e)}
        return e.code, body


def http_patch_json(path, data, token):
    """PATCH JSON, returns (status_code, parsed_json)."""
    url = f"{CTFD_URL}{path}"
    req = urllib.request.Request(
        url, data=json.dumps(data).encode(), method="PATCH"
    )
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Token {token}")
    try:
        resp = opener.open(req)
        return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read())
        except Exception:
            body = {"error": str(e)}
        return e.code, body


def extract_nonce(html):
    """Extract CSRF nonce from HTML form."""
    m = re.search(r'name=["\']nonce["\'][^>]*value=["\']([^"\']+)', html)
    if m:
        return m.group(1)
    m = re.search(r'value=["\']([^"\']+)["\'][^>]*name=["\']nonce["\']', html)
    if m:
        return m.group(1)
    return None


def extract_csrf_nonce(html):
    """Extract csrfNonce from JS config in page."""
    m = re.search(r"['\"]csrfNonce['\"]:\s*['\"]([^'\"]+)", html)
    return m.group(1) if m else None


# ---------------------------------------------------------------------------
# Step 1: Wait for CTFd
# ---------------------------------------------------------------------------

def wait_for_ctfd():
    log("Waiting for CTFd...")
    for i in range(60):
        try:
            code, _ = http_get("/")
            if code in (200, 302):
                ok(f"CTFd responding (HTTP {code})")
                return
        except Exception:
            pass
        time.sleep(2)
    fail("CTFd did not start within 120 seconds")


# ---------------------------------------------------------------------------
# Step 2: Initial setup (if needed)
# ---------------------------------------------------------------------------

def run_setup():
    log("Checking if initial setup is needed...")
    code, body = http_get("/setup")

    if code != 200 or "setup" not in body.lower():
        ok("Already set up — skipping")
        return

    log("Running initial setup...")
    nonce = extract_nonce(body)
    if not nonce:
        fail("Could not extract nonce from setup page")

    code, _ = http_post_form("/setup", {
        "ctf_name": "TechFest 2026",
        "ctf_description": "Cyberpunk Arcade CTF",
        "user_mode": "teams",
        "team_size": "10",
        "name": "admin",
        "email": "admin@techfest.local",
        "password": "admin",
        "ctf_logo": "",
        "ctf_banner": "",
        "ctf_small_icon": "",
        "ctf_theme": "arcade",
        "theme_color": "",
        "start": "",
        "end": "",
        "nonce": nonce,
        "_submit": "Submit",
    })

    ok("CTFd initialized (admin/admin, teams mode, arcade theme)")


# ---------------------------------------------------------------------------
# Step 3: Get API token
# ---------------------------------------------------------------------------

def get_api_token():
    log("Authenticating as admin...")

    # Login
    code, body = http_get("/login")
    nonce = extract_nonce(body)
    if not nonce:
        fail("Could not extract nonce from login page")

    code, body = http_post_form("/login", {
        "name": "admin",
        "password": "admin",
        "nonce": nonce,
        "_submit": "Submit",
    })

    # Get CSRF from settings page (proves login succeeded)
    code, body = http_get("/settings")
    csrf = extract_csrf_nonce(body)
    if not csrf:
        fail("Login failed — could not reach settings page. Check admin credentials.")

    # Create API token (session auth requires CSRF-Token header)
    url = f"{CTFD_URL}/api/v1/tokens"
    req = urllib.request.Request(
        url,
        data=json.dumps({"description": "docker-init", "expiration": None}).encode(),
        method="POST",
    )
    req.add_header("Content-Type", "application/json")
    req.add_header("CSRF-Token", csrf)
    try:
        resp = opener.open(req)
        data = json.loads(resp.read())
        token = data["data"]["value"]
        ok("Authenticated")
        return token
    except Exception as e:
        fail(f"Could not create API token: {e}")


# ---------------------------------------------------------------------------
# Step 4: Import challenges
# ---------------------------------------------------------------------------

def import_challenges(token):
    log("Looking for challenge repo...")

    categories_dir = os.path.join(CHALLENGE_REPO, "categories")
    convert_script = os.path.join(CHALLENGE_REPO, "scripts", "convert-to-ctfd.py")

    if not os.path.isdir(categories_dir):
        warn(f"No categories/ directory at {CHALLENGE_REPO}")
        warn("Mount the challenge repo: CHALLENGE_REPO=../techfest docker compose up")
        return

    if not os.path.isfile(convert_script):
        warn(f"convert-to-ctfd.py not found at {convert_script}")
        return

    log("Converting challenges...")
    try:
        result = subprocess.run(
            ["python3", convert_script, "--categories-dir", categories_dir],
            capture_output=True, text=True, check=True,
        )
        challenges = json.loads(result.stdout)
    except Exception as e:
        warn(f"Challenge conversion failed: {e}")
        return

    # Fetch existing challenges so we can update them if they already exist
    log("Fetching existing challenges...")
    existing_map = {}  # name -> id
    code, resp = http_get_json("/api/v1/challenges?view=admin", token)
    if code == 200 and "data" in resp:
        for ec in resp["data"]:
            existing_map[ec["name"]] = ec["id"]
        if existing_map:
            ok(f"Found {len(existing_map)} existing challenges")

    log(f"Importing {len(challenges)} challenges...")
    imported = 0
    updated = 0
    skipped = 0
    failed = 0

    for c in challenges:
        flags = c.pop("flags", [])
        tags = c.pop("tags", [])
        hints = c.pop("hints", [])
        c.pop("files", [])
        requirements = c.pop("requirements", None)

        # Check if challenge already exists
        existing_id = existing_map.get(c["name"])

        if existing_id:
            # Update existing challenge (description, points, category, etc.)
            code, data = http_patch_json(
                f"/api/v1/challenges/{existing_id}", c, token
            )
            if code == 200:
                updated += 1
                print(f"  {CYAN}↻{NC} {c['name']} (updated)", flush=True)
            else:
                failed += 1
                print(f"  {RED}✗{NC} {c['name']}: update failed HTTP {code}", flush=True)
            continue

        # Create new challenge
        code, data = http_post_json("/api/v1/challenges", c, token=token)

        if code == 200:
            cid = data["data"]["id"]

            for flag in flags:
                flag["challenge_id"] = cid
                http_post_json("/api/v1/flags", flag, token=token)

            for tag in tags:
                http_post_json("/api/v1/tags", {"challenge_id": cid, "value": tag}, token=token)

            for hint in hints:
                hint["challenge_id"] = cid
                http_post_json("/api/v1/hints", hint, token=token)

            imported += 1
            print(f"  {GREEN}✓{NC} {c['name']} ({c['category']}, {c['value']} pts)", flush=True)

        elif code == 400:
            skipped += 1

        else:
            failed += 1
            print(f"  {RED}✗{NC} {c['name']}: HTTP {code}", flush=True)

    ok(f"Import complete — {imported} new, {updated} updated, {skipped} skipped, {failed} failed")


# ---------------------------------------------------------------------------
# Step 5: Sync config (theme, name, landing page)
# ---------------------------------------------------------------------------

LANDING_PAGE_HTML = (
    '<div class="landing-hero">'
    '<div class="hero-glitch" data-text="TECHFEST CTF 2026">TECHFEST CTF 2026</div>'
    '<div class="hero-tagline typewriter">CYBERPUNK ARCADE EDITION</div>'
    '<div class="hero-cta">'
    '<a href="/challenges" class="hero-btn">INSERT COIN</a>'
    '<a href="/register" class="hero-btn hero-btn-alt">JOIN THE GRID</a>'
    '</div>'
    '<div class="hero-stats">'
    '<div class="hero-stat"><span class="hero-stat-num">71</span>'
    '<span class="hero-stat-label">CHALLENGES</span></div>'
    '<div class="hero-stat"><span class="hero-stat-num">9</span>'
    '<span class="hero-stat-label">ZONES</span></div>'
    '<div class="hero-stat"><span class="hero-stat-num">10</span>'
    '<span class="hero-stat-label">MAX PARTY</span></div>'
    '</div></div>'
)


def sync_config(token):
    log("Syncing platform config...")

    code, _ = http_patch_json("/api/v1/configs/ctf_name", {"value": "TechFest 2026"}, token)
    if code == 200:
        ok("CTF name: TechFest 2026")
    else:
        warn(f"Failed to set CTF name (HTTP {code})")

    code, _ = http_patch_json("/api/v1/configs/ctf_theme", {"value": "arcade"}, token)
    if code == 200:
        ok("Theme: arcade")
    else:
        warn(f"Failed to set theme (HTTP {code})")

    # Find the landing page by route instead of assuming ID 1
    page_id = find_index_page(token)
    if page_id:
        code, _ = http_patch_json(
            f"/api/v1/pages/{page_id}",
            {"content": LANDING_PAGE_HTML, "format": "html"},
            token,
        )
        if code == 200:
            ok("Landing page configured")
        else:
            warn(f"Failed to update landing page (HTTP {code})")
    else:
        # No index page exists — create one
        log("No index page found, creating one...")
        code, data = http_post_json("/api/v1/pages", {
            "title": "TechFest 2026",
            "route": "index",
            "content": LANDING_PAGE_HTML,
            "format": "html",
            "draft": False,
            "hidden": False,
            "auth_required": False,
        }, token=token)
        if code == 200:
            ok("Landing page created")
        else:
            warn(f"Failed to create landing page (HTTP {code}, {data})")


def find_index_page(token):
    """Find the page with route='index', return its ID or None."""
    code, data = http_get_json("/api/v1/pages?type=page", token)
    if code != 200 or "data" not in data:
        warn(f"Could not list pages (HTTP {code})")
        return None

    for page in data["data"]:
        if page.get("route") == "index":
            return page["id"]

    return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print(f"\n{CYAN}╔══════════════════════════════════════════╗{NC}")
    print(f"{CYAN}║{NC}  TechFest CTF 2026 — Docker Init         {CYAN}║{NC}")
    print(f"{CYAN}╚══════════════════════════════════════════╝{NC}\n")

    wait_for_ctfd()
    run_setup()
    token = get_api_token()
    import_challenges(token)
    sync_config(token)

    print(f"\n{GREEN}  ✓ Init complete!{NC}")
    print(f"  {CYAN}Platform:{NC}  {CTFD_URL}")
    print(f"  {CYAN}Admin:{NC}     admin / admin")
    print(f"  {CYAN}Theme:{NC}     arcade\n")


if __name__ == "__main__":
    main()
