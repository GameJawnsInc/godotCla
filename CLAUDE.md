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
    `DRAFT_SLOTS`/`AFFINITY_IGNORED_TAGS` shapes, the D5 `RESONANCES` rows and
    their reach, plus a self-test that feeds the lint deliberately bad rows
    (including the mobility-tagged and need-1 resonances) both in the whole
    table AND alone, so no fixture's own rule can be shadowed by the
    one-row-per-tag rule, and the planned rider rows)
  - `godot --headless --path . --script tests/test_grammar.gd` — effect grammar
    behaviour: rider evaluation, returned outcomes, the data tables driven
    through `Game._apply_effect` on hand-built states, the D4 draft slots
    (affinity/upgrade/wild candidates, the one-draw-per-slot count, focus) and
    the D5 tag counts, active set, the shipped hook row, the drop-below-need
    toggle and the `stat` shape through an injected `_ResProbe` row (no
    shipped row carries `stat` or `mod`, so the probe plus its
    a-stat-row-shipped tripwire is that shape's only behaviour coverage)
  - `godot --headless --path . --script tests/test_economy.gd` — shrine economy
    and quota: config-independent main rng, shop stock filters, graft/ability/
    press/forge purchase rules, the shrine reroll (legality, price escalation,
    the cap, offer exclusion, closed slots, rng-state independence), quota
    re-clamp, damage attribution, and the D5 resonances (no main-rng draw, the
    graft + resonance stat sum, a graft mod shadowing a resonance mod)
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
    (the shell reads the sim, so a sim change can break it), plus the two
    player-facing gates: `_check_card_text` holds every shipped description
    to a readable size on the tightest shrine card, and `_check_cleanse_hint`
    holds CLEANSE's refusal to the truth
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
  other two), `measure_bosses` and `sweep_resonance` (whose FREE mode takes
  the three; its locked mode names its own kit); `verify_kit`,
  `measure_fanatic`, `draft_oracle` and `sweep_packages` still build their
  configs inline and ignore the three:
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
  - `tests/sweep_resonance.gd` (D5) — per `Content.RESONANCES` row, a kit that
    MEETS the row's threshold built from the draft pool plus tag-carrying
    grafts, run locked beside the free-drafting config on the same seeds:
    exposure (runs met, first floor, share of turns, breaks), firings and
    LANDINGS, the last matched against the row's own effects because
    `hook_uses` is charged BEFORE they run. Generic over the table with no
    per-row special-casing. It GATES on the D5 design phase's pre-registered
    cut line — a `hooks` row must fire at least once a run on its own kit
    (`cinder_grip` 9.53, the cut `follow_through` 0.73); `RESONANCE_GATE=0`
    disables, `RESONANCE_BOT` / `RESONANCE_SEEDS` / `RESONANCE_SEED_FROM` /
    `RESONANCE_ROWS=a,b` / `RESONANCE_MODE=both|locked|free` narrow a run.
    Caveat on locked mode, recorded in BALANCE.md and deliberately not
    changed: `_locked_config` appends tag-carrying grafts in `Content.GRAFTS`
    TABLE ORDER, which for fire picks `ember_sap` — whose own `ignite` hook
    kills the body that `cinder_grip` would root, and which is scanned first.
    Swapping it for `oil_tithe` on the same kit and seeds reads 57 landings
    against 24, so the runner's "best case" is measured with the row's
    worst-case partner
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
  are design intent kept as data, and the two of them the review raised as
  design tensions are SETTLED, not open - `roots_burn` (fire x growth) is off
  on THEME, because the tender restores a poisoned floor and growth IS the
  restoration, so a balance argument is not grounds to re-open it, while
  `smoke_smother` (smoke x fire) is off only because nothing needs it and
  could be revived by a mechanic that did; `docs/PROGRESSION_REVIEW.md` §6.6) and `Content.STATUSES` (stack rule, blocked
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
  into the combo rate. Live rider rows (C2, added at bump 4; the `+`
  rows were renamed to their D6 A variants at bump 13): `grow_spike`
  and `grow_spike+impale` carry `per` (growth_adjacent_target over a base 3,
  cap 1 and cap 2), `sun_flare` and `sun_flare+corona` a `bonus` (+1 on an
  enemy standing in fire, which their own ignite pass can light under it), and
  `seed_bomb+tangle`, `vine_whip+lash` and `water_jet+pin` a `then` (root on
  freshly planted tiles, stun when the drag crossed fire, root when the shove
  both pushed and collided) —
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
  rejects `surge` on an effect dict. Seven rows carry one today (D6
  A-variant keys since bump 13): `grow_spike` and `grow_spike+impale`
  `{dmg: 1}`, `water_jet` and
  `water_jet+pin` `{push: 1, collision_dmg: 1}`, `sun_flare` and
  `sun_flare+corona` `{cost: -1, radius: 1}` (the discount they always had,
  plus reach) and `seed_bomb+tangle` `{radius: 1}` (base `seed_bomb` keeps the
  default). Three D6 B siblings carry a surge dict of their own —
  `water_jet+sluice` `{push: 1, collision_dmg: 1}`, `sun_flare+smoulder`
  `{cost: -1, radius: 1}` and `grow_spike+throng` `{dmg: 1}`, each the same
  dict as its A sibling, so the surge is never part of a fork. Separately,
  four cost-2 B rows (`seed_bomb+reclaim`, `root_wall+cage`,
  `pollen_burst+drift`, `moss_filter+prism`) carry NO surge dict and so take
  the `Content.SURGE_DEFAULT` `{cost: -1}`: cast from growth they cost 1 —
  the same as their cost-1 A sibling — and eat the tile underfoot. Their
  "costs twice as much" fork notes are the price OFF growth.
  (`solar_lance+pierce` is default-surge-eligible too, but its A sibling is
  cost 2 as well, so the discount is not part of that fork.)
  Two grammar changes ride along: `grow_radius` now READS its `radius` key
  (review defect 16) — radius 1 is the plus it always drew, radius 2 the
  13-tile diamond a surged `seed_bomb+tangle` reaches — and the new
  positional op `plant_origin {kind}` (kind closed to `Content.TERRAIN`) writes that kind on
  `ctx.origin` when the tile the cast left is floor, terrain-free and empty of
  enemies, counting as planted so `status_target who: on_planted`, the
  `growth_planted` hook and `effective_uses` all see it. `mycelium_dash+trail` is
  Spore Trail: `[{op: teleport}, {op: plant_origin, kind: growth}]`, cost and
  range unchanged. Terrain insertion order is hash-visible (`terrain.keys()`
  feeds the growth target list and `state_hash` hashes `str(snapshot())`), so
  `grow_radius` keeps its pre-D1 target-then-DIRS order for the plus and only
  the outer rings iterate dy-then-dx — a radius-1 cast is byte-identical to
  before. `tests/regressions/d1_*.json` demos six cases: the three stat
  surges, the `seed_bomb+tangle` diamond, Spore Trail, and a cost-1 default-surge
  ability leaving the tile standing.
- Grafts are data (`docs/PROGRESSION_REVIEW.md` §6.3 C3): every `Content.GRAFTS`
  row is `{name, desc, tags, price}` (tags a `Content.TAGS` subset, `price` an
  int >= 1 — both lint-enforced) plus exactly one of
  `stat: {key: int}` — summed by `Game._passive_stat(key)` over the held grafts
  and then the active resonances (D5 renamed `_graft_stat`),
  keys `bank_cap`, `shield_cap`, `regen`, `regen_on_growth`, `growth_heal`,
  `cleanse_bloom` (`regen_on_growth` is added to regen only on the turns the
  tender begins standing on growth; NOTHING uses it — no graft row, and no
  resonance since `deep_loam` was cut, so it is a live, lint-legal ORPHAN key
  with a `_begin_player_turn` read and no consumer, kept deliberately:
  `docs/BALANCE.md` 2026-09-08 records that a growth-conditional charge bonus
  is a greed subsidy at every threshold, so the key waits for a payoff shape
  that pays on an ACT rather than on a turn spent in place);
  `mod: {key: value}` — first held value via `Game._passive_mod(key, default)`
  (grafts in held order, then the active resonances in table order, so a graft
  mod shadows a resonance mod), keys `floor_start_shield`, `oil_cast_discount`;
  or `hooks: [rows]`. There is
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
  kit slots 0..n (an `ABILITIES` row may carry `hooks`; none does yet), then
  `player.grafts` in held order, then (D5) the active resonances in
  `Content.RESONANCES` key order, each with the resonance id as its source id.
  A row is `{on, effects, cap_per_turn?, if?}`;
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
  documents; since D5 the same `_lint_hook_row` walks the resonance hook rows,
  so the forbidden-op list covers all three sources.
  `tests/regressions/c3_*.json` demos one rule each.
- Package `+` rows (C4): every `Content.PACKAGES` ability now has a `<id>+`
  row — `spore_cloud+`, `fungal_ring+`, `burrow+`, `tide+`, `steam_vent+`,
  `geyser+`, `gust+`, `updraft+`, `clear_air+`. The draft offers `<id>+` only
  when the base is held and the shrine forge only upcycles a held base, so
  `Content.DRAFT_POOL` and base-pool balance are untouched. Convention: costs
  never move, numeric bumps only (range, dist, radius, dmg, ttl; a row may bump
  more than one) and at most one C1 rider, only where the vocabulary states the base identity
  (`grow_radius` ignores its `radius` key, so `fungal_ring+` takes the
  `seed_bomb+tangle` on-planted root instead of a wider ring).
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
  `upgrade_or_affinity` arm reads `deepenings` — so the `mycelium_dash`
  variants and `burrow+` are off that slot while `updraft+`
  (`["wind", "mobility"]`) stays,
  the UNIVERSE is untouched (a wild slot still offers the dash upgrade, and
  the shrine forge, which reads the kit, still upcycles it), and under
  `draft_upgrades_only` the `+` list IS the universe so that arm keeps using
  `upgrades` — filtering it could empty a draft that today has offers. It is
  tags, never `role`. Unfiltered, `mycelium_dash+` (as the id then was) was
  offered 158 times in
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
  a `mycelium_dash` variant, the forge still upcycling it, and the draw
  count held at 3 for kits whose filtered and unfiltered lists differ by 0, 1 and 2 entries)
  and the draw-count assert (rng.state after a roll equal across
  kits with different candidate counts, and equal to a fresh generator
  advanced `count` times) and the starved cases (a 3-ability kit under
  `upgrades_only` buying no focus card, a mobility-only kit whose focus slot
  falls back to wild and is still reported `focus`). A role is CODE, not data:
  `Game._draw_draft_offers` is the only site that implements one (a match on
  the role strings with `wild` as the catch-all), so adding an entry to
  `DRAFT_SLOT_ROLES` without an arm there silently rolls it as wild —
  `sim/content.gd` says so beside the table. Demos (re-pinned at bump 13, when
  the D6 fork moved every offer list):
  `tests/regressions/d4_affinity_slot.json`,
  `d4_upgrade_slot.json` and `d4_wide_draft_slots.json` are one seed and one
  board through three configs (the flarekeeper's affinity slot deals a sun
  base, the tidewarden's deals a displace base and its slot 1 a held variant,
  and the wide draft appends a fourth wild offer to the flarekeeper's three
  unchanged ones; since D6 the wild slot of the first two deals the OTHER
  sibling of the base the upgrade slot just dealt, which is the universe rule
  in one roll), and `d4_focus_skip.json` skips a draft and descends again
  for the four-offer roll whose last slot is `focus` — its two rolls also pin
  the D6 parity rule, `solar_lance+noon` entering floor 2 and
  `seed_bomb+reclaim` entering floor 3, and its slot 1 pins the upgrade filter
  (a seed-bomb variant where the unfiltered rule dealt a dash one).
  `d4_starved_slot.json`
  pins the one-draw-per-slot contract in plain mode: a kit and pool that leave
  the affinity slot exactly one candidate, so a draw that skips or shortens
  itself on a one-candidate list shifts the two offers after it (the mutation
  deals `seed_bomb+reclaim` where the wild slot deals `mycelium_dash+scatter`).
  `d4_upgrade_filter.json` (seed 5 -> seed 2 at bump 13) pins both halves of
  the filter on one board — the
  upgrade slot deals the build-defining `seed_bomb+tangle` while the WILD slot
  deals `mycelium_dash+trail` on the same roll; unfiltered, the same seed deals
  `mycelium_dash+trail` from the UPGRADE slot,
  so removing the filter fails it in plain mode. `c4_upgrades_only.json`
  records the deliberate exemption: a mobility variant still appears there
  and in no other slot pin, and since D6 that mutator's candidate list is
  every variant of every held base (six ids for the starting kit, not three).
