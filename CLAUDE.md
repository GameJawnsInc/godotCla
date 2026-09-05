# godotCla — Roguelike

A turn-based roguelike built in Godot (4.7.1 stable), architected so an AI coding
agent can build, playtest, and balance it autonomously in a headless environment.
Graphics come later; the simulation is the game.

## Architecture style guide

These principles were agreed with the project owner. Follow them for all game
code. When a new feature seems to conflict with one, flag the tension instead of
silently breaking the principle — but remember the principles serve the game,
not the other way around: fun mechanics win over architectural purity, and the
architecture below is designed to bend rather than block.

### 1. Pure simulation core

- All game rules (map, entities, combat, items, turns) live in plain GDScript
  classes (`RefCounted`, not `Node`) under `sim/`. They never touch scenes,
  signals, rendering, input, or anything in the scene tree.
- Godot scenes are a thin shell that draws sim state and forwards player input.
- Everything in the sim must be drivable and inspectable from a headless script.

### 2. Seeded determinism

- One injected RNG (`RandomNumberGenerator` seeded at game creation) owned by
  the sim. Never call global `randi()`/`randf()` in game logic.
- Same seed + same action sequence = identical game state, always.
- Bugs are reported and regression-tested as (seed, action list) pairs.

### 3. Discrete turns through one entry point — kept flexible

- The sim advances only through a single `step(action)` entry point. No timers,
  no physics, no wall-clock time. Prefer integers over floats.
- The step system must stay flexible enough for fun mechanics, not just
  "one move per turn": energy/speed systems, multi-action turns, interrupts,
  delayed effects, and reaction triggers are all in scope. Design `step()` as
  "advance the world until the player must decide again," not "one actor moves."
- Never reject a mechanic because it strains the turn model; extend the model.

### 4. Self-printing state, renderer-agnostic

- The sim can dump itself as ASCII (map + status line + recent event log) from
  day one. This is the agent's primary way to "watch" the game.
- ASCII output is just one view. Design for later graphics injection: the sim
  exposes a clean read-only state/snapshot API plus an event stream of what
  happened each step, and any renderer (ASCII, TileMap, future juice/VFX)
  consumes those without the sim knowing which renderer exists.
- Get mechanics smooth first; visuals plug in later without sim changes.

### 5. Bot players as first-class citizens

- Bots implement a common interface: `choose_action(visible_state) -> Action`.
- Bots double as user-persona models — e.g. a random-walker (crash finder), a
  cautious noob, a greedy explorer, an extreme minmaxer. Balance questions are
  asked per-persona ("floor 2 kills 60% of noob bots but 5% of minmaxers").
- The playtest harness runs N seeds × M bots headless and reports death rates
  per floor, turns per depth, softlocks, and errors.
- Current roster (`bots/`): wanderer (random, crash finder), sprout (cautious
  noob), magpie (greedy explorer), fanatic (commits to one build archetype per
  run; reports per-build win rates), optimizer (heuristic skilled play), and
  deeproot (clone()-based 1-ply search; the measurable skill ceiling — bots
  that need the sim as a forward model implement `set_sim(game)`).

### 6. Data-driven content

- Monsters, items, spawn tables, and similar content are data (dictionaries /
  JSON-like resources), not classes. Adding content means adding data.
- Balance sweeps mutate data, rerun the bot harness, and compare metrics.

### 7. Procgen with checkable — but flexible — invariants

- Map generators are validated over many seeds with invariant checks
  (reachability, nothing embedded in walls, spawn bounds, etc.).
- Invariants are pluggable per generator/level-type, not a hardcoded global
  list. Complicated maps (vaults, locked doors, secret rooms, multi-zone
  floors) get their own invariant sets. When a feature legitimately breaks an
  old invariant, update the invariant — they encode current design intent,
  not permanent law.

### 8. Thin vertical slice, then layers

- Keep the game fully bot-playable end to end at every commit. New systems are
  modules dropped into the already-tested loop, one at a time.

## Practical notes

- Godot 4.7.1 stable is installed headless via the SessionStart hook
  (`.claude/hooks/session-start.sh`); binary at `/usr/local/bin/godot`.
- Run headless: `godot --headless --path . --script <script.gd>`.
- No display in this environment: never rely on rendering, input events, or
  visual inspection to verify behavior — assert on sim state instead.
- Verification suite (run all of it before committing sim or bot changes):
  - `godot --headless --path . --script tests/test_invariants.gd` — procgen sweep
    (raw `Content.FLOORS` plus `Game.floor_def` for every tier and mutator)
  - `godot --headless --path . --script tests/test_determinism.gd` — rerun + replay hashes
  - `godot --headless --path . --script tests/test_content.gd` — ability tags/roles,
    `Content.ARCHETYPES` cores, `base_id`, `archetypes_for`
  - `godot --headless --path . --script tests/test_regressions.gd` — replays every
    `tests/regressions/*.json` (seed, config, actions) pair: illegal/error events,
    outcome, expected event patterns; `REGRESS_STRICT=1` also checks the state
    hash, `REGEN=1` re-stamps outcomes/hashes after a deliberate sim change
    (check the printed diffs by hand first), `REGRESS_DIR` points at another corpus
  - `godot --headless --path . --script tests/playtest.gd` — bot personas, balance
    metrics, and the BALANCE.md band gates (exit 1 when a persona's whole Wilson
    interval sits outside its band; `PLAYTEST_GATE=0` disables, `PLAYTEST_SEEDS`
    and `PLAYTEST_BOTS=a,b,c` narrow a run)
  - `godot --headless --path . --script tests/test_meta.gd` — career unlocks, profile io,
    mutator invariants, package pools
