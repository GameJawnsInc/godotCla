# Progression review: build depth and combo potential

An adversarial review of TENDER's progression systems (draft, kit, shrine,
grafts, items, upcycling, bloom economy, green gate, meta career) and of the
batch AI runners that are supposed to measure them. The question asked was:
*why does the game not yet have build depth or combo potential, and what would
give it both?*

Method: four code audits (primitives, in-run progression, meta + runners, bot
coverage), two instrumented headless measurements (event-stream telemetry over
180 bot runs; a synergy-lift sweep of 7 hypothesised pairs at 24 seeds per
config, tier 0 and tier 6), then five adversarial lenses each followed by a
refuter that re-checked every claim against the code, a three-angle design
panel with a judge, and a completeness critic. Every claim below cites a
`file:line` in the tree at commit `eb4425f`; numbers come from the scripts
listed in Appendix C.

Date: 2026-09-05. Branch: `claude/skill-auto-runner-review-g24u57`.

---

## 1. Verdict in one page

**The game has one build.** Across 180 runs and five personas the final kit
contained `solar_lance`, `seed_bomb`, and `mycelium_dash` in 35-40 of 40 runs
per bot; all variety lives in two flex slots dominated by `grow_spike`,
`thorn_shield`, and `sun_flare`. Strike plus `solar_lance` plus `grow_spike`
account for 97% of enemy damage for the optimizer, 98% for magpie, 97% for
sprout, and 78% for the ceiling bot. Terrain-derived damage (fire, collision,
thorns, spore) is 1.5% to 3.9% for heuristic play and 11% at the ceiling.

**Combos do not fire.** With `grow_spike` and `overgrowth` locked into the
ceiling bot's kit for 24 runs, the spike landed next to overgrowth-made growth
3 times in total. With `sun_flare` and `root_wall` locked in, the flare went
off while a wall stood 4 times in 24 runs. No hypothesised pair shows positive
lift over its best single at either tier; at tier 6 every pair is worth *less*
than the sum of its parts.

**The reasons are structural, not numeric:**

1. The effect grammar cannot express a combo. Every ability is a flat list of
   effect ops with no conditions, triggers, or scaling
   (`sim/game.gd:1250-1394`). Nine of 24 abilities are pure stat sticks; all
   15 `+` upgrades are numeric bumps; zero grafts touch what an ability does
   (`_apply_effect` has no graft consult).
2. The draft cannot express a commitment. Six 1-of-3 offers from one uniform
   pool that mixes new abilities and upgrades; nearly the whole pool (9 of
   11) is seen every run; no synergy tags, no weighting toward the kit, no
   reroll, no way to protect or replace a starter.
3. The shrine is "buy whatever is stocked." One of each item per floor,
   uniform draws, so the only decision is affordability. Every bot encodes
   this as a fixed purchase order; the ceiling bot buys nothing and wins with
   43 bloom unspent.
4. Grafts are six flat stat modifiers consulted at exactly six sites
   (`game.gd:350, 386, 771, 861, 1153, 1157`). None creates a build.
5. The meta layer forces content rather than offering it: unlocked packages
   are always in the pool (`meta/profile.gd:59`), diluting both targeted
   synergies and upgrade odds (36% to 22% per offer with a full kit); no
   package ability has a `+` form; mutators are unlockable but the shell
   never exposes them (`shell/main.gd:193`).
6. The harness cannot see any of this. No runner aggregates the event stream,
   measures synergy lift, or records offer-vs-pick rates; `sweep_combos.gd`
   measures "start with the pair, then drift to the bot's favourites"; the
   ceiling bot cannot plan a two-step combo, never searches its drafts, and
   evaluates as few as one ability per turn at a shrine.

Sections 2 to 4 are the evidence. Section 5 is the adversarially verified
finding list. Section 6 is the judged roadmap. Section 7 is the harness plan
that has to land first, because an unmeasured mechanic reads as neutral and
gets shipped as filler.

