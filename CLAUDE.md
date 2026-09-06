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
  run; reports per-build win rates), optimizer (heuristic skilled play),
  deeproot (clone()-based 1-ply search; the measurable skill ceiling — bots
  that need the sim as a forward model implement `set_sim(game)`), and
  deeproot_plan (deeproot plus option-value eval terms, one-setup-ahead plan
  mode and shrine routing/shopping; the combo-depth instrument - its delta
  against deeproot measures how much setup-then-payoff the content holds).

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
    (check the printed diffs by hand first), `REGRESS_DIR` points at another corpus.
    An event pattern pins a `Vector2i` value as a String (`"to": "(5, 3)"`):
    `regress_lib.event_matches` falls back to `str()` as soon as either side is
    a String, and an `[x, y]` pattern throws on the `!=` operator instead
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
  persona so the legacy ceiling column survives). No persona names a protected
  ability id: the draft drop guards read the run's loadout row through
  `optimizer._protected_ids(snap)` (`Content.LOADOUTS[snap.loadout].protect`,
  falling back to every held `role == "mobility"` ability when the id is
  unknown), and fanatic narrows that to its mobility half with
  `_mobility_ids()` — under `tender` the two reproduce the old
  `["mycelium_dash", "seed_bomb"]` and `["mycelium_dash"]` exactly.
- Balance sweeps (on demand; run before shipping new content, and verify any
  outlier at 30+ seeds before patching — 10-seed spreads are noisy). Shared env:
  `SWEEP_BOT=<roster name>` (default optimizer), `SWEEP_SEEDS` (default 30),
  `SWEEP_SEED_FROM` (out-of-sample checks), plus the three config axes every
  runner that builds its config through `Sweep.env_config()` (the old
  `tier_config`) gets for free: `SWEEP_TIER=<int>`, `SWEEP_LOADOUT=<id>` (a
  `Content.LOADOUTS` id) and `SWEEP_UNLOCK=fresh|package:<id>|all` (the
  unlock-state axis: no packages, the one committed package, or every
  package). An unknown loadout/unlock value is a `push_error` and the key is
  left alone, so the printed header always names the config that actually ran.
  Callers today: `sweep_combos`, `sweep_grafts`, `sweep_tiers` (which sweeps
  the tier axis itself, so it drops `tier` from the base config and keeps the
  other two) and `measure_bosses`; `verify_kit`, `measure_fanatic`,
  `draft_oracle` and `sweep_packages` still build their configs inline and
  ignore the three:
  - `tests/sweep_combos.gd` — locked-kit lift: every config is `{kit: K, pool: K}`,
    `lift = pair - max(single_x, single_y)` with Wilson CIs and a paired sign
    test; `SWEEP_PAIRS=a+b,c+d` selects pairs, `SWEEP_SHARD=i/n` slices the
    66-pair grid (deeproot grid is hours), `SWEEP_MODE=drift` keeps the old
    open-pool "start with the pair" question as a labelled second table
  - `tests/sweep_packages.gd` — each tech package added to the pool
  - `tests/sweep_grafts.gd` — each `Content.GRAFTS` entry pre-installed
    (`{grafts: [g]}`) against the same seeds with none, plus an all-grafts row
    (ten grafts since C3: six stat/mod rows plus `ember_sap`, `undertow`,
    `compost` and `oil_tithe`, so a full sweep is ten configs + base + all);
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
  through `Content.terrain(kind, key, default)`, `Content.is_corruption(kind)`
  and `Content.counts_as_corruption(kind)`),
  `Content.REACTIONS` (rows consumed by `Game._terrain_react()`; disabled rows
  are design intent kept as data) and `Content.STATUSES` (stack rule, blocked
  intents, blocked_event, tick damage, optional stagger-style cooldown).
  Live rows (C1b): TERRAIN has `ash` — burnt oil, corruption true but
  shields_core false, washable, convertible, bloom 1, never generated by mapgen —
  so a burnout leaves corruption standing. Counting reads
  `Content.counts_as_corruption` — corruption, or a kind whose `burns_to` is
  corruption ("pending corruption": a fire that will leave ash) — at exactly
  two sim sites, `_count_corruption` (green-gate clamp, `_reclamp_quota`,
  `floor_restored`) and `_room_has_corruption` (room bloom), so lighting a
  slick never shrinks the quota and the room waits for the ash; every other
  rule (cleanse legality, shields_core, convertible, washable, bot pathing)
  keeps `is_corruption`, and washing the fire or the ash away still re-clamps;
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
  into the combo rate. Live rider rows (C2, added at bump 4): `grow_spike`
  and `grow_spike+` carry `per` (growth_adjacent_target over a base 3, cap 1 and
  cap 2), `sun_flare` and `sun_flare+` a `bonus` (+1 on an enemy standing in
  fire, which their own ignite pass can light under it), and `seed_bomb+`,
  `vine_whip+` and `water_jet+` a `then` (root on freshly planted tiles, stun
  when the drag crossed fire, root when the shove both pushed and collided) —
  `tests/regressions/c2_*.json` demos one row each.
