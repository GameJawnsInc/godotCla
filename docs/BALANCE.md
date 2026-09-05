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
| magpie    | 0–5% canary, top bloom  | full greed loses to the current game almost always; a RISE above 5% means greed got cheap (canary, like turtle). Unmet since before bump 2 (pre-bump 6/100 [3, 12], now 10/100 [6, 17] under v2); the 30-seed gate line is red at 4/30 pending a decision — see 2026-09-05d |
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

### 2026-08-08 deeproot formal baseline

- First 100-seed deeproot measurement: **73/100 wins, avg floor 6.8** -
  squarely in the 70-90 ceiling band, and consistent with every 30-seed
  estimate used this session (22-26/30). The official ceiling reference
  for future content rounds: skilled play wins about three runs in four
  on the current game at tier 0.
- Skill curve at 100 seeds, current game: wanderer 0 · sprout 0 ·
  magpie 1-2 · fanatic 25 · optimizer 45-48 · deeproot 73. Monotonic,
  well-separated, zero timeouts.

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

## 2026-08-11 - bloom economy round (first human-found degenerate line)

A human player won the base run via: farm every early-floor cleanse,
buy all six grafts flat-priced at 5, then solar-lance spam to the end,
skipping cleansing entirely on floors 5-7 (+50 bloom surplus at the
win screen). Instrumentation (30 seeds) confirmed all of it:
optimizer's casts were 77% solar_lance; NEITHER ceiling bot ever
bought a graft; deeproot banked 12.7 surplus bloom with 3 total spent.

Changes:
- Solar lance base loses the clear-skies +1 (flat 2 dmg). The bonus
  is now the + upgrade's edge (3 dmg, 4 under clear skies) - upgrading
  the starter finally matters.
- Graft prices escalate: 4 bloom + 2 per graft already owned
  (4/6/8/10/12/14; full set 54 vs the old flat 30). "Buy every
  permanent upgrade" is a commitment, not a default.
- Cleansing thins the smog by 1: a cleanse turn pauses the clock
  instead of losing it, so late-floor cleansing has tempo value.
  (First tried relief 2: deeproot immediately turned floors 5-7 into
  a stall engine - 3,547 late cleanses / 126 surplus bloom over 30
  seeds, the exact unwinnable-but-unlosable pattern the escalating
  choke exists to kill. Relief must stay strictly below the tick.)
- The shell now surfaces the meta layer: profile persisted on device,
  difficulty picker after the first win, unlock notices on the win
  screen. The answer to "I won easily" is the tier ladder, which was
  invisible on the phone.

Post-change rates: optimizer 51/100 (baseline 48), deeproot 23/30,
magpie 5/100 (top of the greed band - cleanse relief feeds greed;
watch it), sprout 0 with avg floor 4.6, wanderer 0, zero timeouts.
Tier ladder re-run: all tiers winnable; tier 7 is 0/20 for the
heuristic but 5/20 for deeproot (ceiling-hard, fair).

## 2026-08-11b - shover viability round (forced-movement interrupts)

Fanatic's shover build sat at 3-4/25 while pyro ran 13/25. Autopsy
over all 25 shover seeds: deaths cluster on floors 5-7, smog first
(9/21) and bosses second (7/21) - control play stalls the clock, and
BOTH shover buttons were dead against every boss (massive blocks
push/pull entirely, and the pull op returned before dealing damage).

Changes (all system-level, no numbers-only patches):
- Forced movement now staggers: a pushed or pulled enemy drops its
  telegraphed intent and re-decides next turn. Per-enemy 3-turn
  cooldown so cheap displacement cannot interrupt-lock; bosses hold
  their footing.
- Vine whip lashes massive enemies it cannot drag; water jet
  pressure-hits massive enemies it cannot shove. No dead buttons vs
  bosses.
- Shoving an enemy into another enemy deals collision damage to both.
- Numbers: vine_whip 1->2 dmg (+: 2->3), water_jet collision 1->2
  (+: 2->3).

Result: ceiling check is the verdict - deeproot with a FORCED shover
kit wins 9/20 (45%), so the archetype is real. Fanatic-shover stays
low (2-3/25): the 1-ply heuristic cannot play control tempo; recorded
as persona limitation, not archetype failure. Full personas after the
round: fanatic 28-29/100 (in band), optimizer 51/100, magpie 5/100,
deeproot 24/30, zero timeouts everywhere.

## 2026-08-11c - green mechanics round (rooms bloom, consumable satchel)

Theme-first mechanics request: make greenifying the world a core loop.

- Cleansing now leaves growth on the tile - tended rooms literally
  turn green (and feed mycelium_dash / grow_spike / the Dredge).
- Room bloom: when a room's last corruption is cleansed the room
  blooms once - +2 bloom and a supply pod springs up beside the
  tender (nearest open tile; row-major tie-break). Bloomed rooms are
  tinted and flowered in the shell.
- Consumable satchel (2 slots, using one is a FREE action):
  sun_capsule +3 charge, balm_fruit heal 4, spore_vial stun r2,
  clearair_pod smog -5, iron_seed +3 shield. Sources: bloom pods and
  shrines (2 bloom, always stocked). Fills the shell's two reserved
  D-pad corner buttons.

Measurement traps hit and fixed:
- First cut drew shop-item / pod rng from the MAIN stream; one extra
  draw per floor reshuffled every downstream roll and the optimizer
  "dropped" 51->32/100. Isolation (stock line toggled) proved the
  mechanics were neutral; fix is a forked side rng
  (hash(seed, floor, tag)) for side-channel draws. Rule for the
  future: incidental draws NEVER touch the main stream.
- Deeproot ignored pods (1 pickup/20 blooms) until (a) pods drop
  adjacent and (b) its eval scores held items (+30/item, below raw
  effect value so search still spends them).

Post-round: optimizer 20/30 and 51/100 (baseline held), deeproot
25-26/30 (up ~2 - it cleanses, so the loop pays it; intended),
sprout floor 4.7 / bloom 24.9, magpie 1/30, zero timeouts, tier
ladder winnable everywhere (tier 7: 1/20 heuristic, deeproot-fair).
Loop engagement at ceiling: 16 blooms / 15 pickups / 9 uses per 10
runs.

## 2026-08-11d - the green gate (user-directed core mechanic)

Direction: greening is REQUIRED to advance. The stairs lie dormant
until the floor's green quota is cleansed (green_need per floor def:
2/3/3/3/3/4, floor 7 gated by the boss instead; clamped at floor
entry to the corruption that actually generated). Cleansing while
the quota is unmet gives smog relief 2 (net -1: the sky funds the
detour the gate demands); post-quota relief returns to the
stall-safe 1. Extras: growth planted on a vent absorbs that vent's
next smog-clock reinforcement (boss-phase spawns punch through);
cleansing the LAST corruption anywhere restores the floor - dim
clears, smog -8, +5 bloom, one-time.

Tuning history (all measured at 30 seeds, key rates at 100):
- Gate landed hard: optimizer 20->7/30, sprout avg floor 4.6->2.0
  (25/30 deaths were smog with quota UNMET - bots stalled at dormant
  stairs). Bots are part of the game: sprout paths to corruption
  when gated ("even a noob reads the banner"), optimizer cleanses
  whenever standing safe and walks to corruption in calm moments,
  deeproot's field gradient and eval learned the quota.
- Quota trim (floors 4-6: 4/4/5 -> 3/3/4) + gate-aware bots:
  optimizer 13/30, sprout floor 3.9, fanatic 7/30, deeproot 26/30,
  magpie 1/30, zero timeouts.
- Post-gate world is deliberately harder than pre-gate (optimizer
  ~43% vs 51%): mandatory objectives cost tempo. Accepted.
- Tier ladder re-judged: heuristic 10/10/10/6/5/7 through tier 5;
  tiers 6-8 by deeproot: 12/20, 9/20, 8/20. The green economy pays
  skilled play, so high tiers actually softened for the ceiling.

Watch: deeproot 26/30 (87%) - the ceiling exploits quota relief +
restoration + satchel hard. If the human reports the game feels
farmable again, the levers are quota relief (2->fixed 1) and the
restoration bonus (-8 smog / +5 bloom).

## 2026-08-11e - gate balance pass 2 (ceiling guards, Dredge cap)

Measured before tuning: deeproot 55/60 (92%) at the new economy;
optimizer 32/100 with The Dredge suddenly 9/68 deaths (the greened
world feeds the growth-eating boss); restoration fires 0.00/run for
BOTH bots - it is not the ceiling's engine, compounding skill is.

