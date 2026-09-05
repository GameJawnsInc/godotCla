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
- Cleansing corrupted tiles (via abilities) yields **Bloom**.

### Abilities

- Data-driven recipes over effect primitives: damage, push, pull, dash, swap,
  shield, apply_status, create_terrain, convert_terrain, summon, drain/grant
  charge. Targeting shapes: melee, line, cone, radius, blink, growth-network.
- Loadout: 4 ability slots + 1 mobility slot. Drafting while full = drop one.
- Draft cadence: 1-of-3 at each descent; shrines/shops mid-floor spend Bloom.
- Upgrades appear as draft options (e.g. cost reduction, bigger shape).
- Starting pool: **Horticulture** core set (~12 abilities). Examples:
  - Solar Lance — line damage, stronger in clear smog.
  - Seed Bomb — radius, creates growth.
  - Vine Whip — pull enemy 2 tiles.
  - Root Wall — create blocking terrain, 2-turn life.
  - Water Jet — push + washes oil/extinguishes fire.
  - Mycelium Dash (mobility) — teleport between growth tiles.

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
- Buying an ability with a full kit names the slot it replaces, exactly as a
  draft does, and neither that purchase nor the forge may ever take the
  mobility ability - a run can always still move. A draft reroll is not in the
  game yet.
- `+` items exist only through the press: the shrine and supply pods stock base
  items only, so item upgrades are a spend, never a drop.
- **Grafts** are the relic analog: passive run-long modifiers, data-driven like
  everything else (e.g. "+2 bank cap", "growth tiles heal +1", "first ability
  each turn that targets oil is free"). Kit stays 4+1; Grafts are where
  long-tail build identity accumulates. Each graft owned raises the price of
  the next.
- Grafts enter the combo-sweep harness the same as abilities, and can be
  pre-installed for a sweep via the run config (`tests/sweep_grafts.gd`).

### Meta-progression

- Permadeath; no permanent power. Milestones unlock **tech packages** of
  abilities into the draft pool:
  - **Mycology** — spores, tunneling, growth-network tricks.
  - **Hydraulics** — water, steam, washing/pushing.
  - **Aeolian** — wind, repositioning, smoke-clearing.
- Every pool addition must pass a harness combo-sweep before shipping.

### Post-win

Both replay hooks, both implemented as data over the same sim:

- **Difficulty tiers** (Ascension-style): numbered, each adding a stacking
  deterministic tweak (thicker smog curve, richer elites, pricier shops).
  Every tier must stay bot-winnable — the harness validates each one.
- **Run modifiers** (mutators): optional, chosen at run start, unlock-gated
  (e.g. "no growth terrain", "double oil", "kit of 3"). Free-form spice on
  top of the tier ladder.

## Playtest personas (style guide §5)

- **Wanderer** (random-walk) — crash and softlock finder.
- **Sprout** (cautious noob) — should die to Smog greed and disruptors
  sometimes; measures teaching-curve fairness.
- **Optimizer** (minmaxer) — searches for best lines; measures true difficulty
  ceiling and finds degenerate combos.
- Key metrics: win rate per persona, death cause distribution, floor-of-death,
  Bloom collected vs. smog deaths, per-ability draft-to-win correlation.

## Open questions

- Furnace numeric tuning (phase HP, cycle lengths) — expect the harness to
  drive this once the sim exists.
- Graft pool size at launch vs. unlock-gated.
- Whether smoke should be pushable by Aeolian abilities from day one or arrive
  with the package.