---

## 2. The systems as they are

### 2.1 Effect grammar

`_apply_effect(eff, adef, target)` dispatches on `eff["op"]` over 21 ops
(`sim/game.gd:1250-1394`). Effects run in list order with no shared per-cast
state, so two effects in one ability, or two abilities in one turn, never
reference each other except through persistent terrain and status.

| Class | Count | Abilities |
|---|---|---|
| World-state conditional (reads terrain, status, dim, position) | 13 | solar_lance, vine_whip, water_jet, mycelium_dash, sun_flare, overgrowth, grow_spike, tide, geyser, gust, updraft, clear_air, moss_filter |
| Reactive (fires on an enemy action) | 2 | bramble_coat, anchor_roots |
| Unconditional stat stick or terrain writer | 9 | thorn_shield, pollen_burst, sap_snare, spore_cloud, burrow, seed_bomb, fungal_ring, root_wall, steam_vent |
| Output scales with a countable world quantity | 10 | solar_lance, water_jet, tide, sun_flare, overgrowth, pollen_burst, spore_cloud, geyser, clear_air, bramble_coat |
| `+` forms that add a condition / remove one / add an op | 1 / 3 / 0 | solar_lance+ adds a dim conditional; seed_bomb+, root_wall+, moss_filter+ drop to cost 1 and lose verdant surge |

Terrain is where DESIGN.md says combos live. The interaction matrix
(Appendix A) shows what exists and what does not:

- **Exists:** lance ignites oil and stops at smoke; wash removes oil and fire
  and pushes the first enemy; pushes deal collision damage into walls, enemies,
  and roots; growth discounts a 2-cost cast (verdant surge), heals, seals a
  vent, is the dash target, the spike condition, and the boss-gate key; fire
  spreads to adjacent oil one tile per turn; roots block pathing, pushes, and
  vent spawns; stun pauses summon/ooze/stoke timers; thorns reflect melee,
  slams within 2, and quakes.
- **Absent:** fire never touches growth, goo, smoke, or roots; water never
  touches goo, smoke, or growth; pull never drags oil or ignites; teleport
  skips `_player_enter_tile` (`game.gd:1338`); root status gates only the
  `move` intent, so a rooted adjacent enemy attacks every turn and the root
  never ticks (`game.gd:569-572`); smoke blocks only the *player's* beam and
  whip line, enemies have no line of sight anywhere; enemies never react to
  growth, oil, goo, or smoke when pathing; statuses never stack (`game.gd:489`).

Fire is the only terrain with a chain reaction, and its `ttl 2` is hardcoded
in five places (`game.gd:613, 764, 1260, 1372, 1579`). Roots are the strongest
hidden combo piece (collision walls, silent vent-spawn skip, BFS blocker) but
beams pass straight through them.

### 2.2 In-run progression

| System | Shape | Where |
|---|---|---|
| Kit | 5 slots (3 under `kit_of_3`), starts with 3 fixed abilities; any slot may be dropped, including the only mobility, which is outside the pool and never re-offered | `content.gd:12, 178`; `game.gd:944-951` |
| Draft | 6 drafts (descents 1-6) x 3 offers; candidates = unowned pool abilities + `+` forms of owned ones, one uniform draw without replacement; full kit turns each new pick into a drop; skip gives nothing | `game.gd:903, 914-929, 958` |
| Upgrades | 15 `+` forms, all numeric; package abilities have none | `content.gd:114-174` |
| Shrine | one heal (3), one ability (4), one graft (4 + 2 per owned), one item (2), each erased on purchase; press two items for 1; forge one ability to `+` by scrapping another for 3 | `game.gd:354-380, 1002-1043, 1097-1145` |
| Grafts | 6 flat modifiers: +2 bank cap, growth heal +1, +2 shield cap, +1 bloom per cleanse, +1 regen, 2 shield at floor start | `game.gd:350, 386, 771, 861, 1153, 1157` |
| Items | 5 base + 5 `+`, satchel 2, use is a free action; only `sun_capsule` (charge) and `iron_seed` (shield cap, +1 max HP on `+`) touch another system; none touches terrain | `game.gd:964-1000` |
| Bloom | +1 per cleanse (+3 rich goo), +2 and a supply pod when a room's last corruption falls, +5 once when a floor is fully restored, +4 per elite kill; sinks as above | `game.gd:861, 880-886, 1078, 1422` |
| Green gate | stairs dormant until `green_need` cleanses (2/3/3/3/3/4), clamped to generated corruption once at floor entry; quota cleanses thin smog by 2, the next four by 1, then 0 | `game.gd:341, 868-873` |
| Verdant surge | a 2+ cost cast on growth costs 1 less and consumes the tile | `game.gd:1172-1189` |