Changes:
- Relief taper: quota cleanses thin smog by 2, the next 4 by 1,
  beyond that cleansing pays bloom/growth/blooms but no longer
  pauses the clock. Insurance against marathon cleanse-stalling
  (the taper barely moved today's rates - kept as a guard).
- Dredge heal cap: 3 hp per bite (uncapped radius-3 dredges swung
  6-8 hp per action post-greening). Optimizer dredge deaths 9->3.
- Optimizer banks the taper: cleanses opportunistically through
  quota+4 while standing safe. 32->40/100, and item usage jumped to
  227 uses/100 runs (more cleansing -> more pods -> satchel works).

Design position, recorded: deeproot ~87-92% on the base run is
ACCEPTED. The base run is the first-run experience; the ceiling's
real game is the tier ladder (deeproot tiers 6-8: 40-60%). Post-gate
optimizer band is 35-45 (currently 40/100).

Watch: magpie logged its first timeout since the tempo fixes (1/30,
turns 129) - greed vs the gate can stall; revisit if it grows.

## 2026-08-11e - skills round (spiked chassis + verdant surge)

Human feedback: "too many runs I get by with just attacking."
Measured mix (strikes vs casts): sprout 67%, optimizer 60% strikes -
while deeproot, the ceiling, plays 17% strikes / 83% casts. Skilled
play is already ability play; strike-spam was merely good enough.

Changes:
- Spiked chassis: coal golems, rust hounds, and EVERY elite hurt to
  punch - a melee strike deals 1 damage back to the attacker. Elites
  become the "bring a tool" moments rather than bigger punching bags.
  Spiked enemies wear visible spike studs; tooltips warn.
- Verdant surge: casting a 2+ cost ability while standing on growth
  consumes the tile for -1 charge. The garden is ability fuel - the
  green loop now feeds skill play, and it is a spend, not a passive
  discount (self-limiting, anti-stall). Ability-bar pips turn green
  when the surge is live; live cost comes from game.ability_cost().
- Optimizer skips punching spiked targets without HP to spare.

Post-round: optimizer 39/100 (band 35-45 held; only 2 golem deaths -
the avoidance works), sprout floor 3.8, fanatic 5/30, magpie 2/30,
deeproot 28/30 (ceiling creeps up again - verdant surge pays perfect
play; base-run ceiling is design-accepted, tiers absorb it), zero
timeouts. Tier ladder: heuristic 7/7/7/7/8/7 through tier 5, tiers
6-8 by deeproot 8/10/6 of 20. Bot strike share moved only a little
(58-62%) - these mechanics primarily target human hands: punching
now has a price where it should, and casting has a visible reward.

## 2026-08-11f - upcycling round (green combining vs evil assimilation)

User direction: creative recycling for the player, an evil mirror for
the combine.

- Shrine press (1 bloom): two held consumables become the + form of
  the kept one - Solar Battery (+6 charge), Orchard Feast (full
  heal), Spore Storm (stun r4 x2), Storm Seed (smog -12), Ironheart
  (+3 shield, +1 max HP).
- Shrine forge (3 bloom): one kit ability becomes its + variant, a
  second is scrapped for parts - power for breadth, frees a slot.
  Only abilities with + forms qualify (package abilities have none).
  Gummed slots remap on the scrap. Two-tap flow in the shell.
- Assimilation: drill bots carry "fuses". With 3+ enemies alive, an
  adjacent pair telegraphs WELD one turn ahead (orange arc drawn
  between them), then merges into a Welded Hulk: hp min(sum, 7),
  dmg 2, slow, spiked. Counterplay: kill or displace either partner
  (stagger clears the intent). Boss-phase spawns unaffected.

Personas after: optimizer 14/30, sprout floor 3.8, magpie 2/30,
fanatic 6/30, deeproot 27/30, zero timeouts - fusion trades attack
count for chunkier hits and measures roughly neutral. Bots do not
yet upcycle (deeproot's eval has no term for + forms, so search
declines the bloom cost); recorded as a known gap - upcycling is
currently human expression, not bot-measured power.

## 2026-09-05 - instrument v2 re-baseline (Block A harness fixes)

Block A of docs/PROGRESSION_REVIEW.md: harness and bot repairs only, no
sim behaviour change, no RUN_SAVE_VERSION bump. **Every number above
this entry was produced by the v1 instruments and is NOT comparable to
anything below it**; comparisons are made within one instrument
version only (the CLAUDE.md practical notes carry the rule).

What changed in the instruments:
- One run loop (`Sweep.run_loop`) and one bot registry
  (`bots/roster.gd`) behind every runner; `tests/tally.gd` counts casts
  by base id, drafts/picks/skips/drops, buys, combos, damage by source,
  stall floors, quota-unmet deaths and illegal actions, and every runner
  prints a header (bot, config, seed range), a Wilson CI and the KPI
  block (strike share, signature share, terrain share, combos/run,
  bloom conversion, kit entropy).
- deeproot: candidate set is round-robin across kit slots with
  nearest-enemy-first targets (per-slot truncation 13-22% -> 0%).
- optimizer/magpie/deeproot drafting: an unlisted offer is taken over
  skip (rank after the list, not 500); `mycelium_dash` joins the list
  last. sap_snare counts as a dodge only against a `move` intent.
- sprout: uses items (balm_fruit at hp <= 4, sun_capsule at 0 charge)
  and casts seed_bomb / grow_spike; every sprout seed re-baselines.
- fanatic: builds come from `Content.ARCHETYPES` (`set_build(id)`),
  off-build ability purchases no longer leak through the parent, and
  measure_fanatic runs every build on every seed (N per build =
  FANATIC_SEEDS, so the old per-build rows are not comparable either).
- sweep_combos measures locked-kit lift (`{kit: K, pool: K}`) instead
  of open-pool drift; sweep_tiers gates on the Wilson upper bound;
  playtest gates each persona's band; tests/test_regressions.gd replays
  a 24-record corpus; tests/draft_oracle.gd is new.

Before (review telemetry, v1 loop, seeds as noted) / after (v2, seeds
1..30, tier 0 unless noted, Wilson 95%):

| persona | before | after | band |
|---|---|---|---|
| optimizer | 17/40 = 42% [29, 58] | 14/30 = 47% [30, 64] | 45-65 ok (35-65 in the playtest gate) |
| magpie | 3/40 = 8% [3, 20] | 2/30 = 7% [2, 21] | 0-5 canary, CI covers it |
| sprout | 0/40 = 0% [0, 9] | 1/30 = 3% [1, 17], avg floor 3.9 | wins rare, depth 3.5-5 ok |
| fanatic (legacy 4 builds by seed) | 10/40 = 25% [14, 40] | 5/30 = 17% [7, 34] | 20-40 soft; see the archetype table |
| deeproot tier 0 | 18/20 = 90% [70, 97] | 27/30 = 90% [74, 97] | 70-90 ok |
| deeproot tier 6 (locked base3+anchor_roots, lift table) | 16/24 = 67% [47, 82] | 18/30 = 60% [42, 75] (open pool, avg floor 6.0) | - |
| deeproot_rollout tier 0 | no prior baseline | 26/30 = 87% [70, 95] | new column |
| wanderer | - | 0/30, floor 1.0 | ok |

Zero timeouts and zero illegal actions for all seven personas; the
playtest gate is all-PASS at 30 seeds; suite green (invariants 1400 +
floor_def 1540 / 0, determinism 45 checks / 7 personas, content OK,
regressions 24/24, meta OK).

KPI block per persona (30 seeds, tier 0; strike = strike share of
enemy damage, sig = signature share, terr = terrain share, cmb =
combos/run, conv = bloom spent/earned, ent = kit entropy bits, shrine =
shrine turns/run, stall = stall floors over 30 runs, qu = quota-unmet
deaths):

| persona | strike | sig | terr | cmb | conv | ent | shrine | unspent charge/end_turn | stall | qu | dmg taken/run |
|---|---|---|---|---|---|---|---|---|---|---|---|
| optimizer | 0.39 | 0.17 | 0.02 | 3.3 | 0.23 | 3.83 | 1.2 | 0.59 | 4 | 2 | 17.6 |
| magpie | 0.30 | 0.37 | 0.02 | 3.4 | 0.40 | 4.23 | 26.5 | 0.67 | 18 | 0 | 37.3 |
| sprout | 0.33 | 0.11 | 0.04 | 7.5 | 0.03 | 4.51 | 0.4 | 0.37 | 10 | 2 | 28.9 |
| fanatic | 0.26 | 0.16 | 0.05 | 12.8 | 0.21 | 3.74 | 0.8 | 0.28 | 7 | 5 | 34.2 |
| deeproot | 0.09 | 0.30 | 0.14 | 10.9 | 0.01 | 3.76 | 0.5 | 0.71 | 3 | 0 | 4.2 |
| deeproot tier 6 | 0.05 | 0.44 | 0.22 | 20.4 | 0.01 | 3.86 | 0.5 | 1.19 | 10 | 1 | 24.0 |
| deeproot_rollout | 0.07 | 0.26 | 0.16 | 11.3 | 0.01 | 4.08 | 0.5 | 1.02 | 5 | 0 | 15.8 |

Readouts worth keeping: optimizer spikes are 136 of 528 player damage
(the spiked filter engages too late); deeproot casts thorn_shield 9.2
times per run (509 hp absorbed by shield against 126 damage taken
over 30 runs; the shield-spam bias is still there) and spends 0.3 of 47 bloom per run;
magpie sits 26 turns per run on shrines and stalls 18 of ~105 floors;
mycelium_dash+ is offered 30 times and picked 0 for both optimizer and
deeproot in the open pool (the unlisted-offer fix only bites in
locked/tiny pools); sprout's combos/run 7.5 is verdant surges from
seed_bomb on growth, not skill.

Fanatic archetypes (measure_fanatic, FANATIC_SEEDS=30, every build on
every seed, base pool; core-complete = floor by which every core id
was held, never = share of runs that never completed the core):

| build | wins | CI | avg floor | core-complete | sig | strike |
|---|---|---|---|---|---|---|
| pyro | 8/30 | [14, 44] | 5.7 | 3.5 (never 37%) | 0.05 | 0.11 |
| pyro_nolance | 8/30 | [14, 44] | 5.3 | 4.7 (never 63%) | 0.34 | 0.29 |
| ember | 9/30 | [17, 48] | 5.4 | 6.8 (never 87%) | 0.49 | 0.17 |
| gardener | 11/30 | [22, 54] | 5.4 | 4.8 (never 63%) | 0.40 | 0.29 |
| shover | 5/30 | [7, 34] | 5.5 | 5.2 (never 70%) | 0.19 | 0.04 |
| shover_nolance | 5/30 | [7, 34] | 4.7 | 5.5 (never 87%) | 0.64 | 0.13 |
| anchor | 6/30 | [10, 37] | 4.7 | 5.0 (never 90%) | 0.00 | 0.57 |
| turtle | 1/30 | [1, 17] | 4.5 | never (100%) | 0.05 | 0.60 |

pyro vs pyro_nolance 8 vs 8 and shover vs shover_nolance 5 vs 5: at 30
seeds the lance adds nothing to either archetype's win count; what it
changes is the signature share (0.05 -> 0.34 fire, 0.19 -> 0.64
control). turtle's core (5 ids + protected mycelium_dash) cannot fit
the kit, so its core-complete is 100% never by construction. Total
53/240 = 22%.

Locked-kit lift (sweep_combos, `{kit: K, pool: K}`, base3 = starters;
lift = pair - max(single); flag needs the pair CI to exclude the best
single AND sign_p < 0.05):

optimizer, tier 0, 30 seeds - baseline 13/30 [27, 61]; singles
grow_spike 9, overgrowth 11, root_wall 11, sun_flare 12, vine_whip 13,
water_jet 12:

| pair | sx | sy | pair | lift | pair - additive | discordant | sign_p | cmb/run |
|---|---|---|---|---|---|---|---|---|
| root_wall + sun_flare | 11 | 12 | 16/30 [36, 70] | +4 | +6 | 9:5 | 0.42 | 3.6 |
| grow_spike + overgrowth | 9 | 11 | 14/30 [30, 64] | +3 | +7 | 10:7 | 0.63 | 2.6 |
| vine_whip + water_jet | 13 | 12 | 15/30 [33, 67] | +2 | +3 | 8:6 | 0.79 | 5.4 |

0/3 flagged. The optimizer casts neither overgrowth nor root_wall in
a locked kit (30-seed probe: casts are the three starters only, and
identical for both), so those rows measure a 4th/5th slot of nothing;
the lift table is deeproot's.

deeproot, tier 6, 16 seeds (a tier-6 lift is lift in a different
economy; compare within the tier only):

baseline (base3 locked) 10/16 [39, 82] (the review's 16/24 was base3 +
anchor_roots, v1 loop - not the same row); singles grow_spike 14,
overgrowth 7, root_wall 11, sun_flare 10, vine_whip 14, water_jet 15:

| pair | sx | sy | pair | lift | pair - additive | discordant | sign_p | cmb/run | sig | terr | dmg |
|---|---|---|---|---|---|---|---|---|---|---|---|
| root_wall + sun_flare | 11 | 10 | 13/16 [57, 93] | +2 | +2 | 5:3 | 0.73 | 13.1 | 0.18 | 0.05 | 22.5 |
| vine_whip + water_jet | 14 | 15 | 14/16 [64, 97] | -1 | -5 | 1:2 | 1.00 | 28.8 | 0.67 | 0.21 | 5.9 |
| grow_spike + overgrowth | 14 | 7 | 13/16 [57, 93] | -1 | +2 | 2:3 | 1.00 | 8.3 | 0.30 | 0.03 | 21.2 |

0/3 flagged. Same shape as the review's v1 table (lift 0 to -1 on
every pair, no pair worth more than its solo gains) with one new
reading the v1 instruments could not give: the shove pair fires 28.8
combos per run at 0.67 signature share and 5.9 damage taken (the
best continuous secondaries of any row) while its win count is capped
by water_jet alone at 15/16. Single-ability value at tier 6 is real
(water_jet +5, grow_spike +4, vine_whip +4 over the 10/16 base;
overgrowth -3). N=16 is a pilot; the 30-seed grid is SWEEP_SHARD
work.

