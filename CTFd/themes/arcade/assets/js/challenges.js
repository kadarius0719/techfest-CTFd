import Alpine from "alpinejs";

import CTFd from "./index";

import { Modal, Tab, Tooltip } from "bootstrap";
import highlight from "./theme/highlight";
import { intl } from "./theme/times";

function addTargetBlank(html) {
  let dom = new DOMParser();
  let view = dom.parseFromString(html, "text/html");
  let links = view.querySelectorAll('a[href*="://"]');
  links.forEach(link => {
    link.setAttribute("target", "_blank");
  });
  return view.documentElement.outerHTML;
}

// ================================================================
// SOLVE CELEBRATION — "STAGE CLEAR" overlay
// ================================================================
function showSolveCelebration(points) {
  const overlay = document.createElement('div');
  overlay.className = 'solve-celebration';
  overlay.innerHTML =
    '<div class="celeb-flash"></div>' +
    '<div class="celeb-body">' +
      '<div class="celeb-title">STAGE CLEAR</div>' +
      '<div class="celeb-points">+' + points + ' PTS</div>' +
    '</div>';
  document.body.appendChild(overlay);

  // Spawn floating particles
  for (let i = 0; i < 24; i++) {
    const p = document.createElement('div');
    p.className = 'celeb-particle';
    p.style.left = (Math.random() * 100) + '%';
    p.style.animationDelay = (Math.random() * 0.6) + 's';
    p.style.animationDuration = (1 + Math.random() * 1.2) + 's';
    const colors = ['#39ff14','#00f0ff','#e100ff','#ffe66d'];
    p.style.background = colors[i % colors.length];
    p.style.boxShadow = '0 0 6px ' + colors[i % colors.length];
    overlay.appendChild(p);
  }

  setTimeout(() => {
    overlay.classList.add('celeb-out');
    setTimeout(() => overlay.remove(), 600);
  }, 2200);
}

window.Alpine = Alpine;

Alpine.store("challenge", {
  data: {
    view: "",
  },
});

Alpine.data("Hint", () => ({
  id: null,
  html: null,

  async showHint(event) {
    if (event.target.open) {
      let response = await CTFd.pages.challenge.loadHint(this.id);

      // Hint has some kind of prerequisite or access prevention
      if (response.errors) {
        event.target.open = false;
        CTFd._functions.challenge.displayUnlockError(response);
        return;
      }
      let hint = response.data;
      if (hint.content) {
        this.html = addTargetBlank(hint.html);
      } else {
        let answer = await CTFd.pages.challenge.displayUnlock(this.id);
        if (answer) {
          let unlock = await CTFd.pages.challenge.loadUnlock(this.id);

          if (unlock.success) {
            let response = await CTFd.pages.challenge.loadHint(this.id);
            let hint = response.data;
            this.html = addTargetBlank(hint.html);
          } else {
            event.target.open = false;
            CTFd._functions.challenge.displayUnlockError(unlock);
          }
        } else {
          event.target.open = false;
        }
      }
    }
  },
}));

