# Balance targets and measurements

Reference numbers for TENDER's difficulty, and the discipline for changing them.

## Method

- 30-seed playtests (`tests/playtest.gd`) are smoke tests: good for "did this
  break the game," too noisy for tuning calls (±8 wins swing observed on
  identical builds across seed batches).
- Balance decisions require 100+ seeds. The `tests/sweep_lib.gd` runner makes
  ad-hoc measurement scripts trivial.
- Any sweep outlier gets verified at 30+ seeds before a patch (see the
  thorn_shield false positive: 5/10 in a pair sweep, 11/30 solo vs 10/30
  baseline — flagged, verified, not patched).

## Targets (full 7-floor run, tier 0, base pool)

| persona   | target                  | why |
|-----------|-------------------------|-----|
| deeproot  | 70–90% wins             | the search ceiling: near-perfect play should nearly always win |
| optimizer | 30–50% wins             | skilled play should win often but never be safe |
| fanatic   | 15–30% overall; every build > 0 | committing to a niche build must stay viable |
| magpie    | 5–15%, top bloom        | full greed should usually lose to the clock, richly |
| sprout    | avg depth 3.5–5, wins rare | noobs feel progress; full clears are earned |
| wanderer  | dies floor 1–2, 0 wins  | the world must punish random play |
| all       | zero timeouts/softlocks | every run ends in win or death |

Death-cause shape: optimizer dies mostly to combat, sprout mostly to smog
(greed), and deaths spread across floors rather than piling on one wall.

## Measurements

### 2026-08-08 (upgrades + elites + vaults in)

- optimizer, 100 seeds: **32 wins**, avg floor 5.03,
  deaths by floor {2:13, 3:16, 4:7, 5:15, 6:17} — in band, no wall.
- 30-seed personas: sprout avg floor 4.5 (smog-dominated deaths, bloom ~22),
  wanderer floor-1 deaths, timeouts ≈ 0–1.
- Tier ladder (20 seeds each): 8/7/7/7/5/3 — monotonic, all winnable.
- Packages (20 seeds): baseline 8, +mycology 7, +hydraulics 6, +aeolian 7 —
  mild pool dilution, no dominant ability.

### 2026-08-08 later (content breadth + Overseer + clone in)

- optimizer, 100 seeds: **42 wins**, avg floor 5.25. Both bosses drawn
  (furnace_core 17 arrivals, overseer 25); every floor-7 arrival converted.
- Slams widened to a cross (tile + neighbors) after the arrival-conversion
  finding; optimizer still dodges perfectly, sprout does not (~5/30 floor-7
  deaths). Decision: tier-0 bosses are a skill check that perfect play
  passes; the tier ladder supplies post-win boss pressure.
- 30-seed personas: optimizer 11/30, sprout avg floor 4.5 (smog 24/30),
  wanderer floor 1. Win rate drifting toward the top of the 30-50% band as
  player-power content accumulates - re-measure after each content round.

### 2026-08-08 latest (six-persona roster + vent-clog boss gate)

- Ladder (30 seeds): wanderer 0/30 · sprout 0/30 (depth 4.5) · magpie 2/30
  (bloom 38, the economy king) · fanatic 7/30 · optimizer 9/30 · deeproot
  24/30 (depth 6.8). Deeproot's 80% establishes the true skill ceiling ~2.5x
  heuristic play.
- The fanatic exposed a design flaw: the phase-3 growth gate made every
  non-gardener build unwinnable (pyro/shover/turtle 0 wins, deaths at the
  boss). Fix: phase 3 clogs the boss's vents with goo; cleansing (universal)
  or growth (the gardener shortcut) exposes the core. Pyro went 0/8 -> 4/8.
- Per-build wins after damage-anchor redefinition: pyro 4/8, gardener 2/7,
  shover 1/8, turtle 0/7. Turtle is a real gap: pure-defense builds lack a
  win condition (see watch list).

### 2026-08-08 thorns + ceiling sweeps

- Bramble Coat (thorns) added to the base pool: melee attackers and quakers
  take reflected damage. Modest by design.
- Fanatic build table, 100 seeds (~25 runs/build): pyro 8/25, shover 6/25,
  gardener 3/25, turtle 1/25.
- **Turtle verdict:** even with thorns, a growth engine, and a longer
  duration, pure-defense play loses to the clock - upkeep consumes the whole
  charge budget once smog dims regen. Recorded as an identity statement, not
  a bug: this game counters passivity the way it counters greed. The fanatic
  keeps the turtle archetype as a canary - if turtle win rates ever rise
  sharply, the clock has broken.
- Deeproot tier ladder (10 seeds/tier): 8/7/7/7/8/8 - flat. Current tier
  modifiers punish inefficiency (smog, prices), which near-optimal play
  routes around. Future tiers that should bind the ceiling need modifiers
  that bind optimal play too: enemy stats, elite density, boss buffs.

### 2026-08-08 ceiling tiers 6-8

- Three stat-based tiers appended (Hardened Plating: enemy hp +1; Sharpened
  Drills: enemy dmg +1; Overcharged Core: boss hp +6, +1 elite/floor).
- Optimizer ladder (20 seeds): 5/4/4/9/8/6 across tiers 0-5 (noise band),
  then 2/3/2 at tiers 6-8 - brutal for heuristic play but winnable.
- Deeproot ladder (20 seeds): 14/12/12/13/14/14 flat through tier 5, then
  **9/7/8 at tiers 6-8** with avg depth 6.7 -> 5.7. The stat tiers are the
  first content that binds near-optimal play - the ladder now has a top.
- Sweeps accept SWEEP_BOT=deeproot for ceiling-accurate runs; sweep_tiers
  fails on zero-win tiers <= 5 with the optimizer, and on any zero-win tier
  when judged by the ceiling bot.

### 2026-08-08 ceiling combo sweep

- First full pairwise sweep judged by Deeproot (SWEEP_BOT=deeproot, 45 pairs
  x 10 seeds; baseline 8/10, avg floor 6.7).
- Pool is balanced at the ceiling: 40/45 pairs within 20 points of baseline;
  no pair warps the draft.
- All three 10/10 pairs include bramble_coat (root_wall, water_jet,
  pollen_burst) - thorns pays off at the ceiling, where positioning makes
  enemies impale themselves. Within noise of an 80% baseline; noted, not
  flagged.
- Two pairs flagged at 5/10; 30-seed re-verification (tests/verify_kit.gd,
  baseline 23/30 = 77%): vine_whip + root_wall 21/30 - noise, cleared.
  thorn_shield + overgrowth 17/30 (57%) - a real but mild anti-synergy: two
  charge-hungry setup abilities and no finisher between them. Under the
  30-point action threshold and both abilities score fine in every other
  pairing, so recorded as a design note - support tools are supposed to need
  a damage plan next to them. No data change.

## Watch list

- `parched` mutator barely affects the optimizer (banking may be undervalued).
- Boss deaths are rare once seed_bomb is protected; arrivals are the real
  filter. If arrival rates rise, re-check Furnace difficulty.
- Elites are tanky bounty-carriers (+2 hp, +0 dmg, +4 bloom). The +1 dmg
  variant measurably overshot (optimizer ~17% at 30 seeds).
- Turtle is a designed anti-pattern (see 2026-08-08 thorns entry); fanatic
  tracks it as a canary metric.
- Deeproot logs occasional timeouts (2/30): the searcher can still judge
  stalling safest. Revisit if it grows.
- Magpie deaths cluster on floor 2 (harvest greed vs first real roster) -
  watch after any floor 2 tuning.
