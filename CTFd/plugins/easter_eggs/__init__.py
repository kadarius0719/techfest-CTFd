"""
TechFest CTF 2026 — Easter Eggs Plugin
=======================================
Adds hidden flags throughout the CTFd platform for bonus challenges.

Easter eggs implemented here:
  - robots.txt          → Disallow /secret-arcade-room (flag at that URL)
  - X-Secret-Level      → Response header on every page
  - sitemap.xml         → Points to /bonus-level-unlocked (flag at that URL)
  - /api/easter-egg     → Undocumented API endpoint
  - /coffee             → HTTP 418 I'm a Teapot
  - IDDQD team name     → Flag in JSON response

Security:
  - Easter Egg challenges are set to state="hidden" so they don't appear
    in /api/v1/challenges for non-admin users.
  - A custom /api/v1/egg-status endpoint provides minimal data (IDs, points,
    solved status) for the ? zone UI without leaking names or category.
"""

from flask import Blueprint, Response, make_response, request, session, jsonify

from CTFd.utils import set_config, get_config
from CTFd.utils.user import get_current_team, get_current_user, is_admin
from CTFd.models import db, Challenges, Solves
from CTFd.cache import cache


# The trophy map lives server-side so we don't leak challenge names to the client
TROPHY_MAP = {
    "View Source Veteran":      {"icon": "\U0001f441",  "name": "THE ARCHITECT"},
    "The Konami Code":          {"icon": "\U0001f3ae", "name": "CHEAT CODE MASTER"},
    "Robots Exclusion":         {"icon": "\U0001f916", "name": "THE EXCLUDED"},
    "Cookie Monster":           {"icon": "\U0001f36a", "name": "COOKIE JAR"},
    "Header Hunter":            {"icon": "\U0001f4e1", "name": "SIGNAL INTERCEPTOR"},
    "404 Warp Zone":            {"icon": "\U0001f300", "name": "WARP ZONE"},
    "Console Cowboy":           {"icon": "\U0001f4bb", "name": "CONSOLE COWBOY"},
    "Favicon Secret":           {"icon": "\U0001f50d", "name": "PIXEL HUNTER"},
    "Sitemap Spelunker":        {"icon": "\U0001f5fa",  "name": "CARTOGRAPHER"},
    "Inspect the Scoreboard":   {"icon": "\U0001f3c6", "name": "HIDDEN SCORE"},
    "CSS Art Gallery":          {"icon": "\U0001f3a8", "name": "STYLE MASTER"},
    "API Archaeologist":        {"icon": "\u26cf",  "name": "ARCHAEOLOGIST"},
    "IDDQD God Mode":           {"icon": "\u2694",  "name": "GOD MODE"},
    "The Source Map":            {"icon": "\U0001f5dd",  "name": "KEY MASTER"},
    "The Teapot":               {"icon": "\U0001fad6", "name": "RFC CONNOISSEUR"},
}


def _hide_easter_eggs(app):
    """Set all Easter Egg challenges to hidden state so they don't appear
    in the public /api/v1/challenges endpoint."""
    with app.app_context():
        eggs = Challenges.query.filter_by(category="Easter Eggs").all()
        for egg in eggs:
            if egg.state != "hidden":
                egg.state = "hidden"
        db.session.commit()


