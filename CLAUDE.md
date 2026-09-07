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
    lint (closed op/rider vocabulary, TERRAIN/REACTIONS/STATUSES rows, the D4
    `DRAFT_SLOTS`/`AFFINITY_IGNORED_TAGS` shapes, plus a self-test that feeds
    the lint deliberately bad rows and the planned rider rows)
  - `godot --headless --path . --script tests/test_grammar.gd` — effect grammar
    behaviour: rider evaluation, returned outcomes, the data tables driven
    through `Game._apply_effect` on hand-built states, and the D4 draft slots
    (affinity/upgrade/wild candidates, the one-draw-per-slot count, focus)
  - `godot --headless --path . --script tests/test_economy.gd` — shrine economy
    and quota: config-independent main rng, shop stock filters, graft/ability/
    press/forge purchase rules, the shrine reroll (legality, price escalation,
    the cap, offer exclusion, closed slots, rng-state independence), quota
    re-clamp, damage attribution
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
  Shrine rerolls (D2, legal only under the `spinning_shrine` mutator — a
  default run never lists the action) are a persona choice, read from
  `snapshot().shop` (`reroll_price` / `rerolls_left`), never from the sim:
  optimizer spins only
  with the graft counter open, no affordable offer scoring on its kit-tag fit,
  a spin left and a purse still covering the spin plus the cheapest
  `Content.GRAFTS` price (so a spin is never a run's last bloom), magpie
  (the canary) spins whenever nothing on the counter is affordable, and
  sprout, wanderer and fanatic-beyond-optimizer are unchanged. deeproot and
  deeproot_plan evaluate `reroll` like any other legal action — and because
  the redraw is side-rng deterministic, a clone-based search *sees the new
  offers before paying for them*. That is an instrument property, not a bug:
  their reroll numbers are an oracle upper bound on the sink (BALANCE.md), and
  the gap to optimizer/magpie is the value of information a human does not
  have.
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
  enter/tick damage, blocks, blocks_beam, heal, burns_to, convertible,
  screens; read
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
  carry `surge` (a row-level key, never an effect key — see the surge bullet
  below). New ops, predicates, counts or terrain
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
- Verdant surges are data (D1, `docs/PROGRESSION_REVIEW.md` §6.4; bump 9):
  an ability row's optional `surge` dict (default `Content.SURGE_DEFAULT`,
  `{cost: -1}`) says what standing on growth buys that cast. One rule,
  `Game._surges(adef)`: a cast SURGES when the tender stands on growth and the
  surge dict carries something that applies to it — a cost delta that actually
  lowers a cost >= 2 (`maxi(1, base + surge.cost) < base`), or any stat key. A
  surged cast erases the growth tile underfoot and emits `verdant`, exactly as
  before. A cost-1 ability with only the default surge therefore never surges
  and never eats the tile (pre-D1 it did not either); a cost-1 ability with a
  stat surge does eat it, and gets the stat. The closed surge key set is
  `{cost, dmg, push, collision_dmg, radius, dist, turns, ttl}`, each an int;
  `cost` prices the cast (`ability_cost`, unchanged in shape, and
  `legal_actions` through it) while every other key is a stat delta added by
  `Game._apply_effect` to the matching key of every effect of that cast that
  carries it — on a duplicated effect, before `per` grows it and before the op
  runs, and `then` sub-effects inherit it through ctx. A surged cast that
  applied at least one stat delta emits `{t: "surge", id, keys: [...]}` once,
  after its `ability` event (event order: `verdant`, `ability`, `surge`, then
  the effects). The lint requires every surge stat key to be carried by some
  effect of the row — a surge that touches nothing is a data error — and
  rejects `surge` on an effect dict. Seven rows carry one today: `grow_spike`
  and `grow_spike+` `{dmg: 1}`, `water_jet` and `water_jet+`
  `{push: 1, collision_dmg: 1}`, `sun_flare` and `sun_flare+`
  `{cost: -1, radius: 1}` (the discount they always had, plus reach) and
  `seed_bomb+` `{radius: 1}` (base `seed_bomb` keeps the default).
  Two grammar changes ride along: `grow_radius` now READS its `radius` key
  (review defect 16) — radius 1 is the plus it always drew, radius 2 the
  13-tile diamond a surged `seed_bomb+` reaches — and the new positional op
  `plant_origin {kind}` (kind closed to `Content.TERRAIN`) writes that kind on
  `ctx.origin` when the tile the cast left is floor, terrain-free and empty of
  enemies, counting as planted so `status_target who: on_planted`, the
  `growth_planted` hook and `effective_uses` all see it. `mycelium_dash+` is
  Spore Trail: `[{op: teleport}, {op: plant_origin, kind: growth}]`, cost and
  range unchanged. Terrain insertion order is hash-visible (`terrain.keys()`
  feeds the growth target list and `state_hash` hashes `str(snapshot())`), so
  `grow_radius` keeps its pre-D1 target-then-DIRS order for the plus and only
  the outer rings iterate dy-then-dx — a radius-1 cast is byte-identical to
  before. `tests/regressions/d1_*.json` demos six cases: the three stat
  surges, the `seed_bomb+` diamond, Spore Trail, and a cost-1 default-surge
  ability leaving the tile standing.
