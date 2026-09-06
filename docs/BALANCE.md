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
| magpie    | 0–5% design target, top bloom; gate trips at a 10% CI lower bound | full greed loses to the current game almost always; a RISE means greed got cheap (canary, like turtle). Under instrument v2 the recorded baseline is 10/100 [6, 17]; a 100-seed lower bound clearing 17% is the signal — see 2026-09-05d |
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
same single failure as bump 2 as shipped, at the same 4/30. (Resolved in
2026-09-05d by re-deriving the gate's trip line to 10%; the sim and the 4/30
measurement below are unchanged.)

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

## 2026-09-05d - magpie canary: trip line re-derived to 10% (no sim change)

The bump-2 revision above left `tests/playtest.gd` red on one line -
`FAIL magpie canary <= 5%: 4/30 CI [5%, 30%]`. This entry records what that
line measures and the decision taken on it (owner: "whatever you think"):
the **gate trip line moves from a 5% to a 10% Wilson lower bound**
(`MAGPIE_MAX_LOWER := 0.05 -> 0.10`), the **0-5% design target stays** in the
Targets table, and the 100-seed `verify_kit` number **10/100 [6, 17]** is
recorded as the baseline a future rise is judged against. Nothing in the sim
or the bots changed; no replay moved; nothing was re-recorded.

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

### The decision, and why not the other two

Chosen: move the trip line to 10% and keep the target. Rejected: re-tuning
greed now (a shop-economy change hits every persona for the sake of a bot
band that 30 seeds cannot resolve, and 10% still reads as "full greed loses
almost always"), and leaving the line red (a gate everyone learns to ignore
stops being a gate). The rule from here: a 30-seed run trips from 7/30 up
(true rate roughly doubled); the real canary is the 100-seed `verify_kit`
line, and a rise whose lower bound clears the recorded [6, 17] is the signal
that greed got cheap. Re-tuning greed toward 0-5% stays on the watch list as
its own balance question with its own 100-seed before/after.

### Suite after the change

- `tests/playtest.gd` 30 seeds, gate ON: **exit 0, "gate: all PASS"**, magpie
  line `PASS magpie canary <= 10% (design target 0-5%): 4/30 CI [5%, 30%]`.
  Win counts identical to 2026-09-05c (wanderer 0, sprout 1, magpie 4,
  fanatic 7, optimizer 12, deeproot 24 of 30; 0 timeouts, 0 illegal).
- Every other suite unchanged from 2026-09-05c (no code outside the gate
  constant and its label changed).

## 2026-09-06 - bump 3 (C1b): ash, root semantics, spore stacking, item stun through the table

Block C1's second commit from docs/PROGRESSION_REVIEW.md 6.3. C1a - the
tables commit, which has no entry of its own here because it changed no
behaviour and moved no hash (see the "Status (2026-09-05c)" paragraph in
docs/PROGRESSION_REVIEW.md) - put every terrain, reaction and status literal
behind `Content.TERRAIN` / `REACTIONS` / `STATUSES`; C1b changes behaviour by
editing those rows. The instruments did not change (still v2), so this
entry's numbers compare with the "bump 2 revision" (2026-09-05c) and "magpie
canary" (2026-09-05d) entries above it, and with nothing older.

What changed:

- **Ash (1).** New `TERRAIN` row `ash`: corruption true, `shields_core`
  false, not flammable, washable, `convertible` true, bloom 1, no ttl.
  `TERRAIN.fire.burns_to` and `REACTIONS.fire_burns_out.result` are now
  `ash`, so a fire tile whose ttl expires becomes `{kind: "ash"}` (carrying
  the fire tile's bloom flag) and emits `{t: "ash", tile}` instead of
  vanishing. Ash cleanses to growth like any corruption, counts toward
  `greened` and the room-bloom check, and never gates the boss core
  (`_corruption_adjacent` reads `shields_core`). The `convert_radius` literal
  became a table read (`convertible`: oil, goo, ash true; `rich_goo` false).
  Mapgen never emits ash - `test_invariants` reports the generated kind set
  as `["oil", "goo", "growth", "rich_goo"]`.
- **Root semantics (2).** `STATUSES.root.blocks` is `["move", "advance",
  "drag"]` - a rooted enemy cannot walk, cannot close and cannot haul the
  player - and the row gained `cooldown: 2`. Landing root writes
  `root_cd = max(existing, resulting duration + cooldown)`; while that
  cooldown stands and root is not active, a fresh application is refused and
  emits `{t: "resisted", id, status}`. The cooldown decrements once per
  `_execute_intent`, stagger-style. Massive enemies (every boss) stay immune
  to every status.
- **Spore stacking (3).** `STATUSES.spore` is `stack: "add"`, `cap: 6` - the
  first row to use C1a's add-with-cap path. Re-dosing deepens the poison
  instead of refreshing it.
- **Items through the table (4).** `spore_vial` / `spore_vial+` apply stun
  through `_apply_status` (radius and turns unchanged: 2 tiles 1 turn, 4
  tiles 2 turns). The hardcoded boss exclusion became the table's massive
  immunity - the same affected set, but the immune event now fires for bosses
  in range and a `status` event now fires for every enemy the vial stuns
  (C1a set the field silently).
- **Spread fire inherits the bloom flag (5)** - the one C1a deviation, now
  paid. `fire_spreads` and `_ignite` copy the source oil tile's `bloom` key,
  so enemy-made oil burns into bloom-0 fire and bloom-0 ash: cleansing it
  pays no bloom but still counts toward `greened`.
- **Version (6).** `Game.SIM_VERSION := 3`. `shell/main.gd`
  RUN_SAVE_VERSION, `tests/regress_lib.gd` and `tests/autopsy.gd` read the
  same constant.
- Consumers in the same block: `optimizer._dodge` reads
  `Content.STATUSES.root.blocks` instead of the literal `"move"`; ash has an
  SVG sprite, a shell legend row and the ASCII glyph `,`; `tests/tally.gd`
  counts ash events, cleanses by kind (the `cleanse` event gained `kind`),
  `resisted` events, and status events by status name.

**The quota claim in the 6.3 spec did not hold as C1b shipped it - CLOSED by
the 2026-09-06b revision below.** The spec assumed ash would stop a burn from
opening the green gate. As committed here it did not: `_reclamp_quota` fired
at *ignition*, because fire was not corruption in `Content.TERRAIN`, and the
clamp only ever lowers `green_need`. Ash restored the corruption count *after*
the burn, so later re-clamps shrank the quota less, but lighting a slick still
opened a dormant stairs exactly as it did in bump 2 (`test_economy` as
committed here: "quota reclamp: wash 2->0, ignite 2->0, burnout to ash no
reclamp, ash wash 2->0, partial 3->2"; the `blockb_quota_reclamp.json` record
replayed its `quota_reclamp need 1 was 2` / `stairs_awaken` / `descend` chain
unchanged). Closing the line needed fire to count as pending corruption - a
sim change, which the next entry makes: `Content.counts_as_corruption` now
counts a fire as the ash it will leave, at the same `SIM_VERSION` 3. Read this
paragraph as the state of the tree at commit 347c9b4 only; every number in
this entry still stands, because the revision moved no win count.

What this invalidates: **every pre-bump replay hash.** All 32
`tests/regressions/*.json` records carry `sim_version: 3`, and an action log
recorded before the bump can desync outright - two did. Aggregate win rates
still compare across the bump (same instruments, same seeds 1..30, same
bots), but per-seed pairing does not: a burnt tile that used to disappear now
stands as corruption, so the same bot makes different choices from that point
on. Nothing before 2026-09-05 (instrument v1) compares at all.

### Suite

All green, gate included:

- `tests/test_invariants.gd`: "invariants: 1400 generations, 0 violations",
  "terrain kinds: ["oil", "goo", "growth", "rich_goo"] (0 violations)" (new
  check), "floor_def invariants: 11 configs, 1540 generations, 0 violations"
- `tests/test_determinism.gd`: "determinism: OK (55 checks, 7 personas)"
- `tests/test_content.gd`: "effect grammar: 39 ability rows over 22 ops;
  terrain 9, reactions 5, statuses 3" (terrain 8 -> 9), "content: OK"
- `tests/test_meta.gd`: "meta: OK"
- `tests/test_economy.gd`: "economy: OK (95 checks)" (84 -> 95)
- `tests/test_grammar.gd`: "grammar: OK (195 checks)" (152 -> 195 over this
  bump)
- `tests/test_regressions.gd`: "regressions: 32 ok, 0 failed", and
  `REGRESS_STRICT=1` "regressions: 32 ok, 0 failed" (27 -> 32 records)
- `tests/test_shell.gd`: "shell smoke: OK"
- `tests/playtest.gd` 30 seeds, gate ON: exit 0, "gate: all PASS"

Before the corpus was regenerated, `test_regressions` was "regressions: 0 ok,
27 failed", exit 1, every line "stale record: sim_version 2 != 3" - the
expected shape of a version bump, and the reason the corpus phase exists.

### Persona table

Before = the 2026-09-05c revision (the last full playtest; 2026-09-05d
changed only the gate constant). After =
`=== playtest | bot wanderer,sprout,magpie,fanatic,optimizer,deeproot |
config {  } | seeds 1..30 (30) ===` and
`=== playtest | bot deeproot_rollout | config {  } | seeds 1..30 (30) ===`.
Both columns are seeds 1..30, tier 0, Wilson 95% as printed.

| persona | 2026-09-05c revision | this bump | moved outside CI? |
|---|---|---|---|
| wanderer | 0/30 = 0% [0, 11], floor 1.0 | 0/30 = 0% [0, 11], floor 1.0 | no |
| sprout | 1/30 = 3% [1, 17], floor 3.5 | 1/30 = 3% [1, 17], floor 3.5 | no |
| magpie | 4/30 = 13% [5, 30], floor 3.8 | 5/30 = 17% [7, 34], floor 3.8 | no |
| fanatic (legacy seed-split) | 7/30 = 23% [12, 41], floor 5.4 | 9/30 = 30% [17, 48], floor 5.6 | no |
| optimizer | 12/30 = 40% [25, 58], floor 5.9 | 11/30 = 37% [22, 54], floor 5.9 | no |
| deeproot | 24/30 = 80% [63, 90], floor 6.9 | 23/30 = 77% [59, 88], floor 6.9 | no |
| deeproot_rollout | 28/30 = 93% [79, 98], floor 7.0 | 29/30 = 97% [83, 99], floor 7.0 | no |

Zero timeouts and zero illegal actions for all seven personas. Every point
estimate lies inside the other column's interval in both directions, so the
bump is win-rate neutral at 30 seeds by the Method rule. Note this is the
*aggregate* comparison the instruments support; per-seed pairing is void
across the bump (see above), and the corpus phase's two re-records
(det_optimizer_s42 win -> floor-7 death, det_sprout_s42 floor 5 -> floor 4)
are corpus assertions, not balance evidence.

Against the Targets table: deeproot 77% sits inside the 70-90% band;
optimizer 37% clears the gate's 35-65% band but sits under the Targets
table's 45-65%, exactly as 40% did in 2026-09-05c - unchanged drift, not this
bump's. sprout avg floor 3.5 is at the low edge of its 3.5-5 target, also
unchanged from 05c. wanderer, fanatic (every build > 0, below) and the
zero-timeout target all hold.

### KPI block (playtest, 30 seeds, tier 0)

Same derivation and columns as the 2026-09-05c table: strike/sig/terr =
shares of enemy damage, cmb = combos/run, conv = bloom spent/earned, ent =
kit entropy bits, shrine = shrine turns/run, unspent = unspent charge per
end_turn, stall = stall floors over 30 runs, qu = quota-unmet deaths, dmg =
player damage per run.

| persona | strike | sig | terr | cmb | conv | ent | shrine | unspent | stall | qu | dmg |
|---|---|---|---|---|---|---|---|---|---|---|---|
| wanderer | 0.32 | 0.00 | 0.02 | 30.33 | 0.00 | 0.00 | 0.77 | 0.10 | 20 | 25 | 42.4 |
| sprout | 0.38 | 0.12 | 0.01 | 6.40 | 0.11 | 4.29 | 1.00 | 0.36 | 15 | 2 | 34.4 |
| magpie | 0.39 | 0.27 | 0.01 | 2.80 | 0.51 | 4.05 | 23.17 | 0.64 | 19 | 4 | 32.3 |
| fanatic | 0.21 | 0.21 | 0.05 | 12.23 | 0.25 | 3.54 | 1.37 | 0.79 | 9 | 3 | 26.5 |
| optimizer | 0.43 | 0.12 | 0.02 | 4.13 | 0.26 | 4.28 | 1.47 | 0.75 | 5 | 2 | 23.4 |
| deeproot | 0.09 | 0.38 | 0.15 | 15.53 | 0.01 | 3.83 | 0.27 | 0.70 | 7 | 0 | 10.6 |
| deeproot_rollout | 0.06 | 0.25 | 0.13 | 11.80 | 0.01 | 4.11 | 0.37 | 1.22 | 4 | 0 | 3.1 |

`riders: 0.00/run` for every persona, as in C1a: no content row carries a
rider yet, so the C2 vocabulary is still measured at zero. Upcycles are still
0/0 everywhere - press and forge remain dead sinks across three bumps.
Choice sinks, graft offers discarded over 30 runs (05c in brackets):
wanderer 0 [0], sprout 10 [12], magpie 84 [83], fanatic 42 [40], optimizer 41
[44], deeproot 0 [0], deeproot_rollout 0 [0].

### The terrain line (new Tally counters)

`tests/tally.gd` prints one new line per persona: ash events (fires that
burnt out), cleanses split by the kind removed, `resisted` events, and status
events by status name. Verbatim, 30 seeds each:

```
wanderer          terrain: ash 26  cleanses by kind { "ash": 6, "oil": 8, "goo": 5 }  resisted 0  statuses {  }
sprout            terrain: ash 86  cleanses by kind { "oil": 316, "goo": 142, "rich_goo": 4, "ash": 40 }  resisted 0  statuses {  }
magpie            terrain: ash 169  cleanses by kind { "oil": 686, "goo": 263, "rich_goo": 29, "ash": 42 }  resisted 0  statuses { "stun": 29, "root": 2 }
fanatic           terrain: ash 261  cleanses by kind { "oil": 455, "goo": 230, "rich_goo": 23, "ash": 63 }  resisted 0  statuses { "stun": 30, "root": 23 }
optimizer         terrain: ash 259  cleanses by kind { "oil": 515, "goo": 259, "rich_goo": 18, "ash": 20 }  resisted 0  statuses { "stun": 18 }
deeproot          terrain: ash 539  cleanses by kind { "oil": 444, "goo": 262, "rich_goo": 32, "ash": 65 }  resisted 0  statuses { "stun": 22 }
deeproot_rollout  terrain: ash 355  cleanses by kind { "oil": 445, "goo": 309, "rich_goo": 34, "ash": 52 }  resisted 0  statuses { "stun": 12 }
```

Read: **ash is a live mechanic in play** - 1,695 ash tiles created over 210
runs, and every persona cleanses some of them (6 to 65 per 30 runs). It is
not a majority of cleansing work anywhere; oil and goo still dominate. The
deeproot row is the extreme: 539 burnouts, 65 ash cleanses, so the ceiling
burns far more than it tidies.

**Root and spore are close to unmeasured.** `resisted` is 0 in all 210
playtest runs (3 in 100 magpie seeds, below) - no bot re-applies root to the
same enemy inside the 2-turn cooldown. `root` statuses appear only for
fanatic (23, the anchor/turtle builds) and magpie (2). `spore` never appears
at all: no persona casts `spore_cloud` or stacks it, so the add-with-cap rule
is exercised only by `tests/test_grammar.gd` and the hand-scripted
`c1b_spore_stack.json` record. The same gap covers the whole bot-derived
regression corpus: 0 rooted, 0 resisted, 0 spore events across all 27
pre-existing records.

### Magpie canary at 100 seeds

`=== verify_kit | bot magpie | config {  } | seeds 1..100 (100) ===`:
**13/100 = 13% wins, win CI [8%, 21%]**, avg floor 3.8, turns on wins 213.8,
damage taken 33.0/run, **0 timeouts**, 0 illegal, ability buys 102.
Its terrain line: `terrain: ash 444  cleanses by kind { "oil": 2247, "goo":
932, "rich_goo": 136, "ash": 193 }  resisted 3  statuses { "stun": 157,
"root": 32 }`.

Against the 2026-09-05d rule ("the real canary is the 100-seed `verify_kit`
line, and a rise whose lower bound clears the recorded [6, 17] is the
signal"): the recorded baseline is 10/100 = 10% [6, 17]; this bump measures
13/100 = 13% [8, 21]. The lower bound is 8%, which does not clear 17%, and
each point estimate sits inside the other interval (13% in [6, 17], 10% in
[8, 21]). **Not a signal.** The 0-5% design target is still unmet, as it has
been since before bump 2.

Two magpie numbers worth naming without a CI to judge them by: the 1 timeout
in 100 runs recorded in 2026-09-05c is now 0, and this is the only run in the
whole bump where `resisted` is non-zero (3 refusals in 100 runs).

### Gate verdict

`tests/playtest.gd` at 30 seeds, gate ON: **exit 0, "gate: all PASS"**.

```
PASS wanderer 0 wins, avg floor <= 2: 0 wins, avg floor 1.00
PASS wanderer illegal actions == 0: 0
PASS sprout wins rare (<= 1 per 30 seeds): 1/30
PASS sprout illegal actions == 0: 0
PASS magpie canary <= 10% (design target 0-5%): 5/30 CI [7%, 34%] (fails when the lower bound clears the trip line)
PASS magpie illegal actions == 0: 0
PASS fanatic illegal actions == 0: 0
PASS optimizer band 35-65%: 11/30 CI [22%, 54%]
PASS optimizer timeouts == 0: 0
PASS optimizer illegal actions == 0: 0
PASS deeproot band 70-90%: 23/30 CI [59%, 88%]
PASS deeproot timeouts == 0: 0
PASS deeproot illegal actions == 0: 0
gate: all PASS
```

`PLAYTEST_BOTS=deeproot_rollout PLAYTEST_SEEDS=30`: exit 0.

```
PASS deeproot_rollout illegal actions == 0: 0
gate: all PASS
```

### Fanatic archetypes

`=== measure_fanatic | bot fanatic | config {  } | seeds 1..30 (30) ===`,
"builds: pyro, gardener, turtle, shover, pyro_nolance, shover_nolance, ember,
anchor  (pool 14 ids)". **Before = the 2026-09-05b table**, which is the last
one recorded: 2026-09-05c removed the full-kit ability purchase without
re-running `measure_fanatic`, so part of any move below belongs to that
revision rather than to C1b. Both columns are FANATIC_SEEDS=30, seeds 1..30.

| build | 2026-09-05b | this bump | avg floor | core-complete (never) | sig | strike |
|---|---|---|---|---|---|---|
| pyro | 5/30 [7, 34] | 8/30 [14, 44] | 5.7 | 3.3 (43%) | 0.04 | 0.08 |
| pyro_nolance | 15/30 [33, 67] | 15/30 [33, 67] | 6.3 | 4.6 (47%) | 0.31 | 0.28 |
| ember | 9/30 [17, 48] | 5/30 [7, 34] | 5.5 | 5.3 (77%) | 0.46 | 0.16 |
| gardener | 6/30 [10, 37] | 6/30 [10, 37] | 5.6 | 4.6 (67%) | 0.39 | 0.32 |
| shover | 6/30 [10, 37] | 5/30 [7, 34] | 5.7 | 5.3 (80%) | 0.19 | 0.03 |
| shover_nolance | 5/30 [7, 34] | 4/30 [5, 30] | 4.5 | 4.5 (87%) | 0.64 | 0.12 |
| anchor | 3/30 [3, 26] | 4/30 [5, 30] | 4.4 | never (100%) | 0.00 | 0.57 |
| turtle | 1/30 [1, 17] | 1/30 [1, 17] | 4.2 | never (100%) | 0.06 | 0.57 |
| total | 50/240 = 21% | 48/240 = 20% | - | - | - | - |

Every build stays above zero, so the hard fanatic target holds, and the total
is flat. No row moves outside both intervals: the two largest swings are
`ember` 9/30 -> 5/30 (17% is the exact lower bound of the old [17, 48]) and
`pyro` 5/30 -> 8/30, both borderline rather than clean. One timeout,
`shover_nolance seed 1 floor 4` - the same timeout 2026-09-05b recorded, and
it reproduces on the pristine pre-C1b tree, so it is not this bump's.

### Graft sweep

`=== sweep_grafts | bot optimizer | config {  } | seeds 1..30 (30) ===`,
"grafts: deep_cells, verdant_pulse, thick_bark, bloom_surge, solar_core,
carapace". Each row pre-installs its graft(s) before floor 1 on the same
seeds as the base row; delta is against the base row and the sign test is
paired. In-sample only, as instructed.

| row | wins | CI | avg floor | delta | discordant | sign_p | cmb/run | conv | dmg | turns(w) | timeouts |
|---|---|---|---|---|---|---|---|---|---|---|---|
| (no graft) | 11/30 | [22, 54] | 5.9 | +0 | 0:0 | 1.00 | 4.13 | 0.26 | 23.4 | 82 | 0 |
| deep_cells | 12/30 | [25, 58] | 5.9 | +1 | 3:2 | 1.00 | 4.13 | 0.32 | 20.8 | 85 | 0 |
| verdant_pulse | 14/30 | [30, 64] | 6.3 | +3 | 4:1 | 0.38 | 4.03 | 0.29 | 31.8 | 95 | 0 |
| thick_bark | 12/30 | [25, 58] | 6.0 | +1 | 2:1 | 1.00 | 4.30 | 0.29 | 22.5 | 87 | 0 |
| bloom_surge | 12/30 | [25, 58] | 6.1 | +1 | 2:1 | 1.00 | 4.53 | 0.23 | 22.8 | 84 | 0 |
| **solar_core** | **20/30** | **[49, 81]** | 6.6 | **+9** | **10:1** | **0.01** | 4.47 | 0.38 | 19.1 | 73 | 0 |
| carapace | 12/30 | [25, 58] | 5.8 | +1 | 3:2 | 1.00 | 4.03 | 0.29 | 31.3 | 89 | 1 |
| all 6 | 13/30 | [27, 61] | 6.3 | +2 | 6:4 | 0.75 | 3.33 | 0.03 | 31.5 | 70 | 1 |

**`solar_core` now clears p < 0.05 in sample** (+9, 10:1 discordant, p=0.01,
damage taken 23.4 -> 19.1, turns-on-wins 82 -> 73), where 2026-09-05b
measured it at +7, 10:3, p=0.09. Its out-of-sample re-check already survived
the Method rule in bump 2 (`SWEEP_SEED_FROM=101`: 25/30 [66, 93] vs 10/30
[19, 51], 16:1, p=0.00). Two independent seed ranges and two bumps now say
the same thing: a pre-installed +1 regen is worth roughly +30 to +50 points
of optimizer win rate and the other five grafts sit inside noise. Nothing was
patched here - graft values are Block C3's, and 6.3 lists them as data work.
The "all 6" row is still not six grafts' worth of power: owning six drives
`shop_cost("graft")` up, so the run buys nothing (conversion 0.03, grafts
bought {}) and takes the most damage of any row.

### Quota probe (before/after)

Per the instruction to compare the quota counters against 2026-09-05c. Both
columns are the 30-seed playtest, same seeds, same personas.

| persona | quota reclamps 05c | this bump | quota-unmet deaths 05c | this bump |
|---|---|---|---|---|
| wanderer | 0 | 0 | 29 | 25 |
| sprout | 0 | 0 | 3 | 2 |
| magpie | 0 | 0 | 4 | 4 |
| fanatic | 0 | 0 | 3 | 3 |
| optimizer | 0 | 0 | 4 | 2 |
| deeproot | 0 | 0 | 0 | 0 |
| deeproot_rollout | 0 | 0 | 0 | 0 |

Plus the 100-seed magpie canary: `quota reclamps 0`, quota-unmet deaths 8.

**`quota_reclamp` has still never fired in a bot run** - 0 over the 210
playtest runs, 0 over the 240 graft-sweep runs, 0 over the 100 magpie seeds.
The counter is now three bumps old and entirely synthetic in its coverage
(`tests/test_economy.gd` section g plus `blockb_quota_reclamp.json` and the
new `blockb_quota_reclamp_wash.json`). C1b does not change that and, per the
premise note above, ash makes the re-clamp shrink the quota *less* rather
than not at all. Quota-unmet deaths drift down slightly on three personas
(wanderer 29 -> 25, sprout 3 -> 2, optimizer 4 -> 2) and are flat on the
rest; no interval attaches to a death-cause count, and the wanderer's own win
rate did not move, so this is not evidence that ash eased the gate.

### Regression corpus regen

Numbers from the corpus phase, reproduced here because they are the bump's
replay record. **27 -> 32 records.** Before the regen:
"regressions: 0 ok, 27 failed", exit 1, every failure "stale record:
sim_version 2 != 3". After: **"regressions: 32 ok, 0 failed"**, exit 0, plain
and with `REGRESS_STRICT=1`.

- 25 records re-stamped with `REGEN=1`, **zero outcome diffs** (won / floor /
  turns / timeout identical everywhere); 10 of them moved their state hash,
  15 came out byte-identical in outcome *and* hash.
- 2 records re-recorded because their stored action log desynced under ash:
  `det_optimizer_s42` (372 -> 467 actions, WON floor 7 -> died floor 7) and
  `det_sprout_s42` (529 -> 389 actions, died floor 5 -> died floor 4).
- 5 new hand-scripted records pin the new behaviour and all five fail against
  the pre-C1b tree on exactly their own pattern: `c1b_ash_cleanse` (burnout ->
  `ash` -> `cleanse kind ash` -> `room_bloom` -> `floor_restored`),
  `c1b_root_drag` (root blocks two drags, a re-snare inside the cooldown is
  `resisted`, the drag lands once root ends), `c1b_spore_stack` (3 + 3 = 6 at
  the cap kills a 5-hp extractor that survives under max-stacking),
  `c1b_spore_vial` (the vial now emits a `status` event), and
  `blockb_quota_reclamp_wash` (the wash path, which is the removal that is
  permanent under ash).
- Ash events per replayed record run from 72 (`det_deeproot_s11`) down to 0;
  `det_sprout_s11` earns 37 bloom instead of 39 because one ash tile left
  standing costs that room its `room_bloom` bonus.
- Items 2 and 3 fire zero times across all 27 bot-derived records, which is
  why the hand-scripted ones exist.

### Anything else that moved

- **deeproot takes more damage: 7.5 -> 10.6 per run** (30 seeds, no CI on a
  damage mean) while its combos/run rose 14.10 -> 15.53 and its stall floors
  held at 7. `deeproot_rollout` moved the same way, 2.8 -> 3.1. The searcher
  burns more and now stands next to what it burnt.
- **The two cleanest personas more than doubled their stall floors:**
  optimizer 2 -> 5 and deeproot_rollout 1 -> 4 over 30 runs (fanatic 6 -> 9 is
  the same +3; wanderer 24 -> 20, sprout 14 -> 15, magpie 18 -> 19, deeproot
  7 -> 7). Timeouts stayed 0 everywhere, so nothing loops on ash, but "the
  floor is not finished when the fire goes out" is the shape that would
  produce this.
- **magpie shrine turns/run 22.70 -> 23.17** - the 2026-09-05c anomaly is
  unchanged, not worsened; greed still loiters at a shrine it can spend
  little at.
- **fanatic signature share 0.24 -> 0.21 with combos/run 11.37 -> 12.23** and
  23 `root` statuses, the only persona applying root at any volume.
- Kit entropy moved most for magpie (4.28 -> 4.05), deeproot_rollout
  (4.32 -> 4.11) and sprout (4.45 -> 4.29); wanderer, fanatic, optimizer and
  deeproot are flat to within 0.05 bits. No persona changed which abilities it
  builds around.
- Nothing else left a CI.

## 2026-09-06b - bump 3 revision: burning oil counts as pending corruption

`Game.SIM_VERSION` stays 3 (bump 3 was never shipped) and the instruments are
unchanged (still v2), so this entry compares directly with the "bump 3 (C1b)"
entry above it and with the 2026-09-05c / 05d entries above that. It closes
the one premise C1b recorded as refuted.

**The rule.** A terrain kind counts as corruption *for counting purposes*
when it is corruption itself **or** its `burns_to` is corruption - the new
`Content.counts_as_corruption(kind)` (`sim/content.gd:559-566`), which is true
for oil, goo, rich_goo and ash as before and now also for fire, the one kind
that is "pending corruption": a tile that will leave ash behind. Exactly two
sim sites read it, `_count_corruption` (`sim/game.gd:1252`, which feeds the
floor-entry clamp, `_reclamp_quota` and the `floor_restored` check) and
`_room_has_corruption` (`sim/game.gd:1260`, the room bloom); every other rule -
cleanse legality, `shields_core`, `convertible`, `washable`, and the bots'
pathing to cleansable tiles - still reads `is_corruption`, so a fire is still
not a thing you can cleanse and still does not shield the Furnace core.

**What it changes for play.** Lighting a slick no longer discounts the green
quota: ignition emits no `quota_reclamp`, the burnout to ash emits none
either, and a dormant stairs stays dormant through the entire burn. The room
bloom and the floor restore now wait for the ash - a room whose last corrupt
tile is on fire does not bloom while it burns, and blooms exactly once when
the ash is cleansed - and `floor_restored` waits with it. Washing the fire (or
the ash) away is still a bloomless removal and still re-clamps, so the only
way to shrink the gate remains actually removing corruption. Burning is a
delay, not a shortcut, which is what §6.3 assumed and what the bump-3 entry
had to record as not holding.

### Suite

All green, gate included:

- `tests/test_invariants.gd`: "invariants: 1400 generations, 0 violations",
  "terrain kinds: ["oil", "goo", "growth", "rich_goo"] (0 violations)",
  "floor_def invariants: 11 configs, 1540 generations, 0 violations"
- `tests/test_determinism.gd`: "determinism: OK (55 checks, 7 personas)"
- `tests/test_content.gd`: "effect grammar: 39 ability rows over 22 ops;
  terrain 9, reactions 5, statuses 3", "content: OK" (unchanged - the TERRAIN
  lint reads each row's own `corruption` / `convertible` fields, not the
  helper)
- `tests/test_meta.gd`: "meta: OK", "tier-0 career: 20 runs, 12 wins, best
  floor 7"
- `tests/test_economy.gd`: "economy: OK (120 checks)" (95 -> 120), with the two
  new section-g lines verbatim: "pending corruption: fire counts for the
  quota, the room bloom and the floor restore; it never shields the core and
  is never cleansable" and "quota reclamp: wash 2->0, ignite no reclamp (fire
  counts), burnout to ash no reclamp, fire/ash wash 2->0, partial 3->2; enemy
  oil / bloom-0 ash pay 0 bloom, count greened"
- `tests/test_grammar.gd`: "grammar: OK (207 checks)" (195 -> 207)
- `tests/test_regressions.gd`: "regressions: 32 ok, 0 failed", and
  `REGRESS_STRICT=1` "regressions: 32 ok, 0 failed" (32 records, unchanged
  count)
- `tests/test_shell.gd`: "shell smoke: OK"
- `tests/playtest.gd` 30 seeds, gate ON: exit 0, "gate: all PASS"

### Persona table

Before = the "bump 3 (C1b)" entry above. That column was also re-measured in
this session against a pristine `git archive HEAD` tree (commit 347c9b4) so
that both columns come from one machine and one instrument run; the HEAD
re-run reproduced the bump-3 entry cell for cell, including the terrain lines
and the quota counters. After =
`=== playtest | bot wanderer,sprout,magpie,fanatic,optimizer,deeproot |
config {  } | seeds 1..30 (30) ===` and
`=== playtest | bot deeproot_rollout | config {  } | seeds 1..30 (30) ===`.
Both columns are seeds 1..30, tier 0, Wilson 95% as printed.

| persona | bump-3 entry | this revision | moved outside CI? |
|---|---|---|---|
| wanderer | 0/30 = 0% [0, 11], floor 1.0 | 0/30 = 0% [0, 11], floor 1.0 | no |
| sprout | 1/30 = 3% [1, 17], floor 3.5 | 1/30 = 3% [1, 17], floor 3.5 | no |
| magpie | 5/30 = 17% [7, 34], floor 3.8 | 5/30 = 17% [7, 34], floor 3.8 | no |
| fanatic | 9/30 = 30% [17, 48], floor 5.6 | 9/30 = 30% [17, 48], floor 5.6 | no |
| optimizer | 11/30 = 37% [22, 54], floor 5.9 | 11/30 = 37% [22, 54], floor 5.9 | no |
| deeproot | 23/30 = 77% [59, 88], floor 6.9 | 23/30 = 77% [59, 88], floor 6.9 | no |
| deeproot_rollout | 29/30 = 97% [83, 99], floor 7.0 | 29/30 = 97% [83, 99], floor 7.0 | no |

**Every win count is identical, seed for seed**, so no interval moves and no
persona's average floor moves. Zero timeouts and zero illegal actions for all
seven personas, both columns. This is a stronger statement than the usual
"inside the other CI": the revision changes what a burning tile *counts* as,
and at 30 seeds that never changed which runs were won.

The trajectories are not identical, though, and the diff against the pristine
HEAD tree says exactly who moved:

- **wanderer and optimizer: byte-identical output blocks.** Neither ever
  reaches a decision where a fire is the last corruption in a room or in the
  floor count.
- **sprout, magpie, fanatic: a handful of room blooms and one death cause.**
  sprout room_bloom 4.10 -> 4.07/run and pickups 50 -> 49; magpie room_bloom
  7.77 -> 7.73/run, bloom earned 55.7 -> 55.6/run, avg bloom 27.2 -> 27.1;
  fanatic player damage 795 -> 791 over 30 runs with one death moving from
  `smog` to `drill_bot` (causes drill_bot 8 -> 9, smog 7 -> 6). The room-bloom
  delay is the whole mechanism: a room stops paying its bonus at the moment
  the fire goes out and starts paying it when the ash is cleansed.
- **deeproot and deeproot_rollout moved most**, as expected for the two
  personas that use the sim as a forward model - the counting rule is inside
  their eval. deeproot: avg turns 102.6 -> 101.9, avg bloom 45.4 -> 45.2, ash
  539 -> 528, ash cleanses 65 -> 67, combos/run 15.53 -> 15.27, player damage
  317 -> 314. deeproot_rollout: avg turns 87.5 -> 86.0, stall floors 4 -> 3,
  ash 355 -> 352, ash cleanses 52 -> 50, combos/run 11.80 -> 11.07, player
  damage 94 -> 77 (3.1 -> 2.6/run), unspent charge 1.22 -> 1.08.

### KPI block (playtest, 30 seeds, tier 0)

Same derivation and columns as the bump-3 table: strike/sig/terr = shares of
enemy damage, cmb = combos/run, conv = bloom spent/earned, ent = kit entropy
bits, shrine = shrine turns/run, unspent = unspent charge per end_turn, stall
= stall floors over 30 runs, qu = quota-unmet deaths, dmg = player damage per
run.

| persona | strike | sig | terr | cmb | conv | ent | shrine | unspent | stall | qu | dmg |
|---|---|---|---|---|---|---|---|---|---|---|---|
| wanderer | 0.32 | 0.00 | 0.02 | 30.33 | 0.00 | 0.00 | 0.77 | 0.10 | 20 | 25 | 42.4 |
| sprout | 0.38 | 0.12 | 0.01 | 6.40 | 0.11 | 4.29 | 1.00 | 0.36 | 15 | 2 | 34.4 |
| magpie | 0.39 | 0.27 | 0.01 | 2.80 | 0.51 | 4.05 | 23.17 | 0.64 | 19 | 4 | 32.3 |
| fanatic | 0.21 | 0.21 | 0.05 | 12.23 | 0.25 | 3.54 | 1.37 | 0.79 | 9 | 3 | 26.4 |
| optimizer | 0.43 | 0.12 | 0.02 | 4.13 | 0.26 | 4.28 | 1.47 | 0.75 | 5 | 2 | 23.4 |
| deeproot | 0.09 | 0.38 | 0.16 | 15.27 | 0.01 | 3.83 | 0.27 | 0.70 | 7 | 0 | 10.5 |
| deeproot_rollout | 0.07 | 0.25 | 0.12 | 11.07 | 0.01 | 4.11 | 0.37 | 1.08 | 3 | 0 | 2.6 |

Against the bump-3 KPI table the only cells that move are the ones listed
above: fanatic dmg 26.5 -> 26.4, deeproot cmb 15.53 -> 15.27 / terr 0.15 ->
0.16 / dmg 10.6 -> 10.5, deeproot_rollout cmb 11.80 -> 11.07 / strike 0.06 ->
0.07 / terr 0.13 -> 0.12 / unspent 1.22 -> 1.08 / stall 4 -> 3 / dmg 3.1 ->
2.6. Everything else is unchanged to the printed precision. `riders: 0.00/run`
for every persona (no content row carries a rider yet) and upcycles are still
0/0 everywhere - three bumps and a revision with press and forge dead.
Choice sinks, graft offers discarded over 30 runs, are unchanged from bump 3:
wanderer 0, sprout 10, magpie 84, fanatic 42, optimizer 41, deeproot 0,
deeproot_rollout 0.

**Stall floors did not rise.** The bump-3 Watch entry asked whether "the floor
is not finished when the fire goes out" would show up as a stall regression
now that the room bloom waits for the ash: wanderer 20, sprout 15, magpie 19,
fanatic 9, optimizer 5, deeproot 7 are all identical to bump 3, and
deeproot_rollout drops 4 -> 3. Timeouts stayed 0 everywhere.

### Quota probe (before/after)

Both columns are the 30-seed playtest, same seeds, same personas; "before" is
the bump-3 entry, re-measured this session on the pristine HEAD tree.

| persona | quota reclamps bump 3 | this revision | quota-unmet deaths bump 3 | this revision |
|---|---|---|---|---|
| wanderer | 0 | 0 | 25 | 25 |
| sprout | 0 | 0 | 2 | 2 |
| magpie | 0 | 0 | 4 | 4 |
| fanatic | 0 | 0 | 3 | 3 |
| optimizer | 0 | 0 | 2 | 2 |
| deeproot | 0 | 0 | 0 | 0 |
| deeproot_rollout | 0 | 0 | 0 | 0 |

Plus the 100-seed magpie canary: `quota reclamps 0`, quota-unmet deaths 8 -
both unchanged.

**The counter was already 0 before this revision, and it is 0 after.** The sim
report's "quota reclamps 0 on every choice-sinks line (was nonzero before this
revision)" is wrong: the pristine HEAD tree prints `quota reclamps 0` on all
seven personas too. Nothing about the bot-visible reclamp rate changed here,
because no bot has ever driven the reclamp in play. What changed is
synthetic-only coverage: `tests/test_economy.gd` section g now asserts the
*absence* of the event on the ignite and burnout paths, where it previously
asserted its presence. `quota_reclamp` has now never fired in a bot run across
three bumps and a revision - 0 over this entry's 210 playtest runs and 100
canary runs, on top of everything before it.