def load(app):
    """Called by CTFd plugin loader."""

    easter_eggs = Blueprint("easter_eggs", __name__)

    # Hide Easter Egg challenges from the public API
    _hide_easter_eggs(app)

    # ----------------------------------------------------------------
    # Easter Egg: Robots Exclusion (15 pts)
    # Set robots.txt config to hint at /secret-arcade-room
    # CTFd serves this via its built-in /robots.txt route in views.py
    # ----------------------------------------------------------------
    with app.app_context():
        current = get_config("robots_txt")
        if not current or "secret-arcade-room" not in current:
            set_config(
                "robots_txt",
                "User-agent: *\n"
                "Disallow: /secret-arcade-room\n"
                "Disallow: /admin\n"
                "\n"
                "# Nothing to see here... or is there?\n"
            )

    @easter_eggs.route("/secret-arcade-room")
    def secret_arcade_room():
        html = """<!DOCTYPE html>
<html>
<head><title>SECRET ARCADE ROOM</title>
<style>
  body {
    background: #06060e;
    color: #39ff14;
    font-family: 'VT323', 'Courier New', monospace;
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    margin: 0;
    flex-direction: column;
    text-align: center;
  }
  h1 {
    font-size: 2.5rem;
    text-shadow: 0 0 20px #39ff14, 0 0 40px rgba(57, 255, 20, 0.3);
    letter-spacing: 5px;
    margin-bottom: 1rem;
  }
  .flag {
    color: #00f0ff;
    font-size: 1.4rem;
    text-shadow: 0 0 15px #00f0ff;
    margin-top: 2rem;
    padding: 1rem 2rem;
    border: 1px solid rgba(0, 240, 255, 0.3);
    background: rgba(0, 240, 255, 0.05);
  }
  .subtitle {
    color: #e100ff;
    font-size: 1.2rem;
    text-shadow: 0 0 10px #e100ff;
    letter-spacing: 3px;
  }
  .hint {
    color: #4a4a6a;
    font-size: 1rem;
    margin-top: 3rem;
  }
</style>
</head>
<body>
  <h1>SECRET ARCADE ROOM</h1>
  <p class="subtitle">YOU FOUND THE HIDDEN LEVEL</p>
  <div class="flag">TECHFEST{robots_told_you_not_to_look_here}</div>
  <p class="hint">Hint: Always read the robots.txt</p>
</body>
</html>"""
        return Response(html, mimetype="text/html")

    # ----------------------------------------------------------------
    # Easter Egg: Header Hunter (15 pts)
    # X-Secret-Level response header on every page
    # ----------------------------------------------------------------
    @app.after_request
    def add_secret_header(response):
        response.headers["X-Secret-Level"] = "TECHFEST{http_headers_hide_secrets_in_plain_sight}"
        return response

    # ----------------------------------------------------------------
    # Easter Egg: Sitemap Spelunker (15 pts)
    # /sitemap.xml points to /bonus-level-unlocked
    # ----------------------------------------------------------------
    @easter_eggs.route("/sitemap.xml")
    def sitemap_xml():
        base = request.host_url.rstrip("/")
        content = f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>{base}/</loc><priority>1.0</priority></url>
  <url><loc>{base}/challenges</loc><priority>0.9</priority></url>
  <url><loc>{base}/scoreboard</loc><priority>0.8</priority></url>
  <url><loc>{base}/teams</loc><priority>0.7</priority></url>
  <url><loc>{base}/bonus-level-unlocked</loc><priority>0.1</priority></url>
</urlset>"""
        return Response(content, mimetype="application/xml")

    @easter_eggs.route("/bonus-level-unlocked")
    def bonus_level():
        html = """<!DOCTYPE html>
