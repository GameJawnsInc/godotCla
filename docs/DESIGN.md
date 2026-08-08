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

### Meta-progression

- Permadeath; no permanent power. Milestones unlock **tech packages** of
  abilities into the draft pool:
  - **Mycology** — spores, tunneling, growth-network tricks.
  - **Hydraulics** — water, steam, washing/pushing.
  - **Aeolian** — wind, repositioning, smoke-clearing.
- Every pool addition must pass a harness combo-sweep before shipping.

## Playtest personas (style guide §5)

- **Wanderer** (random-walk) — crash and softlock finder.
- **Sprout** (cautious noob) — should die to Smog greed and disruptors
  sometimes; measures teaching-curve fairness.
- **Optimizer** (minmaxer) — searches for best lines; measures true difficulty
  ceiling and finds degenerate combos.
- Key metrics: win rate per persona, death cause distribution, floor-of-death,
  Bloom collected vs. smog deaths, per-ability draft-to-win correlation.

## Open questions

- Boss design for the Furnace (multi-phase intents? arena terrain?).
- Whether unspent Charge banks, converts, or is lost (tuning lever).
- Shop/shrine variety and Bloom sink depth.
- Win-streak or challenge modifiers after first clear.