Draft oracle (tests/draft_oracle.gd, optimizer, 30 seeds, 138 drafts,
552 forks, 80 s; chosen-fork rollout agreed with the real outcome at
138/138):
- Stakes: 44/138 drafts decisive (some fork wins and some loses), 56
  all-won, 38 all-lost; mean stakes 0.32 wins. Floor 2 is the only
  draft that matters much (14/30 decisive, turn spread 24); floor 7 is
  1/15.
- Regret: best fork 100 wins, bot pick 84, always-skip 77 -> regret 16
  (0.12 per draft); the pick matched the best fork at 122/138 drafts
  and skip matched it at 115/138. Skip was strictly best (every pick
  lost) at exactly 1 draft, so skipping is not already the best pick.
- Per offer (P(win|pick) - P(win|skip), paired): grow_spike +28%
  (5:0, p=0.06), moss_filter +24% (5:1), sun_flare +5%, thorn_shield
  +7%; mycelium_dash+ -14% (2:6), water_jet -9%, solar_lance+ -3%;
  overgrowth, anchor_roots, bramble_coat, vine_whip, seed_bomb+ exactly
  0 (never cast, never matter). Kit-conditional: solar_lance+|grow_spike
  -27% (n=11), pollen_burst|grow_spike -20% (n=10). Nothing clears
  p < 0.05 at 30 seeds; the caveat stands (a rollout values an offer by
  what this persona does with it).

Watch list additions (post-v2 bands):
- optimizer 47% sits inside both bands but the CI [30, 64] straddles
  the BALANCE.md 45% floor; the playtest gate uses the review's 35-65
  until the next 100-seed run settles which band is right.
- magpie 2/30: the CI upper bound (21%) is above the 5% canary at any
  30-seed run; the gate only fires when the lower bound clears 5%.
  Judge magpie at 100 seeds.
- sprout 1/30 is exactly on the "<= 1 win per 30 seeds" gate; any
  further sprout skill change must re-check it (the metric we care
  about is avg depth 3.9, in band).
- fanatic 5/30 (17%) is under the 20-40 soft band as the legacy
  seed-split roster; the per-build table (22% total) is the number to
  track from now on.
- deeproot thorn_shield 9.2 casts/run and bloom conversion 0.01: the
  shield-spam bias and the unspent-bloom ceiling the review named are
  both confirmed by the tally; deeproot_plan (7.5) is the fix, not a
  content change.
- deeproot_rollout 26/30 is within CI of deeproot (27/30) but wins in
  85.7 turns against 71.3, takes 15.8 damage per run against 4.2 (295
  of it smog), casts thorn_shield 16.7/run and mycelium_dash 14.9/run,
  and drafts solar_lance+ 16/33 (list deeproot 7/37): the 60-turn
  rollout horizon cannot see the stalls its upgrade picks cause
  (review 7.4 caveat, WP5 note). Not a ceiling column yet - keep
  deeproot as the ceiling reference; a turn-cost term or a longer
  horizon before publishing rollout numbers as "the" ceiling.
