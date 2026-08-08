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
| optimizer | 45–65% wins             | skilled play should win often but never be safe (raised from 30–50 after the tempo fix — the old band measured a bot flaw) |
| fanatic   | every build > 0 at 100 seeds (hard); 20–40% total (soft) | committing to a niche build must stay viable; the total tracks content difficulty and moves when content does |
| magpie    | 0–5% canary, top bloom  | full greed loses to the current game almost always; a RISE above 5% means greed got cheap (canary, like turtle) |
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

### 2026-08-08 ceiling package sweep

- Deeproot, 20 seeds per config: baseline pool 14/20; + mycology 16/20;
  + hydraulics 15/20; + aeolian 17/20; all three 13/20. Everything within
  noise of baseline - no package is a trap pick or a power spike at the
  ceiling.
- Package abilities are genuinely drafted in winning kits (gust and updraft
  4 wins each under aeolian; spore_cloud and fungal_ring under mycology;
  geyser and tide under hydraulics) - the unlocks add variety, not filler.
- "All three" dipping slightly below baseline echoes the optimizer-side
  pool-dilution note from the package round: more choices, same power.
  Within noise; no action.

### 2026-08-08 optimizer survival gate

- Autopsy (seed 2) caught the optimizer at 4 HP trading 1-dmg strikes with
  a telegraphed 2-dmg attacker - its strike rung outranked dodging. Added a
  survival gate: when its tile is threatened and hp + shield <= 2x incoming
  telegraphed damage, strike only for the kill, otherwise dodge.
- Effect is aggregate-neutral: 42/100 before, 42/100 after (avg floor
  5.25 -> 5.1); tier 7 3/30 vs 3/20 before. The trade-deaths were mostly
  symptoms of runs already behind tempo - those runs now die to smog
  instead. Kept regardless: combat deaths dropped (30-seed causes:
  4 drill_bot vs 17 smog), so autopsy output now shows real causes of loss
  rather than bot error, and the reference heuristic no longer models play
  no human would choose.
- Post-gate persona snapshot (30 seeds) all in band: wanderer 0 (floor 1),
  sprout 0 (depth 4.5), magpie 4, fanatic 2, optimizer 8, deeproot 23
  (avg floor 6.8, zero timeouts).

### 2026-08-08 mutator round (all six, both bots, 30 seeds)

- New mutators: Overtime Shift (+1 of each non-boss floor's most common
  enemy) and Boarded Shrines (shops sell nothing). Both in the daily
  rotation; both unlock at 2 career wins.
- Full table (optimizer / deeproot): baseline 8/23; kit_of_3 14/18;
  double_oil 14/20; brittle 8/23; parched 12/20; overtime 14/23;
  boarded 17/23.
- **Parched verdict (closes watch-list item):** binds the ceiling (-3) and
  not the optimizer, because banked burst only matters to skilled play.
  Working as designed; keep.
- **The systemic finding: five of six "handicaps" help the optimizer.**
  Boarded Shrines is +9 wins (30 points). Its deaths are smog-dominated,
  and every mutator that removes an option (shopping detours, cleanse
  windows, kit breadth) forces the tempo-optimal play it won't choose
  itself. Deeproot is flat on the same mutators - so the mutators are
  ceiling-neutral spice as intended, and the paradox is a bot flaw:
  the optimizer over-values economy and under-values descent speed.
  Its 42/100 baseline partly measures that error, not game difficulty.
- kit_of_3 is the strongest ceiling bind (-5): kit breadth genuinely
  matters at the top. brittle is flat for both - neither bot dies to
  raw damage at 30-seed resolution.

### 2026-08-08 optimizer clock discipline (the tempo fix)

- Chased the mutator-paradox finding to ground. Three fixes, only the last
  one mattered:
  1. Dim-gated cleansing/resting/detours: 8/30 -> 9/30. Nearly worthless.
  2. Autopsy caught an infinite dodge oscillation (two tiles, 25 turns,
     choke death). Dodges now tie-break toward the stairs - a fighting
     retreat instead of a standstill. Broke the loop, aggregate flat.
  3. The experiment: disabling shrine detours alone -> 17/30, exactly the
     Boarded Shrines number. **Cross-floor shopping trips were the entire
     paradox.** Detours now require the shrine to be <= 4 extra tiles off
     the direct stairs path (BFS-measured) and clear skies (dim 0).
- Re-baseline, 100 seeds: **59/100** (was 42), avg floor 6.1. Target band
  raised to 45-65%. Boarded Shrines re-check: 19/30 vs 17/30 baseline -
  paradox neutralized (shops are now roughly free, as they should be).
- Death-cause shape finally matches design intent: optimizer deaths are now
  combat-dominated (8 drill_bot / 3 smog, floors 5-6), not clock-dominated.
- Ripple: fanatic 2/30 -> 9/30 (pyro 4/8, shover 4/8 - it inherits the
  pathing fix and stops donating tempo; turtle still 0, canary intact).
  Deeproot unchanged at 23/30. Skill ladder stays strictly ordered:
  0 / 0 / 2 / 9 / 17 / 23 across the six personas.

