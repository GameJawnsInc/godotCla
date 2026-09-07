# Design: TENDER (working title)

A solarpunk ability-loadout roguelike. Deterministic tactical combat in a random
world; permadeath with an unlockable content pool. Target run length ~30 minutes.

See `CLAUDE.md` for the architecture style guide this design must live within.

## Pitch

You are a **Tender** — a verdant engineer descending into the **Combine**, a
derelict fossil-fuel megafacility whose furnace still burns. Fight its machinery
(drill bots, coal golems, oil sludges, smog wraiths) with living tech: vines,
spores, water, and solar charge. Purify what it poisoned. Shut down the heart.

Theme rule of thumb: eco-tech is the player's toolkit, carbon/oil is the enemy's.
The theme should do mechanical work, not just paint.

## Core loop

1. Enter a floor. Enemies telegraph their next action at all times.
2. Each turn: spend **Charge** (solar energy, N per turn) on movement and
   abilities, in any order and combination. End turn; telegraphed enemy intents
   resolve deterministically.
3. Explore, fight, and **cleanse** corrupted tiles for **Bloom** (run currency)
   — while the floor's **Smog** meter rises.
4. Descend: draft 1-of-3 (new ability or upgrade). Repeat for 7 floors; kill the
   Furnace boss.

## Pillars

- **Random world, deterministic rules.** Layouts, spawns, drops are seeded RNG.
  Damage, effects, and enemy behavior are fixed and readable. Every turn is a
  solvable puzzle; variety comes from the situation.
- **Intent visibility is sacred.** Every enemy always shows what it does next.
  Disruption is allowed to attack the player's *options* (targeting, ability
  slots, resources) but never the *information layer*.
- **Terrain warfare is the combo engine.** Abilities and terrain compose;
  synergies emerge from primitives rather than being scripted.
- **Greed has a shape.** Staying to cleanse earns Bloom and drafts; the Smog
  clock punishes lingering. The central dilemma of every floor.

## Systems

### Turns and Charge

- Player turn grants base 3 Charge (subject to Smog dimming, below).
- Move = 1 Charge per tile; abilities cost their printed Charge.
- Any number of actions per turn while Charge remains; then intents resolve.
- Unspent Charge **banks** across turns, capped at 6 (2× base regen). Smog
  dimming reduces regen, never the bank. Banking rewards setup turns without
  the pressure of use-it-or-lose-it conversion.
- Step model per style guide §3: `step()` = "advance until the player must
  decide again." Reaction-style passives and multi-action turns are in scope.

### Smog (the clock)

- Per-floor meter that rises each turn (curve tunable per floor/biome).
- Thresholds (all telegraphed in advance):
  - Reinforcement spawns at marked vents.
  - Heavy smog dims solar regen (3 → 2 → 1 Charge per turn).
- Deterministic: same seed and actions → same smog events.

### Terrain

- Enemy terrain: **oil slick** (flammable, spreads slowly, slows), **sludge**
  (damages on entry), **smoke** (blocks targeting through it; never hides
  intents).
- Player terrain: **growth** (planted by abilities; slow heal while standing on
  it; some abilities require or empower on growth).
- Neutral: **fire** (ignited oil; damages everyone; burns out), water, rubble,
  destructible machinery.
- **Ash** — what a fire leaves when its ttl runs out. Still corruption, so it
  counts against the floor's green quota and cleansing it pays Bloom like any
  other corrupt tile, but it never shields the Furnace core, never catches
  fire again, and mapgen never places it: ash only exists where something was
  set alight. Water washes it away and convert-radius abilities turn it into
  growth, exactly as they do oil and goo. Burning a slick therefore trades a
  cleanup job for a different cleanup job instead of erasing it.
- **Pending corruption** — a fire counts as the ash it will leave. For the
  three *counting* questions — the floor's green quota, whether a room is
  fully tended, and whether the floor is restored — a burning tile is already
  corruption, so lighting a slick never discounts the quota, a room whose last
  corrupt tile is on fire waits for the ash before it blooms, and the floor is
  not restored until the burn is cleaned up. Everything else still asks the
  plain question: fire is not cleansable while it burns, does not shield the
  core, and washing it away is a real removal that does shrink the quota.
  Burning is a delay, not a shortcut.