### The terrain line

`tests/tally.gd`, 30 seeds each, verbatim:

```
wanderer          terrain: ash 26  cleanses by kind { "ash": 6, "oil": 8, "goo": 5 }  resisted 0  statuses {  }
sprout            terrain: ash 86  cleanses by kind { "oil": 316, "goo": 142, "rich_goo": 4, "ash": 40 }  resisted 0  statuses {  }
magpie            terrain: ash 169  cleanses by kind { "oil": 686, "goo": 263, "rich_goo": 29, "ash": 42 }  resisted 0  statuses { "stun": 29, "root": 2 }
fanatic           terrain: ash 261  cleanses by kind { "oil": 455, "goo": 230, "rich_goo": 23, "ash": 63 }  resisted 0  statuses { "stun": 30, "root": 23 }
optimizer         terrain: ash 259  cleanses by kind { "oil": 515, "goo": 259, "rich_goo": 18, "ash": 20 }  resisted 0  statuses { "stun": 18 }
deeproot          terrain: ash 528  cleanses by kind { "oil": 440, "goo": 259, "rich_goo": 32, "ash": 67 }  resisted 0  statuses { "stun": 22 }
deeproot_rollout  terrain: ash 352  cleanses by kind { "oil": 445, "goo": 311, "rich_goo": 34, "ash": 50 }  resisted 0  statuses { "stun": 12 }
```

Read against bump 3: five of seven lines are identical; the two search
personas burn slightly less (deeproot ash 539 -> 528, rollout 355 -> 352) and
deeproot cleans up slightly more of what it burnt (ash cleanses 65 -> 67)
while rollout cleans up less (52 -> 50). 1,681 ash tiles over 210 runs against
1,695 before - ash is still a live mechanic in play and the revision did not
scare any persona off fire. `resisted` is still 0 in all 210 runs and `spore`
still never appears, so root's cooldown and spore's stacking remain
unmeasured; that gap is bump 3's, not this revision's.

### Magpie canary at 100 seeds

`=== verify_kit | bot magpie | config {  } | seeds 1..100 (100) ===`:
**13/100 = 13% wins, win CI [8%, 21%]**, avg floor 3.8, turns on wins 213.8,
damage taken 33.0/run, **0 timeouts**, 0 illegal, ability buys 102, stall
floors 58, quota-unmet deaths 8, `quota reclamps 0`. Its terrain line:
`terrain: ash 444  cleanses by kind { "oil": 2247, "goo": 932, "rich_goo":
136, "ash": 193 }  resisted 3  statuses { "stun": 157, "root": 32 }`.