Alpine.data("Challenge", () => ({
  id: null,
  next_id: null,
  submission: "",
  tab: null,
  solves: [],
  submissions: [],
  solution: null,
  response: null,
  share_url: null,
  max_attempts: 0,
  attempts: 0,
  ratingValue: 0,
  selectedRating: 0,
  ratingReview: "",
  ratingSubmitted: false,

  async init() {
    highlight();
  },

  getStyles() {
    let styles = {
      "modal-dialog": true,
    };
    try {
      let size = CTFd.config.themeSettings.challenge_window_size;
      switch (size) {
        case "sm":
          styles["modal-sm"] = true;
          break;
        case "lg":
          styles["modal-lg"] = true;
          break;
        case "xl":
          styles["modal-xl"] = true;
          break;
        default:
          break;
      }
    } catch (error) {
      // Ignore errors with challenge window size
      console.log("Error processing challenge_window_size");
      console.log(error);
    }
    return styles;
  },

  async init() {
    highlight();
  },

  async showChallenge() {
    new Tab(this.$el).show();
  },

  async showSolves() {
    this.solves = await CTFd.pages.challenge.loadSolves(this.id);
    this.solves.forEach(solve => {
      solve.date = intl.format(new Date(solve.date));
      return solve;
    });
    new Tab(this.$el).show();
  },

  async showSubmissions() {
    let response = await CTFd.pages.users.userSubmissions("me", this.id);
    this.submissions = response.data;
    this.submissions.forEach(s => {
      s.date = intl.format(new Date(s.date));
      return s;
    });
    new Tab(this.$el).show();
  },

  getSolutionId() {
    let data = Alpine.store("challenge").data;
    return data.solution_id;
  },

  getSolutionState() {
    let data = Alpine.store("challenge").data;
    return data.solution_state;
  },

  setSolutionId(solutionId) {
    Alpine.store("challenge").data.solution_id = solutionId;
  },

  async showSolution() {
    let solution_id = this.getSolutionId();
    CTFd._functions.challenge.displaySolution = solution => {
      this.solution = solution.html;
      new Tab(this.$el).show();
    };
    await CTFd.pages.challenge.displaySolution(solution_id);
  },

  getNextId() {
    let data = Alpine.store("challenge").data;
    return data.next_id;
  },

  async nextChallenge() {
    let modal = Modal.getOrCreateInstance("[x-ref='challengeWindow']");

    // TODO: Get rid of this private attribute access
    // See https://github.com/twbs/bootstrap/issues/31266
    modal._element.addEventListener(
      "hidden.bs.modal",
      event => {
        // Dispatch load-challenge event to call loadChallenge in the ChallengeBoard
        Alpine.nextTick(() => {
          this.$dispatch("load-challenge", this.getNextId());
        });
      },
      { once: true },
    );
    modal.hide();
  },

  async getShareUrl() {
    let body = {
      type: "solve",
      challenge_id: this.id,
    };
    const response = await CTFd.fetch("/api/v1/shares", {
      method: "POST",
      body: JSON.stringify(body),
    });
    const data = await response.json();
    const url = data["data"]["url"];
    this.share_url = url;
  },

  copyShareUrl() {
    navigator.clipboard.writeText(this.share_url);
    let t = Tooltip.getOrCreateInstance(this.$el);
    t.enable();
    t.show();
    setTimeout(() => {
      t.hide();
      t.disable();
    }, 2000);
  },

  async submitChallenge() {
    this.response = await CTFd.pages.challenge.submitChallenge(
      this.id,
      this.submission,
    );

    // Challenges page might be visible to anonymous users, redirect to login on submit
    if (this.response.data.status === "authentication_required") {
      window.location = `${CTFd.config.urlRoot}/login?next=${CTFd.config.urlRoot}${window.location.pathname}${window.location.hash}`;
      return;
    }

    await this.renderSubmissionResponse();
  },

  async renderSubmissionResponse() {
    if (this.response.data.status === "correct") {
      this.submission = "";
      showSolveCelebration(Alpine.store("challenge").data.value);
    }

    // Decide whether to check for the solution
    if (this.getSolutionId() == null) {
      if (
        CTFd.pages.challenge.checkSolution(
          this.getSolutionState(),
          Alpine.store("challenge").data,
          this.response.data.status,
        )
      ) {
        let data = await CTFd.pages.challenge.getSolution(this.id);
        this.setSolutionId(data.id);
      }
    }

    // Increment attempts counter
    if (
      this.max_attempts > 0 &&
      this.response.data.status != "already_solved" &&
      this.response.data.status != "ratelimited"
    ) {
      this.attempts += 1;
    }

    // Dispatch load-challenges event to call loadChallenges in the ChallengeBoard
    this.$dispatch("load-challenges");
  },

  async submitRating() {
    const response = await CTFd.pages.challenge.submitRating(
      this.id,
      this.selectedRating,
      this.ratingReview,
    );
    if (response.value) {
      this.ratingValue = this.selectedRating;
      this.ratingSubmitted = true;
    } else {
      alert("Error submitting rating");
    }
  },
}));