<html>
<head><title>BONUS LEVEL</title>
<style>
  body {
    background: #06060e;
    color: #ffe66d;
    font-family: 'VT323', 'Courier New', monospace;
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    margin: 0;
    flex-direction: column;
    text-align: center;
  }
  h1 {
    font-size: 2.5rem;
    text-shadow: 0 0 20px #ffe66d, 0 0 40px rgba(255, 230, 109, 0.3);
    letter-spacing: 5px;
    animation: flash 1s ease-in-out infinite alternate;
  }
  @keyframes flash {
    from { text-shadow: 0 0 20px #ffe66d; }
    to { text-shadow: 0 0 40px #ffe66d, 0 0 80px rgba(255, 230, 109, 0.5); }
  }
  .flag {
    color: #00f0ff;
    font-size: 1.4rem;
    text-shadow: 0 0 15px #00f0ff;
    margin-top: 2rem;
    padding: 1rem 2rem;
    border: 1px solid rgba(0, 240, 255, 0.3);
    background: rgba(0, 240, 255, 0.05);
  }
  .coins {
    font-size: 2rem;
    margin-top: 1rem;
    animation: bounce 0.6s ease-in-out infinite alternate;
  }
  @keyframes bounce {
    from { transform: translateY(0); }
    to { transform: translateY(-10px); }
  }
</style>
</head>
<body>
  <div class="coins">🪙 🪙 🪙</div>
  <h1>BONUS LEVEL UNLOCKED!</h1>
  <p style="color: #e100ff; font-size: 1.2rem; letter-spacing: 3px;">YOU FOUND THE SITEMAP SECRET</p>
  <div class="flag">TECHFEST{sitemaps_reveal_hidden_paths}</div>
</body>
</html>"""
        return Response(html, mimetype="text/html")

    # ----------------------------------------------------------------
    # Easter Egg: API Archaeologist (35 pts)
    # Undocumented /api/easter-egg endpoint
    # ----------------------------------------------------------------
    @easter_eggs.route("/api/easter-egg")
    def api_easter_egg():
        return {
            "status": "success",
            "message": "You found the hidden API endpoint!",
            "data": {
                "flag": "TECHFEST{undocumented_apis_are_treasure_maps}",
                "discovery": "API Archaeologist",
                "points": 35,
                "hint": "Not all endpoints are listed in the docs..."
            }
        }

    # ----------------------------------------------------------------
    # Easter Egg: The Teapot (20 pts)
    # /coffee → HTTP 418 I'm a Teapot
    # ----------------------------------------------------------------
    @easter_eggs.route("/coffee")
    def coffee():
        html = """<!DOCTYPE html>
<html>
<head><title>418 - I'M A TEAPOT</title>
<style>
  body {
    background: #06060e;
    color: #ff6b35;
    font-family: 'VT323', 'Courier New', monospace;
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    margin: 0;
    flex-direction: column;
    text-align: center;
  }
  .teapot {
    font-size: 6rem;
    margin-bottom: 1rem;
    animation: steam 2s ease-in-out infinite;
  }
  @keyframes steam {
    0%, 100% { transform: rotate(-5deg); }
    50% { transform: rotate(5deg); }
  }
  h1 {
    font-size: 2.5rem;
    text-shadow: 0 0 20px #ff6b35;
    letter-spacing: 5px;
  }
  .code {
    color: #ff003c;
    font-size: 3rem;
    text-shadow: 0 0 30px #ff003c;
    margin-bottom: 1rem;
  }
  .flag {
    color: #00f0ff;
    font-size: 1.4rem;
    text-shadow: 0 0 15px #00f0ff;
    margin-top: 2rem;
    padding: 1rem 2rem;
    border: 1px solid rgba(0, 240, 255, 0.3);
    background: rgba(0, 240, 255, 0.05);
  }
  .rfc {
    color: #4a4a6a;
    font-size: 0.9rem;
    margin-top: 2rem;
  }
</style>
</head>
<body>
  <div class="teapot">🫖</div>
  <div class="code">418</div>
  <h1>I'M A TEAPOT</h1>
  <p style="color: #e100ff; letter-spacing: 3px;">THIS SERVER REFUSES TO BREW COFFEE</p>
  <div class="flag">TECHFEST{i_am_a_teapot_not_a_coffee_maker}</div>
  <p class="rfc">RFC 2324 — Hyper Text Coffee Pot Control Protocol</p>
</body>
</html>"""
        resp = make_response(html, 418)
        resp.headers["Content-Type"] = "text/html"
        return resp

    # ----------------------------------------------------------------
    # Easter Egg: Highscore Injection (30 pts)
    # Team name "IDDQD" (DOOM god mode cheat) → flag in API response
    # This adds middleware that checks team name on scoreboard API calls
    # ----------------------------------------------------------------
    @easter_eggs.route("/api/v1/iddqd")
    def iddqd_cheat():
        return {
            "status": "GOD MODE ACTIVATED",
            "cheat": "IDDQD",
            "game": "DOOM (1993)",
            "message": "You know your classic cheat codes!",
            "flag": "TECHFEST{iddqd_god_mode_activated}",
        }

    # ----------------------------------------------------------------
    # Secure Easter Egg Status API
    # Returns minimal data for the ? zone UI without leaking names
    # or the "Easter Eggs" category to network sniffers.
    # ----------------------------------------------------------------
    @easter_eggs.route("/api/v1/egg-status")
    def egg_status():
        """Return minimal easter egg data for the ? zone.

        Response shape:
        {
          "eggs": [
            {"id": 78, "value": 15, "solved": true, "trophy": {"icon": "📡", "name": "SIGNAL INTERCEPTOR"}},
            {"id": 81, "value": 15, "solved": false, "hint": "Robots Exclusion"},
            ...
          ],
          "total": 15,
          "solved": 3
        }

        Solved eggs get their trophy icon/name. Unsolved eggs get only
        the challenge name as a hint (same as what appears on the trophy card).
        """
        # Must be logged in
        user = get_current_user()
        if not user:
            return jsonify({"success": False, "errors": ["Authentication required"]}), 403

        # Get the current team (CTF is in teams mode)
        team = get_current_team()

        eggs = Challenges.query.filter_by(category="Easter Eggs").order_by(Challenges.value).all()

        # Get solve IDs for this team
        if team:
            solved_ids = set(
                row.challenge_id for row in
                Solves.query.filter(
                    Solves.team_id == team.id,
                    Solves.challenge_id.in_([e.id for e in eggs])
                ).all()
            )
        else:
            solved_ids = set()

        egg_list = []
        for egg in eggs:
            solved = egg.id in solved_ids
            entry = {
                "id": egg.id,
                "value": egg.value,
                "solved": solved,
            }
            if solved:
                trophy = TROPHY_MAP.get(egg.name, {"icon": "?", "name": "UNKNOWN"})
                entry["trophy"] = trophy
            else:
                # Only expose the challenge name as a hint (shown on locked trophy cards)
                entry["hint"] = egg.name
            egg_list.append(entry)

        return jsonify({
            "success": True,
            "eggs": egg_list,
            "total": len(eggs),
            "solved": len(solved_ids),
        })

    # ----------------------------------------------------------------
    # Easter Egg Solves API (for scoreboard flair + team trophies)
    # Returns which teams have solved how many easter eggs, and
    # optionally a specific team's trophy list.
    # ----------------------------------------------------------------
    @easter_eggs.route("/api/v1/egg-solves")
    def egg_solves():
        """Return easter egg solve counts per team for scoreboard flair.

        Optional ?team_id=N parameter returns trophy details for that team.
        """
        user = get_current_user()
        if not user:
            return jsonify({"success": False, "errors": ["Authentication required"]}), 403

        eggs = Challenges.query.filter_by(category="Easter Eggs").all()
        egg_ids = [e.id for e in eggs]
        egg_name_map = {e.id: e.name for e in eggs}

        if not egg_ids:
            return jsonify({"success": True, "counts": {}, "trophies": []})

        # Get all solves for easter egg challenges
        solves = Solves.query.filter(Solves.challenge_id.in_(egg_ids)).all()

        # Build per-team counts
        counts = {}
        for solve in solves:
            tid = solve.team_id or solve.account_id
            if tid:
                counts[str(tid)] = counts.get(str(tid), 0) + 1

        # If a specific team is requested, return their trophies too
        team_id = request.args.get("team_id")
        trophies = []
        if team_id:
            try:
                team_id = int(team_id)
                team_solves = [s for s in solves if (s.team_id or s.account_id) == team_id]
                for s in team_solves:
                    name = egg_name_map.get(s.challenge_id, "")
                    trophy = TROPHY_MAP.get(name, {"icon": "?", "name": "UNKNOWN"})
                    trophies.append(trophy)
            except (ValueError, TypeError):
                pass

        return jsonify({
            "success": True,
            "counts": counts,
            "trophies": trophies,
        })

    app.register_blueprint(easter_eggs)