Against the 2026-09-05d rule ("the real canary is the 100-seed `verify_kit`
line, and a rise whose lower bound clears the recorded [6, 17] is the
signal"): the recorded rise baseline is 10/100 = 10% [6, 17]; this revision
measures 13/100 = 13% [8, 21], lower bound 8%, which does not clear 17%.
**Not a signal**, and it is the same 13/100 [8, 21] bump 3 measured - every
field the bump-3 canary paragraph recorded comes back identical, terrain line
included. The same 100-seed run on the pristine HEAD tree differs in exactly
two printed cells: room_bloom 8.04 -> 8.03/run (804 -> 803 room blooms over
100 runs) and satchel_full 273 -> 272. Wins, CI, average floor, turns on wins,
damage, the terrain line and both quota counters are identical. The 0-5%
design target is still unmet, as it has been since before bump 2.

### Gate verdict

`tests/playtest.gd` at 30 seeds, gate ON: **exit 0, "gate: all PASS"**.

```
PASS wanderer 0 wins, avg floor <= 2: 0 wins, avg floor 1.00
PASS wanderer illegal actions == 0: 0
PASS sprout wins rare (<= 1 per 30 seeds): 1/30
PASS sprout illegal actions == 0: 0
PASS magpie canary <= 10% (design target 0-5%): 5/30 CI [7%, 34%] (fails when the lower bound clears the trip line)
PASS magpie illegal actions == 0: 0
PASS fanatic illegal actions == 0: 0
PASS optimizer band 35-65%: 11/30 CI [22%, 54%]
PASS optimizer timeouts == 0: 0
PASS optimizer illegal actions == 0: 0
PASS deeproot band 70-90%: 23/30 CI [59%, 88%]
PASS deeproot timeouts == 0: 0
PASS deeproot illegal actions == 0: 0
gate: all PASS
```

`PLAYTEST_BOTS=deeproot_rollout PLAYTEST_SEEDS=30`: exit 0.

```
PASS deeproot_rollout illegal actions == 0: 0
gate: all PASS
```

### Regression corpus

**32 records, unchanged in count. Three records changed in substance, one
more got a note-only edit, and the other 28 files are byte-identical to bump
3.** Plain and `REGRESS_STRICT=1` both "regressions: 32 ok, 0 failed", exit 0.
Before the corpus work the suite was "regressions: 30 ok, 2 failed", exit 1.
From the sim report, with the cause column re-attributed where the review
corrected it:

- `blockb_quota_reclamp.json` - re-scripted, because under the new rule the
  old script never opened the gate at all (it ended on `stairs_dormant`). Old
  expectation: `[cleanse, ignite, quota_reclamp need 1 was 2, stairs_awaken,
  ash, descend]`, turns 3, hash `512d1c4e...`. New: `[cleanse kind oil,
  ignite, ash, cleanse kind ash, stairs_awaken, descend to_floor 2]`, turns 4,
  hash `c878ec82...`, and no `quota_reclamp` anywhere in the 17-event replay
  trace. This record is now the burn path's truth; its sibling
  `blockb_quota_reclamp_wash.json` (note updated, hash unchanged) is the wash
  path that still shrinks the gate.
- `det_optimizer_s42.json` - re-recorded, not `REGEN`'d: the stored action log
  desynced (1 illegal event on replay). {won false, floor 7, turns 99} ->
  {won false, floor 7, turns 101}, 467 -> 474 actions, hash `b836da6f...` ->
  `2ed44917...`.
- `det_sprout_s42.json` - re-recorded; outcome identical ({died, floor 4,
  turns 126}) and the action count unchanged at 389, hash `dfc7a3af...` ->
  `65872625...`.
- Cause for both re-records: **the room-bloom site**, not the quota. HEAD
  bloomed a room while a fire still burned; the revision waits for the ash, so
  the bloom (and its supply drop) lands later or not at all, and the persona
  diverges from there. The sim report's cause table attributed this to the
  quota clamp; the first divergence in both records is the room bloom.
- The other 28 files came back byte-identical after a `REGEN=1` pass plus an
  int-normalisation pass, confirming only the three intended records moved.
  (`REGEN=1` re-emits every numeric config and action value as a float, which
  `regress_lib.ints_from_json` folds back on load, so nothing fails but the
  corpus churns on disk; the sim phase worked around it with a scratch
  normaliser. A permanent fix belongs in `regress_lib.save_record`.)

The negative assertion - "ignition emits no `quota_reclamp`" - is pinned in
the corpus only indirectly (a reclamp-free replay trace plus the state hash),
because the record format has no negative-event assertion. The explicit
absence checks live in `tests/test_economy.gd` section g.

### Anything else that moved

- **Nothing with a CI.** No win count, no average floor, no interval, on any
  of the seven personas at 30 seeds or on the 100-seed canary. The revision is
  a rules fix whose measured cost is a few room blooms and two search
  personas' trajectories.
- **Not measured:** no `sweep_grafts`, `sweep_combos`, `measure_fanatic` or
  `draft_oracle` run was made for this revision. Per-build win rates,
  per-graft lift and draft regret are still the bump-3 numbers. The fire-using
  builds (`pyro`, `ember`, `pyro_nolance`) are the ones most likely to feel a
  burn that no longer discounts the quota, and `measure_fanatic` is where that
  would show; it is the obvious follow-up before any fire-pool content ships.
- **`counts_as_corruption` reads `TERRAIN.burns_to`, but the burnout that
  actually happens comes from `REACTIONS.fire_burns_out.result`.** Both say
  `ash` today and `burns_to` now has no other reader, so nothing lints that
  the two agree; if a future edit desyncs them, a fire would be counted as
  pending corruption that never arrives, and the floor would only re-clamp
  once the tile resolved. Flagged by review, not patched here.

## 2026-09-06c - bump 4 (C2): riders on the + forms and two base rows

Block C's second content commit from docs/PROGRESSION_REVIEW.md 6.3 ("C2").
Seven ability rows gained a rider and nothing else in the sim changed: C1a's
grammar (`Game._rider_if` / `_rider_per` / `_bonus_dmg` / `then` +
`status_target`) already read every key these rows use, so this bump is
`sim/content.gd` data plus a version constant. `tests/test_content.gd`'s lint
accepted all seven unchanged ("8 rider rows -> 0 failures"). The instruments
did not change (still v2), so this entry compares directly with the
2026-09-06b revision above it, with the "bump 3 (C1b)" entry above that, and
with nothing before 2026-09-05.

**The seven rows, verbatim** (`sim/content.gd`; cost, tags, role, target shape
and range untouched except where noted):

```
sun_flare    effects [{op: aoe_damage, dmg: 1, radius: 2, ignite: true,
                       bonus: {dmg: 1, if: [{target_on: ["fire"]}]}}]
grow_spike   effects [{op: damage, dmg: 3,
                       per: {count: growth_adjacent_target, cap: 1, add: {dmg: 1}}}]
seed_bomb+   effects [{op: grow_radius, radius: 1,
                       then: [{op: status_target, status: root, turns: 1, who: on_planted}]}]
vine_whip+   effects [{op: pull, dist: 3, dmg: 3,
                       then: [{op: status_target, status: stun, turns: 1,
                               if: [{outcome_crossed: fire}]}]}]
water_jet+   effects [{op: wash_push, push: 3, collision_dmg: 3,
                       then: [{op: status_target, status: root, turns: 1,
                               if: [{outcome: collided}, {outcome: pushed}]}]}]
sun_flare+   effects [{op: aoe_damage, dmg: 2, radius: 2, ignite: true,
                       bonus: {dmg: 1, if: [{target_on: ["fire"]}]}}]
grow_spike+  effects [{op: damage, dmg: 3,
                       per: {count: growth_adjacent_target, cap: 2, add: {dmg: 1}}}]
```

`grow_spike+` is the one row whose *base* number moved: it was a flat `dmg: 4`
and is now `3 + per` capped at 2, so with growth only under the target and none
orthogonally adjacent it deals 3 where it used to deal 4, and 5 where the
review wanted 5. `grow_spike` (base) keeps cap 1 and range 3 while the `+` form
keeps cap 2 and range 4, so the upgrade stays an upgrade - a deliberate
deviation from the 6.3 text, which gave the base row cap 2 as well. Each row's
`ABILITY_DESC` entry names its rider in one clause.

**Version.** `Game.SIM_VERSION := 4` (`sim/game.gd:34`). What it invalidates:
**every pre-bump replay hash and every stored action log that casts one of the
seven ids.** Before the corpus work `tests/test_regressions.gd` was
"regressions: 0 ok, 32 failed", exit 1, every line "stale record: sim_version 3
!= 4"; 8 of those 32 also diverged on content or on the new bot branches.
Aggregate win rates still compare across the bump (same instruments, same seeds
1..30, same bots), but per-seed pairing does not: a spike that now kills at 4
ends a fight a turn earlier and the persona diverges from there.

**Bots in the same block** (`bots/optimizer.gd`, `bots/fanatic.gd`): the
optimizer's hardcoded damage guesses are replaced by `_est_dmg(aid, target,
snap)`, which reads `Content` and estimates `per` / `bonus` off the snapshot
terrain with no sim call, and it gained a seed-on-head branch (bomb an enemy's
own tile, then spike it the same turn); fanatic's gardener leads with the same
branch. Every before/after pair below therefore measures **row + bot together**,
which is what ships; the one place they are separated is the locked
`water_jet` / `vine_whip` blocks, which came back byte-identical.

### Suite

All green, gate included:

- `tests/test_invariants.gd`: "invariants: 1400 generations, 0 violations",
  "terrain kinds: ["oil", "goo", "growth", "rich_goo"] (0 violations)",
  "floor_def invariants: 11 configs, 1540 generations, 0 violations"
- `tests/test_determinism.gd`: "determinism: OK (55 checks, 7 personas)"
- `tests/test_content.gd`: "effect-grammar self-test: 19 bad rows -> 19
  failures; 8 rider rows -> 0 failures", "effect grammar: 39 ability rows over
  22 ops; terrain 9, reactions 5, statuses 3", "content: OK" (row and op counts
  unchanged - the seven rows are edits, not additions)
- `tests/test_economy.gd`: "economy: OK (120 checks)" (unchanged)
- `tests/test_grammar.gd`: "grammar: OK (273 checks)" (207 -> 273; five new
  `_check_c2_*` sections cast the real abilities through `Game.step`)
- `tests/test_regressions.gd`: "regressions: 39 ok, 0 failed" and, with
  `REGRESS_STRICT=1`, "=== regressions | dir res://tests/regressions | 39
  records | strict true | regen false ===" / "regressions: 39 ok, 0 failed"
  (32 -> 39 records)
- `tests/test_meta.gd`: "meta: OK"
- `tests/test_shell.gd`: "shell smoke: OK"
- `tests/playtest.gd` 30 seeds, gate ON: exit 0, "gate: all PASS"

### Persona table

Before = the 2026-09-06b revision entry above. After =
`=== playtest | bot wanderer,sprout,magpie,fanatic,optimizer,deeproot |
config {  } | seeds 1..30 (30) ===` and
`=== playtest | bot deeproot_rollout | config {  } | seeds 1..30 (30) ===`.
Both columns are seeds 1..30, tier 0, Wilson 95% as printed.

| persona | 06b revision | this bump | moved outside CI? |
|---|---|---|---|
| wanderer | 0/30 = 0% [0, 11], floor 1.0 | 0/30 = 0% [0, 11], floor 1.0 | no |
| sprout | 1/30 = 3% [1, 17], floor 3.5 | 1/30 = 3% [1, 17], floor 3.5 | no |
| magpie | 5/30 = 17% [7, 34], floor 3.8 | 5/30 = 17% [7, 34], floor 4.1 | no |
| fanatic | 9/30 = 30% [17, 48], floor 5.6 | 9/30 = 30% [17, 48], floor 5.6 | no |
| optimizer | 11/30 = 37% [22, 54], floor 5.9 | 13/30 = 43% [27, 61], floor 5.8 | no |
| deeproot | 23/30 = 77% [59, 88], floor 6.9 | 22/30 = 73% [56, 86], floor 6.9 | no |
| deeproot_rollout | 29/30 = 97% [83, 99], floor 7.0 | 28/30 = 93% [79, 98], floor 7.0 | no |

**No persona moved outside the other column's interval**, and four of seven win
counts are identical. The two that moved are the two the bot work touched most
(optimizer +2, deeproot -1, both well inside both intervals). Zero illegal
actions for all seven personas. Timeouts are **not** unchanged: magpie went
0 -> 1 over the same 30 seeds (seed 22, floor 4, the pre-existing two-tile
oscillation loop the autopsy shows at (22,11)/(22,12) with the stairs
reachable - not a combo loop). optimizer, deeproot and deeproot_rollout, the
personas the gate binds, stayed at 0.

Per-build fanatic (`FANATIC_SEEDS=30
FANATIC_BUILDS=turtle,gardener,pyro,ember,pyro_nolance`, `=== measure_fanatic |
bot fanatic | config {  } | seeds 1..30 (30) ===`), measured on the pristine
pre-C2 tree and on this one:

| build | pre-C2 | this bump |
|---|---|---|
| turtle | 1/30 [1, 17], floor 4.2, signature 0.06 | 1/30 [1, 17], floor 4.2, signature 0.06 |
| gardener | 6/30 [10, 37], floor 5.6, signature 0.39 | 9/30 [17, 48], floor 5.6, signature 0.50 |
| pyro | 8/30 [14, 44], floor 5.7, signature 0.04 | 9/30 [17, 48], floor 5.7, signature 0.05 |
| ember | 5/30 [7, 34], floor 5.5, signature 0.46 | 6/30 [10, 37], floor 5.5, signature 0.46 |
| pyro_nolance | 15/30 [33, 67], floor 6.3, signature 0.31 | 16/30 [36, 70], floor 6.3, signature 0.32 |
| total | 35/150, timeouts: [] | 41/150, timeouts: [] |

Every build is still above zero, no build moved outside the other interval, and
the **turtle canary row is identical cell for cell** (1/30, floor 4.2,
core-complete "never", signature 0.06, strike 0.57, 0 timeouts).

### KPI block (playtest, 30 seeds, tier 0)

Same derivation and columns as the 06b table: strike/sig/terr = shares of enemy
damage, cmb = combos/run, conv = bloom spent/earned, ent = kit entropy bits,
shrine = shrine turns/run, unspent = unspent charge per end_turn, stall = stall
floors over 30 runs, qu = quota-unmet deaths, dmg = player damage per run.

| persona | strike | sig | terr | cmb | conv | ent | shrine | unspent | stall | qu | dmg |
|---|---|---|---|---|---|---|---|---|---|---|---|
| wanderer | 0.32 | 0.00 | 0.02 | 30.33 | 0.00 | 0.00 | 0.77 | 0.10 | 20 | 25 | 42.4 |
| sprout | 0.36 | 0.14 | 0.01 | 8.67 | 0.11 | 4.29 | 0.80 | 0.37 | 14 | 2 | 31.5 |
| magpie | 0.26 | 0.57 | 0.01 | 20.50 | 0.50 | 4.22 | 29.60 | 0.49 | 23 | 3 | 43.6 |
| fanatic | 0.19 | 0.25 | 0.05 | 17.20 | 0.26 | 3.54 | 1.50 | 0.94 | 9 | 3 | 25.7 |
| optimizer | 0.34 | 0.36 | 0.01 | 12.10 | 0.29 | 4.05 | 2.07 | 0.59 | 4 | 1 | 21.9 |
| deeproot | 0.09 | 0.39 | 0.16 | 16.70 | 0.01 | 4.08 | 0.23 | 0.73 | 8 | 0 | 11.0 |
| deeproot_rollout | 0.07 | 0.32 | 0.11 | 14.03 | 0.00 | 3.87 | 0.33 | 0.86 | 3 | 0 | 3.4 |

The riders line - `riders: 0.00/run` for every persona in every entry before
this one, because no content row carried a rider:

```
wanderer   riders: 0.00/run  by kind {  }  by ability {  }
sprout     riders: 2.10/run  by kind { "per": 60, "then": 3 }  by ability { "grow_spike": 59, "seed_bomb+": 3, "grow_spike+": 1 }
magpie     riders: 17.10/run  by kind { "per": 507, "bonus": 6 }  by ability { "grow_spike": 375, "grow_spike+": 132, "sun_flare": 6 }
fanatic    riders: 5.20/run  by kind { "then": 32, "per": 115, "bonus": 9 }  by ability { "seed_bomb+": 32, "grow_spike": 65, "grow_spike+": 50, "sun_flare+": 2, "sun_flare": 7 }
optimizer  riders: 7.47/run  by kind { "per": 209, "bonus": 15 }  by ability { "grow_spike": 174, "grow_spike+": 35, "sun_flare+": 6, "sun_flare": 9 }
deeproot   riders: 1.33/run  by kind { "then": 1, "per": 31, "bonus": 8 }  by ability { "water_jet+": 1, "grow_spike+": 7, "grow_spike": 24, "sun_flare": 4, "sun_flare+": 4 }
deeproot_rollout  riders: 2.77/run  by kind { "then": 13, "per": 67, "bonus": 3 }  by ability { "seed_bomb+": 5, "grow_spike": 32, "water_jet+": 8, "sun_flare": 1, "grow_spike+": 35, "sun_flare+": 2 }
```

Read against the 06b KPI table: **signature share is the cell that moved**
(magpie 0.27 -> 0.57, optimizer 0.12 -> 0.36, sprout 0.12 -> 0.14, fanatic 0.21
-> 0.25, deeproot 0.38 -> 0.39) and it moved because `grow_spike` carries it -
over these same 30 seeds, 375 of magpie's 507 `per` riders and 174 of the
optimizer's 209 are the base spike. Combos/run rose with it (magpie 2.80 ->
20.50, fanatic 12.23 -> 17.20, optimizer 4.13 -> 12.10, deeproot 15.27 ->
16.70) - note that `riders`
are counted inside `combo_rate`, so a large part of that rise *is* the rider
counter, not new terrain play. Damage taken per run fell for the two personas
that use the spike best (optimizer 23.4 -> 21.9, fanatic 26.4 -> 25.7) and rose
for magpie (32.3 -> 43.6), which now stays alive longer at the shrine (avg
turns 168.5, shrine turns 29.60 against 23.17). Stall floors: wanderer 20 -> 20,
sprout 15 -> 14, magpie 19 -> 23, fanatic 9 -> 9, optimizer 5 -> 4, deeproot
7 -> 8. Upcycles are still 0/0 for every persona and `quota reclamps 0`
everywhere - four bumps with press, forge and the re-clamp dead in play.

**`resisted` is no longer zero.** fanatic's terrain line reads `resisted 2
statuses { "stun": 30, "root": 57 }` against `resisted 0 statuses { "stun": 30,
"root": 23 }` in 06b, and sprout picked up `root: 4`. `seed_bomb+`'s root rider
is the first content in the project to exercise root's cooldown in bot play -
the bump-3 watch item that recorded 0 `resisted` events over 210 runs is now
partly answered.

### Shipping gate, row by row

Gate text is docs/PROGRESSION_REVIEW.md 6.0: (i) a regression demo exists;
(ii) the Tally shows the combo firing at least once per run in a forced kit at
30 seeds; (iii) its locked lift CI is not below zero; (iv) signature-damage or
terrain-derived share, or a continuous metric such as turns on wins or damage
taken, moves in the intended direction; (v) magpie stays at or under 5% at 100
seeds, the turtle canary and timeout count are unchanged, and wanderer at 100
seeds shows zero script errors and zero illegal actions; (vi) shield / heal /
thorns / cleanse riders need a deeproot-plan solo check - **not applicable, no
row here grants any of those.**

"Forced kit" below is the locked config `{kit: base3 + X, pool: base3 + X}`
(`=== locked_kits(scratch) | bot optimizer | config { "locked": true } | seeds
1..30 (30) ===`, base3 = `["solar_lance", "seed_bomb", "mycelium_dash"]`),
because a locked pool offers only `+` upgrades and is the only configuration in
which the `+` rows are reliably drafted. Column (ii) is that config's
`riders: ... by ability` count divided by 30.

| row | (i) demo | (ii) riders/run, forced kit | (iii) locked lift | (iv) metric moved | verdict |
|---|---|---|---|---|---|
| `grow_spike` | `c2_grow_spike_base.json`, `combo_seedbomb_growspike.json` | **1.73** (52/30, base3+grow_spike) | +7 (10/30 [19, 51] -> 17/30 [39, 73]) | sig 0.36 -> 0.83, dmg taken 19.1 -> 13.7 | **SHIP** |
| `grow_spike+` | `c2_grow_spike_plus.json` | **23.87** (716/30) | shares the row above (the `+` is the drafted form) | signature damage is 0.83 of the kit's total | **SHIP** |
| `seed_bomb+` | `c2_seed_bomb_plus_head.json` | **5.30** (159/30, base3+grow_spike = the seed-on-head kit); 0.07 in base3 alone | no single-row contrast exists (`seed_bomb` is in `STARTING_KIT`) | fanatic `root` 23 -> 57 and `resisted` 0 -> 2; seed_bomb casts/run 1.4 -> 9.0 | **SHIP** |
| `sun_flare` | `c2_sun_flare_base.json` | **0.03** (1/30) | -1 (10/30 [19, 51] -> 9/30 [17, 48]); pre-C2 same config 12/30 [25, 58] | sig 0.05 -> 0.16, casts/run 1.1 -> 5.5, dmg taken 23.1 -> 22.3, turns(w) 89.8 -> 85.2, wins 12 -> 9 | **HOLD** (ii) |
| `sun_flare+` | `c2_sun_flare_plus.json` | **0.63** (19/30) | shares the row above | as above | **HOLD** (ii) |
| `water_jet+` | `c2_water_jet_pin.json` | **0.00** (0/30) | 0 (10/30 [19, 51], identical to pre-C2) | **nothing moved** - the whole 30-seed block is byte-identical to the pre-C2 tree | **HOLD** (ii, iv) |
| `vine_whip+` | `c2_vine_whip_embers.json` | **0.00** (0/30) | +2 (12/30 [25, 58], identical to pre-C2) | **nothing moved** except one `seed_bomb+` root | **HOLD** (ii, iv) |

Gate (v) is shared by all seven rows and is reported under "Canaries" below:
wanderer clean, turtle unchanged, magpie's rise inside the standing trip line
but its timeout count **not** unchanged (0 -> 1).

**The four HOLD rows are held, not removed - that is the owner's call.** What
the numbers say about each:

- **`sun_flare` / `sun_flare+` fire, just not once per run.** The bonus needs an
  enemy standing *in fire* at the moment the flare resolves, and the review's
  own telemetry put that at "under 1% of sightings". In the forced kit the
  optimizer casts the flare 5.5 times a run (up from 1.1 - the `_aoe_finishes`
  branch is doing its job) and lands the bonus 0.63 times. Over every run in
  this entry the bonus fired 20 times in the locked kit, 17 in the open-pool
  forced kit, 15 for the optimizer and 6 for magpie in the playtest, and 18 for
  magpie over 100 canary seeds. The rider works; the board rarely offers it.
- **`water_jet+`'s pin is reachable but no heuristic bot reaches it.** The
  `then` needs `collided` *and* `pushed`, i.e. the enemy actually moved and then
  hit something. In the forced kit the optimizer collides 0.27 times a run and
  every one of those is a wall-adjacent enemy that moved 0 tiles - `collided`
  is true by construction on a collision event, so `pushed` is the only
  conjunct that can fail, and it fails 8 times out of 8. It does fire for the two search personas that use the sim as a
  forward model: **1 rider over 30 deeproot runs and 8 over 30
  deeproot_rollout runs.** Across every run in this entry - 210 playtest, 100
  magpie canary, 100 wanderer canary, 270 forced-kit - `water_jet+` fired 9
  rider events, all of them from search.
- **`vine_whip+`'s ember drag never fired at all.** 0 rider events over the same
  680 runs, search personas included. Its `outcome_crossed: fire` needs a
  burning tile on the pull path in the same cast, and no persona lines that up.
- Neither of those two is a *broken* row: `tests/test_grammar.gd` casts both
  through `Game.step` and `tests/regressions/c2_water_jet_pin.json` /
  `c2_vine_whip_embers.json` replay them exactly. They are rows whose
  opportunity rate in play is at or near zero, which is what gate (ii) is for.

### Locked lift table (gate iii), verbatim

`=== sweep_combos | bot optimizer | config { "tier": 0 } | seeds 1..30 (30) ===`,
`mode lift | extras 12 -> 66 pairs, 3 selected | pairs
grow_spike+sun_flare,water_jet+vine_whip,grow_spike+water_jet`, base3
`["solar_lance", "seed_bomb", "mycelium_dash"]`:

```
baseline (base3 locked): 10/30    [19%, 51%]         3.43        90     25.8

singles (base3 + X locked, 6 ids x 30 seeds):
  ability            wins CI           combos/run  turns(w)      dmg
  grow_spike     17/30    [39%, 73%]        33.43        76     13.7
  grow_spike     17/30    [39%, 73%]        33.43        76     13.7
  sun_flare       9/30    [17%, 48%]         6.73        85     22.3
  vine_whip      12/30    [25%, 58%]         5.07        92     23.6
  water_jet      10/30    [19%, 51%]         4.83        92     23.6
  water_jet      10/30    [19%, 51%]         4.83        92     23.6