- Bots live in one registry, `bots/roster.gd` (`Roster.names()/make(name, seed)`);
  every runner resolves persona names through it, and an unknown name fails
  loudly. `deeproot_rollout` is deeproot with rollout drafting (a separate
  persona so the legacy ceiling column survives).
- Balance sweeps (on demand; run before shipping new content, and verify any
  outlier at 30+ seeds before patching — 10-seed spreads are noisy). Shared env:
  `SWEEP_BOT=<roster name>` (default optimizer), `SWEEP_SEEDS` (default 30),
  `SWEEP_SEED_FROM` (out-of-sample checks), `SWEEP_TIER`:
  - `tests/sweep_combos.gd` — locked-kit lift: every config is `{kit: K, pool: K}`,
    `lift = pair - max(single_x, single_y)` with Wilson CIs and a paired sign
    test; `SWEEP_PAIRS=a+b,c+d` selects pairs, `SWEEP_SHARD=i/n` slices the
    66-pair grid (deeproot grid is hours), `SWEEP_MODE=drift` keeps the old
    open-pool "start with the pair" question as a labelled second table
  - `tests/sweep_packages.gd` — each tech package added to the pool
  - `tests/sweep_tiers.gd` — every difficulty tier must stay bot-winnable (fails
    when the Wilson upper bound is under 10%; binds only at SWEEP_SEEDS >= 35);
    `SWEEP_REFERENCE_ROWS=1` adds the permanent locked reference kits
    (starter5, lance_free_A, lance_free_B)
  - `tests/verify_kit.gd` — one config at N seeds (`VERIFY_BOT`, `VERIFY_SEEDS`,
    `VERIFY_TIER`, `VERIFY_EXTRAS`), prints wins, CI and the Tally KPI block
  - `tests/measure_fanatic.gd` — every `Content.ARCHETYPES` build on every seed
    (`FANATIC_SEEDS`, `FANATIC_SEED_FROM`, `FANATIC_BUILDS`, `FANATIC_PACKAGES`,
    `FANATIC_TIER`, `FANATIC_MUTATORS`, `FANATIC_VERBOSE=1`)
  - `tests/measure_bosses.gd` — arrivals/conversions per boss and per kit
    signature; `BOSS_KIT=a,b,c` locks an archetype kit against each boss
  - `tests/draft_oracle.gd` — forks every draft the policy faces (each offer +
    skip), rolls out with a fresh persona: P(win|pick) - P(win|skip), stakes
    per draft, policy regret (`ORACLE_BOT`, `ORACLE_SEEDS`, `ORACLE_SEED_FROM`,
    `ORACLE_TIER`, `ORACLE_SHARD=i/n`, `ORACLE_JSON=<path>`)
- Measurement discipline: the harness changed on 2026-09-05 ("instrument v2",
  see BALANCE.md). Numbers recorded before that entry and numbers recorded
  after it are never mixed in one comparison; every runner prints a header
  (bot, config, seed range) and a Wilson CI — quote both.
- Side-channel rng: incidental draws (shop flavor, supply drops) use
  `_side_rng(tag)` (hash of seed+floor+tag), NEVER the main `rng` stream -
  one stray main-stream draw reshuffles every seed's downstream rolls and
  invalidates cross-version win-rate comparisons.
- Sim run config: `Game.new(seed, {kit, pool, packages, tier, mutators})` for
  sweeps, meta-unlocks, and post-win difficulty tiers.
- Meta layer: `meta/profile.gd` records runs against `Content.MILESTONES` and
  hands back the next run's config; the sim itself stays career-agnostic.
- Balance targets and the measurement discipline live in `docs/BALANCE.md`;
  `tests/daily_run.gd` generates the date-seeded daily challenge.
- Death autopsy (`tests/autopsy.gd`): `AUTOPSY_BOT=<persona> AUTOPSY_SEED=<n>`
  reruns a game and prints the last `AUTOPSY_LAST` ASCII frames — use it to
  "watch" any death a sweep or playtest flags. `AUTOPSY_TIER`/`AUTOPSY_MUTATORS`/
  `AUTOPSY_KIT` set the config; `AUTOPSY_JSON=<path>` dumps the run as a
  (seed, config, actions) regression pair and `AUTOPSY_REPLAY=<path>` replays one.
- Sim changes that alter replay behaviour must bump RUN_SAVE_VERSION in
  `shell/main.gd` - live phone runs persist as replayable action logs and a
  stale log replayed across sim changes diverges silently.
- Human shell (`shell/`): SVG-sprite Godot scene over the sim — see
  `docs/SHELL.md` for controls. `tests/test_shell.gd` smoke-tests it
  headless; `tests/render_frame.gd` renders any game state as a standalone
  SVG screenshot (the agent's way to see the shell). Sprites are hand-written
  SVG strings in `shell/svg_art.gd`. The sim must never depend on the shell.
- Workflow: no PRs; commit on `claude/godot-setup-q6hk6p` and merge/push
  straight to `main`.