- Grafts are data (`docs/PROGRESSION_REVIEW.md` §6.3 C3): every `Content.GRAFTS`
  row is `{name, desc, tags, price}` (tags a `Content.TAGS` subset, `price` an
  int >= 1 — both lint-enforced) plus exactly one of
  `stat: {key: int}` — summed by `Game._graft_stat(key)` over the held grafts,
  keys `bank_cap`, `shield_cap`, `regen`, `regen_on_growth`, `growth_heal`,
  `cleanse_bloom` (`regen_on_growth` is added to regen only on the turns the
  tender begins standing on growth; no shipped row uses it — the key exists so a
  conditional alternative to `solar_core` can be probed in a scratch tree);
  `mod: {key: value}` — first held value via `Game._graft_mod(key, default)`,
  keys `floor_start_shield`, `oil_cast_discount`; or `hooks: [rows]`. There is
  no `_has_graft`: a graft that needs a new number needs a new stat/mod key and
  a table read at the site, never an id literal in `game.gd`. Ten rows today:
  `deep_cells`, `thick_bark`, `solar_core`, `verdant_pulse`, `bloom_surge`
  (stat), `carapace`, `oil_tithe` (mod), `ember_sap`, `undertow`, `compost`
  (hooks). `oil_tithe` takes 1 off the first oil-aimed cast of each turn
  (floored at 1; `ability_cost(aid, target)` prices it, `legal_actions` prices
  each target, `{t: "tithe", id}` marks the spend, `tithe_used_this_turn` resets
  in `_begin_player_turn`). A graft's `price` is what the shrine charges for it
  (bump 8): `Game.shop_cost(item, id = "")` reads `Content.GRAFTS[id].price` for
  item `"graft"` with a known id, then adds `GRAFT_PRICE_STEP` (2) per owned
  graft and the tier markup — `SHOP_COSTS["graft"]` (4) survives only as the
  id-less fallback for callers that want "the graft price". Prices are pure
  table reads and never touch the rng. `legal_actions` prices every offer
  separately, so a purse can afford one pick and not the other; `_act_buy`
  resolves the pick before pricing and deducts that offer's own price; and
  `snapshot().shop` carries `graft_prices` (aligned with `grafts`, derived per
  snapshot, never stored) so the shell and the bots read prices without calling
  the sim. Prices today — `solar_core` 8 (the one measured lever), `compost` 6,
  `ember_sap` 5, `oil_tithe` 5, `undertow` 4, and the five noise-level stat rows
  `deep_cells`/`thick_bark`/`verdant_pulse`/`bloom_surge`/`carapace` at 3 — come
  from measuring every graft pre-installed (`{grafts: [g]}`) before pricing it;
  the sweeps are in `docs/BALANCE.md` (2026-09-06d, 06f and 07).
