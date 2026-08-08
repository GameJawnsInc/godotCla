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
- Verification suite (run all three before committing sim changes):
  - `godot --headless --path . --script tests/test_invariants.gd` — procgen sweep
  - `godot --headless --path . --script tests/test_determinism.gd` — rerun + replay hashes
  - `godot --headless --path . --script tests/playtest.gd` — bot personas, balance metrics
- Balance sweeps (on demand; run before shipping new content, and verify any
  outlier at 30+ seeds before patching — 10-seed spreads are noisy):
  - `tests/sweep_combos.gd` — pairwise ability win rates vs baseline
  - `tests/sweep_packages.gd` — each tech package added to the pool
  - `tests/sweep_tiers.gd` — every difficulty tier must stay bot-winnable
- Sim run config: `Game.new(seed, {kit, pool, packages, tier})` for sweeps,
  meta-unlocks, and post-win difficulty tiers.
- Workflow: no PRs; commit on `claude/godot-setup-q6hk6p` and merge/push
  straight to `main`.