- Locked-kit lift stays flat at tier 6 with the repaired deeproot
  (0/3 pairs flagged, lift +2/-1/-1 at n=16): "combos do not fire" was
  not only the candidate-truncation artifact; the review's Block C
  case still stands. Re-run the three rows at 30 seeds
  (SWEEP_SEEDS=30, ~1 h) before any content decision quotes them.

## 2026-09-05b - bump 2: side-rng shop, attribution, quota re-clamp, choice sinks

Block B of docs/PROGRESSION_REVIEW.md 6.2, shipped as one batched sim patch.
The instruments did not change (still v2), so this entry's numbers compare
with the "instrument v2 re-baseline" entry above it and with nothing older.

What changed:

- **Version.** `sim/game.gd` gained `const SIM_VERSION := 2`, the single
  replay-version source; `shell/main.gd` RUN_SAVE_VERSION,
  `tests/regress_lib.gd` and `tests/autopsy.gd` now reference it.
- **Side-rng shop stock.** `_stock_shop` returns `{}` on a shrineless floor
  and otherwise draws the ability from `_side_rng("shop_ability")`, two
  distinct grafts from one `_side_rng("shop_graft")` generator and the item
  from `_side_rng("shop_item")`; shop and supply pods offer base item ids
  only. Map generation is now the only kit/graft/pool/bloom-dependent
  main-rng consumer at floor entry (`test_economy`: "rng independence: 50
  seeds x 5 configs, 0 mismatches").
- **Damage attribution.** Fire tiles carry `by`; enemy-side sources are
  `fire:<by>` and `collision:<aid>`, and the four hardcoded ability strings
  became the casting ability id. Player-side sources are untouched, so
  `death_cause` and the death tables are unchanged.
- **Quota re-clamp.** `_reclamp_quota()` runs at the end of every playing
  `step()`, lowering `green_need` to `greened + _count_corruption()` and
  emitting `quota_reclamp` (plus `stairs_awaken` when the stairs were
  dormant). Enemy-made oil is written `{bloom: 0}`: cleansing it pays no
  bloom but still counts toward `greened`. This is the only intended balance
  change of the bump.
- **Config keys and choice sinks.** `Game.new(seed, {grafts, bloom, ...})`;
  the graft offer is two ids and buying one discards the other; an ability
  bought on a full kit names a drop slot and may never drop a mobility
  ability; press (1) and forge (3) are priced through `Content.SHOP_COSTS`
  so Gouging Prices marks them up and Boarded boards them, and the forge is
  capped at one use per floor.

What this invalidates: **every pre-bump replay hash**. All 28
`tests/regressions/*.json` records carry a new hash and `sim_version: 2`;
seed-to-seed pairing across the bump is void, because removing the two
per-floor main-rng shop draws re-phases every downstream main-rng roll from
floor 1 on. Aggregate win rates still compare (same instruments, same seeds
1..30), and only within this entry's before/after.

### Suite

All green except the playtest gate (below):

- `tests/test_invariants.gd`: "invariants: 1400 generations, 0 violations",
  "floor_def invariants: 11 configs, 1540 generations, 0 violations"
- `tests/test_determinism.gd`: "determinism: OK (55 checks, 7 personas)"
- `tests/test_content.gd`: "shop costs: { heal: 3, ability: 4, graft: 4,
  item: 2, press: 1, forge: 3 }; items: 5 base, 10 total", "content: OK"
- `tests/test_meta.gd`: "meta: OK"
- `tests/test_economy.gd`: "economy: OK (82 checks)" - new suite member
- `tests/test_regressions.gd`: "regressions: 28 ok, 0 failed", and
  `REGRESS_STRICT=1` "regressions: 28 ok, 0 failed"
- `tests/test_shell.gd`: "shell smoke: OK"

### Persona before/after

Before = the instrument-v2 re-baseline entry above (seeds 1..30, tier 0).
After = `=== playtest | bot wanderer,sprout,magpie,fanatic,optimizer,deeproot
| config {  } | seeds 1..30 (30) ===` and
`=== playtest | bot deeproot_rollout | config {  } | seeds 1..30 (30) ===`.
Wilson 95% as printed.

| persona | before | after | moved outside CI? |
|---|---|---|---|
| optimizer | 14/30 = 47% [30, 64] | 12/30 = 40% [25, 58], avg floor 5.8 | no |
| magpie | 2/30 = 7% [2, 21] | 4/30 = 13% [5, 30], avg floor 4.9 | no (but see the 100-seed row) |
| sprout | 1/30 = 3% [1, 17], avg floor 3.9 | 0/30 = 0% [0, 11], avg floor 3.5 | no |
| fanatic (legacy seed-split) | 5/30 = 17% [7, 34] | 7/30 = 23% [12, 41], avg floor 5.4 | no |
| deeproot | 27/30 = 90% [74, 97] | 24/30 = 80% [63, 90], avg floor 6.9 | no |
| deeproot_rollout | 26/30 = 87% [70, 95] | 27/30 = 90% [74, 97], avg floor 7.0 | no |
| wanderer | 0/30, floor 1.0 | 0/30 = 0% [0, 11], floor 1.0 | no |
| deeproot tier 6 | 18/30 = 60% [42, 75] | not re-measured (deferred with the grafted-ceiling re-judgement) | - |

Zero timeouts and zero illegal actions for all seven personas. No persona's
point estimate left the other run's interval; the bump is win-rate neutral at
30 seeds by that test.

### KPI block (playtest, 30 seeds, tier 0)

strike/sig/terr = shares of enemy damage, cmb = combos/run, conv = bloom
spent/earned, ent = kit entropy bits, shrine = shrine turns/run, unspent =
unspent charge per end_turn, stall = stall floors over 30 runs, qu =
quota-unmet deaths, dmg = player damage per run.

| persona | strike | sig | terr | cmb | conv | ent | shrine | unspent | stall | qu | dmg |
|---|---|---|---|---|---|---|---|---|---|---|---|
| wanderer | 0.31 | 0.00 | 0.02 | 30.67 | 0.00 | 0.00 | 0.53 | 0.10 | 24 | 29 | 43.4 |
| sprout | 0.35 | 0.21 | 0.02 | 6.77 | 0.15 | 4.45 | 1.47 | 0.36 | 14 | 3 | 34.4 |
| magpie | 0.35 | 0.27 | 0.01 | 6.33 | 0.47 | 4.22 | 8.33 | 0.89 | 20 | 4 | 33.7 |
| fanatic | 0.20 | 0.24 | 0.05 | 11.37 | 0.26 | 3.65 | 0.57 | 0.74 | 6 | 3 | 26.8 |
| optimizer | 0.48 | 0.13 | 0.02 | 3.47 | 0.32 | 4.57 | 1.10 | 0.56 | 2 | 4 | 21.9 |
| deeproot | 0.09 | 0.37 | 0.15 | 14.07 | 0.01 | 3.83 | 0.20 | 0.53 | 7 | 0 | 7.5 |
| deeproot_rollout | 0.07 | 0.22 | 0.13 | 10.47 | 0.01 | 4.08 | 0.27 | 0.63 | 4 | 0 | 4.4 |

New bump-2 counters, over 30 runs each:

| persona | graft offers discarded | full-kit ability buys | quota reclamps | upcycles (press/forge) |
|---|---|---|---|---|
| wanderer | 0 | 0 | 0 | 0/0 |
| sprout | 11 | 5 | 0 | 0/0 |
| magpie | 107 | 75 | 0 | 0/0 |
| fanatic | 40 | 2 | 0 | 0/0 |
| optimizer | 46 | 13 | 0 | 0/0 |
| deeproot | 0 | 0 | 0 | 0/0 |
| deeproot_rollout | 0 | 0 | 0 | 0/0 |

**`quota_reclamp` fired 0 times in 550 bot runs** (7 personas x 30 in the
playtest, 8 x 30 optimizer graft-sweep rows, 100 magpie seeds). The only
intended balance change of the bump is therefore unexercised by every bot;
its only coverage is synthetic (`tests/test_economy.gd` section g and
`tests/regressions/blockb_quota_reclamp.json`). Nothing here says the
strandable green gate is closed *in play* - it says the code path exists and
no bot has ever walked into the case. **No press or forge use either**, so
the two new bloom sinks are unmeasured.

Attribution now resolves every fire and collision hit (the `env` fallback
never appeared, and enemy igniters name themselves):