- Shrine reroll (Block D2, `docs/PROGRESSION_REVIEW.md` §6.4): the one
  repeatable bloom sink, and a choice sink — **held behind a switch**: the
  action is legal only under the `spinning_shrine` mutator (config key
  `shop_reroll`, read live through `_mut`; unlocked at the first win), because
  with it on the magpie canary rose 8% -> 15.5% over 200 paired seeds and
  every single price/cap lever still failed the 30-seed gate (BALANCE.md
  2026-09-07e) — default-on is an owner decision, one `_mut` default away.
  A default run never lists the action and its derived `rerolls_left` reads
  0, so the shell draws no card. Under the mutator: action `{"type": "reroll"}`,
  legal in phase `play` while the tender stands on the shrine, the counter
  still holds a re-drawable slot (`ability`, `grafts` or `item` — bought slots
  never come back), `shop.rerolls < Content.SHOP_REROLL_CAP` and the purse
  covers `shop_cost("reroll")`; every other case is
  `{t: "illegal", action: "reroll"}`. It costs bloom, never a charge. Each
  stocked re-drawable slot is redrawn from the same candidate rule
  `_stock_shop` uses (`_shop_ability_candidates` / `_shop_graft_candidates` /
  `_base_item_ids`, one shared `_shop_draw`), minus the offer on the counter
  whenever an alternative exists — with none the offer stays and that slot is
  not redrawn — each from its own side generator
  `_side_rng("reroll<n>_ability" / "reroll<n>_graft" / "reroll<n>_item")` with
  `n` the spins already taken, so the main rng never moves. Price is data:
  `Content.SHOP_COSTS["reroll"]` (2) plus `Content.SHOP_REROLL_STEP` (1) per
  spin already taken plus the tier markup every price pays — 2, 3, 4 at tier 0
  — and `Content.SHOP_REROLL_CAP` (3) bounds the spins per shrine (the cap
  bounds the action space and the search bots' shrine branching; the step
  keeps a repeatable sink getting dearer). `shop.rerolls` is stored stock
  (`_stock_shop` seeds it at 0, `clone()` copies it, `state_hash()` sees it);
  `reroll_price` and `rerolls_left` are derived `_shop_snapshot` keys, so the
  shell and the bots read the price without calling the sim and the hash never
  sees them. Event: `{t: "reroll", n, cost, ability?/grafts?/item?}` naming the
  slots actually redrawn (`tests/tally.gd` counts rerolls, bloom spent on them
  and buys after one). `tests/regressions/d2_reroll.json`,
  `d2_reroll_escalates.json`, `d2_reroll_closed_slot.json` and
  `d2_reroll_boarded.json` demo the rule (each carries the mutator in its
  config).