Draft decision space, measured by Monte Carlo over the real
`_draw_draft_offers` (20k runs): about 9.0 of the 11 non-starter pool
abilities are seen every run (12 of 20 with packages); random-legal policies
reach 7k to 17k distinct final kits against an analytic bound of 122k (545k
with packages). The pool is small enough that "what you see" is not the
source of variety; only ordering and timing are.

Per-floor bloom supply (200 seeds, tier 0): generated corruption
6.0 / 9.9 / 16.1 / 21.9 / 24.2 / 22.9 / 6.0 tiles on floors 1-7, rich goo
0.8-1.3 tiles on floors 2-6, 3-5 bloomable rooms per floor. A full-clear
floor yields roughly 17 to 46 bloom; a quota-only floor 2 to 8. The whole
graft set costs 54.

### 2.3 Meta career

`meta/profile.gd` unlocks by career events: reach floor 5 (mycology), first
win (tier 1, hydraulics, `kit_of_3`, `double_oil`), first tier-1+ win
(aeolian, `brittle`, `parched`), second win (`overtime`, `boarded`), then one
tier per win up to 8. Everything a player can *choose* collapses to the tier
picker: `game_config()` returns every unlocked package unconditionally
(`profile.gd:59`), and the shell calls it with no mutators argument
(`shell/main.gd:193`; `grep muta shell/` is empty). Six of nine milestones
unlock content the shipped game cannot select. All eight tiers are difficulty
or price modifiers; none reshapes the draft or the build space.

### 2.4 Bots and runners