pairs (base3 + X + Y locked, 3 pairs x 30 seeds), sorted by lift:
  pair                               sx    sy  pair   max  lift   add  p-add discordant    cmb/r  t/o
  grow_spike + sun_flare          17/30  9/30 22/30    17    +5    16     +6 10:5  p=0.30  33.17    0
  grow_spike + water_jet          17/30 10/30 20/30    17    +3    17     +3  8:5  p=0.58  33.23    0
  vine_whip + water_jet           12/30 10/30 10/30    12    -2    12     -2  7:9  p=0.80   7.20    0

0/3 pairs flagged (pair CI excludes the max-single fraction AND sign_p < 0.05); discordant = seeds won by pair only : by best single only; sx/sy/pair are wins/30
secondaries per pair (signature share / terrain share / turns on wins / dmg taken / avg floor):
  grow_spike + sun_flare          sig 0.83  terrain 0.01  turns(w) 89  dmg 13.0  floor 6.4
  grow_spike + water_jet          sig 0.80  terrain 0.01  turns(w) 89  dmg 15.4  floor 6.4
  vine_whip + water_jet           sig 0.08  terrain 0.02  turns(w) 90  dmg 25.3  floor 6.0
```

Pair CIs (the pairs table does not print them; computed with the same
`Sweep.wilson`, z = 1.96, and cross-checked against a runner that does print
22/30): 22/30 = [56%, 86%], 20/30 = [49%, 81%], 10/30 = [19%, 51%]. No pair is
flagged, so nothing here is a measured combo warp at 30 seeds. Read as
directions: light-then-flare (`grow_spike + sun_flare`, +5) and the spike next
to a shove (+3) both point up, and **pin-plus-drag (`vine_whip + water_jet`,
-2, sig 0.08) is the worst locked row in the table** - the two rows that never
fire their riders are also the two whose pair loses wins against holding
`vine_whip` alone. Duplicate `grow_spike` / `water_jet` rows in the singles
block are a display artefact of `sweep_combos._run_lift` (an id in two selected
pairs is appended to `single_ids` twice); both copies are the same
measurement.

**A/B against the pristine pre-C2 tree.** Every locked config above was also
run on `git archive HEAD` (commit 293020b, `SIM_VERSION` 3, pre-C2 content and
pre-C2 bots), same seeds, same script:

| locked kit | pre-C2 | this bump | riders/run |
|---|---|---|---|
| base3 | 10/30 [19, 51], turns(w) 90.2, dmg 25.8 | 10/30 [19, 51], turns(w) 90.2, dmg 25.8 | 0.00 -> 0.07 |
| base3 + `grow_spike` | 10/30 [19, 51], turns(w) 73.3, dmg 19.1, sig 0.36 | 17/30 [39, 73], turns(w) 76.4, dmg 13.7, sig 0.83 | 0.00 -> 30.90 |
| base3 + `sun_flare` | 12/30 [25, 58], turns(w) 89.8, dmg 23.1, sig 0.05 | 9/30 [17, 48], turns(w) 85.2, dmg 22.3, sig 0.16 | 0.00 -> 0.67 |
| base3 + `water_jet` | 10/30 [19, 51], turns(w) 92.1, dmg 23.6, sig 0.01 | 10/30 [19, 51], turns(w) 92.1, dmg 23.6, sig 0.01 | 0.00 -> 0.00 |
| base3 + `vine_whip` | 12/30 [25, 58], turns(w) 92.3, dmg 23.6, sig 0.04 | 12/30 [25, 58], turns(w) 92.3, dmg 23.6, sig 0.04 | 0.00 -> 0.03 |

The `water_jet` block is **byte-identical** across the bump and the `vine_whip`
block differs only in `combos/run 5.03 -> 5.07`, `riders 0.00 -> 0.03` and
`statuses { "stun": 27 } -> { "stun": 27, "root": 1 }` - one `seed_bomb+` root
that changed no other printed cell. That is the cleanest statement this entry
can make: two of the seven rows cost nothing and bought nothing at 30 seeds.

Open-pool forced kits (`VERIFY_EXTRAS=X`, `=== verify_kit | bot optimizer |
config { "kit": [...] } | seeds 1..30 (30) ===`), same pre/post A/B, for the
"base row plus its `+` via drafts" question the task asked:

| VERIFY_EXTRAS | pre-C2 | this bump | riders/run by ability, this bump |
|---|---|---|---|
| `grow_spike` | 13/30 [27, 61], sig 0.34, dmg 18.3 | 22/30 [56, 86], sig 0.78, dmg 14.8 | 24.97: grow_spike 488, grow_spike+ 209, seed_bomb+ 48, sun_flare 4 |
| `sun_flare` | 12/30 [25, 58], sig 0.17, dmg 26.6 | 13/30 [27, 61], sig 0.39, dmg 22.8 | 7.43: grow_spike 134, grow_spike+ 72, sun_flare+ 9, sun_flare 8 |
| `water_jet` | 11/30 [22, 54], sig 0.14, dmg 26.0 | 15/30 [33, 67], sig 0.37, dmg 25.4 | 7.77: grow_spike 149, grow_spike+ 75, sun_flare 7, sun_flare+ 2 |
| `vine_whip` | 11/30 [22, 54], sig 0.13, dmg 26.5 | 15/30 [33, 67], sig 0.37, dmg 27.0 | 7.70: grow_spike 156, grow_spike+ 67, sun_flare 6, sun_flare+ 2 |

In an open pool the optimizer drafts `grow_spike` into every one of these kits,
so the rise in the bottom three rows is the spike's, not the named extra's -
`water_jet+` and `vine_whip+` contribute **zero** rider events to any of them.
This is exactly why gate (ii) is measured on the locked config.

### Canaries (gate v)

- **magpie, 100 seeds.** `=== verify_kit | bot magpie | config {  } | seeds
  1..100 (100) ===`: **19/100 = 19% wins, win CI [13%, 28%]**, avg floor 4.1,
  turns on wins 215.2, damage taken 37.6/run, **1 timeout**, 0 illegal,
  `riders: 15.97/run by kind { "per": 1563, "bonus": 18, "then": 16 } by
  ability { "grow_spike": 1221, "grow_spike+": 342, "sun_flare": 13,
  "seed_bomb+": 16, "sun_flare+": 5 }`, stall floors 62, quota-unmet deaths 7,
  `quota reclamps 0`. The same 100 seeds on the pristine pre-C2 tree:
  **13/100 = 13% [8%, 21%]**, avg floor 3.8, turns on wins 213.8, damage 33.0,
  **0 timeouts** - i.e. the 06b number reproduced cell for cell, which is what
  makes the A/B trustworthy. Against the 2026-09-05d rule ("the recorded rise
  baseline is 10/100 = 10% [6, 17]; a 100-seed lower bound clearing 17% is the
  signal"): the lower bound is 13%, which does not clear 17%, so **not a
  signal**. Against the literal 6.0 gate text ("magpie stays at or under 5% at
  100 seeds"), 19% fails - as 13%, 13% and 10% failed before it. The four
  100-seed readings under instrument v2 now run 10/100 [6, 17] (2026-09-05c),
  13/100 [8, 21] (bump 3), 13/100 [8, 21] (06b) and 19/100 [13, 28] here: the
  highest yet, and the first whose whole interval sits above 10%. Compare the
  next one against [6, 17], not against [13, 28].
- **wanderer, 100 seeds.** `=== verify_kit | bot wanderer | config {  } | seeds
  1..100 (100) ===`: **0/100 = 0% [0%, 4%]**, avg floor 1.0, **0 timeouts, 0
  illegal actions, 0 SCRIPT ERROR lines**, `riders: 0.00/run`. Clean pass.
- **turtle.** `FANATIC_BUILDS=turtle,...` at 30 seeds, both trees: **1/30 [1%,
  17%], avg floor 4.2, core-complete "never", signature 0.06, strike 0.57, 0
  timeouts** - identical before and after. Turtle is not at 0 wins and has not
  been since the loop fixes (BALANCE.md Watch list records the canary baseline
  as 5/25); the point of the canary is that it did not *rise*, and it did not
  move at all.
- **Timeouts.** Not unchanged: magpie 0 -> 1 at 30 seeds and 0 -> 1 at 100
  seeds. Every other persona is 0 in every run in this entry (wanderer, sprout,
  fanatic, optimizer, deeproot, deeproot_rollout at 30 seeds; all five fanatic
  builds at 30 seeds; every locked and open-pool forced kit at 30 seeds;
  wanderer at 100 seeds). magpie is not in `playtest.NO_TIMEOUT`, so the gate
  does not bind it.

### Gate verdict

`tests/playtest.gd` at 30 seeds, gate ON: **exit 0, "gate: all PASS"**.

```
PASS wanderer 0 wins, avg floor <= 2: 0 wins, avg floor 1.00
PASS wanderer illegal actions == 0: 0
PASS sprout wins rare (<= 1 per 30 seeds): 1/30
PASS sprout illegal actions == 0: 0
PASS magpie canary <= 10% (design target 0-5%): 5/30 CI [7%, 34%] (fails when the lower bound clears the trip line)
PASS magpie illegal actions == 0: 0
PASS fanatic illegal actions == 0: 0
PASS optimizer band 35-65%: 13/30 CI [27%, 61%]
PASS optimizer timeouts == 0: 0
PASS optimizer illegal actions == 0: 0
PASS deeproot band 70-90%: 22/30 CI [56%, 86%]
PASS deeproot timeouts == 0: 0
PASS deeproot illegal actions == 0: 0
gate: all PASS
```

`PLAYTEST_BOTS=deeproot_rollout PLAYTEST_SEEDS=30`: exit 0.

```
PASS deeproot_rollout illegal actions == 0: 0
gate: all PASS
```

### Regression corpus

**32 -> 39 records, all `sim_version: 4`.** Plain and `REGRESS_STRICT=1` both
"regressions: 39 ok, 0 failed", exit 0. Before the corpus work the suite was
"regressions: 0 ok, 32 failed", exit 1, all 32 "stale record: sim_version 3 !=
4" - the expected shape of a version bump. What the corpus phase did, from its
report:

- **7 new hand-scripted records**, one per row and all 0-turn (ability casts
  only, no `end_turn`, so no enemy-phase noise): `c2_grow_spike_plus`
  (`rider per amt 2` -> `damage amt 5`), `c2_grow_spike_base` (`per amt 1` ->
  `damage amt 4`, cap 1 holding at two adjacent growth), `c2_sun_flare_plus`
  (ignite -> `bonus amt 1` -> `damage amt 3`), `c2_sun_flare_base`
  (-> `damage amt 2`), `c2_water_jet_pin` (`collision:water_jet+ amt 3` ->
  `status root turns 1` -> `then amt 1`), `c2_vine_whip_embers`
  (`fire:env amt 1` -> lash 3 -> `status stun` -> `then amt 1`),
  `c2_seed_bomb_plus_head` (growth -> root -> `seed_bomb+ then` ->
  `grow_spike+ per amt 2` -> `damage amt 5` -> death, two actions, one turn).
  Gate (i) is discharged by these seven.
- **17 records re-stamped only** (expect and hash byte-identical), **1 changed
  by content** (`combo_seedbomb_growspike`, hash `248d888b` -> `42b896e8`: the
  seed's cross now leaves one growth tile beside the target, so the base spike
  reads `rider grow_spike per amt 1` then `damage amt 4` where it read
  `damage amt 3`; the event pattern was hand-edited because `REGEN=1` never
  rewrites patterns), and **14 bot logs re-recorded** because their stored
  action lists no longer replay against the new content and the new optimizer /
  fanatic branches.
- **One outcome flip in the whole corpus**: `det_optimizer_s42` went
  `won false` -> `won true` (floor 7, turns 101 -> 88, 474 -> 390 actions), and
  its new log fires 7 `per` and 4 `bonus` riders, so the flip is C2 plus the new
  branches rather than a corpus error.
- Riders across the re-recorded logs: `per` 94, `bonus` 8, `then` 0.
- Recorded by the corpus phase and not caused by this bump:
  `det_wanderer_s3` / `det_sprout_s3` / `det_sprout_s11` changed on re-record
  although `bots/wanderer.gd` and `bots/sprout.gd` were not edited and reference
  no `Content` symbol; a step-by-step probe on `det_wanderer_s3` reaches the
  identical state hash and legal list at the divergence and still picks a
  different index, so those three logs were already stale before this block.

### Anything else that moved

- **The two heaviest cells are `grow_spike`'s.** Locked, it is +7 wins
  (10/30 [19, 51] -> 17/30 [39, 73]) and it takes over the kit: signature share
  0.36 -> 0.83, `grow_spike` casts/run 14.0 -> 27.1, `solar_lance` casts/run
  10.7 -> 3.4. Open-pool forced, it is 13/30 -> 22/30 [56, 86]. Neither number
  breaks a band - the gated optimizer run is 13/30 [27, 61], inside 35-65% -
  but a single cost-1 row that carries four fifths of a kit's damage is the
  same shape `solar_core` shows in the graft table, and it is worth a 100-seed
  look before C3 adds `compost` (kills leave growth) on top of it.
- **`sun_flare`'s locked row lost 3 wins** (12/30 [25, 58] -> 9/30 [17, 48])
  while every continuous metric moved the right way. The intervals overlap and
  the paired sign test on the pair rows is p = 0.30, so this is inside noise at
  30 seeds; it wants an out-of-sample re-check (`SWEEP_SEED_FROM=101`) before
  anyone reads it as the rider costing wins. The likely mechanism is tempo, not
  the rider: the optimizer's new `_aoe_finishes` branch fires the flare 5x more
  often (1.1 -> 5.5 casts/run) for 2 charge a cast.
- **magpie's damage taken rose 32.3 -> 43.6 per run** and its shrine turns
  23.17 -> 29.60 on the same 5/30 wins, with avg turns 168.5. Greed now has a
  cheap repeatable payoff (`grow_spike` 375 riders per 30 runs) and spends
  longer standing in the smog to buy it. This is the mechanism behind the
  100-seed canary rise; watch it before any further shop or growth content.
- **deeproot's terrain share held at 0.16 and its collision damage is still the
  largest in the roster** (`collision:water_jet` 248, `collision:water_jet+`
  51 over 30 runs) - the pin rider is the one C2 row the search personas use
  and the heuristics do not.
- **Not measured for this bump:** no `sweep_grafts`, `sweep_packages`,
  `sweep_tiers`, `measure_bosses` or `draft_oracle` run. Per-graft lift, tier
  winnability, boss arrivals and draft regret are still the bump-3 numbers.
  `sweep_tiers` in particular has not seen a `grow_spike` that scales with
  growth, and the tier ladder is where a cost-1 payoff row would show up first.
- **`quota_reclamp` has still never fired in a bot run** - 0 over the 680 runs
  in this entry that print the counter (210 playtest, 200 canary, 270
  forced-kit), on top of everything before it. The 150 `measure_fanatic` runs
  cannot say either way: that runner prints its own per-build summary, not the
  Tally block. Press and forge upcycles are still 0/0 for every persona.

## 2026-09-06d - bump 5 (C3): hook dispatcher, grafts as data, four rule grafts

Block C's third content commit from docs/PROGRESSION_REVIEW.md 6.3 ("C3").
Three things landed together and they cannot be separated in the numbers: a
hook dispatcher in `sim/game.gd`, the `GRAFTS` table rewritten as data, and
four new rule grafts that take the table from six rows to ten. The instruments
did not change (still v2), so this entry compares directly with the
2026-09-06c entry above it and with everything back to 2026-09-05; it does
**not** compare per-seed with anything, because the shop's graft draw changed.

**The `GRAFTS` table, verbatim** (`sim/content.gd:316-340`). Every row is
`{name, desc, tags}` plus exactly one of `stat`, `mod` or `hooks`:

```
deep_cells     tags [sun]                     stat  {bank_cap: 2}
verdant_pulse  tags [growth]                  stat  {growth_heal: 1}
thick_bark     tags [bark]                    stat  {shield_cap: 2}
bloom_surge    tags [growth, economy]         stat  {cleanse_bloom: 1}
solar_core     tags [sun]                     stat  {regen: 1}
carapace       tags [bark]                    mod   {floor_start_shield: 2}
ember_sap      tags [fire]                    hooks [{on: ignite, effects: [{op: damage_at, dmg: 1}],
                                                     cap_per_turn: 3}]
undertow       tags [water, displace, control]
                                              hooks [{on: staggered,
                                                     effects: [{op: status_at, status: root, turns: 1}]}]