- Grafts are data (`docs/PROGRESSION_REVIEW.md` §6.3 C3): every `Content.GRAFTS`
  row is `{name, desc, tags}` (tags a `Content.TAGS` subset) plus exactly one of
  `stat: {key: int}` — summed by `Game._graft_stat(key)` over the held grafts,
  keys `bank_cap`, `shield_cap`, `regen`, `growth_heal`, `cleanse_bloom`;
  `mod: {key: value}` — first held value via `Game._graft_mod(key, default)`,
  keys `floor_start_shield`, `oil_cast_discount`; or `hooks: [rows]`. There is
  no `_has_graft`: a graft that needs a new number needs a new stat/mod key and
  a table read at the site, never an id literal in `game.gd`. Ten rows today:
  `deep_cells`, `thick_bark`, `solar_core`, `verdant_pulse`, `bloom_surge`
  (stat), `carapace`, `oil_tithe` (mod), `ember_sap`, `undertow`, `compost`
  (hooks). `oil_tithe` takes 1 off the first oil-aimed cast of each turn
  (floored at 1; `ability_cost(aid, target)` prices it, `legal_actions` prices
  each target, `{t: "tithe", id}` marks the spend, `tithe_used_this_turn` resets
  in `_begin_player_turn`).
- Hook dispatcher (`Game._hook(kind, ctx)`, C3): reactive rules are data.
  Kinds are `Content.HOOK_KINDS` — `ignite`, `staggered`, `cleanse`,
  `growth_planted`, `kill`, `shield_break`, `collision` — each fired at the sim
  site right after the matching `_emit`. Sources are scanned in fixed order:
  kit slots 0..n (an `ABILITIES` row may carry `hooks`; none does yet) then
  `player.grafts` in held order. A row is `{on, effects, cap_per_turn?, if?}`;
  effects are ordinary `_apply_effect` dicts aimed at the hook tile plus the
  three positional ops `damage_at {dmg}`, `status_at {status, turns}` and
  `terrain_at {kind}`. Every row that runs emits `{t: "hook", id, on, tile}`
  (counted by `tests/tally.gd` as `hooks_by_graft` / `hooks_by_kind`).
  `Content.HOOK_DEPTH_MAX` (3) bounds hook-caused nesting and
  `Content.HOOK_STEP_CAP` (12) the rows run per `step()`; past either the hook
  is skipped and `{t: "hook_capped"}` is emitted once per step. Per-turn caps
  live in `hook_uses` (per source id, reset in `_begin_player_turn`, copied by
  `clone()`, deliberately not in `snapshot()`); `tithe_used_this_turn` is kept
  the same way. `tests/test_content.gd` lints every row (tags, the closed
  stat/mod key sets, hook `on` kinds, effect ops) and rejects hook effects that
  grant shield, thorns, heal or cleanse credit — the stall vector BALANCE.md
  documents. `tests/regressions/c3_*.json` demos one rule each.
- Package `+` rows (C4): every `Content.PACKAGES` ability now has a `<id>+`
  row — `spore_cloud+`, `fungal_ring+`, `burrow+`, `tide+`, `steam_vent+`,
  `geyser+`, `gust+`, `updraft+`, `clear_air+`. The draft offers `<id>+` only
  when the base is held and the shrine forge only upcycles a held base, so
  `Content.DRAFT_POOL` and base-pool balance are untouched. Convention: costs
  never move, numeric bumps only (range, dist, radius, dmg, ttl; a row may bump
  more than one) and at most one C1 rider, only where the vocabulary states the base identity
  (`grow_radius` ignores its `radius` key, so `fungal_ring+` takes the
  `seed_bomb+` on-planted root instead of a wider ring).
  `tests/regressions/c4_*_plus.json` demos one row each.