- Evolve forks (Block D6, `docs/PROGRESSION_REVIEW.md` §6.4, the last Block D
  item): every base-pool `+` ability is TWO named variants, so the forge is a
  choice and the draft is a rotation. **Key scheme.** A variant id is
  `<base>+<word>` (word `^[a-z]+$`, never a second `+`);
  `Content.base_id` already cut at the first `+` and is unchanged. The fifteen
  base abilities fork (`solar_lance+noon`/`+pierce`,
  `seed_bomb+tangle`/`+reclaim`, `vine_whip+lash`/`+rake`,
  `water_jet+pin`/`+sluice`, `mycelium_dash+trail`/`+scatter`,
  `root_wall+bulwark`/`+cage`, `pollen_burst+torpor`/`+drift`,
  `sun_flare+corona`/`+smoulder`, `thorn_shield+plate`/`+chaff`,
  `overgrowth+sprawl`/`+palisade`, `sap_snare+tether`/`+blight`,
  `grow_spike+impale`/`+throng`, `bramble_coat+briar`/`+bristle`,
  `anchor_roots+bedrock`/`+heave`, `moss_filter+sieve`/`+prism`); variant A is
  the pre-D6 row renamed, key and display name only, so the measured balance
  point is preserved and every number this block moves is attributable to B
  alone. The nine package `+` rows and every `Content.ITEMS` `+` row keep their
  single plain `+` id — packages sit behind a one-per-run commitment and the
  item press is a different system. **Helpers.** `Content.is_upgrade(aid)`
  (`base_id(aid) != aid`), `Content.variants_of(base)` (every ABILITIES key
  whose base_id is `base` and which is not `base`, derived by SCANNING the
  table in key order — never a hand-maintained list) and
  `Content.variant_for(base, parity)` (`variants_of` indexed by
  `posmod(parity, size)`). Table order is load-bearing: A must be listed
  before B. For a package ability `variants_of` returns a 1-list and
  `variant_for` is the identity, so package drafting is unchanged.
  **Forge.** The `upcycle_ability` action gained a `variant` index into
  `Content.variants_of(base_id(kit[keep]))` and `legal_actions` lists one
  action per (keep, scrap, variant) triple, so a player at the shrine chooses
  which fork; a MISSING `variant` is index 0 — the A row — so an old stored
  forge action forges what it forged then, and an out-of-range index is
  `{t: "illegal", action: "upcycle_ability"}` and changes nothing.
  **Draft parity.** `_draw_draft_offers`'s `universe` holds BOTH siblings of a
  held base (a wild slot may deal either) while `deepenings` — the
  `upgrade_or_affinity` slot's list — holds exactly ONE per held
  build-defining base, `Content.variant_for(base, _pending_floor)`. That is a
  table read, NOT a draw, so the block does not touch the D4 contract: a roll
  still spends exactly one main-rng draw per slot, and WHICH sibling a slot
  could deal is a function of the floor rather than of a roll. Drafts happen
  on floors 2..7, so with A first a run is dealt A on even floors and B on
  odd and both siblings are draftable inside one run; the sibling a floor
  cannot deal is always buyable at the forge, so no fork is unobtainable.
  Because the universe holds both siblings while `_minus` excludes by exact
  id, one roll can present the fork itself: a wild slot may deal the sibling
  the upgrade slot did not (measured at ~12% of optimizer drafts over seeds
  1..40, e.g. `["moss_filter", "seed_bomb+tangle", "seed_bomb+reclaim"]`).
  That is accepted, not a defect — a card pair IS the fork choice — but it
  narrows such a roll to two effective picks, since taking either sibling
  makes the base a variant and drops the other from `bases` and `upgrades`
  for the rest of the run. Excluding by base_id would move every downstream
  offer list and cost another corpus re-record.
  `tests/regressions/d4_affinity_slot.json` is the pin: its one roll deals
  `sun_flare+corona` from the upgrade slot and `sun_flare+smoulder` from the
  wild one.
  **New vocabulary** (six items, all lint-declared in
  `tests/test_content.gd`): `pierce` (bool key on op `lance` — the beam does
  not stop on the first body, so every enemy on the line is hit and every
  flammable tile behind them lights; walls and `blocks_beam` smoke still end
  the walk), `pull_line` (new op, keys `{dist, dmg}`, target shape `dir`, in
  `BONUS_OPS` — the `pull` body against every enemy on the line, nearest
  first, and unlike `pull` a death mid-line does not end the effect),
  `center` (String key on `aoe_status`, closed to `CENTER_VALUES`
  `["self", "target"]` — the tile the radius is measured from), `ignite_ttl`
  (int key on `aoe_damage` — the ttl written on the fires THAT effect lights,
  threaded through `_ignite(p, by, ttl := -1)` into `_tile_dict`; a fire that
  SPREADS from an overridden tile takes the table ttl, and `SURGE_KEYS` carries
  `ttl` and not `ignite_ttl`, so a surge can never lengthen a burn), and
  `kind` + `ttl` on `convert_radius` (what a convertible corruption tile
  becomes and, for a decaying kind, how long — default `growth` is
  byte-identical to before except that the write now goes through
  `_tile_dict`, so a replaced tile's `bloom` flag rides along; a BLOCKING kind additionally takes
  `grow_wall`'s two guards, `_open(t)` and `t != map["stairs"]`, and a `kind`
  naming a corruption row is a LINT ERROR — no variant may create corruption,
  which would be both a bloom faucet and a green-gate faucet). Five B rows are
  sidegrades of their own base rather than supersets (`root_wall+cage`,
  `sap_snare+blight`, `grow_spike+throng`, `bramble_coat+bristle`,
  `overgrowth+palisade`) — an explicit exemption from the C4 "numeric bumps
  only" convention, written down in `sim/content.gd`.
  **The suffix hazard**, which is the whole risk of this block:
  `"solar_lance+pierce".ends_with("+")` is FALSE, so every
  `ends_with("+")` on an ability id silently changed meaning and every
  `trim_suffix("+")` silently returns the variant id UNCHANGED. Both became
  `Content.is_upgrade(aid)` / `Content.base_id(aid)` across `sim/game.gd` (the
  draft `is_upgrade` flag, the forge legality and its old `kid + "+"`
  construction, `_shop_ability_candidates`' `aid + "+"` — now the helper
  `_kit_holds_base`, which folds BOTH sides: a locked-kit sweep config
  (`{kit: K, pool: K}`, the block's own acceptance measurement) puts VARIANT
  ids in the pool, and folding only the kit side would offer a held variant as
  a draft card `_act_draft` then rejects and let the shrine stock a duplicate
  of it — the draft base filter and the upgrades/deepenings build,
  and `_act_draft`'s upgrade path), `bots/optimizer.gd` and `bots/sprout.gd`
  (`_pref_rank` — an unconverted `trim_suffix` would drop
  every variant off `DRAFT_PREF` and collapse both personas' draft
  preference), `bots/deeproot.gd`, `bots/bot_base.gd` (`_kit_id` folds with
  `Content.base_id` in the BASE class, so a new persona inherits the right
  fold; the two subclass overrides that used to work around it are gone),
  `shell/main.gd` (the
  sprite keys, the `+` badge, the draft card's "(upgrade)" suffix and the
  `ABILITY_DESC` fallback), `meta/profile.gd`, `tests/tally.gd` (whose `_base`
  every per-ability table routes through) and the test suite. The
  `Content.ITEMS` press sites KEEP the plain `"+"` — items are not forked —
  and each carries a one-line comment saying so
  (`sim/game.gd` legal_actions press branch, `_base_item_ids`, `_act_upcycle`;
  `bots/sprout.gd`; `shell/main.gd`; `tests/test_content.gd`;
  `tests/test_economy.gd`). Other load-bearing sites: `run_summary`'s
  `uses_by_base` folds base and ALL variants with `max` (both the draft and
  the forge SEED the chosen variant's count from the base's, so a sum would
  double-count), and `Content.MILESTONES`' `upgrades_only` row now requires
  `won_with ["seed_bomb+tangle"]` — a profile recorded before the rename
  stores `"seed_bomb+"`, which `Profile._migrate_ability_id` maps to that
  base's FIRST variant (derived through `Content.variants_of`, never a rename
  table), so old history keeps satisfying that milestone.
  **Demos** (`tests/regressions/d6_*.json`, nine): `d6_lance_pierce`,
  `d6_rake_pull_line`, `d6_drift_center`, `d6_smoulder_ignite_ttl`,
  `d6_palisade_kind` and `d6_palisade_ttl` are one per new op or key;
  `d6_forge_variant_a` and `d6_forge_variant_b` are the SAME seed, board and
  three actions differing only in the `variant` index, and produce different
  kits (Noon Lance kills the smokestack for 4 and lights nothing past it,
  Piercing Lance deals 2 and lights the oil behind it); `d6_draft_parity`
  descends twice and is dealt `solar_lance+noon` from the upgrade slot
  entering floor 2 and `moss_filter+prism` entering floor 3. Each fails in
  plain (non-strict) mode under a targeted mutation of the rule it pins —
  eleven mutations run and checked: restore the lance `break`; break out of
  the `pull_line` loop after the first enemy, or reverse its walk order;
  force `center` to "self"; ignore `ignite_ttl`; force `convert_radius`
  `kind` to "growth", or drop its stairs guard (which fails the record on an
  illegal move); ignore the convert `ttl`; pin the forge index at 0 or at 1;
  freeze `variant_for` at index 0. The two re-pinned D4 rng/filter demos were
  re-checked the same way (`d4_upgrade_filter` under the dropped
  `_build_defining` filter, `d4_starved_slot` under a `randi_range` draw).
  `blockb_forge_once.json` pins the third forge case — an action with no
  `variant` key at all, which is index 0.
- Resonance (Block D5, `docs/PROGRESSION_REVIEW.md` §6.4, the last roadmap
  item): one resonance per element, over kit and graft tags, through the hook
  and mod layer. D5 adds a passive SOURCE, not a system — no new op, stat key,
  mod key, hook kind, predicate, terrain key or status. `Content.RESONANCES` is
  one row per resonating tag, `{name, desc, tag, need}` plus EXACTLY ONE of
  `stat: {key: int}` / `mod: {key: value}` / `hooks: [rows]` — the same
  three-way choice a `Content.GRAFTS` row makes, read by the same
  `Game._passive_stat` / `_passive_mod` / `_hook` machinery with the ROW ID as
  the source id, so `cap_per_turn`, `hook_uses` and `tests/tally.gd` needed no
  change. ONE row ships, and the roadmap bullet therefore shipped as ONE
  element, not four: `cinder_grip` (fire, need 3, hook on `ignite` ->
  `status_at` root 1, `cap_per_turn` 3 — a machine standing on a tile as it
  catches fire is rooted a turn). Key order is load-bearing (the hook scan
  order after the grafts, and the order of `snapshot().resonances`); rows are
  listed in `Content.TAGS` order, so A-before-B matters the day a second row
  lands. TEN tags ship nothing and `sim/content.gd` records why beside the
  table (mobility is lint-excluded; sun double-pays off the two fire cards;
  water is an ability-side subset of displace; wind and smoke are
  package-locked — wind 2 is met from turn one on the skyrunner kit, the exact
  failure the roadmap bullet deferred this item on; bark's only seat fires
  0.83 times a run and every payoff its vocabulary offers is survivability -
  and since the owner settled §6.6 on 2026-09-08 (no `bark_burst`, the turtle
  stays a designed anti-pattern) that emptiness is settled design rather than
  a gap: a bark payoff needs a NEW shape that is not defence, and none has
  been proposed; control has NO event, nothing fires when a status lands;
  economy is carried by zero abilities) — and for the two tags that were authored a row and then
  lost it, displace and growth, it records the measurement instead of a
  reason. **BOTH cut rows are one dict entry away and their numbers are in
  `docs/BALANCE.md` (2026-09-08).** `follow_through` (displace 2, hook on
  `collision` -> `damage_at` 1, `cap_per_turn` 2) was cut in the design phase
  on its own pre-registered falsifier: 22 hooks over 30 optimizer runs on the
  locked displace kit against a stated cut line of 30, 21 out of sample, and
  only 5 of the 22 landing anything — a collision that kills erases the body
  before the hook runs, and on that kit three quarters of collisions kill. It
  was alive at the ceiling (deeproot 8.8-9.1 hooks a run on the same kit) and
  invisible to the band persona, which is a ceiling-only row, not the build
  identity the block set out to ship; its levers were both dead ends (`need` 2
  is the lint minimum and the row was active in 30/30 of those runs anyway,
  and `cap_per_turn` never binds at 0.73 hooks a run) and displace has nowhere
  else to sit — `collision` is the only hook kind forced movement produces,
  and every closed stat/mod key is survivability, charge or bloom.
  `deep_loam` (growth 3, `stat {regen_on_growth: 1}`) was implemented,
  measured and then cut by the OWNER on the greed canary: magpie on `spiker`,
  300 seeds a setting, against `tests/playtest.gd`'s `MAGPIE_MAX_LOWER` 0.10,
  which trips when the Wilson LOWER bound clears 10% — row absent 38/300 =
  12.7% [9.4, 16.9] pass, need 3 56/300 = 18.7% [14.7, 23.5] FAIL, need 4 (the
  PRE-REGISTERED lever) 48/300 = 16.0% [12.3, 20.6] FAIL, need 5 39/300 =
  13.0% [9.7, 17.3] pass at +0.3 POINTS (one win over the row's absence),
  which is a pass bought by switching the row off. There is no threshold at
  which it both clears the canary and does anything, because its canary cost
  is proportional to its effect: it pays per
  turn BEGUN standing on growth and the greed persona spends about twice the
  share of its turns standing there (magpie 23.6% on tender / 26.7% on spiker
  against optimizer 13.4% / 15.8%), so `need` changes how OFTEN a row is on
  and never WHO it pays. A growth-conditional charge bonus is structurally a
  greed subsidy; growth waits for a key that pays on an ACT, which the closed
  stat/mod set does not contain. One consequence for the tables: NO shipped
  row carries `stat` or `mod`, so both shapes are live-but-unshipped
  vocabulary, exercised by lint fixtures and by injected `_ResProbe` rows in
  `tests/test_grammar.gd` (six checks) and `tests/test_economy.gd` (four) —
  and NO regression record can catch the deletion of `_passive_stat`'s or
  `_passive_mod`'s resonance loop, so `tests/test_grammar.gd` carries a
  tripwire that fails if such a row ever ships without those probes being
  revisited. **The active set is derived.**
  `Game._tag_counts()` counts tags over the held kit and the held grafts — the
  ABILITIES row is read straight with a guarded get, never folded through
  `Content.base_id`, because a variant row carries its base's tags verbatim, so
  a forge or draft UPCYCLE never moves a count and an unknown sweep id counts
  nothing. `Game._resonances()` returns the active ids in table order (a row is
  active while `_tag_counts()[row.tag] >= row.need`) and `_resonance_rows()` is
  the `[id, row]` seam its three readers share. Nothing is stored: a draft drop
  or a forge scrap turns a row off between one step and the next with nothing to
  unwind, and only those two can lower a count (grafts are only ever appended).
  `snapshot()` gains a derived `resonances` array for the shell and the bots and
  `state_hash()` ERASES it beside the shop swap, so a resonance can never move a
  hash by itself — the derived-key rule the bump-8 note documents.
  `_graft_stat` / `_graft_mod` became `_passive_stat` / `_passive_mod` in one
  pass (nine call sites): the stat sum is grafts THEN active resonances, the mod
  scan is grafts first, so a graft mod shadows a resonance mod (unobservable on
  shipped data — no resonance carries a `mod` — and pinned in
  `tests/test_economy.gd` through a subclass that injects one).
  **The lint is where the rules live.** `tests/test_content.gd` `_lint_resonances`
  reuses the graft shape checks (exactly one of stat|mod|hooks, the shared
  `PASSIVE_STAT_KEYS` / `PASSIVE_MOD_KEYS`, every hook row through the existing
  `_lint_hook_row` so `HOOK_FORBIDDEN_OPS` covers resonance hooks too) and adds
  four D5 checks: the tag is in `Content.TAGS`, the tag is NOT in
  `Content.AFFINITY_IGNORED_TAGS` (this is how "mobility never counts" is
  enforced — in data, not by a tag literal in `sim/game.gd`), `need` is an int
  >= 2, and at most one row per tag; ids must also be disjoint from the GRAFTS
  and ABILITIES keys, which share the `hook_uses` cap namespace.
  A resonance stat row may also not name a key in
  `RESONANCE_FORBIDDEN_STAT_KEYS` (`cleanse_bloom` today): PASSIVE_STAT_KEYS is
  shared with GRAFTS, where every key is PRICED and declinable, so the keys
  that MAKE the currency are the stat-side twin of `HOOK_FORBIDDEN_OPS` — the
  same key is a 3-bloom purchase as `bloom_surge` and a free permanent bloom
  faucet as a resonance. `_lint_resonance_reach` fails a row ONE RUN cannot
  meet, which is not the same as one the tables cannot: carriers are the
  `Content.DRAFT_POOL` bases plus every graft plus the BEST SINGLE package,
  because Block A made a package a one-per-run commitment — counting the whole
  ABILITIES table would pass a `smoke` row at need 3 (steam_vent is
  hydraulics, gust and clear_air aeolian) that no default run can meet. It
  prints "resonance reach: 1 / 1 rows can be met (fire 4)" — a margin of
  exactly one over `need`, and it is mutator-blind (under `no_lance` the true
  ceiling is 3, so it catches dead data, not thin data). The lint SELF-TEST
  lints every bad row BOTH in the whole table and ALONE, because `Content.TAGS`
  has 11 entries against 23 bad fixtures and the one-row-per-tag rule was
  standing in for six other rules' failures; the two rows whose violation is a
  relationship are declared in `BAD_RESONANCE_PAIR_ONLY`, and the printed line
  carries both numbers ("23 bad rows -> 37 failures (21 rejected alone)").
  Resonance tags deliberately do NOT feed the D4 affinity set — feeding one back
  would make the draft chase a threshold it created. Three demos:
  `tests/regressions/d5_cinder_grip.json` (fire 3 from two kit cards plus
  `oil_tithe`; the lance lights the oil under a coal golem, the hook roots it and
  the golem's next action is a `{t: "rooted"}` in the fire) and the forge pair
  `d5_upcycle_keeps_count.json` / `d5_resonance_off.json`: one seed,
  one board and one action list differing ONLY in the forge's scrap index.
  Its kit is [`solar_lance`, `sun_flare+corona`, `moss_filter`, `seed_bomb`]
  plus `oil_tithe` — fire 3, one of the tags carried by a VARIANT row on
  purpose. Scrapping `seed_bomb` upcycles `moss_filter` and takes no fire tag,
  so the count is still 3 and the lance's ignite roots the drill bot into its
  own fire; scrapping `sun_flare+corona` drops the count to 2, the same lance
  lights the same oil, no hook runs, and the unrooted bot takes the D3
  `avoid: ["fire"]` step off the tile, walks to the tender and bills it 2 —
  that last `{t: "damage", who: "player"}` is the OFF record's positive pin,
  because a record can pin only what happens, never that a hook did not run.
  Each fails in plain (non-strict) mode under a targeted mutation; four were
  run and checked (see the SIM_VERSION 14 note), and a fifth — dropping the
  resonance loop from `_passive_stat` — passes all 96 records, which is the
  coverage the `deep_loam` cut took with it.
  The bots read the active set from `snapshot().resonances` and never re-derive
  the threshold rule: `bots/optimizer.gd` `_drop_breaks_resonance` refuses a
  draft drop that would put a lit row out (netting the incoming card's tags
  against the dropped card's, with a fallback pass so a pick is still made when
  every drop breaks one) and `bots/deeproot_plan.gd` scores an active row at a
  flat `RESONANCE_POINTS`. Neither names a tag or a resonance id. The persona
  change landed in the same bump as the content, so no `deeproot_plan` column
  from before bump 14 is comparable to one after it — and neither is a two-row
  bump-14 column comparable to a one-row one, because the optimizer drop guard
  has one fewer row to protect and its drafting moved; BALANCE.md says so.
- Run summary and effective casts (C4): `Game.effective_uses` (base id -> int)
  counts a cast only when something happened — an effect outcome fired or a
  rider ran — while `player.uses` stays the raw count. It is copied by
  `clone()` and deliberately not in `snapshot()`, so it never churns the state
  hash. Teleport, dash, clear_smoke and self-only ops set no outcome counter
  and so never count as effective; `create_terrain` counts (planted), and
  since D1 so does `plant_origin` — a `mycelium_dash+trail` hop that leaves growth
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
  consumer — `game_config` / `available_loadouts`; `unlocked_grafts` is dead at
  BOTH ends and has been since it was written — no shipped `MILESTONES` row
  carries a `graft` kind, so nothing ever writes the bucket, and `game_config`
  returns no `grafts` key, so nothing reads it; the dispatch arm and one test
  fixture are all that keep it alive, and the sim's `grafts` config key it
  would feed is used only by sweeps); an unknown kind is a `push_error` and is skipped. `load_from` filters every
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
- `Game.SIM_VERSION` in `sim/game.gd` is the single replay-version source (14
  today: Block D5 — one resonance per element. ONE `Content.RESONANCES` row
  ships, `cinder_grip` (fire 3 -> an ignite hook that roots), and it changes
  what happens in PLAY the moment a run's kit and grafts reach fire 3, so a
  stored log diverges at its FIRST IGNITION after that and at nothing else —
  a log that never reaches fire 3 replays byte for byte. Nothing else moved:
  the row adds no main-rng draw (`tests/test_economy.gd`'s ten pinned
  floor-entry rng states are byte-identical to bump 13's), and the derived
  `snapshot().resonances` key is erased from the `state_hash()` view beside
  the shop swap, so a state whose resonances changed nothing hashes exactly as
  it did at 13 — the derived-key rule the bump-8 note documents. (Leaving
  `resonances` in that view is a checked mutation: it fails every record in
  strict mode.) TWO more rows were authored and CUT inside this same
  uncommitted bump, which is why 14 is a one-row version and not a three-row
  one. `follow_through` (displace 2, a collision hook for 1) went in the design
  phase on its own pre-registered falsifier: 22 hooks over 30 optimizer runs on
  the locked displace kit against a stated cut line of 30, 21 out of sample,
  only 5 of the 22 landing anything (a collision that kills erases the body
  before the hook runs). `deep_loam` (growth 3, `stat {regen_on_growth: 1}`)
  went afterwards, by the owner, on the greed canary — 12.7% -> 18.7% at need
  3 and still 16.0% at the PRE-REGISTERED lever of need 4, with need 5 passing
  only by switching the row off. SIM_VERSION deliberately STAYED at 14 across
  that cut: nothing outside the working tree ever ran 14, so it is a change
  inside an uncommitted bump, exactly the precedent the D4 upgrade-slot filter
  set at 12. `sim/content.gd` records both readings beside the table and
  `docs/BALANCE.md` carries the numbers; re-adding either row is one dict entry.
  The cuts are why the corpus is as quiet as it is. Against bump 13 ALL 93
  pre-existing records are STAMP-ONLY — `sim_version` is the single differing
  key in every one, with zero action, outcome, event-pattern or hash diffs —
  and ALL 20 bot logs are byte-identical to their bump-13 recordings,
  re-recorded on their personas to prove it rather than merely replayed (the
  rule is re-record everything the change COULD have moved, not only what
  stops replaying). Three logs had been re-recorded while `deep_loam` existed
  and every one landed back on its bump-13 recording when the row went:
  `det_fanatic_s3` (floor 4 in 161 turns, not 118), `det_magpie_s11` (died
  floor 2 in 93, not floor 3 in 131) and `det_optimizer_s42` (won floor 7 in
  123, not 93). Those three are EXACTLY the records that reach growth 3
  (`det_fanatic_s3` at action 155, `det_magpie_s11` at 101,
  `det_optimizer_s42` at 201, which reaches growth 4), established by probing
  all 96 for the max tag count each run holds — the moved set and the
  mechanism coincide with nothing left over. `c3_undertow` is the same story
  for the other cut: its kit plus `undertow` is displace 2, it moved while
  `follow_through` existed, and it reverted to its bump-13 hash when that row
  went. The corpus went 93 -> 96 with three `d5_*` demos: `d5_cinder_grip`
  (fire 3 from two kit cards plus `oil_tithe`; the lance lights the oil under
  a coal golem and the hook roots it) and the forge pair
  `d5_upcycle_keeps_count` / `d5_resonance_off` — one seed, one board, one
  action list differing only in the forge's scrap index. Four targeted
  mutations fail a record in plain (non-strict) mode: drop the resonance loop
  from `_resonance_rows` (`d5_cinder_grip` and `d5_upcycle_keeps_count`), stop
  `_resonances()` re-checking `need` (`d5_resonance_off`, the only demo that
  pins a row being OFF), make `_tag_counts` skip variant ids
  (`d5_upcycle_keeps_count`, whose kit holds `sun_flare+corona` for exactly
  that reason) and raise `cinder_grip`'s `need` to 4. A FIFTH — dropping the
  resonance loop from `_passive_stat` — passes all 96 records and is the
  coverage the `deep_loam` cut took with it: with no shipped `stat` or `mod`
  row no replay can observe either passive loop, so that rule lives in the
  injected `_ResProbe` rows in `tests/test_grammar.gd` and
  `tests/test_economy.gd` alone.
  Bump 13 was Block D6 — evolve forks. Every base-pool `+` row is gone: the fifteen
  base abilities each fork into two `<base>+<word>` variants, so EVERY
  `solar_lance+`-style id in a stored log names an ability that no longer
  exists and its cast is an unknown ability. Beyond the rename the draft's
  universe holds both siblings of every held base and its upgrade slot lists
  one per base picked by `Content.variant_for(base, _pending_floor)` (a parity
  read, no draw), so every offer list moved; the forge action gained a
  `variant` index (missing = 0, the A row); `draft_offers` is a stored
  snapshot key, so a record that ENDS mid-draft hashes differently on its
  pending offer list alone, even when nothing it actually did moved
  (`blockb_quota_reclamp` and `blockb_quota_reclamp_wash` are that case — both
  end in the draft phase with an EMPTY shop, and `blockb_quota_reclamp`'s
  pending offers went `["solar_lance+", "seed_bomb+", "mycelium_dash+"]` ->
  `["seed_bomb+reclaim", "solar_lance+noon", "seed_bomb+tangle"]`). The shrine
  itself never stocks a variant in a default run: `_shop_ability_candidates`
  draws from `draft_pool`, which holds base ids unless a `pool` config names a
  variant. And
  a default `convert_radius` now writes through `_tile_dict`, so a converted
  enemy-made oil tile carries its `bloom` flag into the growth (hash-visible,
  no rule reads it). The nine package `+` rows and every `Content.ITEMS` `+`
  row are untouched by construction. The corpus went 83 -> 92 with nine
  `d6_*` demos (one per new op or key, the two forge halves and the parity
  draft). Twenty hand-authored records carried 52 base-`+` id occurrences
  (`seed_bomb+` 14, `grow_spike+` 8, `water_jet+` 7, `solar_lance+` 7,
  `sun_flare+` 6, `mycelium_dash+` 6, `vine_whip+` 4; the other eight base
  `+` ids appeared in no record at all), every one renamed to the A variant
  that inherits the behaviour, and eleven of them — `c4_no_lance`,
  `c4_upgrades_only`, `c4_wide_draft`, `c5_loadout_kit_ban`, `c5_open_pool`
  and the six `d4_*` — were re-pinned BY REPLAY because their offer lists
  moved as well (`d4_upgrade_filter` moved from seed 5 to seed 2, where the
  filtered roll still puts the mobility variant in the wild slot so both
  halves of the filter stay visible on one board). `blockb_forge_once` needed
  only the rename and became the missing-`variant` pin: its stored action has
  no `variant` key and still forges `solar_lance+noon`. The 13 re-stamp then
  rewrote `sim_version` across the 63 non-bot records with no outcome diff
  anywhere: 41 stamp-only (version alone), and 22 whose hash also moved — the
  20 whose event patterns carry a renamed id (nine of them needed the rename
  alone, eleven a replay re-pin) plus `blockb_quota_reclamp` and
  `blockb_quota_reclamp_wash`, whose only change is the pending `draft_offers`
  list they end on.
  All 20 bot logs were re-recorded on their personas: 16 came back different
  and four byte-identical — the three `det_wanderer_*` (a wanderer never
  descends, so they are the check that non-drafting play is untouched) and
  `det_magpie_s42`, which DOES draft, twice, and whose BOTH offer lists moved
  (`["sun_flare", "solar_lance+", "overgrowth"]` ->
  `["sun_flare", "solar_lance+noon", "grow_spike"]` entering floor 2 and
  `["sap_snare", "seed_bomb+", "bramble_coat"]` ->
  `["sap_snare", "seed_bomb+reclaim", "solar_lance+pierce"]` entering floor 3
  — the parity rule visible in one log, A on the even floor and B on the odd);
  it replayed and re-recorded unchanged only because its stored pick index 0
  names the affinity offer in both lists, which is the index-pick hazard
  arriving as a coincidence again. `det_fanatic_s3` is this bump's version
  of the index-pick hazard: it replayed with the SAME actions and the SAME
  outcome and only its HASH moved (its final kit names a variant id), which
  is again why a re-record is never limited to the logs that stop replaying.
  Where the fork arrives as difficulty rather than as a stale log:
  `det_optimizer_s3` reaches floor 6 in 107 turns where it took 293,
  `det_sprout_s11` reaches floor 5 in 261 turns where it died on floor 3 in
  84, `det_magpie_s3` falls from floor 5 in 178 turns to floor 2 in 274, and
  `det_deeproot_s42` and `det_optimizer_s42` still win floor 7 but in 107 and
  123 turns (was 98 and 115).
  Bump 12 was Block D4 — the affinity-slotted draft with focus on skip.
  Offer i of a descent draft is rolled by the role `Content.DRAFT_SLOTS[i]` over the same
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
  SVG screenshot and `tests/render_sheet.gd` does the same for a shrine or
  draft SHEET (`SHEET=shop|draft|drop`), which is where the reading happens —
  both are the agent's way to see the shell. Sprites are hand-written
  SVG strings in `shell/svg_art.gd`. The sim must never depend on the shell.
- Every choice card — shrine, draft, drop, forge — is ONE function
  (`shell/main.gd` `_card`) over ONE layout dict (`_card_layout`), and the
  three card lists (`_shop_cards` / `_draft_cards` / `_drop_cards`) are data
  before anything is drawn, so the headless test asserts what a sheet offers
  and `tests/render_sheet.gd` draws the same dict as SVG. A card is: name on
  the head row, charge cost as the ability bar's own gold PIPS (never also
  spelled out), a gold `+` for an upgrade, EITHER a slot badge or a bloom
  price on the right edge (red when the purse cannot meet it), and the
  description across the card's full width WRAPPED onto two lines. The wrap
  is the fix for a real report: a description was one `_txt_fit` line and
  `_fit_size` shrinks to 9px to make a long line fit, so the worst shrine
  card rendered its description at ELEVEN PIXELS on a 1080x2400 phone.
  Wrapping alone was not enough - the strings came down too, longest
  `Content.ABILITY_DESC` row 144 chars -> 81, and the shell's own framing
  with them ("Graft (permanent): " -> "Permanent  ·  ",
  "Consumable: " -> "One use  ·  ", prices out of the name entirely). Both
  halves are gated: `tests/test_shell.gd` `_check_card_text` lays out every
  shipped ability, graft, item and resonance description on the tightest card
  a seven-offer shrine can draw and fails if ANY has to shrink — measured on
  the tree first, per the gate discipline, and all 84 render at the full
  nominal 34px, so the line is a property that holds and not a wish. New
  content that blows the budget fails the suite instead of shipping
  unreadable.
- CLEANSE reaches a tile BESIDE the tender, and only corruption. Its refusal
  is `shell/main.gd` `_cleanse_hint`, because "no corruption beside you" was
  the only answer and it is a LIE in the two cases that happen: standing ON
  the slick, and a slick the tender's own lance set alight (fire is not
  corruption until it burns down to ash, which IS). Both read as a soft lock
  from the player's seat - the tutorial's last cleanse step allows no ability,
  so a player told there is nothing there has nothing left to try. Reported
  by the owner as "wasn't able to clean up the second oil spill".
  `tests/test_shell.gd` `_check_cleanse_hint` drives all three refusals and
  then checks the ash the burning one promises really does open the aim.
- Going back is ONE function (`shell/main.gd` `_back(quit_at_root)`), and it is
  the only place in the shell that implements "back". Android's Back button
  reaches it through `_notification(NOTIFICATION_WM_GO_BACK_REQUEST)` (with
  `application/config/quit_on_go_back=false` in `project.godot`, or the OS
  quits the app before the shell is asked - and note `project.godot` takes `;`
  comments, NOT `#`, which are silently swallowed along with the line after
  them), ESC reaches it from `_key`, and the sheets' own BACK/CLOSE tags
  reach the same tap tags it calls. It goes UP ONE LEVEL per press - tooltip,
  then sheet, then the forge's three taps one at a time, then an aim, then the
  room camera, then the menu - and only the MENU quits, only for Back
  (`quit_at_root`), never for ESC. Aims are cancelled through `_cancel_aim`,
  which the Back button, a D-pad press in a tile aim and a second tap on the
  aiming slot all share: entering an aim costs nothing, so leaving one costs
  nothing. Two rules the same principle bought elsewhere: the tooltip arm of
  `_back` drops `_held` as well as the text, because `_process` re-raises a
  tooltip while the press that made it is still down - clearing only the text
  let the next frame put it back and every later Back be eaten by it in turn,
  so Back did NOTHING while a finger rested on the map; and `_dir_input` has
  an arm for the forge's three modal steps (`up_keep`/`up_scrap`/`up_variant`),
  because the two selection steps draw no sheet, so the D-pad is on screen
  beside the SHRINE SHOP button the context line names and falling through to
  `_move_or_strike` there struck whatever stood next to the tender and dropped
  the forge for a charge and a turn. `tests/test_shell.gd` `_check_back` /
  `_check_aim_cancel` / `_check_modal_dpad` drive the notification itself and
  assert an adjacent enemy's HP, the tender's position, the charge and the turn
  counter are all untouched.
- The tutorial floor (`shell/tutorial.gd` ROOM) puts its second slick OFF the
  golem's row on purpose: the guide teaches lancing down that row two steps
  before it asks for a cleanse, the lance ignites oil, and a burning tile is
  not corruption - so CLEANSE refuses the step's own target until the fire
  burns out. The last cleanse step says "the last of it", never "the last
  oil", because by then the tile can be ash.
- The career profile is written ATOMICALLY (`meta/profile.gd` `save`: temp file,
  then rename) because it is saved exactly when a run ends, and a phone can
  take the app away mid-write; `load_from` accepts only a Dictionary (a JSON
  array used to return null out of it, and the shell cannot boot on a null
  profile) and clamps `unlocked_tier` to `Content.TIERS.size()`, the one unlock
  with no Content table to filter against - the shell bounds it a second time
  in `_max_tier()`, because an out-of-range tier read empties the whole menu.
- Workflow: no PRs; commit on `claude/godot-setup-q6hk6p` and merge/push
  straight to `main`.