compost        tags [growth]                  hooks [{on: kill, effects: [{op: terrain_at, kind: growth}]}]
oil_tithe      tags [fire, water, economy]    mod   {oil_cast_discount: 1}
```

The six pre-existing grafts are pure migration: `Game._graft_stat(key)` sums
`stat[key]` over held grafts and `Game._graft_mod(key, default)` returns the
first held `mod`, replacing all six `_has_graft` call sites (`_has_graft` no
longer exists in the tree). The sim phase proved the migration is numerically
identical with a parity probe against the pristine pre-C3 tree - optimizer, 10
seeds, each of the six legacy grafts pre-installed, comparing the per-step
event-stream hash, the final `state_hash` and `rng.state` after `Game.new`:
"PARITY: identical (60 rows)", diff empty, plus a 70-row `rng.state` check
with the shop kept.

**The dispatcher.** `Game._hook(kind, ctx)` (`sim/game.gd:2037`) runs
immediately after the existing `_emit` at seven kinds -
`Content.HOOK_KINDS = ["ignite", "staggered", "cleanse", "growth_planted",
"kill", "shield_break", "collision"]` - scanning sources in fixed order (kit
slots 0..n, then `player.grafts` in held order). Rows are
`{on, effects, cap_per_turn?, if?}`; effects reuse `_apply_effect` aimed at the
hook tile plus three positional ops (`damage_at`, `status_at`, `terrain_at`)
that read the tile out of `ctx`. Every row that runs emits
`{t: "hook", id, on, tile}`, which is what the new Tally `hooks` line counts.
`Content.HOOK_DEPTH_MAX = 3` and `Content.HOOK_STEP_CAP = 12` bound nesting and
per-step work; past either the hook is skipped and `{t: "hook_capped"}` is
emitted once for the step. Per-turn caps live in `hook_uses`, and `oil_tithe`'s
once-a-turn discount in `tithe_used_this_turn`; both reset in
`_begin_player_turn`, are copied by `clone()` and are **not** in `snapshot()`.
`ability_cost(aid, target)` applies the discount and emits `{t: "tithe", id}`,
and `legal_actions` prices each target individually while the mod is unspent.

**Bots.** `optimizer._first_graft` now scores every stocked offer by tag
overlap with the kit (`Content.ABILITIES[base_id].tags` counted with
multiplicity) and takes the best, ties falling back to the lowest offer index;
magpie and fanatic call the same helper. Everything is read from `Content`, so
a future `GRAFTS` row ranks itself. deeproot is untouched and buys no grafts,
so the ranking is unexercised at the ceiling.

**Version.** `Game.SIM_VERSION := 5` (`sim/game.gd:37`). What it invalidates:
**every stored replay hash, and every shop stock draw in the project.** The
shrine picks its two graft offers from `Content.GRAFTS` through the side-rng
`shop_graft` draw, so a table of ten instead of six changes which grafts every
seed is offered - before any bot decides anything. Add the tag-overlap pick on
top and a persona's held grafts diverge from its first shrine on. Aggregate win
rates still compare across the bump (same instruments, same seeds 1..30, same
personas); **per-seed pairing does not**, and no number in this entry is paired
against a pre-C3 tree.

### Suite

All green, gate included:

- `tests/test_invariants.gd`: "invariants: 1400 generations, 0 violations",
  "terrain kinds: ["oil", "goo", "growth", "rich_goo"] (0 violations)",
  "floor_def invariants: 11 configs, 1540 generations, 0 violations"
- `tests/test_determinism.gd`: "determinism: OK (55 checks, 7 personas)"
- `tests/test_content.gd`: "graft lint self-test: 23 bad rows -> 23 failures;
  5 good rows -> 0 failures", "grafts: 10 rows (5 stat, 2 mod, 3 hooks); hook
  kinds 7, depth max 3, step cap 12", "effect-grammar self-test: 19 bad rows ->
  19 failures; 8 rider rows -> 0 failures", "content: OK" (the ability grammar
  line is unchanged: "39 ability rows over 22 ops; terrain 9, reactions 5,
  statuses 3")
- `tests/test_economy.gd`: "economy: OK (123 checks)" (120 -> 123; the stock
  filter is generalised to ten grafts)
- `tests/test_grammar.gd`: "grammar: OK (364 checks)" (273 -> 364; a new
  "Block C3" section casts every hook through `Game.step`)
- `tests/test_regressions.gd`: "=== regressions | dir res://tests/regressions |
  45 records | strict false | regen false ===" / "regressions: 45 ok, 0
  failed", and with `REGRESS_STRICT=1` "strict true" / "regressions: 45 ok, 0
  failed" (39 -> 45 records)
- `tests/test_meta.gd`: "meta: OK"
- `tests/test_shell.gd`: "shell smoke: OK"
- `tests/playtest.gd` 30 seeds, gate ON: exit 0, "gate: all PASS"

### Persona table

Before = the 2026-09-06c entry above. After =
`=== playtest | bot wanderer,sprout,magpie,fanatic,optimizer,deeproot |
config {  } | seeds 1..30 (30) ===` and
`=== playtest | bot deeproot_rollout | config {  } | seeds 1..30 (30) ===`.
Both columns are seeds 1..30, tier 0, Wilson 95% as printed.

| persona | 06c | this bump | moved outside CI? |
|---|---|---|---|
| wanderer | 0/30 = 0% [0, 11], floor 1.0 | 0/30 = 0% [0, 11], floor 1.0 | no |
| sprout | 1/30 = 3% [1, 17], floor 3.5 | 1/30 = 3% [1, 17], floor 3.5 | no |
| magpie | 5/30 = 17% [7, 34], floor 4.1 | 5/30 = 17% [7, 34], floor 4.2 | no |
| fanatic | 9/30 = 30% [17, 48], floor 5.6 | 7/30 = 23% [12, 41], floor 5.6 | no |
| optimizer | 13/30 = 43% [27, 61], floor 5.8 | 14/30 = 47% [30, 64], floor 6.0 | no |
| deeproot | 22/30 = 73% [56, 86], floor 6.9 | 22/30 = 73% [56, 86], floor 6.9 | no |
| deeproot_rollout | 28/30 = 93% [79, 98], floor 7.0 | 27/30 = 90% [74, 97], floor 7.0 | no |

**No persona moved outside the other column's interval.** wanderer, sprout,
magpie and deeproot are identical win counts; the three that moved (fanatic -2,
optimizer +1, deeproot_rollout -1) are all well inside both intervals, and all
three are personas whose held grafts changed. Zero illegal actions for all
seven personas. **Timeouts are 0 for every persona at 30 seeds**, which closes
06c's one open gate-(v) item: magpie's 30-seed timeout is gone (1 -> 0) and so
is its 100-seed one (see Canaries).

### KPI block (playtest, 30 seeds, tier 0)

Same derivation and columns as the 06c table: strike/sig/terr = shares of enemy
damage, cmb = combos/run, conv = bloom spent/earned, ent = kit entropy bits,
shrine = shrine turns/run, unspent = unspent charge per end_turn, stall = stall
floors over 30 runs, qu = quota-unmet deaths, dmg = player damage per run.

| persona | strike | sig | terr | cmb | conv | ent | shrine | unspent | stall | qu | dmg |
|---|---|---|---|---|---|---|---|---|---|---|---|
| wanderer | 0.32 | 0.00 | 0.02 | 30.33 | 0.00 | 0.00 | 0.77 | 0.10 | 20 | 25 | 42.4 |
| sprout | 0.36 | 0.13 | 0.01 | 9.27 | 0.11 | 4.36 | 1.00 | 0.36 | 14 | 2 | 32.2 |
| magpie | 0.27 | 0.53 | 0.01 | 22.27 | 0.50 | 4.39 | 27.57 | 0.39 | 24 | 3 | 52.1 |
| fanatic | 0.19 | 0.24 | 0.05 | 16.73 | 0.29 | 3.44 | 1.67 | 0.97 | 10 | 2 | 25.2 |
| optimizer | 0.31 | 0.39 | 0.02 | 14.33 | 0.28 | 3.86 | 1.23 | 0.61 | 4 | 0 | 22.3 |
| deeproot | 0.09 | 0.39 | 0.16 | 16.70 | 0.01 | 4.08 | 0.23 | 0.73 | 8 | 0 | 11.0 |
| deeproot_rollout | 0.07 | 0.30 | 0.11 | 14.20 | 0.00 | 3.71 | 0.40 | 1.06 | 4 | 0 | 4.1 |

The riders line (C2's counter, unchanged content, printed for continuity):

```
wanderer   riders: 0.00/run  by kind {  }  by ability {  }
sprout     riders: 2.00/run  by kind { "per": 58, "then": 2 }  by ability { "grow_spike": 57, "seed_bomb+": 2, "grow_spike+": 1 }
magpie     riders: 17.83/run  by kind { "per": 533, "bonus": 2 }  by ability { "grow_spike": 533, "sun_flare": 2 }
fanatic    riders: 5.10/run  by kind { "then": 29, "per": 121, "bonus": 3 }  by ability { "seed_bomb+": 29, "grow_spike": 89, "sun_flare": 3, "grow_spike+": 32 }
optimizer  riders: 8.50/run  by kind { "per": 242, "bonus": 13 }  by ability { "grow_spike": 177, "grow_spike+": 65, "sun_flare": 9, "sun_flare+": 4 }
deeproot   riders: 1.33/run  by kind { "then": 1, "per": 31, "bonus": 8 }  by ability { "water_jet+": 1, "grow_spike+": 7, "grow_spike": 24, "sun_flare": 4, "sun_flare+": 4 }
deeproot_rollout  riders: 3.00/run  by kind { "per": 72, "then": 15, "bonus": 3 }  by ability { "grow_spike": 37, "seed_bomb+": 7, "water_jet+": 8, "sun_flare": 1, "grow_spike+": 35, "sun_flare+": 2 }
```

The hooks line - new this bump, `hooks: 0` for every persona in every entry
before it, because no hook existed:

```
wanderer   hooks: by graft {  }  by kind {  }  capped 0  tithe 0
sprout     hooks: by graft { "compost": 37 }  by kind { "kill": 37 }  capped 0  tithe 3
magpie     hooks: by graft { "compost": 546, "ember_sap": 21 }  by kind { "kill": 546, "ignite": 21 }  capped 0  tithe 6
fanatic    hooks: by graft { "compost": 187, "ember_sap": 41, "undertow": 4 }  by kind { "kill": 187, "ignite": 41, "staggered": 4 }  capped 0  tithe 11
optimizer  hooks: by graft { "ember_sap": 46, "compost": 51, "undertow": 5 }  by kind { "ignite": 46, "kill": 51, "staggered": 5 }  capped 0  tithe 2
deeproot   hooks: by graft {  }  by kind {  }  capped 0  tithe 0
deeproot_rollout  hooks: by graft {  }  by kind {  }  capped 0  tithe 0
```

Four readings from those two blocks. (1) **`hook_capped` is 0 in every run in
this entry that prints the counter** - 210 playtest runs, 200 canary runs and
540 hook-probe runs, 950 in all: neither `HOOK_DEPTH_MAX` nor `HOOK_STEP_CAP` has ever bound in
play, and the caps' only coverage is `tests/test_grammar.gd`'s direct `_hook`
calls and `c3_ember_sap_cap.json`'s per-turn cap. (2) **The two search personas
print an empty hooks line** because they buy no grafts at all (deeproot shrine
turns/run 0.23, buys `{ "item": 5 }`), so every ceiling number below comes from
a pre-installed config, never from play. (3) **`compost` dominates the counter
wherever it is held** - 546 of magpie's 567 hooks, 187 of fanatic's 232 - which
is what a kill hook does in a game whose bots kill a lot. (4) magpie's
signature share is 0.53 against 0.57 in 06c and its damage taken rose 43.6 ->
52.1 on the same 5 wins; `ember_sap` shows up in its own damage table (`by
family { ..., "ember_sap": 5 }` dealt, and **1 point taken**: `player dmg ... {
"ember_sap": 1 }`, the first time a graft has damaged the player).

### Choice sinks: the graft pick is no longer offer 0

The shrine's two graft offers are drawn from `Content.GRAFTS` through the
side-rng `shop_graft` tag, so a ten-row table re-rolls **every** shop on every
seed; on top of that optimizer, magpie and fanatic now pick by tag overlap
instead of taking offer 0. Graft buys by id over the 30-seed playtest (each buy
discards the other offer, so buys = discards):

```
sprout     grafts { "compost": 3, "oil_tithe": 3, "solar_core": 1, "carapace": 2, "verdant_pulse": 1 }               10 buys / 10 discarded
magpie     grafts { "bloom_surge": 12, "solar_core": 10, "verdant_pulse": 14, "compost": 14, "carapace": 4,
                    "oil_tithe": 8, "deep_cells": 9, "ember_sap": 11, "thick_bark": 5, "undertow": 6 }               93 buys / 93 discarded
fanatic    grafts { "ember_sap": 7, "compost": 8, "undertow": 2, "verdant_pulse": 8, "deep_cells": 9,
                    "thick_bark": 2, "solar_core": 4, "oil_tithe": 3, "bloom_surge": 3, "carapace": 1 }              47 buys / 47 discarded
optimizer  grafts { "ember_sap": 7, "verdant_pulse": 7, "carapace": 2, "oil_tithe": 6, "compost": 3,
                    "solar_core": 6, "undertow": 4, "deep_cells": 5, "bloom_surge": 6 }                              46 buys / 46 discarded