- Cleansing corrupted tiles (via abilities) yields **Bloom**.
- Terrain is **data, not code**: `Content.TERRAIN` holds one row per kind
  (corruption, shields_core, flammable, washable, bloom yield, ttl/decays,
  entry and per-turn damage, blocks, blocks_beam, heal, burns_to) and the sim
  reads it through `Content.terrain(kind, key, default)`. Terrain *reactions*
  are data too: `Content.REACTIONS` rows (fire spreads into oil, fire burns
  out; damp, roots-burn and smoke-smother present but disabled) are consumed
  by one `_terrain_react()` in the environment phase. Enemy statuses live in
  `Content.STATUSES` (stack rule, which intents the status blocks, the event a
  blocked intent emits, per-turn tick damage, an optional re-application
  cooldown). Adding a kind, a reaction or a status means adding a row.
- Status rows in play: **root** blocks `move`, `advance` *and* `drag` — a
  rooted enemy cannot walk, cannot close, and cannot haul the player around —
  and carries a stagger-style cooldown of 2 turns, so a snare cannot be
  chain-cast on the same enemy; a refused re-application emits `resisted`.
  **Spore** stacks by *addition* up to a cap of 6 turns, so re-dosing a
  target deepens the poison instead of merely refreshing it. **Stun** does
  neither. Massive enemies (every boss) are immune to all three.

### Abilities

- Data-driven recipes over effect primitives: damage, push, pull, dash, swap,
  shield, apply_status, create_terrain, convert_terrain, summon, drain/grant
  charge. Targeting shapes: melee, line, cone, radius, blink, growth-network.
- Primitives compose through **riders**, four optional keys on any effect dict
  (evaluated only by `Game._rider_if` / `_rider_per` / `_bonus_dmg`): `if` is a
  closed predicate set that gates the effect (`target_on`, `target_adjacent`,
  `self_on`, `dim`, `casts_this_turn_min`, and inside a `then` the parent's
  `outcome` / `outcome_crossed`); `per` scales a number with a board count
  (`growth_adjacent_target`, `fire_within_self`, `oil_in_line`,
  `enemies_adjacent_target`, capped); `bonus` adds damage per affected enemy
  when that enemy's tile satisfies its predicates; `then` runs sub-effects once
  when the parent actually did something, never nested. An ability row may also
  carry a `surge` dict — what standing on growth buys that cast (below).
  Every effect returns an outcome — hit / ignited / pushed / collided /
  converted / planted / washed / statused, the enemies affected, the terrain they crossed
  — which is what riders read, so "lance the oil the enemy stands on, then the
  flare hits harder" is a data row rather than a special case in code. Riders
  emit a `rider` event so the harness can measure how often combos fire.