- Enemies read terrain (Block D3, `docs/PROGRESSION_REVIEW.md` §6.4; the review
  finding 5.2 "enemies are terrain-blind"): both halves are data.
  **Avoid lists.** A `Content.ENEMIES` row may carry `avoid: [terrain kinds]`
  (default `[]` = terrain-blind, exactly the pre-D3 chase). Seven rows carry
  `["fire"]` — `drill_bot`, `oil_sludge`, `sludgeling`, `leech_drone`,
  `tar_spitter`, `rust_hound`, `magnet_crane`; `welded_hulk` (nothing stops the
  hulk), `coal_golem` (made of coal), `cinder_mite` (the igniter WANTS fire),
  the three stationary kinds and every boss carry none, and each row that
  deviates from its family carries the one-line reason. `Game._chase_step` is a
  Dijkstra over integer costs: entering a tile costs 1, plus
  `Content.ENEMY_AVOID_COST` (4) when its terrain kind is in the row's `avoid`;
  passability stays `_open()`; the goal is any tile at manhattan 1 from the
  tender; the first step of the cheapest path is returned; the tile the enemy
  stands on is never charged. The cost is a price, never a wall — a detour up
  to ENEMY_AVOID_COST longer is taken and a longer one is not (the equal-cost
  tie rule below, fewer avoided tiles first, is what makes the "up to"
  inclusive: a detour exactly ENEMY_AVOID_COST longer ties on cost and wins
  on avoided tiles; grid detours differ by an even count, so at 4 the bracket
  is +4 taken, +6 not), so a ring of
  fire is never an immortal fence (the enemy walks in when that is the cheapest
  way) and the constant is the one tuning lever. Ties break deterministically:
  ascending cost, then fewer avoided tiles, then push order with neighbours
  pushed in `DIRS` order — so for an empty `avoid` list every key is
  `(cost, 0)`, nothing is ever re-pushed, the drain order IS the old BFS's
  dequeue order and the returned step is byte-identical to the pre-D3 chase
  (`tests/test_grammar.gd` keeps that BFS as a reference implementation and
  asserts equality over 210 generated floors x every enemy x sampled tender
  positions). The `move` intent and the boss `advance` intent both call it, so
  both gained the rule with no special-casing.
  **Smoke screens.** `Content.TERRAIN` gained the bool key `screens` (true on
  `smoke` alone) and `Content.SCREENED_INTENTS` is the closed list `drain`,
  `gum`, `drag`. `Game._screened` is read at `_execute_intent` ONLY — the
  intent is still computed and telegraphed, so a gum is something the tender
  can step into smoke to dodge — and it fizzles such an intent when the
  tender's own tile or any of its four `DIRS` neighbours screens, the enemy is
  not adjacent (manhattan > 1: you cannot smoke-screen at arm's length) and its
  row lacks the `massive` trait (bosses see through smoke, the same exemption
  `_apply_status` uses). It is adjacency-based on purpose: not a `_line_clear`,
  never consulting intervening enemies or walls. A screened intent emits
  `{t: "screened", id, intent}` and ends that enemy's action; `tests/tally.gd`
  counts it as `screened_by_intent` (the denial line prints `screened n/run`
  beside `enemy fire dmg n/run`), and the shell logs it as
  "<Name>'s <intent> is lost in the smoke" and adds an `avoids: fire` line to
  the enemy tooltip straight off the row. `tests/test_content.gd` lints `avoid`
  entries against `Content.TERRAIN`, `ENEMY_AVOID_COST` as an int >= 1,
  `SCREENED_INTENTS` as a subset of the intent vocabulary and `screens` as a
  TERRAIN bool. Five demos, each of which a targeted mutation breaks in plain
  (non-strict) mode: `tests/regressions/d3_avoid_detour.json` (a drill bot pays
  two extra tiles to go round a burning corridor — the `sap_snare` after the
  turn is an illegal action unless it did), `d3_avoid_no_fence.json` (ringed by
  fire with no detour it walks in and eats the enter plus tick damage),
  `d3_coal_walks_fire.json` (the same board and a coal golem takes the short
  burning corridor — the list is per kind, and no kind is named in
  `sim/game.gd`), `d3_screened_gum.json` (a telegraphed gum fizzles beside
  smoke, lands one tile away with that same smoke still standing, and fizzles
  again on the step back — the adjacency rule, not the ttl) and
  `d3_screen_melee.json` (the same smoke, an adjacent spitter, gummed).
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
  `pool_ban`, `kit_ban`, `draft_offers`, `draft_upgrades_only`, `open_pool`,
  `shop_reroll`. Eleven rows — the six originals (`kit_of_3`, `brittle`, `parched`,
  `double_oil`, `overtime`, `boarded`) reproduce their old numbers exactly,
  plus the three C4 rows: `no_lance` (`pool_ban: ["solar_lance"]` + `kit_ban`
  — the lance leaves the starting kit and the draft pool, and the shrine stock
  follows the pool), `wide_draft` (`draft_offers: 4`) and `upgrades_only`
  (`draft_upgrades_only` — candidates are only the `+` forms of held
  abilities; with none available the draft is skipped as before), plus the one
  Block A row: `open_pool` (`open_pool: true` — every `Content.PACKAGES`
  ability joins the draft pool, the old all-packages variety kept as a
  deliberate choice now that a package is a one-per-run commitment; the
  profile unlocks it at one win), plus the one Block D row: `spinning_shrine`
  (`shop_reroll: true` — the D2 shrine reroll, held behind this switch after
  its measurement; unlocked at one win). Adding a mutator means adding a row; one
  that needs a new number needs a new config key, a `_mut` read at the site
  and the key in `MUTATOR_CONFIG_KEYS` (which `tests/test_content.gd` lints).
  `tests/regressions/c4_no_lance.json`, `c4_wide_draft.json` and
  `c4_upgrades_only.json` demo the three C4 rows.
- Affinity draft (Block D4, `docs/PROGRESSION_REVIEW.md` §6.4): the descent
  draft is slotted, so a run's own build steers what it is offered.
  `Content.DRAFT_SLOTS` (`["affinity", "upgrade_or_affinity", "wild"]`) names
  the role of offer i; an offer past the list (`wide_draft` asks for 4) is
  `wild`. Roles come from the closed `Content.DRAFT_SLOT_ROLES`, and what an
  offer reports is one of `Content.DRAFT_SLOT_REPORTS`
  (`affinity`/`upgrade`/`wild`/`focus`). The run's affinity tag set is the
  union of `Content.ABILITIES[id].tags` over the held kit (a `+` form carries
  its base's tags) and `Content.GRAFTS[id].tags` over the held grafts, minus
  `Content.AFFINITY_IGNORED_TAGS`. That constant means "these tags do not
  define a build" (`["mobility"]` — every loadout carries a mobility ability,
  so counting it would make every run mobility-affine) and BOTH build-steering
  slots read it through the one helper pair `Game._tag_defines_build(tag)` /
  `Game._build_defining(aid)` (the latter guards its row read, so an unknown
  id defines nothing). The affinity tag SET has one reader,
  `Game._affinity_tags()`, and the two candidate lists in
  `_draw_draft_offers` are the only other place the
  sim reads `tags` — all of it serves this one draft rule, and nothing else in
  the sim reads a tag. Candidates come from the universe the
  draft already used — unowned `draft_pool` bases (never a base whose `X` or
  `X+` is held) plus the `+` forms of held bases; under `draft_upgrades_only`
  only the `+` forms, and every role collapses to that list. `affinity` =
  unowned pool bases sharing a tag with the set; `upgrade_or_affinity` = the
  `+` forms of held BUILD-DEFINING bases (reported `upgrade`), else the
  affinity list; `wild` = the whole universe. The upgrade filter is the
  affinity set's own rule applied to the other half of the universe: the kit
  scan builds two lists in one pass, `upgrades` (every `+` form of a held
  base) and `deepenings` (the same minus rows where `_build_defining` is
  false), `universe` is still `bases + upgrades` and only the
  `upgrade_or_affinity` arm reads `deepenings` — so `mycelium_dash+` and
  `burrow+` are off that slot while `updraft+` (`["wind", "mobility"]`) stays,
  the UNIVERSE is untouched (a wild slot still offers the dash upgrade, and
  the shrine forge, which reads the kit, still upcycles it), and under
  `draft_upgrades_only` the `+` list IS the universe so that arm keeps using
  `upgrades` — filtering it could empty a draft that today has offers. It is
  tags, never `role`. Unfiltered, `mycelium_dash+` was offered 158 times in
  511 optimizer drafts and taken 0; filtered it is 36 offers, all from wild
  slots, and 0 of 310 upgrade-slot offers over seeds 1..60 are a pure-mobility
  `+` form (BALANCE.md 2026-09-07g). An id already
  drawn is excluded from every later slot. `_draw_draft_offers(count)` spends EXACTLY one
  main-rng draw per slot: a slot whose list is empty after exclusions falls
  back to wild-minus-drawn (reported `wild` — except the focus slot, which
  keeps its `focus` label through the fallback whatever list it drew from),
  and when that is empty too the
  draw still happens and the slot yields nothing — so the number of main-rng
  draws is the slot count and never the kit, the grafts or the pool, which is
  what keeps two configs on one seed comparable downstream (Godot's
  `randi_range(lo, lo)` is an early return that does not advance the
  generator, so the draw is `rng.randi()` and the index its remainder).
  `draft_slots` is stored beside `draft_offers` — the role that produced each
  offer, cleared with it — and the new stored int `focus` (0 or 1) is armed by
  a skip: the next draft rolls `count + 1` offers whose extra trailing slot is
  an affinity slot reported `focus`, and the roll spends the flag whether or
  not the player then picks. A skip still never pays bloom. The focus slot can
  buy nothing: under `draft_upgrades_only` a 3-ability kit has exactly three
  upgrade candidates, the three ordinary slots take them all and the focus
  slot's list (and the wild fallback, which is the same list) is empty, so the
  roll spends its draw, clears the flag and deals no fourth card — a skip is
  strictly dominated under that mutator, pinned by `tests/test_grammar.gd`. Both `draft_slots`
  and `focus` are in `snapshot()` and therefore in `state_hash()`. Events: the
  `draft_offer` event carries `offers`, `slots` and `focus` (bool);
  `draft_pick` / `draft_upgrade` / `draft_skip` and the `legal_actions` /
  `_act_draft` pick/drop/skip shape are unchanged. `tests/tally.gd` counts
  `offers_by_slot` / `picks_by_slot` / `focus_drafts` and prints one `draft:`
  line (picks/offers by slot, focus drafts of drafts, skips); the shell's
  draft sheet labels each card with its role and its skip button reads
  "skip - next draft: +1 affinity offer"; the sheet learns whether the ROLL
  spent a focus from the `draft_offer` event (`_draft_focus_spent`), not from
  the cards, so a focus slot that dealt nothing says "your skip found nothing
  left to focus on" instead of reading as an ordinary draft. `tests/test_content.gd` lints
  `DRAFT_SLOTS` (non-empty, entries from `DRAFT_SLOT_ROLES`) and
  `AFFINITY_IGNORED_TAGS` (a duplicate-free `Content.TAGS` subset) with a
  self-test fixture per bad shape (an ignored-tag list covering every
  `Content.TAGS` entry is rejected too — nothing would define a build) plus
  `_lint_loadout_affinity`, which requires every `Content.LOADOUTS` kit to
  hold at least one build-defining ability ("loadout affinity: 6 / 6 kits hold
  a build-defining ability"); `tests/test_grammar.gd` holds the behaviour
  tests, including check (i) for the upgrade filter (the helpers, a
  whole-table pass over all 48 abilities, all six loadouts x seeds 1..44 =
  264 drafts with 0 pure-mobility upgrade offers, `updraft+` still dealt on a
  skyrunner/aeolian config, the starved fallbacks, a wild slot still offering
  `mycelium_dash+`, the forge still upcycling it, and the draw count held at
  3 for kits whose filtered and unfiltered lists differ by 0, 1 and 2 entries)
  and the draw-count assert (rng.state after a roll equal across
  kits with different candidate counts, and equal to a fresh generator
  advanced `count` times) and the starved cases (a 3-ability kit under
  `upgrades_only` buying no focus card, a mobility-only kit whose focus slot
  falls back to wild and is still reported `focus`). A role is CODE, not data:
  `Game._draw_draft_offers` is the only site that implements one (a match on
  the role strings with `wild` as the catch-all), so adding an entry to
  `DRAFT_SLOT_ROLES` without an arm there silently rolls it as wild —
  `sim/content.gd` says so beside the table. Demos:
  `tests/regressions/d4_affinity_slot.json`,
  `d4_upgrade_slot.json` and `d4_wide_draft_slots.json` are one seed and one
  board through three configs (the flarekeeper's affinity slot deals a sun
  base, the tidewarden's deals a displace base and its slot 1 a held `+` form,
  and the wide draft appends a fourth wild offer to the flarekeeper's three
  unchanged ones), and `d4_focus_skip.json` skips a draft and descends again
  for the four-offer roll whose last slot is `focus` (its slot 1 pins the
  upgrade filter too — `seed_bomb+` where the unfiltered rule dealt
  `mycelium_dash+`). `d4_starved_slot.json`
  pins the one-draw-per-slot contract in plain mode: a kit and pool that leave
  the affinity slot exactly one candidate, so a draw that skips or shortens
  itself on a one-candidate list shifts the two offers after it.
  `d4_upgrade_filter.json` pins both halves of the filter on one board — the
  upgrade slot deals the build-defining `seed_bomb+` while the WILD slot deals
  `mycelium_dash+` on the same roll; unfiltered, the same seed swaps those two
  roles, so removing the filter fails it in plain mode. `c4_upgrades_only.json`
  records the deliberate exemption: the mobility `+` form still appears there
  and in no other slot pin.
- Run summary and effective casts (C4): `Game.effective_uses` (base id -> int)
  counts a cast only when something happened — an effect outcome fired or a
  rider ran — while `player.uses` stays the raw count. It is copied by
  `clone()` and deliberately not in `snapshot()`, so it never churns the state
  hash. Teleport, dash, clear_smoke and self-only ops set no outcome counter
  and so never count as effective; `create_terrain` counts (planted), and
  since D1 so does `plant_origin` — a `mycelium_dash+` hop that leaves growth
  behind it is an effective cast, so `effective_uses["mycelium_dash"]` is
  non-zero where the base dash's bare teleport never counted. `Game.run_summary()`
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
- `Game.SIM_VERSION` in `sim/game.gd` is the single replay-version source (12
  today: Block D4 — the affinity-slotted draft with focus on skip. Offer i of
  a descent draft is rolled by the role `Content.DRAFT_SLOTS[i]` over the same
  candidate universe as before, and `_draw_draft_offers` spends exactly one
  main-rng draw per slot — a padded empty slot included — instead of the old
  `min(count, candidates)` draws from one uniform list, so every log that
  reached a draft diverges at its first `draft_offer` and every downstream
  draw shifts; a skip arms the stored `focus` and the next draft rolls one
  extra affinity slot; and the `upgrade_or_affinity` slot draws from the `+`
  forms of held BUILD-DEFINING bases only, so its offer moves again wherever
  the unfiltered list would have dealt a pure-mobility `+`.
  `draft_slots` and `focus` are stored snapshot keys, so
  the hash of EVERY record moved, drafting or not. The 12 re-stamp rewrote
  `sim_version` and the hash across all 77 old records: 57 stamp-only
  (version + hash, no outcome, action or event-pattern diff), all 20 bot logs
  replayed on their personas of which 16 came back different — an index pick
  lands on a different ability now even where the stale list still replayed
  legally, which is why the re-record is not limited to the desyncing logs;
  the three `det_wanderer_*` logs (a wanderer never descends, so they are the
  check that non-drafting play is untouched) and `det_magpie_s11` came back
  byte-identical — the magpie log DOES draft, and its one draft's offer list
  changed (`["anchor_roots", "pollen_burst", "vine_whip"]` ->
  `["bramble_coat", "solar_lance+", "vine_whip"]`); it replayed unchanged only
  because its stored pick index 2 lands on `vine_whip` in both lists, which is
  the index-pick hazard below arriving as a coincidence — and four
  hand-authored demos re-pinned by hand:
  `c4_no_lance`, `c4_wide_draft` and `c5_loadout_kit_ban` keep their seed and
  actions with a new offer list, while `c5_open_pool` moved from seed 1 to
  seed 5, where the package id that carries its point is dealt by the AFFINITY
  slot (`fungal_ring` is growth-tagged, so `open_pool` widens what every slot
  draws from and not just the wild one). The re-recorded logs are where the
  new draft arrives as difficulty rather than as a stale log:
  `det_optimizer_s11` no longer wins on floor 7 (121 turns, was a win in 83)
  and `det_fanatic_s11` now reaches floor 7 in 247 turns where it used to die
  on floor 2 in 50. The upgrade-slot filter landed inside the same
  uncommitted bump (no second bump: nothing outside this tree ever ran
  SIM_VERSION 12 unfiltered), and it moved the corpus again — `d4_focus_skip`
  re-pinned, three demo notes corrected with no pin change
  (`d4_upgrade_slot`, `d4_starved_slot`, `c4_upgrades_only`), and all 20 bot
  logs re-recorded on their personas of which 13 changed and 7 came back
  byte-identical; `det_optimizer_s42` replayed BYTE-IDENTICAL with a matching
  hash and still changed when re-recorded (its persona now picks index 2
  where it picked 0-and-drop-3), which is the index-pick hazard again and the
  reason a re-record is never limited to the logs that stop replaying. The
  corpus went 77 -> 83 with six `d4_*` demos (the four originals plus
  `d4_starved_slot` and `d4_upgrade_filter`).
  Bump 11 was Block D3 — enemies read terrain. `_chase_step` prices a tile whose
  kind is in the row's `avoid` list at 1 + `Content.ENEMY_AVOID_COST` instead
  of 1, so an avoider takes a different step the moment fire lies on or beside
  its path, and a `Content.SCREENED_INTENTS` intent from a non-adjacent,
  non-massive enemy fizzles when the tender is on or beside smoke. Both are
  ordinary default-config content, so a bot log desyncs from the first floor
  that lights up. The 11 re-stamp rewrote `sim_version` across all 72 old
  records with 69 stamp-only — no outcome, event-pattern or hash diff at all,
  because the hand-authored demos put no avoider beside fire and no smoke
  beside the tender — and three logs whose actions no longer replay
  (`det_deeproot_s11`, `det_deeproot_s42`, `det_magpie_s11`) were re-recorded
  on their personas: `det_deeproot_s42` now WINS on floor 7 in 74 turns where
  it used to die on floor 5 in 86, which is the enemy-AI change arriving as
  difficulty rather than as a stale log. The corpus went 72 -> 77 with the five
  `d3_*` demos. Bump 10 was Block D2 — the shrine reroll, legal only under
  the `spinning_shrine` mutator. No old action became illegal and no main-rng
  draw moved (the redraw is side-rng), but `shop.rerolls` is stored stock, so every record
  whose final shop is still stocked hashes differently: the 10 re-stamp
  rewrote `sim_version` across all 68 old records — 46 with the hash
  unchanged, 18 hash-only (a stocked final shop now stores `rerolls: 0`) —
  with no outcome or event-pattern diff anywhere, and because a default run
  never lists the action every bot log replays its old action list exactly
  (the four magpie/optimizer logs the pre-switch pass had re-recorded went
  back to their bump-9 actions with a hash-only diff). The corpus went
  68 -> 72 with the four `d2_*` demos, each under the mutator. Bump 9 was Block D1 — per-ability
  stat surges and Spore Trail. The surge rule
  moved to `Game._surges` (a cost-1 row with a stat surge now surges and eats
  the tile; a cost-1 row with only the default surge still leaves it alone),
  seven rows gained a `surge` dict, `grow_radius` reads its `radius` key and
  `mycelium_dash+` plants the tile it left, so any log that cast one of those
  from growth diverges from that cast on. The corpus went 62 -> 68 records
  (the six `d1_*` demos are new); the 9 re-stamp rewrote `sim_version` across
  all 62 old records with 56 replaying byte-identical, and seven bot logs
  (`canary_fanatic_s1`, `canary_magpie_s2`, `det_deeproot_s3`,
  `det_deeproot_s11`, `det_deeproot_s42`, `det_magpie_s3`,
  `det_optimizer_s42`) were re-recorded on their personas — the personas read
  costs, damage and clone() outcomes from the sim, so two of those seven
  diverged even though their stale action lists still replayed legally.
  `blockb_quota_reclamp_wash` is the one hand-authored record the bump moved:
  its water_jet is cast from the growth the cleanse left, so it now surges —
  same quota outcome, new hash. Bump 8 was the graft pricing pass — every
  `Content.GRAFTS` row carries a `price`
  and `Game.shop_cost(item, id)` charges it, so a log that bought a graft at the
  old flat 4 now finds that buy illegal and diverges from there, and
  `snapshot().shop` gained `graft_prices`. The 8 re-stamp rewrote `sim_version`
  across all 60 old records — 38 with no hash diff, 18 hash-only — and four bot
  logs whose actions no longer replay (`canary_fanatic_s1`, `canary_magpie_s2`,
  `det_magpie_s42`, `det_optimizer_s42`) were re-recorded on their personas;
  `c6_graft_price` and `c6_solar_core_price` are the two new demos. Derived
  snapshot keys never enter `state_hash()`: it hashes a view of the snapshot
  whose `shop` is the raw stored shop dict, so `graft_prices` (recomputed per
  snapshot from stock, owned grafts and tier) cannot move a hash — the 18
  hash-only bump-8 records were re-stamped back where that was their only
  cause. Adding or removing a derived snapshot key is not a SIM_VERSION bump
  (it is not replay behaviour), only a hash-only `REGEN=1`. Bump 7 was
  Block A — the starting loadout (`Content.LOADOUTS`, config key
  `loadout`) and the `open_pool` mutator. A default-config run was untouched
  (`tender` is `STARTING_KIT` and the pool is unchanged), so the 7 re-stamp
  rewrote only `sim_version` across the corpus with no outcome or hash diff;
  a run recorded with a non-default loadout would replay with a different kit,
  which is what that bump bought. Bump 6 was C4 — the nine package `+` rows (those
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
  (`REGEN=1`) and re-record every bot log the change could have moved — not
  only the ones that stop replaying. Bump 12 is why: a draft pick is an index,
  so a log whose offers changed still replays legally while landing on a
  different ability, and four of the twenty logs were only proved untouched by
  re-recording them and diffing (`det_wanderer_*`, `det_magpie_s11`).
- Human shell (`shell/`): SVG-sprite Godot scene over the sim — see
  `docs/SHELL.md` for controls. `tests/test_shell.gd` smoke-tests it
  headless; `tests/render_frame.gd` renders any game state as a standalone
  SVG screenshot (the agent's way to see the shell). Sprites are hand-written
  SVG strings in `shell/svg_art.gd`. The sim must never depend on the shell.
- Workflow: no PRs; commit on `claude/godot-setup-q6hk6p` and merge/push
  straight to `main`.