wanderer, deeproot, deeproot_rollout: no graft buys at all
```

Magpie and fanatic touch all ten ids and the optimizer nine (never
`thick_bark`), unevenly - which is the point: the distribution tracks the kit,
not the offer order. The bot phase's own probe over seeds 1..20 put the change
at magpie 13 of 60 buys and optimizer 5 of 27 buys landing on offer **1**,
where both were 100% offer 0 before. Kit entropy moved with it (magpie 4.22 ->
4.39, optimizer 4.05 -> 3.86, fanatic 3.54 -> 3.44).

### Graft table, optimizer, tier 0

`=== sweep_grafts | bot optimizer | config {  } | seeds 1..30 (30) ===`,
"grafts: deep_cells, verdant_pulse, thick_bark, bloom_surge, solar_core,
carapace, ember_sap, undertow, compost, oil_tithe". Each row pre-installs its
graft before floor 1 on the same seeds as the base row; delta and the sign test
are paired against that base row. Hooks come from
`=== hooks_probe(scratch) | bot optimizer | config {  } | seeds 1..30 (30) ===`,
a scratch runner that re-runs the identical configs and prints the Tally hook
counters `sweep_grafts`' compact row does not carry (its win column reproduces
the sweep's cell for cell). "own hooks/run" counts only the row's own graft;
the base row's hooks are grafts the bot *bought*.

| row | wins | CI | delta | disc. | p | dmg | turns(w) | t/o | own hooks/run | verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| (no graft) | 14/30 | [30, 64] | +0 | 0:0 | 1.00 | 22.3 | 89 | 0 | - (bought: ember_sap 46, compost 51, undertow 5, tithe 2) | - |
| deep_cells | 15/30 | [33, 67] | +1 | 3:2 | 1.00 | 22.5 | 86 | 0 | n/a (stat) | re-baseline |
| verdant_pulse | 18/30 | [42, 75] | +4 | 5:1 | 0.22 | 31.8 | 90 | 0 | n/a (stat) | re-baseline |
| thick_bark | 13/30 | [27, 61] | -1 | 2:3 | 1.00 | 29.6 | 87 | 0 | n/a (stat) | re-baseline |
| bloom_surge | 16/30 | [36, 70] | +2 | 3:1 | 0.62 | 20.7 | 82 | 0 | n/a (stat) | re-baseline |
| **solar_core** | **26/30** | **[70, 95]** | **+12** | **14:2** | **0.00** | 17.1 | 69 | 0 | n/a (stat) | re-baseline (see the lever below) |
| carapace | 15/30 | [33, 67] | +1 | 3:2 | 1.00 | 16.5 | 86 | 0 | n/a (mod) | re-baseline |
| ember_sap | 12/30 | [25, 58] | -2 | 1:3 | 0.62 | 20.7 | 88 | 0 | **4.93** (148 ignite hooks) | SHIP |
| undertow | 14/30 | [30, 64] | +0 | 1:1 | 1.00 | 21.4 | 90 | 0 | **0.27** (8 staggered hooks) | **HOLD (ii)** |
| compost | 15/30 | [33, 67] | +1 | 3:2 | 1.00 | 25.7 | 94 | 0 | **32.10** (963 kill hooks) | SHIP |
| oil_tithe | 14/30 | [30, 64] | +0 | 3:3 | 1.00 | 22.2 | 89 | 0 | **2.10** (63 tithes; the mod has no hooks) | SHIP |
| all 10 | 26/30 | [70, 95] | +12 | 12:0 | 0.00 | 15.0 | 66 | 0 | compost 809, ember_sap 216, undertow 0, tithe 49 | - |

### Graft table, optimizer, tier 6

`=== sweep_grafts | bot optimizer | config { "tier": 6 } | seeds 1..30 (30) ===`
and `=== hooks_probe(scratch) | bot optimizer | config { "tier": 6 } | seeds
1..30 (30) ===`, same seeds, same ten rows.

| row | wins | CI | delta | disc. | p | dmg | turns(w) | t/o | own hooks/run | verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| (no graft) | 5/30 | [7, 34] | +0 | 0:0 | 1.00 | 28.4 | 94 | 0 | - (bought: compost 137, ember_sap 9, tithe 13) | - |
| deep_cells | 6/30 | [10, 37] | +1 | 2:1 | 1.00 | 24.5 | 90 | 0 | n/a (stat) | re-baseline |
| verdant_pulse | 5/30 | [7, 34] | +0 | 1:1 | 1.00 | 32.2 | 86 | 0 | n/a (stat) | re-baseline |
| thick_bark | 6/30 | [10, 37] | +1 | 1:0 | 1.00 | 25.1 | 92 | 0 | n/a (stat) | re-baseline |
| bloom_surge | 7/30 | [12, 41] | +2 | 2:0 | 0.50 | 26.4 | 103 | 0 | n/a (stat) | re-baseline |
| **solar_core** | **22/30** | **[56, 86]** | **+17** | **19:2** | **0.00** | 26.1 | 77 | 0 | n/a (stat) | re-baseline (see the lever below) |
| carapace | 5/30 | [7, 34] | +0 | 1:1 | 1.00 | 25.6 | 79 | 0 | n/a (mod) | re-baseline |
| ember_sap | 7/30 | [12, 41] | +2 | 2:0 | 0.50 | 25.7 | 87 | 0 | **4.30** (129 ignite hooks) | SHIP |
| undertow | 6/30 | [10, 37] | +1 | 1:0 | 1.00 | 24.8 | 91 | 0 | **0.03** (1 staggered hook in 30 runs) | **HOLD (ii)** |
| compost | 4/30 | [5, 30] | -1 | 2:3 | 1.00 | 33.0 | 100 | 0 | **31.70** (951 kill hooks) | SHIP |
| oil_tithe | 7/30 | [12, 41] | +2 | 3:1 | 0.62 | 26.6 | 108 | 0 | **2.27** (68 tithes) | SHIP |
| all 10 | 24/30 | [63, 90] | +19 | 21:2 | 0.00 | 20.7 | 77 | **1** | compost 1073, ember_sap 154, undertow 5, tithe 35 | - |

### Graft table, deeproot, tier 0 (the four rule grafts)

`=== sweep_grafts | bot deeproot | config {  } | seeds 1..30 (30) ===`,
"grafts: ember_sap, undertow, compost, oil_tithe", with
`=== hooks_probe(scratch) | bot deeproot | config {  } | seeds 1..30 (30) ===`.
deeproot buys **no** grafts, so its base row is the only clean "hooks that
exist only because the config installed them" reading in the project.

| row | wins | CI | delta | disc. | p | dmg | turns(w) | t/o | own hooks/run | verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| (no graft) | 22/30 | [56, 86] | +0 | 0:0 | 1.00 | 11.0 | 75 | 0 | 0 (buys none) | - |
| ember_sap | 22/30 | [56, 86] | +0 | 1:1 | 1.00 | 11.8 | 75 | 0 | **11.13** (334 ignite hooks) | SHIP |
| undertow | 22/30 | [56, 86] | +0 | 0:0 | 1.00 | 11.0 | 75 | 0 | **4.27** (128 staggered hooks) | clears (ii) here |
| compost | 27/30 | [74, 97] | +5 | 6:1 | 0.12 | **4.8** | 83 | 0 | **23.67** (710 kill hooks) | SHIP |
| oil_tithe | 25/30 | [66, 93] | +3 | 6:3 | 0.51 | 7.6 | 88 | 0 | **4.40** (132 tithes) | SHIP |
| all 4 | 27/30 | [74, 97] | +5 | 6:1 | 0.12 | 10.4 | 76 | 0 | compost 675, ember_sap 473, undertow 79, tithe 99 | - |

### Reading the three tables

**Gate (iii) as applied here.** `sweep_grafts` prints a Wilson interval on each
row's own win fraction and a paired sign test against the base row on the same
seeds; it does not print an interval on the delta itself. The operational test
used above is "the row's whole Wilson interval sits below the base row's win
fraction" - and **no row in any of the three tables fails it**. Every rule
graft's delta is indistinguishable from zero at 30 seeds (the worst sign-test
p among the eight rule-graft rows is 0.50, the best 0.12). None of the four is
a measured win-rate warp, in either direction, at either tier, for either bot.

**`undertow` is the one HOLD, and the reason is the persona, not the row.**
Its hook needs a `staggered` event, i.e. forced movement interrupting a
wind-up. Over the 30-seed playtest the optimizer staggers **0.37 times a run**
and deeproot **4.27** - and the graft's own rows land exactly there: 8 hooks in
30 optimizer runs at tier 0, **1** in 30 at tier 6, and 128 in 30 deeproot
runs. It is the C2 `water_jet+` shape again (a control rider only the search
personas reach), except that this time the search persona clears the
once-per-run line comfortably. Before re-judging it, decide whether the fix is
the row, the bot (no heuristic persona seeks a shove into a wind-up), or the
board.

**`compost` is the row to watch, not the row to fear - yet.** It fires more
than any other hook in the project (23-32 per run wherever it is held) and its
only measurable effect on wins is deeproot's +5 [74, 97] against [56, 86] at
p = 0.12, with damage taken **11.0 -> 4.8 per run**, the lowest cell in any
graft table this project has recorded. It is also the row 06c explicitly warned
about: `grow_spike` reads growth adjacent to its target, and `compost` turns
every kill into another growth tile. The optimizer tables do not show that loop
paying (+1 at tier 0, -1 at tier 6, combos/run 14.33 -> 18.13 at tier 0), and
`grow_spike` riders per run did not jump (optimizer 8.50/run against 7.47 in
06c). Verify at 100 seeds and out of sample before shipping any further growth
content.

**`ember_sap` is the first content that damages the player.** magpie's 30-seed
`player dmg ... { "ember_sap": 1 }` and the 100-seed canary's `{ "ember_sap":
1 }` are small, but the hook bills *whoever* stands on the tile, and the
`c3_ember_sap` record pins that the bill lands before the beam does. On the
dealing side it is 34 damage over 100 magpie runs and 14 over 30 optimizer
runs - the hook fires 4-11 times a run and each fire is worth 1.

**`oil_tithe` fires as designed and buys nothing.** 2.10 tithes/run for the
optimizer at tier 0, 2.27 at tier 6, 4.40 for deeproot, +0/+2/+3 wins. A
1-charge discount once a turn is inside the noise of every table it appears in;
what it does change is the *bought* tithe counters everywhere (sprout 3,
magpie 6, fanatic 11, optimizer 2 per 30 runs), so the mod is reachable in
normal play without a pre-install.

**The stat rows are a re-baseline only.** Against the last graft sweep
(2026-09-06 bump 3, same runner, same seeds, same tier, six-graft shop):
base 11/30 [22, 54] -> 14/30 [30, 64]; deep_cells 12/30 -> 15/30;
verdant_pulse 14/30 -> 18/30; thick_bark 12/30 -> 13/30; bloom_surge 12/30 ->
16/30; carapace 12/30 -> 15/30; **solar_core 20/30 [49, 81] -> 26/30 [70, 95]**.
Only `solar_core` moved outside the other reading's interval (87% is above
[49, 81] and 67% is below [70, 95]); every other stat row's point estimate sits
inside its own predecessor's interval. Nothing in C3 changed what any stat
graft does - `_graft_stat` returns the same integers `_has_graft` produced, and
the parity probe proves the event streams are byte-identical - so the movement
is the new shop stock and the new pick, i.e. exactly the re-baseline this bump
exists to record. **These are the numbers to compare against next time; do not
quote the bump-3 graft table beside them.**

### The `solar_core` lever, again

Third and fourth clearing of the Method rule, and the largest yet:

| reading | base | solar_core | delta | discordant | sign p |
|---|---|---|---|---|---|
| 2026-09-05b out-of-sample (seeds 101..130) | 10/30 [19, 51] | 25/30 [66, 93] | +15 | 16:1 | 0.00 |
| 2026-09-06 in-sample (bump 3) | 11/30 [22, 54] | 20/30 [49, 81] | +9 | 10:1 | 0.01 |
| **this bump, tier 0** | 14/30 [30, 64] | **26/30 [70, 95]** | **+12** | 14:2 | **0.00** |
| **this bump, tier 6** | 5/30 [7, 34] | **22/30 [56, 86]** | **+17** | 19:2 | **0.00** |

Four readings, two seed ranges, three bumps, two tiers, the same answer. Two
new things this bump can say that the earlier ones could not:

- **The tier-6 row is the loudest number in the entry.** A +1 regen turns the
  hardest measured tier from 5/30 into 22/30 - it converts tier 6 from
  "barely winnable" (`sweep_tiers` fails a tier when the Wilson upper bound is
  under 10%; the bare row's is 34%) into roughly the bare tier-0 ceiling. The
  difficulty ladder and the graft table are not independent knobs.
- **Ten grafts are worth exactly one graft.** At tier 0 the `all 10` row is
  26/30 [70, 95] - *the same win count as `solar_core` alone*, with the same
  interval. At tier 6 `all 10` is 24/30 [63, 90] against `solar_core`'s 22/30
  [56, 86]. Owning the whole table adds nothing measurable over owning the one
  lever (and costs the run its shop: `grafts bought {}`, conversion 0.02, the
  graft price starts at 4 + 2x9). C3 was the block that owns graft values and
  it did not touch `solar_core`; that is still an open balance question, now
  with four independent readings behind it.

### Canaries (gate v)

- **magpie, 100 seeds.** `=== verify_kit | bot magpie | config {  } | seeds
  1..100 (100) ===`: **17/100 = 17% wins, win CI [11%, 26%]**, avg floor 4.1,
  turns on wins 234.8, damage taken 43.8/run, **0 timeouts**, 0 illegal, 0
  SCRIPT ERROR lines, stall floors 75, quota-unmet deaths 9, `quota reclamps
  0`. Hooks: `by graft { "compost": 1737, "ember_sap": 188, "undertow": 39 }
  by kind { "kill": 1737, "ignite": 188, "staggered": 39 } capped 0 tithe 34`,
  and all ten graft ids appear in `grafts { bloom_surge 36, solar_core 31,
  verdant_pulse 40, compost 42, carapace 15, oil_tithe 35, deep_cells 33,
  ember_sap 41, thick_bark 15, undertow 22 }` over 310 buys.
  Against the 2026-09-05d rule ("the recorded rise baseline is 10/100 = 10%
  [6, 17]; a 100-seed lower bound clearing 17% is the signal"): the lower bound
  is **11%**, which does not clear 17%, so **not a signal**. The v2 series now
  reads 10/100 [6, 17], 13/100 [8, 21], 13/100 [8, 21], 19/100 [13, 28] and
  **17/100 [11, 26]** - the first reading in the series that did not rise.
  **Compare the next one against [6, 17], not against [11, 26].** The timeout
  06c picked up is gone (1 -> 0 at both 30 and 100 seeds), so the one
  gate-(v) item 06c could not deliver is delivered here.
- **wanderer, 100 seeds.** `=== verify_kit | bot wanderer | config {  } | seeds
  1..100 (100) ===`: **0/100 = 0% [0%, 4%]**, avg floor 1.0, **0 timeouts, 0
  illegal actions, 0 SCRIPT ERROR lines**, `hooks: by graft {  } by kind {  }
  capped 0 tithe 0` (wanderer never reaches a shrine purchase). Clean pass.
- **turtle.** `=== measure_fanatic | bot fanatic | config {  } | seeds 1..30
  (30) ===` at 30 seeds: **2/30 [2%, 21%], avg floor 4.2, core-complete
  "never" (never 100%), signature 0.06, strike 0.56, 0 timeouts** against 06c's
  1/30 [1%, 17%], floor 4.2, signature 0.06, strike 0.57. One win apart, each
  point inside the other interval, and every other cell identical - the canary
  did not rise.
- **Timeouts.** 0 for all seven personas at 30 seeds and for both 100-seed
  canaries. The only timeouts anywhere in this entry are **1 in the tier-6
  `all 10` graft row** (30 optimizer runs with every graft pre-installed) and
  **1 in `measure_fanatic`'s `shover_nolance` build** (seed 1, floor 4). 06c
  recorded 1 magpie timeout at 30 seeds and 1 at 100; both are gone.

### Fanatic archetypes

`FANATIC_SEEDS=30`, `=== measure_fanatic | bot fanatic | config {  } | seeds
1..30 (30) ===`, all eight builds (06c ran the five-build subset, so the three
new columns have no before value):

| build | 06c | this bump |
|---|---|---|
| turtle | 1/30 [1, 17], floor 4.2, sig 0.06 | 2/30 [2, 21], floor 4.2, sig 0.06 |
| gardener | 9/30 [17, 48], floor 5.6, sig 0.50 | 11/30 [22, 54], floor 5.7, sig 0.54 |
| pyro | 9/30 [17, 48], floor 5.7, sig 0.05 | 8/30 [14, 44], floor 5.7, sig 0.04 |
| ember | 6/30 [10, 37], floor 5.5, sig 0.46 | 8/30 [14, 44], floor 5.6, sig 0.48 |
| pyro_nolance | 16/30 [36, 70], floor 6.3, sig 0.32 | 13/30 [27, 61], floor 6.3, sig 0.35 |
| shover | not run | 4/30 [5, 30], floor 5.7, sig 0.18 |
| shover_nolance | not run | 3/30 [3, 26], floor 4.4, sig 0.61, **1 timeout** |
| anchor | not run | 4/30 [5, 30], floor 4.3, sig 0.00 |
| total | 41/150 over 5 builds | 53/240 over 8 builds |

**Every build is above zero** (the hard target) and no build with a before
value moved outside the other interval. `shover_nolance`'s timeout (seed 1,
floor 4) is the only one in 240 runs.

### Gate verdict

`tests/playtest.gd` at 30 seeds, gate ON: **exit 0, "gate: all PASS"**.

```
PASS wanderer 0 wins, avg floor <= 2: 0 wins, avg floor 1.00
PASS wanderer illegal actions == 0: 0
PASS sprout wins rare (<= 1 per 30 seeds): 1/30
PASS sprout illegal actions == 0: 0
PASS magpie canary <= 10% (design target 0-5%): 5/30 CI [7%, 34%] (fails when the lower bound clears the trip line)
PASS magpie illegal actions == 0: 0
PASS fanatic illegal actions == 0: 0
PASS optimizer band 35-65%: 14/30 CI [30%, 64%]
PASS optimizer timeouts == 0: 0
PASS optimizer illegal actions == 0: 0
PASS deeproot band 70-90%: 22/30 CI [56%, 86%]
PASS deeproot timeouts == 0: 0
PASS deeproot illegal actions == 0: 0
gate: all PASS
```

`PLAYTEST_BOTS=deeproot_rollout PLAYTEST_SEEDS=30`: exit 0.

```
PASS deeproot_rollout illegal actions == 0: 0
gate: all PASS
```

### Regression corpus

**39 -> 45 records, all `sim_version: 5`.** Plain and `REGRESS_STRICT=1` both
"regressions: 45 ok, 0 failed", exit 0. Before the corpus work the suite was
"regressions: 0 ok, 39 failed", exit 1, every line "stale record: sim_version 4
!= 5". What the corpus phase did, from its report:

- **6 new hand-scripted records**, one per rule graft plus a cap case and a
  stat-graft case: `c3_ember_sap` (the ignite hook bills the tile's occupant
  *before* the beam lands: 1 + 2 kills a 3-hp bot the bare lance leaves alive),
  `c3_ember_sap_cap` (one `sun_flare` lights four oil tiles, three hooks fire
  and the fourth is skipped - proved *positively*, because with the fourth hook
  the bot would die inside the cast and the recorded trailing fire tick and
  death could not exist), `c3_undertow` (jet -> collision -> staggered -> hook
  -> root 1), `c3_compost` (kill -> hook -> growth, then `mycelium_dash`
  teleports onto it to prove it is real growth), `c3_oil_tithe` (turn 1 spends
  1 + 2, turn 2 casts a 2-cost lance on 1 charge - a cast that is illegal
  without the discount), `c3_stat_grafts` (three grafts at once: `thick_bark`
  reads shield 2/4/5 where the bare cap reads 2/3/3, and `solar_core` +
  `deep_cells` pay six lances on turn 4, which neither graft can do alone).
- **18 fixed-board records re-stamped only** (expect and hash byte-identical),
  **3 fixed-board records whose hash changed with expect unchanged**
  (`blockb_forge_once`, `blockb_graft_buy`, `c1b_spore_vial`: their floor
  carries a shrine, the shop is stocked in `_enter_floor` and `snapshot()`
  includes `shop`, so the ten-graft side draw moves the state hash even when
  the shop is never used), **7 bot logs whose action list and outcome survived
  and whose hash moved**, and **11 bot logs re-recorded** because the new stock
  plus the tag-overlap pick desynchronises them from the first shrine on.
- **One hand-edit `REGEN=1` can never do**: `blockb_graft_buy`'s expected event
  id `carapace` -> `bloom_surge`, because that fixed floor's shrine now stocks
  `["bloom_surge", "verdant_pulse"]`.
- **magpie lost both of its determinism-seed wins** on re-record
  (`det_magpie_s3` won floor 7 in 238 turns -> died floor 3 at 113;
  `det_magpie_s42` won floor 7 in 134 -> died floor 4 at 146), while the
  optimizer kept 3/3 on the same seeds but took 30-45 more turns each
  (68 -> 113, 78 -> 83, 88 -> 121). Three seeds is noise and the 30- and
  100-seed numbers above say magpie did not move; recorded here because it is
  the corpus's own evidence and it points the same way as the re-baseline.

### Anything else that moved

- **Nothing in this entry is comparable per seed with anything before it.** The
  ten-graft shop draw reaches every seed of every persona, so this bump is a
  re-baseline by construction. Aggregate win rates still compare (same
  instruments, same seeds, same personas) and none of the seven moved; the
  paired A/B that 06c could run against a pristine tree is not available here.
- **magpie's damage taken rose again**, 43.6 -> 52.1 per run at 30 seeds on the
  same 5 wins, with shrine turns 29.60 -> 27.57 and 93 graft offers discarded.
  Its signature share fell 0.57 -> 0.53. Greed now has ten permanents to shop
  for and spends the same time in the smog buying them.
- **deeproot's damage taken fell 11.0 -> 4.8 per run in the `compost` row** and
  its rollout sibling's is 4.1 in the playtest (3.4 in 06c). The ceiling's
  terrain share held at 0.16 (0.11 for the rollout) and its collision damage is
  still the roster's largest (`collision` 299 over 30 runs).
- **`resisted` is unchanged at 2** (fanatic only, exactly as in 06c; 0 for
  every other persona at 30 seeds and 0 over the 100-seed magpie canary), and
  it is still `seed_bomb+`'s root doing it, not `undertow`'s: root statuses run
  fanatic 56, deeproot_rollout 16, optimizer 5, sprout 2, magpie 1, deeproot 1,
  and at 4-8 `undertow` hooks per 30 optimizer runs the graft cannot exercise
  the cooldown either way. `spore` statuses are still 0 everywhere.
- **`quota_reclamp` has still never fired in a bot run** - 0 over this entry's
  210 playtest runs, 200 canary runs and 900 graft-sweep runs (the 540
  hook-probe runs do not print it), on top of every earlier bump. Five bumps. Its only coverage remains
  `tests/test_economy.gd` and the two `blockb_quota_reclamp*` records.
- **Press and forge are still dead sinks**: `upcycles 0/0` for every persona in
  every run in this entry.
- **`hook_capped` has never fired in play** (0 in all 950 runs that print it),
  so `HOOK_DEPTH_MAX` and `HOOK_STEP_CAP` are load-bearing only in the tests.
  The sim phase notes the reachable nesting in C3 is exactly one level
  (`ember_sap` ignite -> kill -> `compost` growth), so the depth cap has no
  natural pressure until a hook writes terrain that fires another hook.
- **`tests/sweep_grafts.gd` cannot print the hooks line.** Only
  `tests/playtest.gd` and `tests/verify_kit.gd` call `Tally.print_block`;
  `sweep_grafts.gd:84` prints its own compact KPI pair. Every "own hooks/run"
  cell above therefore comes from a scratch probe that re-runs the same configs
  through `Sweep.measure` (win columns reproduce the sweep exactly, which is
  how the probe is validated). Whoever owns `tests/sweep_lib.gd` can end that
  by adding `str(t.hooks_by_graft)` to the per-config line.
- **Not measured for this bump:** no `sweep_combos`, `sweep_packages`,
  `sweep_tiers`, `measure_bosses` or `draft_oracle` run. Locked-kit lift, tier
  winnability, boss arrivals and draft regret are still the 06c / bump-3
  numbers, and all of them predate the ten-graft shop, so every one of them is
  stale in the same way the corpus was.

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
  target has been unmet for longer than bump 2. The gate's trip line was
  re-derived to a 10% CI lower bound (2026-09-05d) so the drift is tracked
  here, not in the merge gate: greed at ~2x its design target is an open
  balance question and the next 100-seed rise above [6, 17] is the real
  signal.
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
  itself is still not met (the interval clears 5%), which is the older drift,
  not this bump's - the gate line now passes only because its trip line was
  re-derived to 10% in 2026-09-05d.
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

### Bump-3 additions (2026-09-06)

- **Ash costs bloom through `room_bloom`, not only through the quota.** The
  cheapest demonstration is in the corpus: `det_sprout_s11` earns 37 bloom
  after the bump instead of 39, because one ash tile left standing keeps its
  room uncleansed and cancels that room's bonus (room_bloom 6 -> 5). A bot
  that ignites now forfeits room bonuses unless it comes back to cleanse the
  burn. No CI attaches to this - it is one record - but it is the mechanism
  behind every "burn then leave" line and it wants a 100-seed look before any
  fire-pool content ships.
- **Lighting oil opened the green gate - CLOSED (2026-09-06b).** As C1b
  shipped, `_reclamp_quota` fired at ignition (fire was not corruption per
  `Content.TERRAIN`) and the clamp only ever lowers `green_need`, so a burn
  woke a dormant stairs. The revision makes fire count as the ash it will
  leave (`Content.counts_as_corruption`, read by `_count_corruption` and
  `_room_has_corruption` only): ignition and burnout now emit no
  `quota_reclamp`, the room bloom and `floor_restored` wait for the ash, and a
  wash is still the bloomless removal that shrinks the gate. Measured cost at
  30 seeds: no win count moved on any of the seven personas, and the 100-seed
  magpie canary is unchanged at 13/100 [8, 21]. What is still open is the
  successor question below - nobody has ever seen `quota_reclamp` fire in
  play, before or after this fix.
- **Root's cooldown and spore's stacking are effectively unmeasured in play.**
  `resisted` is 0 across all 210 playtest runs and 3 across 100 magpie seeds;
  `root` statuses appear only for fanatic (23 per 30 runs) and magpie (2);
  `spore` statuses are 0 everywhere, and the bot-derived regression corpus
  produces 0 rooted, 0 resisted and 0 spore events. Both rules are pinned only
  by `tests/test_grammar.gd` and two hand-scripted records. Measuring root
  pressure needs a persona that spams `sap_snare` (fanatic anchor/turtle at
  more seeds, or a `verify_kit` config that locks it in); measuring spore
  needs any bot that casts `spore_cloud` twice.
- **Stall floors rose on the two cleanest personas without a CI to judge it
  by:** optimizer 2 -> 5 and deeproot_rollout 1 -> 4 over 30 runs (fanatic
  6 -> 9; wanderer, sprout, magpie, deeproot flat or down). Timeouts stayed 0
  everywhere, so nothing loops on ash, but "the floor is not finished when the
  fire goes out" is exactly the shape that would produce this. Re-check at 100
  seeds before treating it as a clock regression or patching anything.
- **deeproot's damage taken rose 7.5 -> 10.6 per run** (rollout 2.8 -> 3.1)
  with combos/run up 14.10 -> 15.53. The ceiling burns more than any persona
  (539 burnouts per 30 runs) and now stands next to what it burnt. Watch it if
  the deeproot band ever slips below 70%.
- **`solar_core` has now cleared the Method rule twice.** In-sample this bump:
  20/30 [49, 81] vs base 11/30 [22, 54], +9, 10:1 discordant, p=0.01;
  out-of-sample in bump 2: 25/30 [66, 93] vs 10/30 [19, 51], 16:1, p=0.00.
  Two seed ranges, two bumps, the same answer - the graft table is one lever
  and five fillers, and 6.3's Block C3 owns the fix. Nothing here was patched.
- **`quota_reclamp` has still never fired in a bot run** - 0 over this bump's
  210 playtest runs, 240 graft-sweep runs and 100 magpie seeds, on top of the
  550 runs bump 2 recorded. Its only coverage remains synthetic
  (`test_economy` section g, `blockb_quota_reclamp.json`, and the new
  `blockb_quota_reclamp_wash.json`). Three bumps is long enough that the honest
  statement is: nobody has ever seen the strandable-gate fix work in play.
- **The magpie canary's rise baseline stays 10/100 [6, 17].** This bump
  measures 13/100 [8, 21], which does not clear it (2026-09-05d's rule), so no
  signal - but it is the second consecutive 100-seed number whose interval sits
  entirely above the 0-5% design target. Compare the next one against [6, 17],
  not against [8, 21].
- **New terrain now costs three consumer edits.** `tests/test_shell.gd`
  asserts every `Content.TERRAIN` kind has an SVG sprite, an
  `AsciiView.TERRAIN_CH` glyph and a shell legend row, and
  `tests/test_invariants.gd` carries a hand-maintained `GEN_ONLY_KINDS` list
  of kinds mapgen must never emit. Adding a row without those fails the shell
  test loudly (intended) but the runtime-only list is a literal nobody
  generates from the table - a future runtime-only kind is silently allowed
  until someone edits it.

### Bump-4 additions (2026-09-06c)

- **Four of the seven C2 rows are on HOLD, and two of those never fire.**
  `water_jet+`'s pin fired 9 rider events over the 680 runs in the 2026-09-06c
  entry - 1 for deeproot, 8 for deeproot_rollout, 0 for every heuristic
  persona - and `vine_whip+`'s ember drag fired **0**. Both are proven correct
  by `tests/test_grammar.gd` and their `c2_*` records; what they lack is an
  opportunity rate. Before re-judging them, decide whether the fix is the row
  (drop the `pushed` conjunct so a wall pin also roots, widen
  `outcome_crossed`), the bot (a lance-line-opening branch), or the board
  (fires and pillars where a shove can use them). `sun_flare` (0.03
  riders/run) and `sun_flare+` (0.63) fire but under gate 6.0's once-per-run
  line; their opportunity rate matches the review's own "on fire under 1% of
  sightings" telemetry, so the honest question is whether that gate line is
  right for a terrain-conditional bonus.
- **The magpie canary rose again: 13/100 [8, 21] -> 19/100 [13, 28]**, measured
  as a same-seed A/B against the pristine pre-C2 tree (which reproduced the 06b
  number exactly). By the 2026-09-05d rule this is not a signal - the lower
  bound 13% does not clear the recorded rise baseline's 17% - but the v2 series
  now reads 10/100, 13/100, 13/100, 19/100, so this is the highest reading yet
  and the first whose whole interval clears 10%, and the 30-seed gate line
  (`5/30 [7, 34]`) passes only because its trip line was re-derived to 10%.
  **Compare the next 100-seed run against [6, 17].** If it clears 17%,
  `grow_spike` is the first place to look: greed's rider count is 1,563 per
  100 runs and 1,221 of them are that one row.
- **magpie gained a timeout** (0 -> 1 at 30 seeds, 0 -> 1 at 100 seeds; seed 22,
  floor 4, 400-turn cap). The autopsy shows the pre-existing two-tile
  oscillation-plus-growth-heal loop at (22,11)/(22,12) with the stairs
  reachable at (21,10), not a combo loop - but it is a stall that C2's cheap
  repeatable heal-adjacent play made reachable on a seed where it was not
  before. magpie is not in `playtest.NO_TIMEOUT` (optimizer and deeproot only),
  so nothing gates this. Gate 6.0 (v) asks for an unchanged timeout count and
  this bump does not deliver one.
- **`grow_spike` is a one-lever kit.** Locked, it is +7 wins and 0.83 of the
  kit's signature damage; open-pool forced, 22/30 [56, 86]. Verify at 100 seeds
  and out of sample (`SWEEP_SEED_FROM=101`) before C3 ships `compost`, which
  turns every kill into another growth tile and therefore another `per` stack.
- **`resisted` is finally non-zero in play** (fanatic 2 over 30 runs, with
  `root` 23 -> 57), so bump 3's "root's cooldown is unmeasured" watch item is
  partly closed by `seed_bomb+`. `spore` statuses are still 0 everywhere.
- **`sweep_combos` prints duplicate singles rows** when an id appears in more
  than one selected pair (`_run_lift` appends to `single_ids` before the
  `singles.has(aid)` guard takes effect for the *next* pair). Display only -
  both copies are the same measurement - but it makes a `SWEEP_PAIRS` table
  look like it measured an id twice.
- **Two rows are the first things to revert if a later sweep dislikes this
  bump**, per the bot phase: `optimizer.gd:216-219` fires `sun_flare` when
  `_aoe_finishes` says the estimate kills inside the radius (delete the
  `or _aoe_finishes(...)` clause), and `fanatic.gd:166-173` hoists the spike
  above the remaining build casts so the seed-on-head lead is not eaten by a
  second bomb. The flare branch is the likeliest cause of `sun_flare`'s locked
  row losing 3 wins.

### Bump-5 additions (2026-09-06d)

- **`solar_core` is now four-for-four and the tier-6 row is the loudest yet:**
  5/30 [7, 34] -> 22/30 [56, 86], +17, 19:2 discordant, p = 0.00, on top of
  tier 0's 14/30 [30, 64] -> 26/30 [70, 95], +12, 14:2, p = 0.00. It is the
  only row in the whole re-baseline that moved outside its own predecessor's
  interval (bump 3: 20/30 [49, 81]; 87% is above that and 67% is below
  [70, 95]). Owning the whole ten-row table is worth the same
  26/30 as owning `solar_core` alone at tier 0. C3 was the block that owns
  graft values and chose not to touch it; the next block that opens `GRAFTS`
  should either price regen or say why it is a deliberate power spike.
- **`undertow` is the C3 row on HOLD:** 8 hooks over 30 optimizer runs at
  tier 0 and **1** over 30 at tier 6, against 128 over 30 deeproot runs. The
  optimizer staggers 0.37 times a run and deeproot 4.27; the row is fine and
  the opportunity rate is not there for heuristic play. Same shape as C2's
  `water_jet+`, which is also a shove rider - two blocks in a row have shipped
  control content only the search personas reach. Judge any further
  displacement content with a deeproot forced-kit run, per the standing watch
  item about fanatic and control archetypes.
- **`compost` fires 23-32 times a run and is the growth-loop risk 06c flagged.**
  Its only visible win effect is deeproot +5 [74, 97] at p = 0.12 with damage
  taken 11.0 -> 4.8 - the lowest damage cell in any graft table on record.
  The `grow_spike` loop it was predicted to feed has not shown up in the
  optimizer tables yet (+1 at tier 0, -1 at tier 6, riders/run 7.47 -> 8.50).
  Verify at 100 seeds and out of sample (`SWEEP_SEED_FROM=101`) before any
  further growth content, and re-run `sweep_combos` for `grow_spike` pairs,
  which has not been measured since the graft table changed.
- **The magpie canary did not rise for the first time in the v2 series.**
  10/100 [6, 17], 13/100 [8, 21], 13/100 [8, 21], 19/100 [13, 28], and now
  **17/100 [11, 26]** with **0 timeouts** (06c had 1 at 30 seeds and 1 at 100).
  Not a signal either way by the 2026-09-05d rule; the trip line is still
  "a lower bound clearing 17%", and 11% is well under it. **Compare the next
  100-seed run against [6, 17].**
- **Every pre-C3 measurement of a shop is stale, not just the corpus.** The
  shrine's graft offers come from a side-rng draw over `Content.GRAFTS`, so
  going from six rows to ten re-rolls every shop on every seed even for a bot
  that buys nothing - `blockb_forge_once`, `blockb_graft_buy` and
  `c1b_spore_vial` changed their state hash without changing a single action.
  Any future `GRAFTS` addition does the same thing: it is a `SIM_VERSION` bump
  and a corpus pass, not a data-only edit.
- **The hook caps are untested in play.** `hook_capped` is 0 across all 950
  runs in this entry that print it, and the only reachable nesting in C3 is
  depth 2. The caps exist for content that does not exist yet; the first hook
  that writes terrain firing another hook is the one to re-measure them on.
- **`tests/sweep_grafts.gd` still prints no hooks line**, so the per-graft hook
  counts in this entry come from a scratch probe rather than a repo runner.
  That is a measurement gap, not a result: the next person to want these
  numbers has to rebuild the probe unless `sweep_lib`'s per-config line grows
  the counter.
- **Two graft rows are the first things to revert if a later sweep dislikes
  this bump**, in this order: `undertow` (no heuristic opportunity rate) and
  `compost` (the growth loop that no 30-seed table has yet priced). `ember_sap`
  and `oil_tithe` both fire several times a run and move no win rate outside
  noise at either tier.