Alpine.data("ChallengeBoard", () => ({
  loaded: false,
  challenges: [],
  challenge: null,
  view: "overworld",
  activeCategory: null,
  selectedChallenge: null,

  // Pac-Man avatar state
  avatarPctX: 14.29,
  avatarPctY: 18.57,
  avatarDir: "right",
  isNavigating: false,
  _currentCategory: "Tutorial Zone",
  _eatenPellets: new Set(),

  // Easter Eggs state (data comes from /api/v1/egg-status, NOT from main challenges list)
  easterEggSubmission: "",
  easterEggResponse: null,
  easterEggSubmitting: false,
  easterEggRevealed: false,
  _easterEggs: [],       // Loaded from custom secure endpoint
  _easterEggsLoaded: false,

  // World map metadata — visual config per category
  _categoryMeta: {
    "Tutorial Zone":    { icon: "▶",  color: "#39ff14" },
    "Cipher Quest":     { icon: "◆",  color: "#e100ff" },
    "Web Warfare":      { icon: "◎",  color: "#00f0ff" },
    "Data Dungeon":     { icon: "▦",  color: "#7b2fff" },
    "Secure Fortress":  { icon: "⬡",  color: "#ff6b35" },
    "Packet Arena":     { icon: "◈",  color: "#00f0ff" },
    "AI Arena":         { icon: "⬢",  color: "#e100ff" },
    "Code Breakers":    { icon: "⚡", color: "#ffe66d" },
    "Bonus Stage":      { icon: "★",  color: "#ff6b35" },
    "Easter Eggs":      { icon: "?",  color: "#ffe66d" },
  },

  // SVG viewBox positions (1400x700 landscape) and percentage equivalents
  // Layout: 3x3 grid — columns at x=200,700,1200; rows at y=130,350,570
  // Waypoints at x=450,950 junction columns for staggered vertical routing
  _nodePositions: {
    // Category nodes
    "Tutorial Zone":    { x: 200,  y: 130, pctX: 14.29, pctY: 18.57 },
    "Cipher Quest":     { x: 700,  y: 130, pctX: 50,    pctY: 18.57 },
    "Web Warfare":      { x: 1200, y: 130, pctX: 85.71, pctY: 18.57 },
    "Data Dungeon":     { x: 200,  y: 350, pctX: 14.29, pctY: 50    },
    "Secure Fortress":  { x: 700,  y: 350, pctX: 50,    pctY: 50    },
    "AI Arena":         { x: 1200, y: 350, pctX: 85.71, pctY: 50    },
    "Packet Arena":     { x: 200,  y: 570, pctX: 14.29, pctY: 81.43 },
    "Code Breakers":    { x: 700,  y: 570, pctX: 50,    pctY: 81.43 },
    "Bonus Stage":      { x: 1200, y: 570, pctX: 85.71, pctY: 81.43 },
    // Easter Eggs — hidden node in center of maze
    "Easter Eggs":      { x: 700,  y: 240, pctX: 50,    pctY: 34.29 },
    // Corridor junction waypoints
    "J_TL":             { x: 450,  y: 130, pctX: 32.14, pctY: 18.57 },
    "J_TR":             { x: 950,  y: 130, pctX: 67.86, pctY: 18.57 },
    "J_ML":             { x: 450,  y: 350, pctX: 32.14, pctY: 50    },
    "J_MR":             { x: 950,  y: 350, pctX: 67.86, pctY: 50    },
    "J_BL":             { x: 450,  y: 570, pctX: 32.14, pctY: 81.43 },
    "J_BR":             { x: 950,  y: 570, pctX: 67.86, pctY: 81.43 },
  },

  // Maze corridor adjacency — staggered verticals force L-shaped paths with turns
  // Rows 1→2 connect via x=450,950 columns; Rows 2→3 via x=200,700,1200 columns
  _mazeGraph: {
    // Top row (y=130)
    "Tutorial Zone":   ["J_TL"],
    "J_TL":            ["Tutorial Zone", "Cipher Quest", "J_ML"],
    "Cipher Quest":    ["J_TL", "J_TR", "Easter Eggs"],
    "Easter Eggs":     ["Cipher Quest", "Secure Fortress"],
    "J_TR":            ["Cipher Quest", "Web Warfare", "J_MR"],
    "Web Warfare":     ["J_TR"],
    // Middle row (y=350)
    "Data Dungeon":    ["J_ML", "Packet Arena"],
    "J_ML":            ["Data Dungeon", "Secure Fortress", "J_TL"],
    "Secure Fortress": ["J_ML", "J_MR", "Code Breakers", "Easter Eggs"],
    "J_MR":            ["Secure Fortress", "AI Arena", "J_TR"],
    "AI Arena":        ["J_MR", "Bonus Stage"],
    // Bottom row (y=570)
    "Packet Arena":    ["Data Dungeon", "J_BL"],
    "J_BL":            ["Packet Arena", "Code Breakers"],
    "Code Breakers":   ["J_BL", "Secure Fortress", "J_BR"],
    "J_BR":            ["Code Breakers", "Bonus Stage"],
    "Bonus Stage":     ["J_BR", "AI Arena"],
  },

  async init() {
    // Load main challenges and filter out any Easter Eggs that might leak through
    const allChallenges = await CTFd.pages.challenges.getChallenges();
    this.challenges = allChallenges.filter(c => c.category !== "Easter Eggs");

    // Load Easter Egg data from secure endpoint (no names/category leaked)
    await this._loadEasterEggs();

    this.loaded = true;

    if (window.location.hash) {
      let chalHash = decodeURIComponent(window.location.hash.substring(1));
      let idx = chalHash.lastIndexOf("-");
      if (idx >= 0) {
        let pieces = [chalHash.slice(0, idx), chalHash.slice(idx + 1)];
        let id = pieces[1];
        await this.loadChallenge(id);
      }
    }
  },

  // --- Map helpers ---

  getCategoryMeta(category) {
    return this._categoryMeta[category] || { icon: "?", color: "#4a4a6a" };
  },

  getCategoryPos(category) {
    return this._nodePositions[category] || { x: 400, y: 450, pctX: 50, pctY: 50 };
  },

  navigateToZone(category) {
    if (this.isNavigating) return;

    // If already at target, just enter
    if (this._currentCategory === category) {
      this.enterZone(category);
      return;
    }

    // BFS pathfinding through maze corridors
    const path = this._findPath(this._currentCategory, category);
    if (!path || path.length < 2) {
      this.enterZone(category);
      return;
    }

    this.isNavigating = true;
    this._animatePath(path, 0, () => {
      this.isNavigating = false;
      this._currentCategory = category;
      this.enterZone(category);
    });
  },

  // BFS shortest path through maze graph
  _findPath(from, to) {
    if (from === to) return [from];
    const queue = [[from]];
    const visited = new Set([from]);

    while (queue.length > 0) {
      const path = queue.shift();
      const node = path[path.length - 1];

      const neighbors = this._mazeGraph[node] || [];
      for (const neighbor of neighbors) {
        if (neighbor === to) return [...path, neighbor];
        if (!visited.has(neighbor)) {
          visited.add(neighbor);
          queue.push([...path, neighbor]);
        }
      }
    }
    return null;
  },

  // Animate avatar along path segments one at a time (distance-based speed)
  _animatePath(path, index, onComplete) {
    if (index >= path.length - 1) {
      onComplete();
      return;
    }

    const fromPos = this._nodePositions[path[index]];
    const toPos = this._nodePositions[path[index + 1]];

    // Set direction based on this segment
    const dx = toPos.pctX - fromPos.pctX;
    const dy = toPos.pctY - fromPos.pctY;
    if (Math.abs(dx) > Math.abs(dy)) {
      this.avatarDir = dx > 0 ? "right" : "left";
    } else {
      this.avatarDir = dy > 0 ? "down" : "up";
    }

    const startX = this.avatarPctX;
    const startY = this.avatarPctY;

    // Duration proportional to distance — consistent speed across segments
    const dist = Math.sqrt(dx * dx + dy * dy);
    const speed = 35; // pct units per second
    const duration = Math.max(300, (dist / speed) * 1000);
    const steps = Math.max(15, Math.round(duration / 30));
    let step = 0;
    const self = this;

    const animate = () => {
      step++;
      const t = Math.min(step / steps, 1);

      self.avatarPctX = startX + (toPos.pctX - startX) * t;
      self.avatarPctY = startY + (toPos.pctY - startY) * t;

      // Eat nearby pellets
      self._eatNearbyPellets();

      if (t < 1) {
        setTimeout(animate, duration / steps);
      } else {
        self._animatePath(path, index + 1, onComplete);
      }
    };

    setTimeout(animate, duration / steps);
  },

  // Hide pellets near the avatar's current SVG position
  _eatNearbyPellets() {
    const pellets = document.querySelectorAll('.maze-pellets circle:not(.eaten)');
    // Convert avatar percentage to SVG viewBox coordinates (1400x700)
    const avX = this.avatarPctX / 100 * 1400;
    const avY = this.avatarPctY / 100 * 700;
    const eatRadius = 35; // SVG units

    pellets.forEach((pellet, i) => {
      const cx = parseFloat(pellet.getAttribute('cx'));
      const cy = parseFloat(pellet.getAttribute('cy'));
      const dist = Math.sqrt((cx - avX) ** 2 + (cy - avY) ** 2);
      if (dist < eatRadius) {
        pellet.classList.add('eaten');
        pellet.style.transition = 'opacity 0.15s, transform 0.15s';
        pellet.style.opacity = '0';
        pellet.style.transform = `scale(0)`;
        pellet.style.transformOrigin = `${cx}px ${cy}px`;
      }
    });
  },

  // Reset all eaten pellets (called on page load and when returning to map)
  _resetPellets() {
    const pellets = document.querySelectorAll('.maze-pellets circle.eaten');
    pellets.forEach(p => {
      p.classList.remove('eaten');
      p.style.transition = '';
      p.style.opacity = '';
      p.style.transform = '';
    });
  },

  getCategoryStats(category) {
    if (!category) return { total: 0, solved: 0, percent: 0, hasBoss: false, bossSolved: false };
    // Easter Eggs use separate data source
    if (category === "Easter Eggs") {
      const total = this._easterEggs.length;
      const solved = this._easterEggs.filter(e => e.solved).length;
      return { total, solved, percent: total > 0 ? Math.round((solved / total) * 100) : 0, hasBoss: false, bossSolved: false };
    }
    const chals = this.getChallenges(category);
    const total = chals.length;
    const solved = chals.filter(c => c.solved_by_me).length;
    const boss = chals.find(c => c.tags && c.tags.some(t => t.value === "boss"));
    return {
      total,
      solved,
      percent: total > 0 ? Math.round((solved / total) * 100) : 0,
      hasBoss: !!boss,
      bossSolved: boss ? boss.solved_by_me : false,
    };
  },

  getZoneChallenges() {
    if (!this.activeCategory) return [];
    const chals = this.getChallenges(this.activeCategory);
    // Sort: regular challenges first, boss(es) last
    const regular = chals.filter(c => !this.isBoss(c));
    const bosses  = chals.filter(c => this.isBoss(c));
    return [...regular, ...bosses];
  },

  isBoss(challenge) {
    return challenge.tags && challenge.tags.some(t => t.value === "boss");
  },

  isNextStage(idx) {
    const chals = this.getZoneChallenges();
    if (chals[idx] && chals[idx].solved_by_me) return false;
    // First uncleared stage
    for (let i = 0; i < chals.length; i++) {
      if (!chals[i].solved_by_me) return i === idx;
    }
    return false;
  },

  selectChallenge(id) {
    this.selectedChallenge = id;
    this.loadChallenge(id);
  },

  closePanel() {
    this.selectedChallenge = null;
    Alpine.store("challenge").data = { view: "" };
  },

  // --- Easter Eggs helpers ---
  // Easter Egg data comes from /api/v1/egg-status (secure endpoint),
  // NOT from the main challenges list. This prevents leaking the
  // "Easter Eggs" category, challenge names, etc. in /api/v1/challenges.

  async _loadEasterEggs() {
    try {
      const resp = await CTFd.fetch("/api/v1/egg-status", { method: "GET" });
      const data = await resp.json();
      if (data.success) {
        this._easterEggs = data.eggs;
        this._easterEggsLoaded = true;
      }
    } catch (e) {
      // Silently fail — eggs are a bonus feature
      this._easterEggs = [];
    }
  },

  isEasterEggZone() {
    return this.activeCategory === "Easter Eggs";
  },

  getEasterEggChallenges() {
    return this._easterEggs;
  },

  getEasterEggSolves() {
    return this._easterEggs.filter(e => e.solved);
  },

  hasAnyEasterEggSolve() {
    return this.getEasterEggSolves().length > 0;
  },

  getTrophy(egg) {
    // Solved eggs have trophy from server; unsolved show ?
    return egg.trophy || { icon: "?", name: "UNKNOWN" };
  },

  async submitEasterEgg() {
    if (!this.easterEggSubmission.trim() || this.easterEggSubmitting) return;
    this.easterEggSubmitting = true;
    this.easterEggResponse = null;

    const unsolved = this._easterEggs.filter(e => !e.solved);
    let found = false;

    for (const egg of unsolved) {
      try {
        const resp = await CTFd.pages.challenge.submitChallenge(
          egg.id,
          this.easterEggSubmission,
        );
        if (resp.data.status === "correct") {
          found = true;
          // Refresh egg data from secure endpoint
          await this._loadEasterEggs();
          // Find the now-solved egg to get its trophy
          const solvedEgg = this._easterEggs.find(e => e.id === egg.id);
          this.easterEggResponse = {
            status: "correct",
            trophy: solvedEgg?.trophy || { icon: "🏆", name: "FOUND" },
          };
          showSolveCelebration(egg.value);
          this.easterEggSubmission = "";
          if (!this.easterEggRevealed) {
            this.easterEggRevealed = true;
          }
          break;
        } else if (resp.data.status === "already_solved") {
          continue;
        }
      } catch (e) {
        continue;
      }
    }

    if (!found && !this.easterEggResponse) {
      this.easterEggResponse = { status: "incorrect" };
    }

    this.easterEggSubmitting = false;
    setTimeout(() => {
      this.easterEggResponse = null;
    }, 5000);
  },

  enterZone(category) {
    this.activeCategory = category;
    this.selectedChallenge = null;
    // Pre-check if easter eggs have been found
    if (category === "Easter Eggs") {
      this.easterEggRevealed = this.hasAnyEasterEggSolve();
      this.easterEggSubmission = "";
      this.easterEggResponse = null;
      // Refresh egg data when entering the zone
      this._loadEasterEggs();
    }
    this.view = "zone";
    window.scrollTo({ top: 0, behavior: "smooth" });
  },

  exitZone() {
    // Close panel and clear challenge data
    this.selectedChallenge = null;
    Alpine.store("challenge").data = { view: "" };
    // Avatar stays at the category we were viewing
    const pos = this.getCategoryPos(this.activeCategory);
    this.avatarPctX = pos.pctX;
    this.avatarPctY = pos.pctY;
    this._currentCategory = this.activeCategory;
    this.activeCategory = null;
    this.view = "overworld";
    // Reset pellets so they reappear fresh
    this.$nextTick(() => this._resetPellets());
  },

  // --- Original methods (unchanged) ---

  getCategories() {
    const categories = [];

    this.challenges.forEach(challenge => {
      const { category } = challenge;

      if (!categories.includes(category)) {
        categories.push(category);
      }
    });

    // Add Easter Eggs as a category if we have egg data (they're hidden
    // from the main challenges list so won't appear naturally)
    if (this._easterEggsLoaded && this._easterEggs.length > 0 && !categories.includes("Easter Eggs")) {
      categories.push("Easter Eggs");
    }

    try {
      const f = CTFd.config.themeSettings.challenge_category_order;
      if (f) {
        const getSort = new Function(`return (${f})`);
        categories.sort(getSort());
      }
    } catch (error) {
      // Ignore errors with theme category sorting
      console.log("Error running challenge_category_order function");
      console.log(error);
    }

    return categories;
  },

  getChallenges(category) {
    let challenges = this.challenges;

    if (category !== null) {
      challenges = this.challenges.filter(challenge => challenge.category === category);
    }

    try {
      const f = CTFd.config.themeSettings.challenge_order;
      if (f) {
        const getSort = new Function(`return (${f})`);
        challenges.sort(getSort());
      }
    } catch (error) {
      // Ignore errors with theme challenge sorting
      console.log("Error running challenge_order function");
      console.log(error);
    }

    return challenges;
  },

  async loadChallenges() {
    const allChallenges = await CTFd.pages.challenges.getChallenges();
    this.challenges = allChallenges.filter(c => c.category !== "Easter Eggs");
  },

  async loadChallenge(challengeId) {
    await CTFd.pages.challenge.displayChallenge(challengeId, challenge => {
      challenge.data.view = addTargetBlank(challenge.data.view);
      Alpine.store("challenge").data = challenge.data;

      // In zone view, render into the side panel instead of a modal
      if (this.view === "zone") {
        history.replaceState(null, null, `#${challenge.data.name}-${challengeId}`);
        return;
      }

      // nextTick is required here because we're working in a callback
      Alpine.nextTick(() => {
        let modal = Modal.getOrCreateInstance("[x-ref='challengeWindow']");
        // TODO: Get rid of this private attribute access
        // See https://github.com/twbs/bootstrap/issues/31266
        modal._element.addEventListener(
          "hidden.bs.modal",
          event => {
            // Remove location hash
            history.replaceState(null, null, " ");
          },
          { once: true },
        );
        modal.show();
        history.replaceState(null, null, `#${challenge.data.name}-${challengeId}`);
      });
    });
  },
}));

Alpine.start();