- **Ten rows carry a rider today** (the rest are plain recipes). Two base
  rows scale with the board: **Grow Spike** deals 3 and +1 for one adjacent
  growth tile, **Sun Flare** deals 1 in a radius, ignites oil and adds +1 to
  anything standing in fire. Five `+` forms - offered only once the base is
  owned, so the base pool's balance is untouched - carry the sharper versions:
  **Grow Spike+** takes the same count to two stacks at range 4 (3 to 5),
  **Sun Flare+** flashes for 2 with the same fire bonus, **Water Jet+** roots
  an enemy that was actually shoved *and* then hit something, **Vine Whip+**
  stuns an enemy dragged across a burning tile, and **Seed Bomb+** roots
  whoever is standing on the growth it just planted. Four combos fall out of
  them, and each is a charge budget as much as a board state: *seed on head*
  (bomb an enemy's own tile, then spike it for 5 - 2 + 1 = 3 charge, one turn),
  *light then flare* (lance the oil line an enemy stands on, then flare it for
  3 - 2 + 2 = 4, so it needs a surge or a capsule), *drag through embers*
  (whip an enemy across fire: 3 + burn + stun for 1 charge), and *pin* (a jet
  collision roots, so the lance line stays open next turn - 1 + 2 = 3).
  Three more riders live on the package `+` forms below.
- **Surge: the tile you stand on is ammunition.** One rule, one place — a cast
  *surges* when the tender stands on growth and the row's `surge` dict carries
  something that applies to it: a `cost` delta that actually lowers a cost-2+
  cast, or any stat delta. A surged cast eats the growth tile underfoot (event
  `verdant`). The default dict is `{cost: -1}`, so most rows behave exactly as
  they always did: a cost-2+ cast from growth is a charge cheaper, a cost-1
  cast leaves the tile alone. Seven rows now spend that same tile on shape
  instead: **Grow Spike** and **Grow Spike+** `{dmg: 1}` (3 → 4 *before* the
  growth-adjacent rider, so a spike from your own garden beside the enemy's
  lands for 5), **Water Jet** and **Water Jet+** `{push: 1, collision_dmg: 1}`
  (shoves a tile further and slams a point harder — a jet that could not reach
  the wall now can), **Sun Flare** and **Sun Flare+** `{cost: -1, radius: 1}`
  (the discount they always had, plus reach 3) and **Seed Bomb+**
  `{radius: 1}` (a 13-tile diamond instead of the plus). Stat keys are int
  deltas — `dmg`, `push`, `collision_dmg`, `radius`, `dist`, `turns`, `ttl` —
  added to the matching key of every effect of that cast that carries it,
  before the riders scale it; the cast emits a `surge` event so the harness
  counts them. The point is the tension: growth heals you while you stand on
  it, and every surge trades that heal for a sharper cast.
- **Spore Trail.** **Mycelium Dash+** leaves growth where you stood — the
  `plant_origin` op writes growth on the departure tile once the tender is
  gone, if that tile is bare floor with nothing standing on it. The mobility
  slot lays its own network as it travels: the tile you left is a tile you can
  dash back to, spike from, or surge off, so a dash is a setup rather than only
  an escape (and a dash that plants counts as an effective cast in the run
  summary).
- Loadout: 4 ability slots + 1 mobility slot. Drafting while full = drop one.
- Draft cadence: 1-of-3 at each descent; shrines/shops mid-floor spend Bloom.
- Upgrades appear as draft options (e.g. cost reduction, bigger shape).
- Starting pool: **Horticulture** core set (~12 abilities). Examples:
  - Solar Lance — line damage, stronger in clear smog.
  - Seed Bomb — radius, creates growth.
  - Vine Whip — pull enemy 2 tiles.
  - Root Wall — create blocking terrain, 2-turn life.
  - Water Jet — push + washes oil/extinguishes fire.
  - Mycelium Dash (mobility) — teleport between growth tiles (its `+` form
    leaves growth behind: Spore Trail).

### Enemies

- All enemies telegraph. Disruptors attack options, not information:
  - **Oil Sludge** — splits when struck (kill method is the puzzle).
  - **Coal Golem** — telegraphed death-burst of smoke.
  - **Leech Drone** — announced Charge drain.
  - **Tar Spitter** — telegraphs gumming up a specific ability slot; cleansing
    your own kit costs turn economy.
  - **Extractor Engine** — visible 3-turn summon cycle until destroyed.
- Enemy content is data (stats, intents, spawn tables) per style guide §6.

### Run structure (~30 min)

- 7 floors, 3 biomes: Strip Mine (1–2, teaching), Refinery (3–5, combos
  expected), Furnace Approach + Furnace boss (6–7).
- Floors are compact tactical spaces: connected rooms, choke points, hazard
  tiles, destructibles. Procgen invariants are pluggable per biome.

### The Furnace (final boss)

Multi-phase intents and arena terrain are the two balance angles; each phase
tests a different build muscle so no single draft strategy trivializes it.

- **Phase 1 — Intake.** Drill limbs telegraph line/row slams; floor vents flood
  rows with oil on a visible cycle. Tests mobility and positioning.
- **Phase 2 — Combustion.** The Furnace ignites standing oil and spawns coal
  golems at marked ports; smog vents accelerate. Tests terrain control — wash,
  block, or pre-burn the oil before it becomes a firestorm.
- **Phase 3 — Meltdown.** The core is exposed but only damageable while its
  cooling vents are overgrown/cleansed. Tests the cleansing toolkit and burst
  under a hard clock.
- All phase transitions and cycles are telegraphed like any other intent.

### Shops and Grafts

- Shrines are Bloom stores, one per floor (the Furnace floor has none, and the
  Boarded mutator boards the shop for the whole run). Stock is fixed in shape:
  a **heal**, **one ability** drawn from the draft pool (never one already in
  the kit, in either its base or `+` form), **two Grafts of which you buy
  one** (the other is discarded), **one base item**, the **press** (upcycle a
  held item to its `+` form) and the **forge** (scrap a kit ability to upgrade
  another, at most once per floor). Every price runs through
  `Content.SHOP_COSTS`, so the Gouging Prices tier marks the whole sheet up.
- With a full kit the shrine's ability card is simply not buyable: that shop
  slot goes dead once you are kitted out (accepted), and the forge is the only
  way to free a kit slot - it may never scrap the mobility ability, so a run
  can always still move. A draft reroll is not in the game yet.
- `+` items exist only through the press: the shrine and supply pods stock base
  items only, so item upgrades are a spend, never a drop.
- **Grafts** are the relic analog: passive run-long modifiers, and they are
  **data, not code**. Every `Content.GRAFTS` row is `{name, desc, tags, price}`
  plus exactly one of three shapes, and the sim reads the shape rather than the
  id:
  - `stat: {key: int}` — summed over everything you hold. Keys are a closed
    set: `bank_cap`, `shield_cap`, `regen`, `regen_on_growth`, `growth_heal`,
    `cleanse_bloom` (`regen_on_growth` pays only on the turns you begin
    standing on growth; no shipped row uses it — it exists so a conditional
    alternative to Solar Core can be measured).
  - `mod: {key: value}` — a rule switch the sim looks up where the rule lives
    (`floor_start_shield`, `oil_cast_discount`).
  - `hooks: [{on, effects, cap_per_turn?, if?}]` — rows the hook dispatcher
    runs when something happens. The seven hook kinds are `ignite`,
    `staggered`, `cleanse`, `growth_planted`, `kill`, `shield_break` and
    `collision`; effects are the ordinary effect grammar aimed at the tile the
    event happened on, plus three positional ops (`damage_at`, `status_at`,
    `terrain_at`). Nesting and per-step work are capped so a hook chain can
    never run away, and `cap_per_turn` bounds a single graft's firing rate.
  Adding a graft means adding a row. Nothing in the shop, the bots, the tests
  or the shell learns its name.
- The ten live rows: **Deep Cells** (+2 bank cap), **Verdant Pulse** (growth
  heals +1), **Thick Bark** (+2 shield cap), **Bloom Surge** (cleansing yields
  +1 bloom), **Solar Core** (+1 charge regen), **Carapace** (start each floor
  with 2 shield), **Ember Sap** (whoever stands on a tile as it catches fire
  takes 1, three times a turn), **Undertow** (staggered enemies are also rooted
  a turn), **Compost** (a kill leaves growth where the enemy fell) and **Oil
  Tithe** (the first cast aimed at oil each turn costs 1 less, never below 1).
  Kit stays 4+1; Grafts are where long-tail build identity accumulates.
- **Each graft carries its own price** (the row's `price`, in Bloom), and each
  graft you already own still raises the price of the next one on top of that.
  A shrine's two offers are therefore usually priced apart, and the card shows
  what each one costs. The prices come from the measured tables, not from
  flavour: Solar Core is 8 because it is the one row that moves win rate on
  its own, Compost 6, Ember Sap and Oil Tithe 5, Undertow 4, and the five
  stat/mod rows that sit inside noise are 3 so they are ever worth taking
  against a lever. **The lever is priced, not nerfed** — Solar Core still does
  exactly what it did, it just costs about a floor's worth of Bloom — and
  whether the row should instead become conditional is an open call for the
  project owner, measured but not taken (see `docs/BALANCE.md`, the
  alternative-probe table).
- Rule grafts are deliberately kept off the stall surface: a hook may not grant
  shield, healing, thorns or cleanse credit, because those are the loops that
  let a run stand still and win. Damage, control and economy only.
- The combos the rule grafts are for: **Ember Sap + water_jet + lance** (shove
  an enemy onto oil and lance the line — ignite 1, burn tick 1, lance 2, four
  damage for three charge); **Undertow + a wide shove** (a whole staggered
  group is rooted for a turn, which buys two clean lance lanes next turn); and
  **Compost + grow_spike** (every kill leaves a growth tile, so the next enemy
  is already standing next to growth) — a growth engine for a kit that never
  drafted the gardener's tools.
- Grafts enter the combo-sweep harness the same as abilities, and can be
  pre-installed for a sweep via the run config (`tests/sweep_grafts.gd`).

### Meta-progression

- Permadeath; no permanent power. Milestones unlock **tech packages** of
  abilities into the draft pool:
  - **Mycology** — spores, tunneling, growth-network tricks.
  - **Hydraulics** — water, steam, washing/pushing.
  - **Aeolian** — wind, repositioning, smoke-clearing.
- Every package ability has its own `+` form, so a package deepens as well as
  widens: **Spore Cloud+** clouds a radius of 3 (two casts fill the spore
  stack cap exactly), **Fungal Ring+** roots whoever is standing where the ring
  sprouts, **Burrow+** tunnels 4, **Tide+** shoves 3 for 2 on impact and roots
  what it slams, **Steam Vent+** holds its smoke 5 turns, **Geyser+** erupts for
  2 and adds 1 to anything standing in fire, **Gust+** blows a line of 4,
  **Updraft+** rides 4, and **Clear Air+** scrubs a radius of 4 and shoves 2.
  Like every `+`, they appear only once the base is held, so adding a package
  never changes the base pool's balance.
- Every pool addition must pass a harness combo-sweep before shipping. Judge a
  package by a persona that commits to its archetype (Tidecaller, Skyrunner,
  Sporewright): a generalist bot drafts package abilities and then never casts
  them, so a flat generalist table means "no dilution", not "no power".
- The career profile keeps a **50-run history of whole runs** — the kit and
  grafts held at the end, bloom, turns, death cause, seed, tier, mutators and
  packages — plus a cumulative count of *effective* casts per ability (a cast
  that actually did something, so a milestone cannot be farmed by casting into
  empty air). Milestones read that history, so unlocks can ask for a **build**
  and not just a depth: win holding a named ability, win holding none of a
  named ability, land N of a cast, win with N grafts. Daily runs are scored
  into their own best-per-seed table and never touch the career.

### Run-start choices

Three picks open a run, on top of the difficulty tier: a **loadout**, at most
**one tech package**, and at most one **mutator**. All three are data the
career unlocks, and all three are visible on the status line while the run is
being played.

- **Loadouts are the starting kit as data.** Six rows: **Tender** (the starter
  — Solar Lance, Seed Bomb, Mycelium Dash), **Tidewarden** (Water Jet shoves in
  place of the lance), **Flarekeeper** (Sun Flare lights the oil),
  **Spiker** (Grow Spike pays off growth), **Lasher** (Vine Whip drags) and
  **Skyrunner** (Gust, Seed Bomb, Updraft — wind positioning, no lance and no
  dash, the one row that needs a package unlocked). Every row keeps **Seed
  Bomb**, the boss-gate key, and exactly **one mobility ability**, so no
  loadout can strand a run; the ids a persona may never drop or scrap travel
  with the row instead of living in bot code.
- **Each loadout is earned by playing the thing it hands you**: reach the
  Refinery Gate for Tidewarden, the Cracking Yard for Flarekeeper, land 30 Grow
  Spikes for Spiker, win a run holding Vine Whip for Lasher, shut down the
  Furnace for Skyrunner.
- **A package is a run-scoped commitment, not a permanent widening.** A run
  drafts from the base pool plus at most one package — 14 ids or 17, never 23 —
  so unlocking the third package deepens the choice instead of diluting every
  draft. The old everything-at-once pool survives as a deliberate choice, the
  **Open Pool** mutator, unlocked by the first win.
- **The daily challenge derives all three from the date seed alone**, over
  frozen lists, so growing a content table never moves an earlier date and
  everyone plays the same run. Daily results are scored into their own
  best-per-seed table and never touch the career.

A loadout is a starting position, not a difficulty setting: the harness gates
each one on being bot-winnable, and the spread between them is a balance
number in `docs/BALANCE.md`, not a design promise.

### Post-win

Both replay hooks, both implemented as data over the same sim:

- **Difficulty tiers** (Ascension-style): numbered, each adding a stacking
  deterministic tweak (thicker smog curve, richer elites, pricier shops).
  Every tier must stay bot-winnable — the harness validates each one.
- **Run modifiers** (mutators): optional, chosen at run start, unlock-gated
  (e.g. "no growth terrain", "double oil", "kit of 3"). Free-form spice on
  top of the tier ladder. Each one is a row of data — a name, a description and
  a small config the sim reads through a single lookup — so a new modifier is a
  table entry, not a branch. Three of them rewrite the draft or the kit rather
  than a stat: **Lance Embargo** takes Solar Lance out of the starting kit, the
  draft pool and the shrine, so the run opens on two abilities and has to find
  its own damage; **Wide Draft** deals four offers instead of three;
  **Upgrades Only** never offers a new ability at all, only the `+` forms of
  what you already hold, so the kit stops widening and starts deepening.

## Playtest personas (style guide §5)

- **Wanderer** (random-walk) — crash and softlock finder.
- **Sprout** (cautious noob) — should die to Smog greed and disruptors
  sometimes; measures teaching-curve fairness.
- **Optimizer** (minmaxer) — searches for best lines; measures true difficulty
  ceiling and finds degenerate combos.
- **Deeproot Plan** (search that plans one setup ahead) — scores what the kit
  *could* do next turn and follows a setup with its payoff inside the same
  turn; the instrument that measures how much combo depth the content holds.
- Key metrics: win rate per persona, death cause distribution, floor-of-death,
  Bloom collected vs. smog deaths, per-ability draft-to-win correlation.

## Open questions

- Furnace numeric tuning (phase HP, cycle lengths) — expect the harness to
  drive this once the sim exists.
- Graft pool size at launch vs. unlock-gated.
- Whether smoke should be pushable by Aeolian abilities from day one or arrive
  with the package.