- Mutators are data (C4): every `Content.MUTATORS` row carries a `config` dict
  and the sim reads it through the one helper `Game._mut(key, default)` — it
  scans the held mutators in order, first hit wins for a scalar, array values
  concatenate. There is no `mutators.has("...")` left in `sim/game.gd`. The
  config keys are the closed set `Content.MUTATOR_CONFIG_KEYS`: `kit_max`,
  `max_hp_delta`, `bank_cap`, `oil_mult`, `extra_common_enemy`, `shop`,
  `pool_ban`, `kit_ban`, `draft_offers`, `draft_upgrades_only`, `open_pool`.
  Ten rows — the six originals (`kit_of_3`, `brittle`, `parched`,
  `double_oil`, `overtime`, `boarded`) reproduce their old numbers exactly,
  plus the three C4 rows: `no_lance` (`pool_ban: ["solar_lance"]` + `kit_ban`
  — the lance leaves the starting kit and the draft pool, and the shrine stock
  follows the pool), `wide_draft` (`draft_offers: 4`) and `upgrades_only`
  (`draft_upgrades_only` — candidates are only the `+` forms of held
  abilities; with none available the draft is skipped as before), plus the one
  Block A row: `open_pool` (`open_pool: true` — every `Content.PACKAGES`
  ability joins the draft pool, the old all-packages variety kept as a
  deliberate choice now that a package is a one-per-run commitment; the
  profile unlocks it at one win). Adding a mutator means adding a row; one
  that needs a new number needs a new config key, a `_mut` read at the site
  and the key in `MUTATOR_CONFIG_KEYS` (which `tests/test_content.gd` lints).
  `tests/regressions/c4_no_lance.json`, `c4_wide_draft.json` and
  `c4_upgrades_only.json` demo the three C4 rows.
- Run summary and effective casts (C4): `Game.effective_uses` (base id -> int)
  counts a cast only when something happened — an effect outcome fired or a
  rider ran — while `player.uses` stays the raw count. It is copied by
  `clone()` and deliberately not in `snapshot()`, so it never churns the state
  hash. Teleport, dash, clear_smoke and self-only ops set no outcome counter
  and so never count as effective; `create_terrain` counts (planted). `Game.run_summary()`
  is the compact end-of-run dict — `{won, floor, turns, kit, grafts,
  uses_by_base, effective_uses_by_base, bloom, death_cause, seed, tier,
  mutators, packages, loadout}` — read by the shell's game-over site and the
  meta layer; the sim never consumes it. `uses_by_base` takes the max of a
  base and its `+` key rather than the sum, because the draft and the forge
  seed the `+` key with the base's count.
- Starting loadouts are data (Block A, `docs/PROGRESSION_REVIEW.md` §6.1):
  `Content.LOADOUTS` rows are `{name, desc, kit: [3 ids], protect: [ids],
  requires: {packages: [...]}}` and `Content.loadouts_for(unlocked_packages)`
  filters by `requires`. Six rows — `tender` (the starter, its kit IS
  `STARTING_KIT`, so a default-config run is byte-identical to before),
  `tidewarden`, `flarekeeper`, `spiker`, `lasher` (each swaps the lance for one
  other ability) and `skyrunner` (`requires {packages: ["aeolian"]}`). Every
  row keeps `seed_bomb` and exactly one `role == "mobility"` ability
  (`tests/test_content.gd` lints both). Three consumers, one key each: the sim
  reads `kit` only, the bots read `protect` (never an id literal), and
  `meta/profile.gd` enforces `requires` — the sim applies whatever loadout id
  it is handed and only warns on an unknown one.