### 2026-08-08 magpie: greed is now lethal - reclassified as a canary

- 100-seed rechecks after the 0/30 playtest flag: original magpie 2/100
  (avg floor 4.0); with its greedy shopping detours restored (they had
  been silently deleted by inheriting the optimizer's on-the-way-only
  rule) 1/100; with harvest/cleanse tightened to stop at first dim,
  still 1/100. The greed dial is insensitive - every setting dies.
- Autopsy: the run is decided in the first ~20 turns. Any persona that
  spends the first two dim stages on economy cannot escape the spawn
  pressure that follows, no matter when it stops harvesting.
- Verdict: the hardened game (escalating choke, new enemies, The Dredge)
  punishes greed as catastrophically as passivity or randomness. This is
  coherent design, not a bug. Magpie's band moves from 5-15% to 0-5%
  and it becomes a canary like turtle: a RISE means greed got cheap.
  The shopping-detour restoration is kept (persona fidelity); the dim
  calibration tweak was reverted as it changed nothing.

### 2026-08-08 Anchor Roots + Moss Filter (pool answers to the new threats)

- Anchor Roots (cost 1, self): drag immunity 4 turns - the counter to
  Magnet Crane and The Dredge's pull. Moss Filter (cost 2, self): dim -1.
  Moss Filter deliberately does NOT touch raw smog: a smog scrubber at
  these costs would hold the clock below choke forever and resurrect the
  camping hole the escalating choke closed. Dim relief is one-shot and
  choke keeps scaling, so the clock still wins.
- First version of Anchor Roots carried a +1 shield rider and collapsed
  deeproot to 14/30 (baseline 26/30): its 1-ply eval scores shield at a
  flat +12/point vs -2/charge, so a cheap shield rider is a strictly
  positive cast every time shield gets chipped - ~20 extra turns/run of
  re-anchoring tempo bleed, then dying to escalated choke in boss fights.
  Shipped as pure anchor: solo check 23/30, playtest deeproot 22/30 -
  collapse reversed.
- Moss Filter solo 23/30... 24/30; optimizer 100-seed 45 vs 48 baseline -
  pool dilution within noise. Suite green, zero timeouts.

### 2026-08-08 thorns reflect close-range slams (measured neutral)

- Slams from a slammer within 2 tiles now trigger thorns, joining melee
  and quakes - "physical contact gets spiked," no arbitrary exception.
- Measured a complete no-op at every level: turtle 1/25 (noise from
  2/25), bramble_coat 23/30 deeproot (identical), boss conversions
  9/9 / 6/6 / 5/9 (identical). Cause: slams are telegraphed and every
  measured player dodges them; reflection only fires on hits that land.
- Kept as a consistency rule: zero measured cost, and human players -
  who tank telegraphed slams far more than bots - are the audience it
  actually serves. Turtle's ceiling remains the clock, per the standing
  identity statement.

### 2026-08-08 ceiling combo re-sweep (post new enemies + bot fixes)

- Deeproot pair table rerun (45 pairs x 10 seeds, baseline 8/10). The
  table compressed: no pair beats baseline now (old table had three
  10/10s) - locked 5-ability kits lost ground as the game hardened.
- Thorns reversal: bramble_coat sat in the old table's three best pairs
  and now sits in five of nine flagged worst. 30-seed verification:
  bramble_coat alone 23/30 vs baseline 26/30 - a real but mild decline.
  Mechanism: Smokestack, Magnet Crane, and The Dredge attack without
  melee contact, so thorns have fewer hits to reflect. Recorded as
  design texture (ability value shifts with the enemy mix), not a bug.
  Candidate future buff if thorns keep sliding: reflect slams from
  slammers within 2 tiles.
- water_jet + overgrowth confirmed weakest pair at 16/30 (-34) - the
  established pure-support-pair pattern (no finisher). No data change,
  consistent with the thorn_shield + overgrowth verdict.
- thorn_shield + bramble_coat 21/30: mild redundant-reflection
  anti-synergy, under threshold.

### 2026-08-08 The Dredge (third floor-7 boss)

- Anti-growth mobile boss: drag-pull (range 4; x2 in phase 2), cross slam
  (range 2), and dredge - all growth within radius 2 (3 in phase 2) turns
  back to goo, healing it 1/tile. Its food is your cleansed garden; the
  counterplay is fighting it away from growth. Standard gate + phase-3
  vent clog apply, so cleansing remains the universal counter even though
  dredging undoes it locally.
- First tier-0 boss with teeth: optimizer converts 5/9 arrivals (vs 9/9
  furnace_core, 6/6 overseer); deeproot converts 14/15 - a skill check,
  not a stat wall, per the boss design precedent.
- tests/measure_bosses.gd added as a permanent harness (per-boss
  arrivals/conversions; BOSS_BOT/BOSS_SEEDS).