| persona | fire damage by igniter | collision damage by ability |
|---|---|---|
| wanderer | solar_lance 5 | - |
| sprout | solar_lance 15, solar_lance+ 8, cinder_mite 3 | - |
| magpie | solar_lance 17, cinder_mite 10, sun_flare 5, solar_lance+ 4, furnace_core 2 | water_jet 10 |
| fanatic | solar_lance 31, cinder_mite 26, solar_lance+ 2, sun_flare 1 | water_jet 30 |
| optimizer | cinder_mite 29, solar_lance 13, sun_flare 1 | water_jet 6 |
| deeproot | solar_lance 51, cinder_mite 33, sun_flare 12, solar_lance+ 11, furnace_core 6, sun_flare+ 3 | water_jet 228, water_jet+ 30 |
| deeproot_rollout | solar_lance 53, cinder_mite 33, solar_lance+ 19, sun_flare 11, furnace_core 5, sun_flare+ 3 | water_jet+ 132, water_jet 78 |

`tally.kpis()` derives families through `base_id(src_family(src))`, so
signature/terrain shares keep their pre-bump meaning across the rename; the
raw `by src` line is where the new detail lives.

### Fanatic archetypes

Before = the v2 re-baseline table (FANATIC_SEEDS=30). After =
`=== measure_fanatic | bot fanatic | config {  } | seeds 1..30 (30) ===`,
"builds: pyro, gardener, turtle, shover, pyro_nolance, shover_nolance, ember,
anchor  (pool 14 ids)".

| build | before | after | avg floor | core-complete (never) | sig | strike |
|---|---|---|---|---|---|---|
| pyro | 8/30 [14, 44] | 5/30 [7, 34] | 5.7 | 3.4 (40%) | 0.03 | 0.10 |
| pyro_nolance | 8/30 [14, 44] | **15/30 [33, 67]** | 6.3 | 4.4 (47%) | 0.35 | 0.29 |
| ember | 9/30 [17, 48] | 9/30 [17, 48] | 5.8 | 5.4 (73%) | 0.49 | 0.15 |
| gardener | 11/30 [22, 54] | 6/30 [10, 37] | 5.5 | 4.8 (67%) | 0.40 | 0.32 |
| shover | 5/30 [7, 34] | 6/30 [10, 37] | 5.6 | 5.2 (87%) | 0.20 | 0.03 |
| shover_nolance | 5/30 [7, 34] | 5/30 [7, 34] | 4.6 | 4.2 (83%) | 0.64 | 0.13 |
| anchor | 6/30 [10, 37] | 3/30 [3, 26] | 4.3 | 7.0 (97%) | 0.00 | 0.56 |
| turtle | 1/30 [1, 17] | 1/30 [1, 17] | 4.3 | never (100%) | 0.06 | 0.60 |
| total | 53/240 = 22% | 50/240 = 21% | - | - | - | - |

One timeout: shover_nolance seed 1 floor 4 (the Block A table recorded no
timeout column, so this is not a comparison).
Every build stays above zero, so the hard fanatic target holds. The only row
that moved outside both intervals is **pyro_nolance 8/30 -> 15/30**: 50% is
above the old [14, 44] and 27% is below the new [33, 67]. Its core-complete
floor improved 4.7 -> 4.4 and never-completed 63% -> 47%, which is the shape
you would expect if the two-graft shrine and the full-kit replacement buy let
a lance-free fire build assemble itself faster; unverified, and 30 seeds is
one sample. gardener 11/30 -> 6/30 is borderline (20% sits just under the old
[22, 54]). Watch both.

### Graft sweep (new runner)

`=== sweep_grafts | bot optimizer | config {  } | seeds 1..30 (30) ===`,
"grafts: deep_cells, verdant_pulse, thick_bark, bloom_surge, solar_core,
carapace". Each row pre-installs its graft(s) before floor 1 on the same
seeds as the base row; delta is against the base row and the sign test is
paired.

| row | wins | CI | avg floor | delta | discordant | sign_p | cmb/run | conv | dmg | turns(w) |
|---|---|---|---|---|---|---|---|---|---|---|
| (no graft) | 12/30 | [25, 58] | 5.8 | +0 | 0:0 | 1.00 | 3.47 | 0.32 | 21.9 | 89 |
| deep_cells | 14/30 | [30, 64] | 6.0 | +2 | 5:3 | 0.73 | 3.57 | 0.39 | 21.4 | 85 |
| verdant_pulse | 16/30 | [36, 70] | 6.2 | +4 | 6:2 | 0.29 | 3.53 | 0.33 | 31.8 | 88 |
| thick_bark | 14/30 | [30, 64] | 5.9 | +2 | 5:3 | 0.73 | 3.63 | 0.35 | 21.1 | 88 |
| bloom_surge | 15/30 | [33, 67] | 6.2 | +3 | 5:2 | 0.45 | 3.53 | 0.27 | 20.5 | 85 |
| solar_core | 19/30 | [46, 78] | 6.3 | +7 | 10:3 | 0.09 | 3.90 | 0.40 | 17.3 | 73 |
| carapace | 13/30 | [27, 61] | 5.7 | +1 | 5:4 | 1.00 | 3.43 | 0.36 | 29.5 | 91 |
| all 6 | 19/30 | [46, 78] | 6.3 | +7 | 10:3 | 0.09 | 4.13 | 0.05 | 34.1 | 76 |

No row clears p < 0.05, so nothing is flagged. `solar_core` is the only
candidate signal (+7, 10:3 discordant, p=0.09, damage taken 21.9 -> 17.3 and
turns-on-wins 89 -> 73); per the Method rule it needs an out-of-sample
30-seed re-check (`SWEEP_SEED_FROM=101`) before anyone acts on it. The "all
6" row is *not* six grafts' worth of power: owning six drives
`shop_cost("graft")` to 16, so the run buys nothing (bloom conversion 0.05,
grafts bought {}) and lands exactly on solar_core's number while taking the
most damage of any row (34.1).

Bot graft demand is now visible: the optimizer buys 46 grafts and discards 46
offers over 30 runs, magpie 110/107. No bot chooses *between* the two offers
on merit - every persona takes pick 0.

### Tier ladder

`=== sweep_tiers | bot optimizer | config {  } | seeds 1..35 (35) ===`,
35 seeds so the 10% Wilson-upper gate binds. Exit 0, no tier flagged
unwinnable.

| tier | wins | CI | avg floor |
|---|---|---|---|
| 0 (base) | 13/35 | [23, 54] | 5.9 |
| 1 (Thicker Smog) | 13/35 | [23, 54] | 5.9 |
| 2 (Busy Vents) | 13/35 | [23, 54] | 5.9 |
| 3 (Rich Veins) | 16/35 | [30, 62] | 6.1 |
| 4 (Dim Skies) | 13/35 | [23, 54] | 5.8 |
| 5 (Gouging Prices) | 13/35 | [23, 54] | 5.8 |
| 6 (Hardened Plating) | 5/35 | [6, 29] | 4.5 |
| 7 (Sharpened Drills) | 4/35 | [5, 26] | 4.5 |
| 8 (Overcharged Core) | 6/35 | [8, 33] | 4.8 |

Zero timeouts on every tier. Tiers 0-5 are one noise band, the stat tiers 6-8
still bind heuristic play, and Gouging Prices now also marks up the press and
the forge (no bot exercises either, so that markup is untested in play).

### The critic's base-only-pods check (review 6.2, last paragraph)

Before (Block A): deeproot 27/30 = 90% [74, 97], 17 item uses per 30 runs
with `clearair_pod+` 5 of them. After
(`=== items_probe | bot deeproot | config {  } | seeds 1..30 (30) ===`,
the same seeds and config as the playtest deeproot row):

- deeproot 24/30 = 80% [63, 90], avg floor 6.9, 0 timeouts.
- item uses by id: `{clearair_pod: 14, iron_seed: 6, balm_fruit: 10,
  spore_vial: 5, sun_capsule: 3}` = 38 uses, **zero `+` items**; pickups 72,
  satchel_full 44.

**Verdict: not a measured nerf.** 80% lies inside the Block A interval
[74, 97] and the two intervals overlap over [74, 90]. Losing `+` items from
pods did not cost deeproot wins at 30 seeds; it more than doubled item use
(17 -> 38), because base pods stock things deeproot will actually spend
(`clearair_pod` 14) instead of an occasional strong upgrade. The satchel now
overflows 44 times per 30 runs, which is the real cost - the press is the
only route to `+` items and deeproot never buys one. A 100-seed check is the
only thing that would tighten this; not run.

### Regression corpus regen

28 records (24 pre-existing + 4 new `blockb_*`: quota_reclamp, graft_buy,
ability_drop_buy, forge_once). Every one of the 28 carries a new top-level
hash and `sim_version: 2`; 0 hashes survived the bump. Of the 24 pre-existing
records, **17 changed floor/turns and 7 did not** (the three `det_wanderer_*`,
which never reach a shrine or any main-rng consumer past mapgen, and the four
hand-scripted `combo_*` demos). Six flipped outcome:

- win -> loss: `canary_fanatic_s1` (7/66 -> floor 5/101),
  `det_deeproot_s42` (7/61 -> floor 5/107), `det_sprout_s42` (7/64 -> floor
  5/184)
- loss -> win: `det_magpie_s3` (floor 3 -> 7), `det_magpie_s42` (floor 6 ->
  7), `det_optimizer_s11` (floor 4 -> 7)

Win count across the 24 is 6 before and 6 after. Cause is not a difficulty
change: removing the two per-floor main-rng shop draws re-phases every
downstream main-rng roll, so a seed is a different game after the bump. These
outcomes are corpus assertions, never a balance argument.

### Gate verdict

`tests/playtest.gd` at 30 seeds, gate ON: **exit 1, "gate: 1 FAIL"**.

```
PASS wanderer 0 wins, avg floor <= 2: 0 wins, avg floor 1.00
PASS sprout wins rare (<= 1 per 30 seeds): 0/30
FAIL magpie canary <= 5%: 4/30 CI [5%, 30%] (fails when the lower bound clears the band)
PASS optimizer band 35-65%: 12/30 CI [25%, 58%]
PASS optimizer timeouts == 0: 0
PASS deeproot band 70-90%: 24/30 CI [63%, 90%]
PASS deeproot timeouts == 0: 0
```
(plus "illegal actions == 0: 0" for all six personas, and all-PASS for
deeproot_rollout in its own run.)

The magpie canary is followed up at 100 seeds as the watch list demands:
`=== verify_kit | bot magpie | config {  } | seeds 1..100 (100) ===`,
**20/100 = 20% wins, win CI [13%, 29%]**, avg floor 5.0, turns on wins 178.2,
0 timeouts, 0 illegal. That interval excludes the 0-5% canary band outright.
It does still overlap the Block A magpie interval (2/30 = 7% [2, 21]) over
[13, 21], so this is not formally a change from the last v2 measurement - it
is a decisive break of the *band*, on the largest sample the canary has had
under v2. Full greed is no longer losing almost always.

The mechanism is not proven, but the tally names two suspects, both from item
5 of this bump and both magpie-shaped: over 100 runs magpie makes **262
full-kit ability replacement buys** (an action that did not exist before -
with a full kit an ability purchase used to be illegal, so magpie's surplus
bloom had nowhere to go) and **discards 364 graft offers**, i.e. it sees two
grafts a shrine instead of one. Bloom conversion is 0.50 and kit entropy 5.59
bits, both the highest ever recorded for the persona. "Choice sinks, no new
power" appears to be new power for the one persona that always had spare
bloom.

**A/B, run after the measurement pass (sim variants as probe subclasses over
`legal_actions()`/`_act_buy`, bots untouched, seeds 1..100 for magpie and
1..30 for optimizer, every row on the bump-2 sim unless marked):**

| variant | magpie 100 seeds | optimizer 30 seeds |
|---|---|---|
| pre-bump HEAD (`b07d284`, clean worktree) | 6/100 = 6% [3, 12], ability buys 93 | 14/30 (Block A entry) |
| bump 2 as shipped | 20/100 = 20% [13, 29], ability buys 364 (262 with a drop) | 12/30 [25, 58], 27 buys (13 drops) |
| bump 2, full-kit ability purchase never legal | 10/100 = 10% [6, 17], ability buys 102 (0 drops) | 12/30 [25, 58], 14 buys |
| bump 2, full-kit purchase priced at 2x (8 bloom) | 17/100 = 17% [11, 26], ability buys 330 (228 drops) | 11/30 [22, 54], 25 buys (11 drops) |

The lever is the full-kit ability purchase itself: removing it takes magpie
from 20/100 to 10/100, whose interval overlaps the pre-bump 6/100, while
doubling its price only trims it to 17/100 (magpie earns about 65 bloom a
run, so 8 bloom a floor is still cheap). The optimizer does not react to any
variant. The two-graft offer is exonerated as the main cause: it stays in the
no-drop row and the win rate still halves. Decision pending: the mechanic
fixed defect 8 (a dead shop slot at a full kit) but is measured power for
greed; either it goes back out, or it is gated on something other than bloom
(the canary band is the target, not the thing to move).

## 2026-09-05c - bump 2 revision: full-kit ability purchase removed

The project owner ruled on the decision left pending in the entry above: the
full-kit drop-slot ability purchase goes back out and review defect 8 (a dead
shop slot once you are kitted out) is accepted as-is - "a dead shop doesn't
feel bad when you're already kitted out, seems like an acceptable defect".
With a full kit the shrine's ability card is simply not for sale:
`legal_actions` offers `{"type": "buy", "item": "ability"}` only while
`kit.size() < _kit_max()`, exactly as before bump 2.

Everything else from bump 2 stays: the graft pick, press/forge pricing and
gating, one forge per floor, mobility never scrapped by the forge, the
side-rng shop, damage attribution, the quota re-clamp, base-only shop/pod
items, and the `grafts`/`bloom` config keys.

**`Game.SIM_VERSION` stays 2.** Bump 2 never reached a phone, so no saved run
log exists that was written against the drop-slot purchase; this is a
revision of the same bump, not a second one. `shell/main.gd`
RUN_SAVE_VERSION reads the same constant and is unchanged.

Instruments are still v2, so this entry's numbers compare with the bump-2
entry above it and with the instrument-v2 re-baseline, and with nothing older.

### Suite

All green except the playtest gate (below), which fails exactly as it did in
bump 2 as shipped:

- `tests/test_invariants.gd`: "invariants: 1400 generations, 0 violations",
  "floor_def invariants: 11 configs, 1540 generations, 0 violations"
- `tests/test_determinism.gd`: "determinism: OK (55 checks, 7 personas)"
- `tests/test_content.gd`: "shop costs: { heal: 3, ability: 4, graft: 4,
  item: 2, press: 1, forge: 3 }; items: 5 base, 10 total", "content: OK"