- Sim run config: `Game.new(seed, {kit, pool, packages, tier, mutators, grafts,
  bloom, loadout})` for sweeps, meta-unlocks, and post-win difficulty tiers.
  `loadout` is a `Content.LOADOUTS` id (default `tender`; unknown -> warning +
  tender) and picks the starting kit, but an explicit `kit` still wins, so
  every locked-kit sweep config is unaffected. `grafts` is
  a list of `Content.GRAFTS` ids installed before floor 1 (unknown ids are
  skipped with a warning; owned grafts raise the shrine's graft price) and
  `bloom` is the starting balance — neither touches the main rng.
- Meta layer: `meta/profile.gd` records runs against `Content.MILESTONES` and
  hands back the next run's config; the sim itself stays career-agnostic.
  `record_run(summary)` takes a `Game.run_summary()` dict (the old
  `{won, floor, tier}` shape still works — every other key defaults) and keeps
  a 50-entry history of compact per-run records (newest last, older dropped)
  plus `casts_by_base`, effective casts summed across runs. Milestone
  `requires` predicates: `best_floor`, `wins`, `tier_wins`,
  `won_with: [base ids]` (a recorded win whose kit held them all, a `+` form
  counting as its base), `wins_without: [base ids]`, `casts: {base id: n}`
  (cumulative effective casts) and `grafts_owned_at_win: n`. A row's `kind`
  dispatches explicitly to `unlocked_packages` / `unlocked_mutators` /
  `unlocked_loadouts` / `unlocked_grafts` (Block A gave `unlocked_loadouts` a
  consumer — `game_config` / `available_loadouts`; `unlocked_grafts` still has
  none); an unknown kind is a `push_error` and is skipped. `load_from` filters every
  stored id against `Content`, so renamed content cannot brick a profile.
  Daily runs go through `record_daily(summary)` into `daily_best[str(seed)]`
  and never touch the career.
- One package per run (Block A): `profile.game_config(tier, mutators, loadout,
  package)` hands back a kit-free `{packages, tier, mutators, loadout}` — the
  package is a run-scoped commitment, so the draft pool is 14 or 17 ids, never
  23; a locked/unknown package degrades to none and a locked loadout (or one
  whose `requires.packages` are unmet) degrades to `tender`. The old
  everything-at-once pool is the `open_pool` mutator. `available_loadouts()`
  is the menu list. The daily is career-agnostic: static
  `Profile.daily_config(seed)` -> `{loadout, package, mutator, tier: 0}` is a
  pure function of the seed over the FROZEN `DAILY_LOADOUTS` /
  `DAILY_PACKAGES` / `DAILY_MUTATORS` lists (frozen so a growing content table
  never moves an earlier date), and `daily_game_config(seed)` spells the same
  choice as a `Game.new` config.
- Balance targets and the measurement discipline live in `docs/BALANCE.md`;
  `tests/daily_run.gd` generates the date-seeded daily challenge through
  `Profile.daily_config`.
- Death autopsy (`tests/autopsy.gd`): `AUTOPSY_BOT=<persona> AUTOPSY_SEED=<n>`
  reruns a game and prints the last `AUTOPSY_LAST` ASCII frames — use it to
  "watch" any death a sweep or playtest flags. `AUTOPSY_TIER`/`AUTOPSY_MUTATORS`/
  `AUTOPSY_KIT` set the config; `AUTOPSY_JSON=<path>` dumps the run as a
  (seed, config, actions) regression pair and `AUTOPSY_REPLAY=<path>` replays one.
- Live-run import (`tests/import_run.gd`): `IMPORT_RUN=<run.save>
  IMPORT_OUT=<record.json> [IMPORT_NOTE=...]` replays a phone run's saved action
  log through the pure sim and writes the regression record it proves; a save
  whose header version is not `Game.SIM_VERSION` is refused, never guessed at.
- `Game.SIM_VERSION` in `sim/game.gd` is the single replay-version source (7
  today: Block A — the starting loadout (`Content.LOADOUTS`, config key
  `loadout`) and the `open_pool` mutator. A default-config run is untouched
  (`tender` is `STARTING_KIT` and the pool is unchanged), so the 7 re-stamp
  rewrote only `sim_version` across the corpus with no outcome or hash diff;
  a run recorded with a non-default loadout would replay with a different kit,
  which is what the bump buys. Bump 6 was C4 — the nine package `+` rows (those
  bases became forgeable at the
  shrine and draftable-as-upgrade once held) and mutator numbers moving into
  `Content.MUTATORS[...].config`; neither changed a default-config run either.
  Bump 5 was C3 grafts-as-data
  and the hook dispatcher — the shrine stocks from ten grafts, so the
  `shop_graft` side draw and every bot's graft pick shifted and any bot log
  recorded at 4 desyncs from its first shrine on; bump 4 was the C2 rider rows
  on `grow_spike(+)`, `sun_flare(+)`, `water_jet+`, `vine_whip+` and
  `seed_bomb+`): bump it whenever a sim change alters replay behaviour.
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