- Post-boss playtest healthy: 0/1/1/7/16/26 wins, zero timeouts, suite
  green. Sprout logged its first-ever win (1/30) - noted, in band.

### 2026-08-08 Smokestack + Magnet Crane (late-floor content)

- Smokestack (floors 5-6): stationary, stokes the smog clock one extra
  full tick every 2 turns while alive - the first enemy that attacks the
  resource. Stokes are complete ticks consumed by _tick_smog, so dim/
  choke/spawn thresholds are never skipped.
- Magnet Crane (floors 4-5): drags the player one tile toward itself each
  turn within range 3, with full tile-entry effects (drag into oil/fire is
  real). Punishes pure kiting; intent telegraphs cleanly.
- Impact at 100 seeds: optimizer 63 -> 48 (back inside its 30-50 band
  after the tempo fixes left it above); deeproot untouched (23 -> 25/30) -
  skilled play absorbs both mechanics, so this is difficulty, not noise.
- Fanatic 100-seed table: pyro 10/25, shover 6/25, turtle 2/25,
  gardener 7/25 - every build still wins (hard target holds), total
  25/100. Band reframed: every-build-viable is the hard target; the
  total (now 20-40 soft) tracks content difficulty by design.
- Zero timeouts everywhere; suite green (39 determinism, 1400/0
  invariants, meta OK).

### 2026-08-08 escalating choke: the clock always wins now

- The last three turtle timeouts were not a bot flaw. Autopsy: cornered in
  a one-entrance niche by an extractor's spawn stream that refills the
  corridor every enemy phase, healing on growth faster than the flat choke
  (1 dmg / 3 turns vs 1 heal / turn). Unwinnable-but-unlosable - a real
  design hole that a defensive human player could hit too, violating both
  the zero-softlock target and "the game counters passivity."
- Sim fix: choke damage now escalates - 1 + (smog - choke) / 60 per tick.
  Invisible within 60 smog of the threshold (no normal run changes),
  out-heals growth past ~120, guarantees every run terminates.
- Fanatic 100-seed table after (tests/measure_fanatic.gd, now a permanent
  harness script): pyro 14/25, shover 14/25, gardener 9/25, turtle 5/25,
  total 42/100, **timeouts: zero**. Every build wins. Band raised to
  30-50%. Turtle canary re-baselined at 5/25: its rise came from the
  survival gate / retreat / cooldown fixes (bot skill), not clock decay -
  the escalating choke strengthens the clock.
- Full suite green with all six personas at zero timeouts for the first
  time: 0/0/3/12/21/23 wins, determinism 39, invariants 1400/0, meta OK.

### 2026-08-08 no greedy cleansing + the timeout hunt

- Rich Veins scoring above base in the post-tempo-fix tier ladder pointed
  at the last dawdling habit: extra enemies were suppressing the greedy
  cleanse. Measured at 100 seeds: removing greedy cleansing entirely is
  +11 wins (59 -> 70 solo; 63/100 with all of this round's fixes in).
  The optimizer now cleanses only where it pays - boss gates and tiles it
  passes anyway. Tier ladder is monotonic again:
  15/14/14/11/11/10/9/7/3 - Rich Veins anomaly gone.
- Timeout hunt (target: zero). All six 30-seed timeouts autopsied; every
  one was the same disease - a locally-reasonable action with no progress
  requirement:
  1. Strike-lowest-HP executed an extractor's endless hp-1 spawn stream
     forever. Summoners now outrank spawns, and blocked routes advance on
     the summoner first.
  2. Fanatic's overgrowth trigger re-cast every turn; growth healing kept
     pace with choke damage - immortal at turn 400. Now on a 6-turn
     cooldown, and build casts defer to the survival gate under lethal
     telegraphed damage. vine_whip gated to enemies within 2.
  3. Magpie dash-dodged between the same two growth tiles forever while
     cornered. Dashes now require strict BFS progress toward the stairs
     (boss floors exempt - any safe dash counts there).
- Playtest after: timeouts 6 -> 1 (one fanatic straggler, watch-listed);
  magpie 3/30 in band with avg turns down 125 -> 97; fanatic 12/30 with
  gardener 5/7 (was the worst build, now the best - the overgrowth
  cooldown freed its charge for seed bombs); optimizer 21/30; deeproot
  23/30 unchanged. Ladder: 0 / 0 / 3 / 12 / 21 / 23.
- Optimizer seed 2 - the death that started the whole tempo
  investigation - now wins.

## Watch list

- Turtle canary baseline is now 5/25 (post loop-fixes). A sharp rise from
  there still means the clock has weakened.
- Deeproot eval bias: flat +12/shield point with no tempo cost makes cheap
  shield riders strictly-positive spam (see Anchor Roots collapse). Any
  future ability with a small self-buff rider needs a deeproot solo check
  before shipping; thorn_shield's persistent mild underperformance in pair
  tables is probably the same bleed.
- Magpie is now a greed canary at 0-5% (see 2026-08-08 magpie entry);
  watch for rises, not falls.
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