- `tests/test_meta.gd`: "meta: OK"
- `tests/test_economy.gd`: "economy: OK (84 checks)" (82 -> 84; the drop-slot
  section became "ability buy: full kit offers 0 ability buys, 3-kit bought
  root_wall (shop stocked grow_spike)")
- `tests/test_regressions.gd`: "regressions: 27 ok, 0 failed", and
  `REGRESS_STRICT=1` "regressions: 27 ok, 0 failed" (28 -> 27: the
  `blockb_ability_drop_buy.json` record was deleted with the mechanic)
- `tests/test_shell.gd`: "shell smoke: OK"

### Persona table

Block A v2 = the instrument-v2 re-baseline entry; bump 2 as shipped = the
entry directly above; this revision =
`=== playtest | bot wanderer,sprout,magpie,fanatic,optimizer,deeproot |
config {  } | seeds 1..30 (30) ===` and
`=== playtest | bot deeproot_rollout | config {  } | seeds 1..30 (30) ===`.
All three columns are seeds 1..30, tier 0, Wilson 95% as printed.

| persona | Block A v2 | bump 2 as shipped | this revision |
|---|---|---|---|
| wanderer | 0/30, floor 1.0 | 0/30 = 0% [0, 11], floor 1.0 | 0/30 = 0% [0, 11], floor 1.0 |
| sprout | 1/30 = 3% [1, 17], floor 3.9 | 0/30 = 0% [0, 11], floor 3.5 | 1/30 = 3% [1, 17], floor 3.5 |
| magpie | 2/30 = 7% [2, 21] | 4/30 = 13% [5, 30], floor 4.9 | 4/30 = 13% [5, 30], floor 3.8 |
| fanatic (legacy seed-split) | 5/30 = 17% [7, 34] | 7/30 = 23% [12, 41], floor 5.4 | 7/30 = 23% [12, 41], floor 5.4 |
| optimizer | 14/30 = 47% [30, 64] | 12/30 = 40% [25, 58], floor 5.8 | 12/30 = 40% [25, 58], floor 5.9 |
| deeproot | 27/30 = 90% [74, 97] | 24/30 = 80% [63, 90], floor 6.9 | 24/30 = 80% [63, 90], floor 6.9 |
| deeproot_rollout | 26/30 = 87% [70, 95] | 27/30 = 90% [74, 97], floor 7.0 | 28/30 = 93% [79, 98], floor 7.0 |

Zero timeouts and zero illegal actions for all seven personas. Five of the
seven win counts are byte-identical to the shipped column; the two that moved
are one win each (sprout 0 -> 1, deeproot_rollout 27 -> 28) and both point
estimates sit inside the other column's interval, except sprout's shipped 0%
which falls one point under the new [1, 17] - a one-win difference, not a
signal. At 30 seeds the removal is win-rate neutral by that test, which is
the expected result: the A/B said the lever only bites on the greed persona
at 100 seeds.

### KPI block (playtest, 30 seeds, tier 0)

Same derivation and columns as the bump-2 KPI table: strike/sig/terr = shares
of enemy damage, cmb = combos/run, conv = bloom spent/earned, ent = kit
entropy bits, shrine = shrine turns/run, unspent = unspent charge per
end_turn, stall = stall floors over 30 runs, qu = quota-unmet deaths, dmg =
player damage per run.

| persona | strike | sig | terr | cmb | conv | ent | shrine | unspent | stall | qu | dmg |
|---|---|---|---|---|---|---|---|---|---|---|---|
| wanderer | 0.31 | 0.00 | 0.02 | 30.67 | 0.00 | 0.00 | 0.53 | 0.10 | 24 | 29 | 43.4 |
| sprout | 0.35 | 0.21 | 0.01 | 7.00 | 0.13 | 4.45 | 1.00 | 0.36 | 14 | 3 | 34.6 |
| magpie | 0.42 | 0.24 | 0.01 | 2.67 | 0.49 | 4.28 | 22.70 | 0.74 | 18 | 4 | 31.8 |
| fanatic | 0.20 | 0.24 | 0.05 | 11.37 | 0.25 | 3.59 | 0.57 | 0.75 | 6 | 3 | 26.5 |
| optimizer | 0.44 | 0.12 | 0.02 | 3.77 | 0.27 | 4.23 | 1.33 | 0.54 | 2 | 4 | 22.6 |
| deeproot | 0.09 | 0.35 | 0.15 | 14.10 | 0.01 | 3.83 | 0.23 | 0.55 | 7 | 0 | 7.5 |
| deeproot_rollout | 0.07 | 0.24 | 0.13 | 10.97 | 0.01 | 4.32 | 0.23 | 0.39 | 1 | 0 | 2.8 |

The `full-kit ability buys` column of the bump-2 counter table is gone with
the counter (`tests/tally.gd` no longer has `ability_drop_buys`, and the
choice-sinks line now prints "graft offers discarded N  quota reclamps N").
The remaining two sinks over 30 runs each: graft offers discarded - wanderer
0, sprout 12, magpie 83, fanatic 40, optimizer 44, deeproot 0,
deeproot_rollout 0; **`quota_reclamp` still fired 0 times in every run of
this entry**, so the one intended balance change of bump 2 remains unexercised
by every bot. Upcycles are still 0/0 for every persona: press and forge stay
dead sinks.

### Magpie canary at 100 seeds

`=== verify_kit | bot magpie | config {  } | seeds 1..100 (100) ===`:
**10/100 = 10% wins, win CI [6%, 17%]**, avg floor 3.7, turns on wins 196.7,
damage taken 31.5/run, 1 timeout, 0 illegal, ability buys 102 (all into a
free kit slot; the drop shape no longer exists).

- **Against the A/B prediction: exact.** The bump-2 A/B row "full-kit ability
  purchase never legal" predicted 10/100 = 10% [6, 17] with 102 ability buys.
  The shipped revision measures 10/100 = 10% [6, 17] with 102 ability buys.
  The probe-subclass A/B and the real removal agree to the win, the interval
  and the buy count, so the attribution in the entry above is confirmed on
  the shipped code.
- **Against bump 2 as shipped: a real drop.** 20/100 = 20% [13, 29] ->
  10/100 = 10% [6, 17]. Each point estimate lies outside the other's
  interval, so this is a move by the Method rule, on the largest sample the
  canary has under v2.
- **Against pre-bump: back inside noise.** Pre-bump HEAD was 6/100 = 6%
  [3, 12]; [6, 17] and [3, 12] overlap over [6, 12], so the revision is not
  distinguishable from the pre-bump canary at 100 seeds.
- **Against the 0-5% band: still out.** [6, 17] sits wholly above 5%, so the
  canary target is not met and the gate still fails. It was not met pre-bump
  either (6/100 = 6% [3, 12] also clears 5%). Removing the purchase undid the
  bump's damage; it did not fix the older drift, which is a separate question
  and not this revision's job.

### Gate verdict

`tests/playtest.gd` at 30 seeds, gate ON: **exit 1, "gate: 1 FAIL"** - the
same single failure as bump 2 as shipped, at the same 4/30. (2026-09-05d
records what the line measures and the owner's options; the gate constant is
unchanged and the line stays red until one is taken.)

```
PASS wanderer 0 wins, avg floor <= 2: 0 wins, avg floor 1.00
PASS wanderer illegal actions == 0: 0
PASS sprout wins rare (<= 1 per 30 seeds): 1/30
PASS sprout illegal actions == 0: 0
FAIL magpie canary <= 5%: 4/30 CI [5%, 30%] (fails when the lower bound clears the band)
PASS magpie illegal actions == 0: 0
PASS fanatic illegal actions == 0: 0
PASS optimizer band 35-65%: 12/30 CI [25%, 58%]
PASS optimizer timeouts == 0: 0
PASS optimizer illegal actions == 0: 0
PASS deeproot band 70-90%: 24/30 CI [63%, 90%]
PASS deeproot timeouts == 0: 0
PASS deeproot illegal actions == 0: 0
gate: 1 FAIL
```

`PLAYTEST_BOTS=deeproot_rollout PLAYTEST_SEEDS=30`: exit 0.

```
PASS deeproot_rollout illegal actions == 0: 0
gate: all PASS
```

### Regression corpus re-record

The 20 bot-derived records (`det_*`, `canary_*`) were re-played on the final
sim **and** the final bots and re-stamped with `regress_lib.record_run`
(expect + hash); the hand-scripted `combo_*` and the remaining three
`blockb_*` records were not touched. `blockb_ability_drop_buy.json` was
deleted with the mechanic, so the corpus is **28 -> 27 records**.

15 of the 20 came out byte-identical - the bots only differ where a full kit
met a stocked, affordable shrine ability, which never happened on these seeds
for wanderer, sprout, fanatic, deeproot or optimizer seed 11. Five changed:

| record | before (bump 2) | after (this revision) | cause |
|---|---|---|---|
| det_magpie_s11 | died floor 4, 224 turns, 551 acts | died floor 2, 134 turns, 344 acts | drop buys gone |
| det_magpie_s3 | WON floor 7, 185 turns, 789 acts | WON floor 7, 244 turns, 974 acts | drop buys gone |
| det_magpie_s42 | WON floor 7, 103 turns, 523 acts | WON floor 7, 133 turns, 635 acts | drop buys gone |
| det_optimizer_s3 | WON floor 7, 94 turns, 445 acts | WON floor 7, 100 turns, 419 acts | drop buys gone |
| det_optimizer_s42 | died floor 7, 93 turns, 466 acts | WON floor 7, 77 turns, 372 acts | drop buys gone |
| det_magpie_s11 hash | 3312c0834de6701d... | c29cc04df667a9b7... | changed |
| det_magpie_s3 hash | e2faee8af7b10a17... | b057818aa18d5810... | changed |
| det_magpie_s42 hash | 7e83e12f19e3fb73... | a59f79e186a0cd2f... | changed |
| det_optimizer_s3 hash | 835adeb1103d91b7... | 1ed42eb6859e6a1f... | changed |
| det_optimizer_s42 hash | 7deff2605d6932e6... | d5e6c416d88a4d81... | changed |
| the other 15 det_*/canary_* | - | byte-identical | bot never hit the case |

One outcome flip, `det_optimizer_s42` loss -> win. That is a corpus assertion,
never a balance argument: the removed action re-phases the persona's own
choice sequence from the first full-kit shrine on, so a seed is a different
game after the removal for any bot that used to buy by replacement.

### Anything else that moved

- **magpie shrine turns/run 8.33 -> 22.70** (30 seeds). Greed now stands on
  the shrine far longer per run while buying strictly less: combos/run
  6.33 -> 2.67 and avg floor 4.9 -> 3.8 on the same four wins. With no
  replacement buy to spend on, magpie's shrine loop reduces to grafts, heals
  and items and it burns clock doing it. No CI attaches to these; flagged for
  the watch list, not patched.
- **deeproot_rollout 27/30 -> 28/30** with zero purchases in either run
  (`buys { item: 4 }`). The searcher plans over `legal_actions`, so removing
  a legal action changes its plan even where it never bought; one win, inside
  both intervals.
- **magpie logged 1 timeout in 100 seeds** (`verify_kit`). The shipped bump-2
  100-seed row recorded 0. One run in a hundred against an "all runs end"
  target is worth a re-check if it grows; not investigated here.
- Nothing else left a CI. The optimizer, fanatic, deeproot and wanderer rows
  are unchanged at 30 seeds, and no suite member changed a count except
  `test_economy` (82 -> 84 checks) and `test_regressions` (28 -> 27 records),
  both of which are direct consequences of the edit.

## 2026-09-05d - magpie canary: status after the revision (no sim change, gate unchanged)

The bump-2 revision above leaves `tests/playtest.gd` red on one line -
`FAIL magpie canary <= 5%: 4/30 CI [5%, 30%]` - and this entry records what
that line is and is not measuring. The gate constant is **unchanged**
(`MAGPIE_MAX_LOWER := 0.05`, the design target); moving it is the owner's
call, not a measurement's, so the options are listed at the end instead.

### What the 5% line separates

Every number below is instrument v2, tier 0, base pool, Wilson 95%.

| tree | 30 seeds | 5% line | 100 seeds | 5% line |
|---|---|---|---|---|
| pre-bump HEAD (`b07d284`) | 2/30 [2, 21] | PASS | 6/100 [3, 12] | PASS |
| bump 2 as shipped | 4/30 [5, 30] | FAIL | 20/100 [13, 29] | FAIL |
| bump 2 revision (this tree) | 4/30 [5, 30] | FAIL | 10/100 [6, 17] | FAIL |

At 30 seeds the line separates 2/30 from 4/30 - a two-win gap - and returns
the same verdict for the shipped bump and for the revision that undid it,
whose 100-seed intervals ([13, 29] vs [6, 17]) do not overlap. The two trees
it cannot tell apart at 100 seeds, pre-bump 6/100 [3, 12] and this tree's
10/100 [6, 17], overlap over [6, 12]. So the 30-seed line reports seed noise
around a true rate near 10%, and the 100-seed line says greed sits at about
twice its 0-5% design target. That is older drift: the pre-bump point
estimate was already 6%, over target, with only the interval covering 5%.
The bump-2 regression (20%) is undone; the drift is not.

### Trip points, for whoever decides

Wilson lower bounds, so a threshold can be argued instead of guessed:
2/30 1.9% | 4/30 5.3% | 6/30 9.5% | 7/30 11.8% | 6/100 2.8% | 10/100 5.5% |
17/100 10.9% | 20/100 13.3%. A 10% line would pass this tree at 30 and 100
seeds, still fail both bump-2 configurations at 100 seeds (17/100 and
20/100), and trip a 30-seed run from 7/30 (23%) up; a 5% line trips a
30-seed run from 4/30 (13%) up, i.e. on one win at the current true rate.

### Options (owner decision, none taken here)

1. Re-tune greed against the 0-5% target as its own change with a 100-seed
   before/after (the honest fix; what makes magpie win is now measurable:
   bloom conversion 0.50, kit entropy 5.6 bits, 293 graft buys per 100 runs).
2. Accept 10% as the gate's trip line (one constant in `tests/playtest.gd`)
   with the 0-5% figure kept as the design target in the Targets table.
3. Leave the line red until 1 is done and read the gate as "12 of 13 pass".

Until one of these is taken the default 30-seed gated playtest exits 1 on
this line alone; every other gate line passes (see 2026-09-05c).

## Watch list

- Turtle canary baseline is now 5/25 (post loop-fixes). A sharp rise from
  there still means the clock has weakened.
- Deeproot eval bias: flat +12/shield point with no tempo cost makes cheap
  shield riders strictly-positive spam (see Anchor Roots collapse). Any
  future ability with a small self-buff rider needs a deeproot solo check
  before shipping; thorn_shield's persistent mild underperformance in pair
  tables is probably the same bleed.
- Magpie is now a greed canary at 0-5% (see 2026-08-08 magpie entry);
  watch for rises, not falls. It was sitting at exactly 5/100 since the
  cleanse-smog-relief change; under instrument v2 it measures **10/100
  [6, 17]** (2026-09-05c) and pre-bump measured 6/100 [3, 12], so the 0-5%
  target has been unmet for longer than bump 2. The 30-seed gate line is red
  at 4/30 and stays so until the owner picks an option in 2026-09-05d
  (re-tune greed, move the trip line to 10%, or read the gate as 12 of 13):
  greed at ~2x its design target is an open balance question and the next
  100-seed rise above [6, 17] is the real signal.
- Fanatic cannot demo control archetypes (shover 2-3/25 while the
  ceiling wins 45% with the same kit): judge push/pull changes with
  deeproot forced-kit runs, not the fanatic number.
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

### Bump-2 additions (2026-09-05b)

- **Magpie broke the canary - RESOLVED by removal (2026-09-05c).** As
  shipped, bump 2 put magpie at 4/30 in the gated playtest (FAIL) and 20/100
  = 20% [13, 29] at `verify_kit` against a 0-5% band - the one thing in bump 2
  that moved a target. The A/B attributed it to the full-kit ability
  replacement buy (262 of them over 100 runs; no-drop 10/100 [6, 17] vs
  shipped 20/100 [13, 29] vs pre-bump 6/100 [3, 12], and a 2x price did not
  fix it at 17/100). The owner removed the purchase path (defect 8 accepted:
  a dead shop slot at a full kit is fine). New canary number:
  **10/100 = 10% [6, 17]**, exactly the A/B's prediction, indistinguishable
  from pre-bump 6/100 [3, 12]. The bump-2 regression is undone; the band
  itself is still not met (the interval clears 5% and the 30-seed gate still
  reads FAIL magpie 4/30 [5, 30]), which is the older drift, not this bump's.
  Two magpie metrics moved without a CI to judge them by: shrine turns/run
  8.33 -> 22.70 and combos/run 6.33 -> 2.67 on the same four wins - greed now
  loiters at a shrine it can spend less at. Watch those, and the 1 timeout in
  100 magpie runs, before any further shop content.
- **The quota re-clamp is unexercised.** 0 `quota_reclamp` events over 550
  bot runs. Every claim that the strandable green gate is closed rests on
  `tests/test_economy.gd` and `tests/regressions/blockb_quota_reclamp.json`,
  not on play. A first deliberate probe - optimizer with a locked
  lance/sun_flare/water_jet kit (`VERIFY_EXTRAS=sun_flare,water_jet`, 30
  seeds, 6/30 wins) - still fired it 0 times: bots cleanse the quota before
  they burn or wash the rest. A persona that burns oil first, or a
  fixed_floor pump-jack map driven to the strand case, is still the missing
  measurement.
- **Press and forge are dead sinks so far.** 0/0 upcycles for every persona
  in every run of this entry, so `shop_cost("press")`/`shop_cost("forge")`,
  the one-forge-per-floor cap and the Gouging Prices markup on both are all
  untested in play. No bot scores a purchase against keeping the bloom.
- **fanatic pyro_nolance 8/30 -> 15/30** was the only archetype row outside
  both intervals; gardener 11/30 -> 6/30 was borderline. Out-of-sample
  re-check (`FANATIC_SEEDS=30 FANATIC_SEED_FROM=101`): pyro_nolance 12/30
  [25, 58], gardener 15/30 [33, 67] - both back inside every earlier
  interval, so noise, not a shift.
- **solar_core replicates, hard.** In-sample +7 wins (10:3, p=0.09); the
  out-of-sample run (`SWEEP_SEEDS=30 SWEEP_SEED_FROM=101 SWEEP_GRAFTS=solar_core`,
  optimizer) gives **25/30 [66, 93] vs base 10/30 [19, 51], +15, discordant
  16:1, sign p=0.00**, damage taken 27.6 -> 13.6, turns-on-wins 90 -> 70.
  A pre-installed +1 regen is worth about +50 points of win rate to the
  heuristic bot; the other five grafts sit within noise. This is the first
  graft number that survives the Method rule and it says the graft table is
  one lever plus five fillers. Not patched here (Block C owns graft values).
- **Deeproot's satchel overflows 44 times per 30 runs** with base-only pods
  (item uses 17 -> 38, wins unchanged within CI). Consumable supply now
  exceeds demand at the ceiling; the press is the only `+`-item route and no
  bot uses it.
- **deeproot tier 6 was not re-measured.** The Block A row (18/30 = 60%
  [42, 75]) is the last number for it, and review 6.2 defers the tier 6-8
  re-judgement to a grafted ceiling. Do not quote the old row next to bump-2
  tier-0 numbers without saying so.
- **`sweep_lib.CAVEAT_LOCKED` changed meaning.** Locked `{kit: K, pool: K}`
  configs now start a seed from the same map and rng state as any open-pool
  config, so locked and open rows pair again; any older text saying the shop
  consumes a main-rng draw is wrong from bump 2 on.
