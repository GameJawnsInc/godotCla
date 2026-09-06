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
    `Content.ARCHETYPES` cores, `base_id`, `archetypes_for`, and the effect-grammar
    lint (closed op/rider vocabulary, TERRAIN/REACTIONS/STATUSES rows, plus a
    self-test that feeds the lint deliberately bad rows and the planned rider rows)
  - `godot --headless --path . --script tests/test_grammar.gd` — effect grammar
    behaviour: rider evaluation, returned outcomes, and the data tables driven
    through `Game._apply_effect` on hand-built states
  - `godot --headless --path . --script tests/test_economy.gd` — shrine economy
    and quota: config-independent main rng, shop stock filters, graft/ability/
    press/forge purchase rules, quota re-clamp, damage attribution
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
  - `godot --headless --path . --script tests/test_shell.gd` — shell smoke test
    (the shell reads the sim, so a sim change can break it)
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
  - `tests/sweep_grafts.gd` — each `Content.GRAFTS` entry pre-installed
    (`{grafts: [g]}`) against the same seeds with none, plus an all-grafts row;
    `SWEEP_GRAFTS=a,b` narrows, `SWEEP_BLOOM=<n>` gives every config, base
    included, that much starting bloom
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
- Effect grammar and data tables (`docs/PROGRESSION_REVIEW.md` §6.3 C1):
  terrain, terrain reactions and statuses are data — `Content.TERRAIN` (one row
  per kind: corruption, shields_core, flammable, washable, bloom, ttl/decays,
  enter/tick damage, blocks, blocks_beam, heal, burns_to, convertible; read
  through `Content.terrain(kind, key, default)` and `Content.is_corruption(kind)`),
  `Content.REACTIONS` (rows consumed by `Game._terrain_react()`; disabled rows
  are design intent kept as data) and `Content.STATUSES` (stack rule, blocked
  intents, blocked_event, tick damage, optional stagger-style cooldown).
  Live rows (C1b): TERRAIN has `ash` — burnt oil, corruption true but
  shields_core false, washable, convertible, bloom 1, never generated by mapgen —
  so a burnout leaves corruption standing (lighting oil still re-clamps the
  quota at ignition because fire is not corruption; the ash only means later
  bloomless removals shrink it less);
  REACTIONS runs `fire_spreads` (inherits the oil tile's bloom flag) and
  `fire_burns_out` (fire ttl -> ash, event `ash`) while `damp`, `roots_burn` and
  `smoke_smother` stay disabled; STATUSES roots block move/advance/drag with a
  cooldown of 2 (a refused re-application emits `resisted`) and spore stacks by
  addition up to a cap of 6. Any effect dict may carry the rider keys
  `if` (closed predicate set: target_on, target_adjacent, self_on, dim,
  casts_this_turn_min, plus outcome/outcome_crossed inside `then`), `per`
  (growth_adjacent_target, fire_within_self, oil_in_line, enemies_adjacent_target),
  `bonus` (per-enemy damage) and `then` (sub-effects, never nested), evaluated
  only by `Game._rider_if` / `_rider_per` / `_bonus_dmg`; an ability row may
  carry `surge` (default `{cost: -1}`). New ops, predicates, counts or terrain
  keys go into the `tests/test_content.gd` vocabulary constants in the same
  change, or the lint rejects them. Riders emit `{t: "rider", id, kind, amt}`,
  which `tests/tally.gd` counts (`riders_by_kind` / `riders_by_aid`) and folds
  into the combo rate.
- Sim run config: `Game.new(seed, {kit, pool, packages, tier, mutators, grafts,
  bloom})` for sweeps, meta-unlocks, and post-win difficulty tiers. `grafts` is
  a list of `Content.GRAFTS` ids installed before floor 1 (unknown ids are
  skipped with a warning; owned grafts raise the shrine's graft price) and
  `bloom` is the starting balance — neither touches the main rng.
- Meta layer: `meta/profile.gd` records runs against `Content.MILESTONES` and
  hands back the next run's config; the sim itself stays career-agnostic.
- Balance targets and the measurement discipline live in `docs/BALANCE.md`;
  `tests/daily_run.gd` generates the date-seeded daily challenge.
- Death autopsy (`tests/autopsy.gd`): `AUTOPSY_BOT=<persona> AUTOPSY_SEED=<n>`
  reruns a game and prints the last `AUTOPSY_LAST` ASCII frames — use it to
  "watch" any death a sweep or playtest flags. `AUTOPSY_TIER`/`AUTOPSY_MUTATORS`/
  `AUTOPSY_KIT` set the config; `AUTOPSY_JSON=<path>` dumps the run as a
  (seed, config, actions) regression pair and `AUTOPSY_REPLAY=<path>` replays one.
- Live-run import (`tests/import_run.gd`): `IMPORT_RUN=<run.save>
  IMPORT_OUT=<record.json> [IMPORT_NOTE=...]` replays a phone run's saved action
  log through the pure sim and writes the regression record it proves; a save
  whose header version is not `Game.SIM_VERSION` is refused, never guessed at.
- `Game.SIM_VERSION` in `sim/game.gd` is the single replay-version source (3
  today: C1b ash, root blocks/cooldown, spore stacking, items through
  `_apply_status`): bump it whenever a sim change alters replay behaviour.
  `shell/main.gd` RUN_SAVE_VERSION, `tests/regress_lib.gd` and
  `tests/autopsy.gd` all read it -
  live phone runs persist as replayable action logs and a stale log replayed
  across sim changes diverges silently. After a bump, re-stamp the corpus
  (`REGEN=1`) and re-record any bot log whose actions no longer replay.
- Human shell (`shell/`): SVG-sprite Godot scene over the sim — see
  `docs/SHELL.md` for controls. `tests/test_shell.gd` smoke-tests it
  headless; `tests/render_frame.gd` renders any game state as a standalone
  SVG screenshot (the agent's way to see the shell). Sprites are hand-written
  SVG strings in `shell/svg_art.gd`. The sim must never depend on the shell.
- Workflow: no PRs; commit on `claude/godot-setup-q6hk6p` and merge/push
  straight to `main`.