Bot coverage of the 24 abilities (Appendix B) is narrow and hardcoded. The
optimizer ladder has cast branches for 15 abilities and never casts nine of
them; `geyser` and `pollen_burst` have branches that are structurally
unreachable because the strike branch (`optimizer.gd:143`) runs first and is
always legal when their trigger is true (22 and 10 held runs, 0 casts).
Sprout casts only `solar_lance`. Fanatic supplies the only real triggers for
the control abilities but aims tile casts at the first legal target, which is
the topmost tile in scan order (`game.gd:1198-1208`), so `overgrowth`
converted anything in at most 17 of 111 casts. Deeproot, the ceiling, is a
greedy 1-ply searcher with `MAX_CANDIDATES = 30` filled in kit-slot order
after all non-ability actions, so `seed_bomb` (slot 1, up to 25 targets)
crowds out drafted abilities in slots 3-4 (23-35% of their candidates
truncated on the base pool, 51-96% with packages); at a shrine 26-29
non-ability actions leave room for zero or one ability. Its `_score()`
(`deeproot.gd:107-135`) has no term for grafts, `+` forms, kit contents,
gummed slots, thorns, anchor, growth underfoot, enemy statuses, terrain, or
raw smog, and it does not search its drafts at all (`deeproot.gd:26` calls
the optimizer's static list).

Twelve runner scripts share one copy-pasted `BOTS` dict (6 copies) and one run
loop (10 copies). `sweep_lib.run_one` returns only `{won, floor, turns, kit}`.
No runner reads the event stream or `player.uses`, computes a confidence
interval, exploits the paired-seed design, measures pair-vs-single lift, or
records offer-vs-pick rates. `sweep_combos.gd` runs 66 pairs at 10 seeds with a
30-point flag while BALANCE.md itself states the noise is plus or minus 8 in
30; `BALANCE.md` still cites 45 pairs. No committed regression corpus exists
despite CLAUDE.md mandating (seed, action list) pairs.

---

## 3. What the measurements say

Scripts: `telemetry.gd` (40 seeds each for optimizer, fanatic, magpie,
sprout; 20 for deeproot; tier 0, base pool) and `lift.gd` (deeproot, locked
kits via `{kit: K, pool: K}`, 24 seeds per config). Full tables in Appendix C.

### 3.1 How bots actually play

| bot | win% | casts/run | strike share of (strike+cast) | top-3 damage sources | terrain-derived damage |
|---|---|---|---|---|---|
| optimizer | 42% | 22 | 58% | strike 39%, solar_lance 39%, grow_spike 19% | 2.3% |
| fanatic | 25% | 67 | 25% | solar_lance 53%, strike 23%, grow_spike 13% | 3.9% |
| deeproot | 90% | 42 | 18% | solar_lance 58%, strike 11%, grow_spike 9% | 11.1% |
| magpie | 8% | 29 | 51% | solar_lance 35%, grow_spike 32%, strike 31% | 1.5% |
| sprout | 0% | 12 | 62% | solar_lance 60%, strike 37% | 2.6% |

Combo firings per run: ability-caused ignites 1.0-2.7 (environmental
ignites 2.4-6.8); verdant surges 1.5-2.2 for optimizer/magpie/sprout, 6.0
fanatic, 3.3 deeproot; staggers 0.17 optimizer, 1.5-1.7 deeproot/fanatic;
collision hits 0.05-1.55; thorns hits 0 for every bot but fanatic (0.6);
spore ticks 0 (no spore source in the base pool); floor restored 0.03-0.05
(magpie 0.62). The `+5` restoration bonus is effectively magpie-only content.

### 3.2 Drafting and kits

Pick rates mirror the optimizer's hardcoded list: `sun_flare` 100%,
`grow_spike` 86-90%, `thorn_shield` 81-87%, `water_jet` 65-84%, versus
`anchor_roots` 0-7%, `bramble_coat` 0%, `root_wall` 0-3%, `overgrowth` 0-9%.
The high-pick abilities are also the most dropped (`water_jet` 18 drops in 40
optimizer runs, cast 0.4 per run held): they are placeholders until
`grow_spike` or `thorn_shield` appear. `mycelium_dash+` was offered 118 times
across four bots and picked 0 times. Skip rate is 0% for optimizer, deeproot,
and magpie. The ceiling bot picks every draft and churns one slot constantly
(2.95 drops per run).

Dead-when-held (casts per run in which the ability was ever held, non-fanatic
bots): `anchor_roots` 0-2.5, `bramble_coat` 0.0, `root_wall` 0.0, `overgrowth`
0.0, `pollen_burst` 0.0-0.07, `sap_snare` 0.0-0.14 (held in 10 deeproot runs,
drafted at 46-62%, cast 0 times). `mycelium_dash` is in 40/40 kits and cast
0.15-0.42 times per run by four of five bots.

Distinct final kit sets: 22/40 optimizer, 15/20 deeproot, 26/40 fanatic and
magpie, 29/40 sprout, but every set contains the three starters.

### 3.3 Economy

Grafts are bought now (contradicting the pre-August BALANCE.md note):
optimizer 55 in 40 runs, magpie 115, fanatic 59, spread almost uniformly over
all six because they are bought by availability, not fit. Deeproot buys 3
items in 20 runs and nothing else, finishing wins with 42.8 bloom unspent.
Every bot ends with 30-44 unspent bloom on average. Upcycling was used 0 times
in 180 runs (press and forge). Every `+` item seen in a satchel came from a
pod or shop that hands out `+` forms directly (half the time), not from
pressing. Bots hit `satchel_full` 0.7-0.9 times per run (magpie 3.5).

### 3.4 Synergy lift

Lift = pair wins minus the better single's wins, deeproot on locked 5-kits,
N = 24, binomial standard error 2.4 wins at p = 0.5 and 1.5 at p = 0.9.

| pair | tier 0 lift | tier 6 lift | tier 6 pair minus additive |
|---|---|---|---|
| grow_spike + overgrowth | +0 | +0 | -2 |
| sun_flare + water_jet | -1 | -2 | -8 |
| sun_flare + root_wall | +0 | -1 | -1 |
| water_jet + vine_whip | +0 | -1 | -5 |
| bramble_coat + root_wall | -1 | -2 | -2 |
| sap_snare + sun_flare | -3 | -4 | -3 |
| thorn_shield + overgrowth | +0 | -8 | -2 |

Tier 0 is a ceiling: the 4-ability baseline (starters plus the near-inert
`anchor_roots`) wins 23/24, so nothing can show lift. Tier 6 opens headroom
(baseline 16/24) and single-ability value becomes visible: `water_jet` +7,
`sun_flare` +6, `bramble_coat` +6, `grow_spike` +4, `vine_whip` +4,
`overgrowth` +2, `root_wall` 0, `sap_snare` -1, `thorn_shield` -6 (a trap for
the search bot: 729 casts in 24 runs, exactly the shield-spam bias on the
BALANCE.md watch list). Every tier-6 pair is worth less than the sum of its
solo gains. Drift controls (kit set but pool left default) confirm the
existing `sweep_combos` methodology measures "start with the pair, then drift
to the bot's favourites": the injected `overgrowth` was cast 0 times in 24
drift runs.

Two conclusions, held apart deliberately: (a) the current harness cannot see
a two-step combo, so these numbers bound what is *measurable*, not what a
human can do; (b) even so, the fact that the ceiling bot wins 96% with four
buttons and gets *worse* with a fifth says the base run rewards a small
efficient kit, not a build.

---

## 4. Confirmed defects and inconsistencies

Each of these was verified by reading the cited lines and, where marked, by a
headless probe (`audit.gd`, `probe.gd`, `gate_scan.gd`, `trunc.gd` in the
scratchpad).

### 4.1 Progression correctness

| # | Defect | Where | Verified |
|---|---|---|---|
| 1 | Shrine can stock the base of an owned `+` ability (`_stock_shop` checks only `kit.has(aid)`); buying yields X and X+ in one kit and the draft then upgrades the duplicate to a second X+ | `game.gd:368` | probe: 31/300 stocks |
| 2 | Shop item and supply pods draw from all `Content.ITEMS.keys()` including the five `+` forms: half of shops and pods hand out upcycled items at 2 bloom, undercutting the 1-bloom press | `game.gd:378, 1092` | probe: 500/1000, 162/311 |
| 3 | Non-cleanse corruption removal (wash, burnout, overgrowth) grants no bloom or `greened` and `green_need` is clamped only at floor entry, so the gate can become unreachable; the optimizer destroys about 10.7 corruption tiles per run bloomlessly | `game.gd:341, 850-885, 1385, 1522` | probe A4/B2; 0 bot softlocks in 120 runs |
| 4 | `fuse` erases the partner with `enemies.erase()`: an elite partner's +4 bounty is never paid, no death event fires, the hulk is not elite | `game.gd:578-582` | probe |
| 5 | `uses[]` never erases the base key on upgrade or forge and keeps dropped/scrapped abilities; it double-counts and feeds `state_hash()` | `game.gd:942, 951, 1032` | probe |
| 6 | Draft drop writes the slot in place, so a live `gummed[slot]` transfers onto the freshly drafted ability across the floor transition | `game.gd:951` vs `389-392` | probe: gummed {3:1} |
| 7 | `mycelium_dash` is droppable but outside `DRAFT_POOL` and shop stock: the only mobility can be lost forever; bots hardcode never dropping it, humans are unprotected | `content.gd:178`; `game.gd:944-951` | code |
| 8 | Ability purchase has no drop path: dead when the kit is full and always dead under `kit_of_3` unless a forge shrinks the kit | `game.gd:217, 1114-1116` | probe |
| 9 | `_stock_shop` draws ability and graft from the main rng while the item uses `_side_rng`; violates the side-channel rule in CLAUDE.md, and the graft draw vanishes once all six are owned, shifting the stream | `game.gd:371, 377` vs `378` | code |
| 10 | Press and forge ignore the Gouging Prices markup and remain available at Boarded shrines | `game.gd:126-134, 1002-1028` | probe |
| 11 | `deep_cells` is dead under `parched` (bank cap forced to 0 first) but still stocked and sold | `game.gd:1150-1153` | code |
| 12 | Heal is a flat +4 for 3 at any HP below max (pays 3 for 1 at max-1) and `balm_fruit` at 2 bloom strictly dominates it when stocked | `game.gd:1106-1113` | probe |
| 13 | `seed_bomb+`, `root_wall+`, `moss_filter+` drop to cost 1 and silently lose the verdant-surge interaction | `game.gd:1185-1189`; `content.gd:119, 135, 171` | code |
| 14 | Enemy-made oil (sludge trail, pump-jack ooze, boss flood) cleanses for bloom and counts toward the quota; floor restoration cannot fire while a sludge or pump jack lives | `game.gd:590-597, 630-641, 719-722, 880-886` | code |

### 4.2 Primitive-system inconsistencies

| # | Issue | Where |
|---|---|---|
| 15 | Damage source strings hardcoded per op (`"solar_lance"`, `"vine_whip"`, `"sun_flare"`, `"grow_spike"`) although `adef` is in scope: geyser kills are attributed to sun_flare; any new ability using these ops is misattributed in events, autopsy, and `death_cause` | `game.gd:1264, 1295, 1376, 1394` |
| 16 | `grow_radius` never reads `eff["radius"]`; the shape is always a plus | `game.gd:1266-1273` |
| 17 | Collision damage hardcoded to 1 in `push_line` and `push_all` while wash ops take it from data; fire ttl 2 hardcoded in five places; smoke-burst ttl 3 hardcoded | `game.gd:613, 764, 1260, 1312, 1318, 1372, 1436, 1579` |
| 18 | Root status only intercepts the `move` intent and only ticks when it blocks one; `sap_snare` does nothing to drain, gum, drag, or summon enemies and a rooted adjacent enemy attacks indefinitely | `game.gd:569-572` |
| 19 | `teleport` skips `_player_enter_tile`; safe today only because tile targets exclude terrain | `game.gd:1338-1340` |
| 20 | Drag destination check uses `_tile()`/`_enemy_at()` rather than `_open()`: the player can be dragged onto roots | `game.gd:672` |
| 21 | Roots on a vent skip the reinforcement silently with no event, a stronger undocumented version of the growth seal | `game.gd:803` |
| 22 | `aoe_damage` ignite radius includes distance 0: `sun_flare` on oil burns the caster | `game.gd:1371` |
| 23 | Immunity split across `massive` (statuses, pull, push, wash) and `boss` (stagger, spore items); items write status directly bypassing `_apply_status` | `game.gd:486, 554, 982-987` |
| 24 | `_compute_intents` assigns intents to stunned enemies that will not execute, so the snapshot's intent on a stunned enemy misleads renderers and bots | `game.gd:422-483, 564-567` |
| 25 | `ELITE_DMG_BONUS := 0` is a dead constant; DESIGN.md says oil "spreads slowly" and "slows" but oil never spreads and slows only the player; `ABILITY_DESC` for root_wall, steam_vent, sap_snare, overgrowth describes behaviour the sim does not have | `content.gd:217-241, 307`; `docs/DESIGN.md:65` |

### 4.3 Bot-versus-sim contradictions

| # | Bot rule | Sim truth |
|---|---|---|
| 26 | `_lance_hits` scans 3 tiles (`optimizer.gd:465`, `sprout.gd:128`) | `solar_lance+` has range 4; the upgrade's extra tile is never used by heuristic play |
| 27 | Boss gate = hp <= 6 and no growth adjacent (`optimizer.gd:61, 66`; `fanatic.gd:72`) | gate_hp is 6/5/5 and the gate also requires adjacent corruption (`game.gd:1414`) |
| 28 | Fanatic "only build abilities" at the shop (`fanatic.gd:49-59`) | falls through to the optimizer's buy-anything branch: 72 of 86 ability purchases were off-build |
| 29 | Optimizer item triggers match exact ids (`optimizer.gd:29-44`) | shop and pods hand out `+` items directly; they sit unused |
| 30 | `_threat_tiles` models attack, slam, quake, ignite_all (`optimizer.gd:400-420`) | 17 intent arms; drag, gum, drain, flood, dredge are invisible to the survival gate |
| 31 | Optimizer geyser/pollen_burst triggers need two adjacent enemies (`optimizer.gd:180, 182`) | strike branch runs first and is always legal then: 0 casts in 32 held runs |
| 32 | Fanatic BUILDS is a const in the bot (`fanatic.gd:7-12`), chosen by `seed % 4` | not content data; omits `anchor_roots`, `moss_filter`, and all 9 package abilities; `measure_fanatic.gd:19` passes no config so packages are never measured |
| 33 | Deeproot drafts by the optimizer's static list (`deeproot.gd:26`) | every "deeproot drafted X" claim in BALANCE.md measures the optimizer's preference list under search-quality play |

### 4.4 Runner and documentation drift

| # | Issue | Where |
|---|---|---|
| 34 | `sweep_combos` pairs: `DRAFT_POOL` minus starters is 12 extras = 66 pairs; BALANCE.md cites 45 | `tests/sweep_combos.gd:22-27`; `docs/BALANCE.md:101, 253` |
| 35 | `SWEEP_BOT` accepts only `deeproot`; any other value silently runs the optimizer; `verify_kit`/`measure_bosses` index `BOTS[env]` unvalidated | `tests/sweep_lib.gd:10-11`; `verify_kit.gd:37`; `measure_bosses.gd:33` |
| 36 | `VERIFY_EXTRAS` appends with no dedupe or `KIT_MAX` check and `Game._init` does not clamp kit size, so 6+ ability kits are measurable but illegal in play | `tests/verify_kit.gd:30-33`; `game.gd:68` |
| 37 | `test_invariants` validates raw `Content.FLOORS`, never `Game.floor_def(n)`, so tier and mutator rosters are never invariant-checked | `tests/test_invariants.gd:17-19` |
| 38 | `daily_run.gd` plays all packages plus one mutator; the shell daily plays profile packages and no mutator: the printed verification hash cannot match a phone run | `tests/daily_run.gd:22-24`; `shell/main.gd:184-193` |
| 39 | The "Instrumentation (30 seeds)" that measured 77% lance casts was never committed | `docs/BALANCE.md:360` |
| 40 | `BALANCE.md` "neither ceiling bot ever bought a graft" is stale for the optimizer (55 grafts in 40 runs) and still true for deeproot | `docs/BALANCE.md:361` |

---

<!-- SECTIONS 5-8 AND APPENDICES ARE FILLED IN FROM THE VERIFIED WORKFLOW OUTPUT -->
