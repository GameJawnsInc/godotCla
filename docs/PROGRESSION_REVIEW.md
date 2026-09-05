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

**Combos do not fire in the harness, and the harness cannot tell us whether
they could.** With `grow_spike` and `overgrowth` locked into the ceiling bot's
kit for 24 runs, the spike landed next to overgrowth-made growth 3 times in
total. With `sun_flare` and `root_wall` locked in, the flare went off while a
wall stood 4 times in 24 runs. No hypothesised pair shows positive lift over
its best single at either tier. This verdict is instrument-conditional: the
only combo-capable bot is a greedy 1-ply searcher that cannot plan a setup
turn and whose candidate list starves late kit slots, so the numbers bound
what the current instrument can see, not what a human can do. Section 7 puts
the instrument fix first for exactly that reason.

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
   ceiling bot cannot plan a two-step combo, never searches its drafts, leaves
   drafted abilities in kit slots 3 and 4 entirely unevaluated on 13% to 22% of
   the turns where they are legal, and can never draft `bramble_coat` or
   `mycelium_dash+` at all because of a rank sentinel in the shared draft code.

One correction to the framing above, raised by the review's own critic: the
world is not entirely indifferent to the build. The Dredge eats growth and
heals from it, and the boss core gate reads adjacent growth and corruption. So
commitment does have a payoff today, but only as punishment for the gardener
and a universal key for everyone else. There is no reward side.

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

### 3.5 Clock slack and the real combo budget

Re-run of the critic's probe (`clock_margin.gd`; optimizer, fanatic, sprout
40 seeds, deeproot 12, tier 0). Smog at descend and slack to the choke
threshold on the floors where skilled play wins:

| bot | floor 1 smog at descend | slack to choke | floor 3 smog | slack | floor 4 smog | slack | turns per floor (f1-4) | unspent charge per end_turn |
|---|---|---|---|---|---|---|---|---|
| deeproot | 5.3 | 32.7 | 5.2 | 30.8 | 5.7 | 28.3 | 8 to 10 | 0.00 to 0.06 |
| optimizer | 5.5 | 32.5 | 7.7 | 28.3 | 14.4 | 19.6 | 9 to 20 | 0.08 to 2.10 |
| fanatic | 6.8 | 31.1 | 9.8 | 26.2 | 13.7 | 20.3 | 10 to 18 | 0.11 to 0.22 |

Deaths happen far past choke, not near it: optimizer floor-4 deaths at mean
smog 50 against a choke of 34, fanatic floor-5 deaths at 91 against 32, both
deeproot deaths at 154 against 30. Those are 20 to 120 turn stalls on one
floor, which no runner flags because the only stall metric is the 400-turn
cap. Quota-unmet deaths cluster on the gate floors: 3 of 5 optimizer and 3 of
10 fanatic floor-6 deaths, 2 of 3 fanatic floor-2 deaths, ended with the quota
unmet while corruption still existed. Two consequences for everything that
follows: the "greed has a shape" clock is not what kills skilled bots, stalls
are; and the binding budget on any multi-step combo is 3 charge per turn, not
smog, so every proposed chain must fit in 3 charge or span turns via bank,
surge, or an item.

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

## 5. Adversarially verified findings

Five lenses produced 59 findings. Each was handed to a refuter who re-opened
the cited lines, re-ran the finder's probes on fresh seeds where numbers were
involved, and tried to break the claim. Tally: 34 confirmed, 25 partial, none
refuted outright, and the refuters added 35 issues the finders missed. What
follows is the surviving set grouped by theme, with the refuter's correction
kept where it changes the reading. Severity is the post-refutation value.

### 5.1 Build depth: kit, draft, archetypes

**Starter incumbency is real but bot-side, and lance is replaceable
(major, partial).** Deeproot on a locked kit with no `solar_lance` and no
`sun_flare` (`seed_bomb`, `mycelium_dash`, `water_jet`, `vine_whip`,
`grow_spike`) won 12/12 at tier 0 with damage split vine_whip 491 / collision
482 / grow_spike 172. A push-and-burn game exists in the sim today. Nothing
structural prevents a human from finding it: any slot can be dropped at a full
draft and the forge can scrap lance. What prevents it is that every bot
protects `mycelium_dash` and `seed_bomb` by hardcoded id
(`optimizer.gd:276-278`) and lance survives as most-used, and that no
BALANCE.md row has ever run a lance-free kit. The finder's original
comparison (5-ability no-lance kit versus the 3-ability starter) was
apples-to-oranges; against 5-ability lance kits the no-lance kit is equal, not
better.

**The draft is kit-blind only in the sense that matters (major, partial).**
Offers do depend on the kit: `+` forms of owned abilities enter the candidate
list and owned bases are excluded. What is missing is affinity between
*different* abilities: no tags, no weighting, so a player who wants fire cannot
raise the odds of seeing `sun_flare`. Pick rates are near-binary because there
is no state for a pick to depend on.

**Archetypes are lance riders by construction (minor, partial).** Fanatic's
pyro is 82% lance damage and shover 79%, but `fanatic.gd:8-11` *defines* pyro
as `[solar_lance, sun_flare]` and shover as including lance, so this measures
the bot's table, not the content. Turtle's zero signature damage is documented
design intent (a canary). Fix the instrument before adding finishers.

**Only growth has a closed loop (major, partial).** Growth participates in
seven mechanics and its generator is a starter. Fire has one chain, fixed
damage, and no reader; water only deletes; smoke is read only by the player's
own beams. The refuter's correction: fire and water do have one payoff the
finder missed, since the boss core gate requires adjacent *corruption* and
fire is not corruption, burning or washing the oil beside the core opens it
(BALANCE.md records pyro going 0/8 to 4/8 from exactly that redesign). The
economic point stands: the optimizer destroys about 10.7 corruption tiles per
run bloomlessly, and the strandable quota (defect 3) is a worse tax than lost
bloom.

**All 15 `+` upgrades are numeric (minor, partial).** Verified. Two
sub-claims failed: a cost-1 `+` is not a hidden downgrade (flat cost 1
weakly dominates cost-2-surged-to-1, since no tile is consumed), and the
0/118 pick rate of `mycelium_dash+` is a bot artifact, not evidence about
upgrade design (see 5.5, the rank sentinel).

**Skipping a draft yields nothing (note, partial).** True, but only
strictly dominated while the kit is not full; once full, skip is the free
option against a forced drop. Fanatic's 51% skip rate is its persona, not
evidence. Any skip reward must be a choice (an extra offer), never bloom: six
drafts times 2 bloom is a free graft for never engaging.

### 5.2 Combo engine: effect grammar, statuses, terrain

**The effect model has no conditions (major, confirmed).** The complete key
vocabulary read from effect dicts is `op, dmg, radius, dist, turns, status,
kind, ttl, push, collision_dmg, amount, ignite, clear_smoke, clear_smog_bonus`.
No `if`, `per`, `when`, or `then`. Effects run in list order with no shared
context, so a second effect cannot depend on the first's outcome. Nit: the ops
themselves are state-dependent (ignite iff oil, convert iff oil or goo), so the
accurate statement is that no conditional is *data-declared*. The game is
playable without this, so it is an architecture gap, not a live defect.

**There is no reaction layer (major, confirmed).** Reactive behaviour exists
as two player fields polled at four hardcoded intent sites (thorns at attack,
slam, quake; anchor at drag) plus one enemy on-death trait by string. `_emit`
appends to lists the sim never reads. On-ignite, on-stagger, on-cleanse,
on-kill, on-shield-break, on-collision cannot be authored for the player at
all. Every chain must therefore fit inside one turn's three charge, which is
why the 1-ply bot finds none.

**The live combo graph is thinner than the pillar claims but not as thin as
the finder said (major, partial).** The finder counted three write-to-read
mechanisms and claimed both firing edges are starter-kit properties. The
refuter found four misses: `moss_filter` writes dim and `solar_lance+` reads
`dim == 0` (verified 3 to 4 damage); growth adjacency lifts the boss gate for
every damage ability; the basic cleanse action plants growth, so `grow_spike`
and the dash combo with the core loop, not only with drafted writers; gust and
clear_air removing smoke re-open beam lines. What survives: seven abilities
(`pollen_burst`, `sap_snare`, `spore_cloud`, `thorn_shield`, `bramble_coat`,
`anchor_roots`, `moss_filter` in the finder's count, minus moss_filter) have
no outgoing edge, statuses are terminal, and drafted-pair edges are thin.

**Statuses are combo dead ends (major, confirmed).** Written by three
abilities, read by zero ops. `_apply_status` uses max so a second
`spore_cloud` on the same target is wasted. Root gates only the `move` intent.
Bonus bug the refuter found: `optimizer._dodge` returns any `sap_snare` cast
as a dodge, but rooting an adjacent attacker prevents nothing, so the dodge is
a charge-wasting no-op that also depresses sap_snare's measured value. Items
write stun directly, bypassing `_apply_status`, a second write path any
status table must route.

**Terrain has no data table (major, confirmed).** Flammability, washability,
corruption membership, passability, enter damage, and fire ttl are each
hardcoded in game.gd, and corruption membership is duplicated in
`deeproot.gd:70-72`, `optimizer._nearest_corruption`, and mapgen. Fire x
growth, water x goo, smoke x fire, roots x fire are all inert. Adding any of
them as content is impossible today and a five-site patch tomorrow.

**Grafts cannot touch abilities (major, confirmed).** Six `_has_graft` sites,
none in `_apply_effect` or targeting. `GRAFTS` holds only name and desc, so
graft behaviour lives in game.gd, which already strains the data-driven
principle. DESIGN.md's own example graft ("first ability each turn that
targets oil is free") needs per-turn state and a target-tile predicate that
do not exist. `Game.new` has no `grafts` config key, so graft combos cannot be
swept regardless of the data model.

**Growth empowers only via surge (minor, partial).** Verified, but the finder
missed the boss gate (the largest growth read) and miscounted cost-1 abilities
(13, not 12). The proposed `overcharge` op cannot work as written: bank is
moved into charge and zeroed at turn start, so bank is always 0 while the
player acts.

**Chain damage is unattributed (minor, confirmed).** Fire tiles carry no
originator; collision damage carries no pushing ability; four ops hardcode
their source string so geyser kills read as sun_flare. The lift script had to
invent proxies (`spike_on_overgrowth`, `flare_with_wall`) to detect combos at
all. Telemetry-only impact, but it blocks every signature-damage metric.

**Displacement into hazards is half-wired (minor, partial).** Pushes react to
fire only. But the finder's "water_jet can never push into fire" is false: the
washed line is only `range` tiles while the push carries `push` tiles beyond
it, and a probe confirmed an enemy landing on fire at distance 3.

**Enemies are terrain-blind (minor, confirmed).** `_chase_step` filters on
`_open` only; ranged intents use manhattan with no line check; smoke is read
only player-side. The proposed fix via the existing `_line_clear` is wrong
because that helper also fails on intervening enemies (a leech behind a drill
bot could no longer drain); an axis-only or adjacency smoke-screen rule is
needed instead.

### 5.3 Economy: shrine, grafts, items

**Bloom never binds after floor 2 (major, confirmed and reproduced).**
Sources per run: optimizer 42.4, fanatic 42.9, deeproot 43.8, magpie 67.2.
Sinks per run: 10.5, 13.0, 0.3, 28.0. At shrine arrival on floors 3 to 6 the
optimizer could afford everything stocked in 33 of 35 arrivals, magpie 54 of
54, deeproot 13 of 13. The refuter's caveat: the optimizer's own comment
records that off-path cleansing costs 11 wins per 100, so cheap bloom is partly
a deliberate consequence of smog being the real currency. Still, no purchase
competes with another after floor 2.

**Graft purchase is never a decision, and the ceiling is calibrated on an
un-grafted bot (major, partial, with a replication failure).** The finder's
24-seed graft table at tier 6 ranked `verdant_pulse` +7 and `solar_core` +4.
The refuter re-ran on 30 fresh seeds: `verdant_pulse` +0, `solar_core` +8,
all six installed +8. Pooled over 54 seeds: none 27, verdant_pulse 34,
solar_core 39, all six 43. So the direction holds (grafts matter at the
ceiling and tiers 6 to 8 were judged by a bot that buys none) but the
per-graft ranking is noise, exactly the 30-seed rule in BALANCE.md. The
reachable pair (solar_core plus verdant_pulse installed at floor 3 for 10
bloom) gave 17/24 versus 11/24, a real uplift.

**The forge is mispriced as an upgrade (minor, partial).** Scrapping a
load-bearing ability costs 8 wins in 24; scrapping a dead one costs nothing.
It is a "prune a dead pick" action sold as concentration. Also repeatable in
one visit down to a 1-ability kit, can scrap the only mobility, ignores tier
markup, and works at Boarded shrines. The `+` value figure (+1/24) is a single
24-seed pair, below the project's own bar.

**The item press has no identity (minor, partial).** Half of shops and pods
hand out `+` items directly. "Strictly dominated" was too strong:
`spore_vial+` beats two vials (status uses max), `clearair_pod+` 12 beats
10, and pressing frees a satchel slot. The real point stands: `+` forms are not
exclusive to the press.

**Dead bloom (minor, confirmed).** 19 to 31 bloom per run is earned after the
last shrine stand and can never be spent; floor 7 stocks a shop with no shrine
and consumes two main-rng draws for it.

**Shrine visit rate is the actual reason the ceiling ignores the economy
(major, partial).** Deeproot stands on a shrine in 7 of 1913 decisions. Its
buy actions are always in the candidate list (non-ability actions are never
truncated) and heal and item purchases are score-positive, yet none happen
because `_refresh_field` never points at the shrine. A purchase oracle alone
would fire almost never; routing is the fix.

**Enemy-made oil is a latent bloom faucet (note, confirmed).** Sludge
trails, pump-jack ooze, and boss floods cleanse for full bloom and quota
credit. Small today (magpie 71 excess cleanses over 144 floors), but any
repeatable bloom sink activates it.

### 5.4 Meta career

**Packages are forced permanent dilution (major, partial, reproduced).**
Monte Carlo over the real draw: a committed two-ability build completes by
the boss in 49.5% to 51.7% of runs on the 14-pool, 40% to 43% with one
package, 27% to 29% with all three; `+` offers of the held pair fall from
0.88 to 0.39 per run. The refuter's caveats: the model omits the shrine
ability buy (absolute rates understated, relative drop holds), and a larger
pool also raises the number of distinct reachable builds, which is the
standard draft trade-off BALANCE.md knowingly recorded as "mild dilution".
Not critical: win rates are flat at both bot levels. Real: package abilities
are forge and upgrade dead ends.

**Tier is the only run-start choice (major, confirmed).** The shell calls
`game_config(sel_tier)` with no mutators; `grep mutator shell/` is empty; the
win screen announces "UNLOCKED: KIT OF 3" for content that can never be
selected (`shell/main.gd:2347-2354`). The sim already consumes `kit`, `pool`,
`packages`, `mutators`; the tutorial passes a kit today. A loadout picker is
profile, shell, and data work with zero sim change.

**All nine milestones fall by run 4 (major, confirmed).** The profile stores
six integers and two id lists; `record_run` receives `{won, floor, tier}`
only; kit, grafts, uses, death cause, and turns are discarded. Build-based
milestones ("win with overgrowth", "win without lance") are inexpressible.

**Tiers never touch the build (minor, partial).** Verified, but DESIGN.md
defines tiers as Ascension-style numeric stacks and the lift data shows tier 6
does re-rank abilities indirectly. This is a design preference, not a defect.

**`kit_of_3` is more coherent than it looks (minor, partial).** The shop
ability slot is dead at start, but forge-then-rebuy re-opens it, so the
mutator has an undocumented economy loop rather than a broken one.

**Fanatic builds live in the bot (major, confirmed).** No meta feature can
share them; package archetypes have never been tested as builds.

**The daily is not the same for everyone (major, confirmed).** Fresh players
draw from the 14-pool, veterans from the 23-pool, on the same seed; shop
stock and every draft differ. Daily results also feed `record_run`
unconditionally (`shell/main.gd:338`), so a public-seed daily win is a
fixed-seed tier unlock.

**Refuter additions in this area:** a stale or renamed package id in a saved
profile raises "Invalid access to property or key" at `Game._init` on every
PLAY (`game.gd:62` indexes `PACKAGES[pkg]` unchecked; `profile.gd:94` loads
ids unvalidated), so renaming content bricks veteran profiles; `record_run`
treats every non-package milestone kind as a mutator, so any new kind would
silently land in `unlocked_mutators`.

### 5.5 Measurement bias

**The rank sentinel makes unlisted content undraftable (major, added by
refuters).** In `optimizer._draft_choice` (inherited by deeproot and magpie,
same pattern in sprout) an offer absent from the preference list scores
`500 * 2 = 1000` (999 for its `+`) while `best_rank` starts at 999 with a
strict less-than, so `bramble_coat` and `mycelium_dash+` can never be picked
by three of six personas, and any *new* pool ability is undraftable by the
ceiling until someone edits the list. Telemetry rows of 0/32, 0/24, 0/15,
0/38 are structural zeros.

**Deeproot's candidate list starves late slots (minor after replication).**
The finder's "23% to 96%" was a per-target figure. Re-run on the finder's
own probe: slot 3 and 4 abilities were entirely unevaluated on 13% to 21% of
decisions where legal (grow_spike 13%, overgrowth 15%, sun_flare 19%,
water_jet 21%). The shrine-starvation scenario did not occur. Real, modest,
and the cheapest fix in the whole review.

**Deeproot cannot see setups (major, confirmed).** Documented on the
BALANCE.md watch list as "eval bias", but read too strongly: a setup that
neither heals nor damages in the simulated turn scores below `end_turn` by
construction. Multi-action turns do let a payoff fire when the setup is
score-positive for another reason, so "drafted abilities never cast" is
false; "setup for its own sake is invisible" holds.

**Deeproot's drafts are not searched (major, confirmed).** `deeproot.gd:26`
returns the optimizer's static list before any clone. Every BALANCE.md claim
about what deeproot "drafts in winning kits" measures list order under
search-quality play.

**The pair sweep measures drift (major, confirmed).** `sweep_combos.gd` passes
`{kit}` without `{pool}`; the optimizer drops the least-used non-protected
slot, which is the injected pair. BALANCE.md:255 even calls these "locked
5-ability kits", so the sweep author believed they were locked. Binomial
check: at n = 10 and p = 0.8, about 2.2 false under-flags are expected across
66 pairs, and BALANCE.md records exactly two 5/10 flags that dissolved at 30
seeds. The refuter notes the drifting sweep still answers a legitimate
question ("does seeding this pair change outcomes under free play"), so the
historical conclusions are weak rather than wrong.

**Locked configs are not seed-paired beyond floor 1 (added by refuters).**
`_stock_shop` skips its main-rng ability draw when the pool equals the kit,
and `_draw_draft_offers` draws fewer times once fewer than three candidates
remain, so "same seeds across configs" is a paired design only for the
floor-1 map. This applies to the lift table in Section 3.4 and to every
sweep; until the shop draws move to the side stream, compare locked against
locked only.

**Fanatic measures four archetypes on four disjoint seed sets (added by
refuters).** `build = seed % 4` assigns each archetype a residue class of
seeds, so the per-build table compares builds on different worlds, and the
"every build > 0 at 100 seeds" gate is confounded with seed subset.

**No draft-decision oracle exists, and the one probe contradicts the
finder's reading (major, partial).** Forking every draft the optimizer faced
(8 seeds, 36 drafts, 26 seconds): 20 drafts were outcome-invariant across all
picks including skip, skip won 19/36, and the optimizer's pick was in the
winning class 31/36. The finder read this as "drafts barely matter"; the
refuter points out 16 of 36 drafts flipped a deterministic run under a fixed
policy, which is evidence they do, and that "invariant" conflates seed
difficulty with draft irrelevance (seed 6 was all-win at every draft, seeds
2, 5, 7, 8 all-lose at 9 of their 12). Nobody measures it; that is the
finding.

**Stalls are counted as losses in every sweep (added by refuters).**
`run_one` caps at 400 turns but returns no timeout flag, so the failure mode
BALANCE.md documents most often reads as "underperforms" with the cause
invisible; only playtest counts timeouts.

**Runners aggregate by raw kit id (added by refuters).** playtest and
sweep_packages never trim `+`, so an ability and its upgrade are two rows,
halving apparent hold and win counts for anything upgraded.

**Every number in BALANCE.md is seeds 1..N (added by refuters).** No runner
offers a seed offset, so "balanced across the pool" is also "balanced on
these specific 30 or 100 floor-1 maps".

### 5.6 What the refuters knocked down

For honesty, the claims that did not survive: that fire and water have no
payoff (the boss gate is one); that the boss gate has a single key (it has
two); that water_jet can never push into fire; that a cost-1 `+` is a
downgrade; that `mycelium_dash+`'s pick rate says anything about upgrade
design; that shrine turns starve deeproot's ability candidates; that
`kit_of_3` permanently kills the shop slot; that the verdant_pulse graft is
strong; that "pair minus additive" being negative at tier 6 is synergy
evidence (only the thorn_shield row, -8, exceeds noise); and that tiers
"never" re-rank abilities. Several headline numbers rest on 12 to 24 seeds
against the project's own 30-seed bar and are labelled as such wherever they
appear above.

---

## 6. Roadmap: the game

Three designers wrote independent roadmaps (primitives-first,
commitment-first, measurement-first); a judge scored them 8 / 8 / 7 and merged
them. The ordering below is the judge's, with the critic's corrections folded
in. Each block gates the next. The rule throughout: no mechanic ships without
the bot branch that exploits it and the runner column that counts it, because
BALANCE.md shows an unexploited mechanic reads as neutral and gets shipped as
filler.

### 6.0 Ordering, bumps, and the shipping gate

- **Block A (now)** is harness, bot, and profile work only. No sim behaviour
  change, no `RUN_SAVE_VERSION` bump. It ends with a v2 instrument
  re-baseline in BALANCE.md; every pre-v2 number is labelled and never mixed.
- **Block B (next, bump 2)** is one batched sim patch whose only intended
  balance change is closing the strandable quota. Everything that reshuffles
  the main rng stream or changes shop shape lands here so BALANCE.md
  re-baselines once.
- **Block C (next, bump 3)** is the effect grammar and the data tables, with
  the grammar preceding every build-defining graft. The critic is right that
  this block as the judge scheduled it carries about 25 content rows behind
  one before/after; it is split below into C1 (vocabulary and tables,
  hash-identical), C2 (riders on `+` forms), C3 (hooks and rule grafts), each
  with its own BALANCE.md entry even if they share a version bump.
- **Block D (later)** items each sit behind a measured gate.
- **Every bump wipes in-flight phone runs.** `shell/main.gd:235-237` deletes
  the saved run silently on a version mismatch and finished logs are deleted
  on completion. Before bump 2, the shell should show a "run lost to update"
  notice and keep the last N finished logs under `user://` with an export
  path, because those logs are exactly the (seed, config, actions) regression
  pairs CLAUDE.md mandates and the only human play data the project could
  have.

**Shipping gate for a content row** (softened from the measurement-first
angle, whose "lift CI excludes zero at 30 seeds" would need about 20 points of
lift and block every honest combo): (i) a regression demo exists; (ii) the
Tally shows the combo firing at least once per run in a forced kit at 30
seeds; (iii) its locked lift CI is not below zero; (iv) signature-damage or
terrain-derived share, or a continuous metric such as turns on wins or damage
taken, moves in the intended direction; (v) magpie stays at or under 5% at 100
seeds, the turtle canary and timeout count are unchanged, and wanderer at 100
seeds shows zero script errors and zero illegal actions; (vi) any rider that
grants shield, heal, thorns, or cleanse credit passes a deeproot-plan solo
check. Every bump gets exactly one BALANCE.md entry with before/after for
optimizer, magpie, deeproot, and deeproot-plan.

**Charge, not smog, is the combo budget.** The critic's probe (re-run for
this document; see Appendix C) found that skilled descents happen with the
clock barely started and unspent charge per turn near zero for the ceiling.
Every combo row below therefore carries a charge line: setup plus payoff
against 3 regen, with and without a surge or item.

### 6.1 Block A: run-start choice with zero sim change

**Content.LOADOUTS and one package per run.** Data:
`LOADOUTS = {id: {name, kit: [3 ids], protect: [ids], requires: {...}}}`.
`tender` is the current starter (always available). Candidates verified
bot-winnable in a 20-seed optimizer probe at tier 0: `tidewarden`
`[water_jet, seed_bomb, mycelium_dash]` 8/20, `flarekeeper` `[sun_flare,
seed_bomb, mycelium_dash]` 8/20, `spiker` `[grow_spike, seed_bomb,
mycelium_dash]` 7/20, `lasher` `[vine_whip, seed_bomb, mycelium_dash]` 6/20,
against 9/20 for the fixed kit. Every shipped loadout keeps `seed_bomb` (the
boss-gate key most players will use) and a mobility ability; `skyrunner`
`[gust, seed_bomb, updraft]` is gated on a 30-seed `verify_kit` pass.
`profile.game_config(tier, mutators, loadout, package)` returns
`{kit, packages: [package] or [], tier, mutators, loadout}`: a package becomes
a run-scoped commitment, so the pool is 14 or 17, never 23. Add `snapshot()`
fields `pool`, `packages`, `loadout` (read-only). Mutator effects move into a
`config` override dict on `MUTATORS` applied generically in `Game._init`
(`kit_max`, `max_hp_delta`, `bank_cap`, `oil_mult`, `pool_ban`,
`draft_offers`) and must reproduce current numbers exactly, verified by
`test_determinism` before and after. No bump: config already lives in the
run-save header.

Combos this makes the spine of a run rather than an accident: tidewarden plus
`sun_flare` (jet pushes an enemy beyond the washed line into flare-lit oil,
verified mechanic); flarekeeper plus `root_wall` (flare in a pen, finally
measurable without lance in the kit); skyrunner (dash-line plus push-line
positioning with no growth dependency, a mobility identity that exists in
data and has never been played as a run). Charge: jet 1 plus flare 2 equals
3, fits one turn.

Bots and harness: the drop guard in optimizer, magpie, and fanatic reads
`LOADOUTS[snapshot.loadout].protect` (fallback: any mobility-tagged ability)
instead of hardcoded ids. `sweep_lib` gains an explicit unlock-state axis
(fresh / committed-package / legacy-all) and `sweep_tiers` gains permanent
lance-free rows. `test_meta` asserts each loadout is 3 known ids with one
mobility ability and is optimizer-winnable at 3/20 or better; each package's
ids land in `draft_pool` and the base pool is otherwise unchanged; each
mutator's declared invariant holds on a fresh game (expectation table in the
test, not in content); `game_config(9, ['nonexistent'])` clamps.

**Mutator picker and career-agnostic daily.** The picker is the zero-design
half of a real defect (unlocks announced, never selectable). A static
`Profile.daily_config(seed)` returning `{loadout, package, mutator, tier: 0}`
from the seed, used by both the shell and `tests/daily_run.gd`, makes the
daily the same run for everyone; daily results go to `profile.daily_best` and
never to `record_run`. The shell must display the active mutator.

Risk: players who liked all-packages variety lose it; offer "open pool" as an
unlockable mutator rather than the default.

**Content.ARCHETYPES and ability tags as sim-ignored data.** Every
`ABILITIES` entry gains `tags` from a closed vocabulary (sun, fire, water,
wind, growth, bark, control, displace, smoke, mobility) and a `role` (setup,
payoff, damage, defense, mobility, utility). `ARCHETYPES = {id: {name, core,
requires}}` carries pyro (with lance), ember (lance-free fire), gardener,
turtle (documented canary), shover, anchor, tidecaller, sporewright,
skyrunner. `Content.archetypes_for(pool)` filters by requirements. The sim
never reads either table, so this is fully compatible with the data-driven
principle. Introduce `Content.base_id(aid)` now so the later fork migration
is one sweep. Do **not** yet use tags to weight any draft (see 6.4).

### 6.2 Block B: bump 2, the measurement-enabling sim patch

One batched change to `RUN_SAVE_VERSION 2`, no intended balance change except
closing the strandable gate:

1. **Side-rng shop stock.** Ability from `_side_rng('shop_ability')`, graft
   from `_side_rng('shop_graft')` (one generator each so list sizes do not
   couple); the ability filter also excludes bases whose `+` is owned; skip
   stocking when `map.shrine == (-1, -1)`. Add a determinism assertion that
   `rng.state` after `_enter_floor` is independent of kit, grafts, and pool
   size on 50 seeds. This is the prerequisite for every shop-shape
   experiment and for seed-paired sweeps beyond floor 1.
2. **Damage attribution.** Fire tiles carry `by` (ability id, `env`, enemy
   kind, `furnace`); enemy-side sources become `fire:<by>` and
   `collision:<aid>`; the four hardcoded source strings use the casting
   ability's id. Player-side sources stay unchanged because `death_cause` and
   the playtest death tables key on them. Strip the suffix at display in
   `shell/main.gd:1083`.
3. **Quota re-clamp.** `green_need = min(green_need, greened +
   _count_corruption())` after wash, convert, burnout, and dredge, emitting
   `quota_reclamp`. No bloom or room-bloom credit for convert (the refuter
   showed `overgrowth+` on a fuel depot converting 13 tiles for one charge
   would be a degenerate quota clearer). Enemy-made oil gets `{bloom: 0}` but
   still counts toward `greened`, so pump-jack floors cannot strand.
4. **Config keys** `grafts` (pre-installed) and `bloom` (starting) for
   sweeps, so graft combos become sweepable as DESIGN.md promised.
5. **Choice sinks, no new power.** Two-graft stock, pick one (the other is
   discarded); ability purchase takes a drop slot like the draft does and can
   never drop a mobility ability; press and forge priced through `shop_cost`
   and gated on `not shop.is_empty()` so Boarded boards them and Gouging
   Prices marks them up; forge capped at one per floor and forbidden from
   scrapping the mobility ability; shop and pods draw from base item ids only
   so `+` items exist only via the press. Deferred to 6.5: reroll, per-HP
   heal, prune-versus-forge split, because stacking nine economy levers in one
   bump makes any canary movement unattributable.

Shell work: two-graft shop UI, source display strip, version notice. Then
`deeproot_plan` (6.6) and `tests/sweep_grafts.gd` on the six existing grafts
at 30 or more seeds, and a re-judgement of tiers 6 to 8 on a grafted ceiling
*before* any economy content. Only after that do graft values enter any bot
table.

The critic flags one silent nerf here: base-only pods remove the `+` items
deeproot actually uses (`clearair_pod+` was 5 of its 17 item uses). Run
deeproot at 30 seeds with base-only pods before shipping that line.

### 6.3 Block C: the effect grammar and the data tables

**C1. Cast context and the `if` / `per` / `then` / `bonus` vocabulary.**
Three optional keys on any effect dict, evaluated by two helpers in game.gd
and nowhere else. `if`: a closed v1 predicate set, `target_on: [kinds]`,
`target_adjacent: [kinds]`, `self_on: kind`, `dim: n`,
`casts_this_turn_min: n`, and inside `then` only `outcome: hit | ignited |
pushed | collided | converted | planted` and `outcome_crossed: kind`. `per`:
`{count: growth_adjacent_target | fire_within_self | oil_in_line |
enemies_adjacent_target, radius, cap, add: {dmg: 1}}`. `bonus`: per affected
enemy inside aoe_damage, lance, damage, and collision. `then`: a nested effect
list run once when the parent's outcome has any counter above zero; no nested
`then` (content lint). `_apply_effect` returns an outcome dict;
`_push_enemy`, `_wash_dir`, and pull thread `collided` and `crossed` back.
Player gains `casts_this_turn` and `moved_this_turn`, reset in
`_begin_player_turn`. Emit `{t: 'rider', id, kind, amt}` for the Tally.

Ship the tables in the same block: `Content.TERRAIN` (corruption,
flammable, washable, bloom, ttl, enter damage, spreads_to, burns_to),
`Content.REACTIONS` (a list consumed by one `_terrain_react()` in the
environment phase), `Content.STATUSES` (stack rule, blocked intents, cap,
tick damage), and a per-ability `surge` key defaulting to `{cost: -1}` so
behaviour is identical. Two commits: the first replaces every literal with a
lookup and must be hash-identical on the determinism seeds; the second
enables ash (burnt oil becomes cleansable corruption that does not shield
the core), root blocking `advance` and `drag` with a stagger-style cooldown,
spore add-stack capped at 6, and item stun routed through `_apply_status`.
Damp, roots-burn, and smoke-smother stay disabled rows. Fix
`optimizer._dodge` to respect the new root semantics in the same change. Ash
needs an ASCII glyph, an SVG sprite, a legend row, `render_frame`, and mapgen
invariants: real shell work, flagged as such.

**C2. Riders on the existing `+` forms first, then two base rows.** Offered
only when the base is owned, so base-pool balance is untouched. Numbers to
start: `grow_spike+` `{dmg: 3, per: {count: growth_adjacent_target, cap: 2,
add: {dmg: 1}}}` (up to 5); `sun_flare+` `{dmg: 2, ignite, bonus: {dmg: 1,
if: [{target_on: [fire]}]}}`; `water_jet+` `then: [{op: status_target,
status: root, turns: 1, if: [{outcome: collided}]}]` with a `moved >= 1`
guard so a wall-pinned enemy cannot be re-rooted every turn for one charge;
`vine_whip+` `then: [{op: status_target, status: stun, turns: 1, if:
[{outcome_crossed: fire}]}]`; `seed_bomb+` `then: root 1 on enemies standing
on planted tiles`. Leave the cost-1 `+` costs alone. Then the two base rows
as separate lift entries: `grow_spike` `per growth_adjacent_target cap 2`
and `sun_flare` `bonus on fire`.

Combos, with charge: seed-on-head (seed_bomb targeted on an enemy's tile
plants the plus around it, grow_spike+ hits for 5; 2 + 1 = 3 charge, same
turn, 1-ply visible); light-then-flare (lance ignites the oil line an enemy
stands on, sun_flare+ deals 3 to it; 2 + 2 = 4, needs a surge or a
capsule); drag through embers (whip pulls across a burning tile for 2 + fire
1 + stun; 1 charge after a 2-charge lance); pin (jet collision roots for a
turn so the lance line stays open; 1 + 2 = 3). Opportunity rates from the
telemetry: enemies adjacent to oil 23% to 27% of sightings, on fire under 1%,
adjacent to two or more growth 7% to 10%.

Bots: deeproot sees same-turn riders through clone search once the
round-robin fix lands; the optimizer replaces its hardcoded damage guesses
with a Content-reading `_est_dmg(aid, target, snap)` that applies `per` and
`bonus`, and gains a seed-on-head branch; fanatic gardener leads with it.

**C3. Hook dispatcher and grafts as data.** `_hook(kind, ctx)` called after
the existing `_emit` at ignite, staggered, cleanse, growth_planted, kill,
shield_break, and collision, with sources in fixed order (kit slots, then
grafts), a per-step depth cap as a Content constant, and positional ops
`damage_at`, `status_at`, `terrain_at`. `GRAFTS` gains `tags` plus
`stat | mod | hooks`; the six existing grafts move to data and
`_graft_stat(key)` replaces the six `_has_graft` sites. First rule grafts
limited to those with no stall surface: `ember_sap` (on ignite, 1 damage to
whoever stands on the tile, per-turn cap 3), `undertow` (staggered enemies
are also rooted 1 turn), `compost` (a kill leaves growth if the tile is
empty), `oil_tithe` (first oil-targeting cast each turn costs 1 less, floored
at 1). Every graft measured pre-installed via `config.grafts` at 30 seeds,
tier 6, with deeproot-plan, reporting hooks fired and timeouts, before it is
priced. Optimizer and magpie pick the stocked graft whose tags match the kit,
read from Content so new grafts auto-rank.

Combos: ember_sap plus water_jet plus lance (shove onto oil, lance the line:
ignite 1 + tick 1 + lance 2 = 4 for 3 charge); undertow plus tide (four
staggered enemies rooted a turn, two clean lance lines next turn); compost
plus grow_spike (every kill is a growth tile, so the next enemy is "near
growth"), a growth loop for non-gardeners.

Dropped from this block on the judge's and refuters' evidence: `tended_bark`
(cleanse grants shield) and any shield-break-to-thorns or burnout-to-growth
graft, because cleanse, shield, and thorns riders are the stall vector
BALANCE.md documents twice; a synthesized `DEFAULT_PLUS` rule for package
abilities (an implicit rule nobody can read in content.gd); per-tile bloom
credit on convert.

**Package `+` rows.** Nine explicit entries once the rider vocabulary exists,
costs never below 2 for cost-2 bases, gated by `sweep_packages` and the
30-seed outlier rule.

**Profile that sees builds (no bump, can land in parallel).** `record_run`
takes the full summary the sim already exposes (`kit`, `grafts`, `uses`
summed by base id, `bloom`, `turns`, `death_cause`, `seed`, `seed_mode`);
`_meets` gains `won_with`, `casts`, `wins_without`, `grafts_owned_at_win`;
explicit kind dispatch (package, mutator, loadout, graft) with `push_error`
on unknown; `load_from` filters ids against Content so renamed content cannot
brick a profile; a 50-entry history. Cast milestones count only casts that
produced an effect event, against farming. Do **not** shrink `DRAFT_POOL`:
every BALANCE.md number rests on the 14-pool; the pool grows only through
loadouts, one package, and unlocked keystones. New mutators `no_lance`
(`pool_ban`), `wide_draft` (`draft_offers: 4`), `upgrades_only`.

### 6.4 Block D: later, each behind its gate

- **Affinity-slotted draft with "focus" on skip.** Slot 1 affinity (shares a
  tag with the kit or grafts), slot 2 upgrade-or-affinity, slot 3 wildcard;
  always exactly three main-rng draws (pad lists) so draw count never depends
  on kit. Skip sets `focus`; the next draft has one extra affinity offer;
  never bloom. Ships only after loadouts vary the third starter,
  `mycelium_dash` is tagged mobility rather than growth, the draft oracle has
  shown skip is not already equal to the best pick, and baseline kit
  diversity is on record. The critic's point stands: kit-set entropy cannot
  be the acceptance KPI here because a uniform lottery maximises it and
  affinity lowers it by design; use the oracle's conditional pick value and
  signature-damage share instead.
- **Evolve forks.** Each `+` becomes two named variants keyed `base+variant`
  with `Content.base_id()` and deterministic parity selection (no rng draw);
  the forge offers both. Effort L, not M: 30 data rows, 6 to 8 op keys
  (pierce, leaves, ignite_ttl, pull_line, status_area, per-tile flammable),
  and the `+` suffix is load-bearing in the forge, `_act_draft`,
  `ABILITY_DESC`, `uses`, shell slot keys, and every bot. Acceptance: no
  strictly dominated sibling at 30 seeds; solo-check every shield, thorns, or
  growth-writing variant.
- **Enemies read terrain.** Per-kind `avoid` lists as data driving a
  Dijkstra with DIRS tie-break; a smoke-screen rule for ranged intents
  (adjacency-based, intent still shown, blocked on execution; not the
  existing `_line_clear`). The row most likely to produce an immortal-fence
  canary hit (fire-avoiding enemies plus pump-jack refuelled oil): turtle and
  magpie 100-seed stall canaries are the gate.
- **Per-ability stat surges and Spore Trail.** `grow_spike` `{surge: {dmg:
  1}}`, `water_jet` `{push: 1, collision_dmg: 1}`, `sun_flare` `{radius: 1}`,
  `seed_bomb+` `{radius: 1}`; `mycelium_dash+` becomes "the departure tile
  becomes growth". Deferred until the surge key exists with identical
  defaults and the gardener's lift is measured; cap `per` at 1 when surged if
  lift is excessive. Drop the overcharge-from-bank op (bank is always 0
  during the player's turn).
- **One resonance per element** over kit and graft tags, through the hook and
  mod layer; growth x2 is met from turn one under the fixed starter, so this
  waits for loadouts; mobility never counts.
- **Repeatable economy sinks, one at a time.** Bloom verified never to bind
  after floor 2, so a sink is eventually needed, but every cheap bloom-to-power
  sink in BALANCE.md history became a farm line and the enemy-oil faucet must
  be closed first. Add exactly one (shrine reroll via side-rng first, a choice
  sink), re-check the magpie canary at 100 seeds and optimizer clock
  discipline, then consider the next. Per-HP repeatable heal was dropped:
  every descent already heals 4 for free, and 30 to 44 surplus bloom would
  become 30 to 44 HP.

### 6.5 Dropped, with reasons

Overcharge and tithe (strictly positive when charge is spare, multiplies legal
actions, crosses the greed currency); per-HP heal (power sink); reroll and
prune in the first shop bump (unattributable); tag-scored optimizer draft
list (a designer prior swapped for a designer prior, re-baselines the
heuristic band for a non-content reason); alternative boss-gate keys as data
(the gate already has two keys, the finding's evidence was wrong); `damp` and
slippery collision in the first terrain ship (a second terrain kind doubles
shell work and re-clamp already handles the strand); constraint tiers 9 and
10 (DESIGN.md defines tiers as numeric stacks and tiers 6 to 8 already sit at
deeproot 8/10/6 of 20); shrinking `DRAFT_POOL` at run 1; a `shover` starter
without `seed_bomb` and a separate `player['mobility']` field (breaks every
kit-slot consumer); redefining fanatic's pyro without lance (add `ember`
beside it instead).

### 6.6 Two design tensions, stated rather than resolved

Turtle remains a designed canary with no win condition; a `bark_burst`
finisher would reverse a documented stance and should be a deliberate
decision, not a content fix. Fire x growth and smoke x fire stay disabled
toggles because they tax gardener-pyro mixes (the vent seal, the dash
network, the boss-gate growth) in ways the designer may or may not want.

---

## 7. Roadmap: the bots and batch runners

This is Block A in full, plus the deeproot-plan persona from Block B. All of
it is harness and bot work with no sim change and no version bump, and it is
the precondition for believing any number in Section 6.

### 7.1 Tally, KPIs, and statistics in `sweep_lib`

A `Tally` (RefCounted) with `add(ev, action)` called on every event returned
by `game.step()` inside one shared `Sweep.run_loop(game, bot, tally)`, which
replaces the ten copies of the run loop. Fields, all ability keys normalised
to base id with a separate `plus_casts` counter: casts by base, strikes,
cleanses, moves, end_turns; offers, picks, upgrades, skips, drops by id;
buys by kind, grafts by id, upcycles, item uses by id; bloom earned and spent,
shrine turns, afford-all-at-arrival; combo counters (ignite by step type,
verdant, staggered, collision hits, thorns hits, fire hits on enemies, spore
ticks, convert, wash, room bloom, floor restored); enemy and player damage by
source (split on `:` after bump 2); `timeout` as its own outcome, never a
loss. The critic's additions, all cheap: smog at descend, gap to first dim
and to choke, turns per floor, unspent charge per `end_turn`, a per-floor
stall flag (turns on floor above 60 or smog above choke plus 30) reported
separately from timeouts; "died with quota unmet" and quota remaining at
death in the death-cause table; damage taken by enemy kind and
strikes-into-spiked per run (the optimizer takes 167 HP from spikes in 40
runs, its second-largest damage source, because its spiked filter only
engages at 6 HP or less, which inflates the 58% strike share); item use with
casts-in-the-same-turn; vault name per floor with bloom, ignites, and
converts inside the vault room; illegal-action count.

KPIs printed by every runner: signature-damage share (enemy damage from
sources outside the loadout kit over total), terrain-derived share, combo
rate per run, bloom conversion (spent over earned), and kit-set entropy
(Shannon over sorted base-id final kits, recorded now as a baseline and read
as a trade-off later, not a target). `wilson(w, n)` and a `paired(a, b)`
discordant-seed sign test, with the stated caveat that pairing is exact only
for the floor-1 map until bump 2. Every runner header prints bot name, config,
and seed range; `SWEEP_SEEDS` and `SWEEP_SEED_FROM` for out-of-sample checks;
playtest replaces "kit wins" with a per-base table of held / cast at least
once / won.

`bots/roster.gd` holds the single `BOTS` dict and a `by_name()` that
`push_error`s on unknown names; `pick_bot` fails loudly instead of silently
running the optimizer.

### 7.2 Instrument repairs and the v2 re-baseline

1. **Round-robin candidates in deeproot.** Group ability actions by slot,
   stable-sort each slot's targets by manhattan distance to the nearest
   enemy, pop one per slot until `MAX_CANDIDATES`. Acceptance via the existing
   truncation probe: per-slot full truncation under 5% (was 13% to 22%).
2. **Pickable unlisted offers.** Unlisted offers rank after every listed id
   instead of 500, `best_rank` initialises huge, `mycelium_dash` joins the
   preference list. Keep this minimal fix rather than re-scoring the list by
   tags.
3. **Fanatic on shared seeds with lance-free variants.** Public
   `set_build(id)`; `measure_fanatic` runs every build on every seed and adds
   `pyro_nolance` and `shover_nolance` beside the existing four (do not
   redefine pyro). Remove non-wanted "buy ability" actions from `legal`
   before calling the parent so purchases stop leaking off-build (72 of 86
   were).
4. **`sap_snare` dodge fix.** Counts as a dodge only when the target's intent
   is `move`.
5. **Sprout repair.** Give it item use and a `seed_bomb` / `grow_spike` cast
   rule (the tutorial teaches both) and re-baseline its floor band; today it
   casts only `solar_lance` and is not a usable instrument for teaching-curve
   questions.

Then record before/after at 30 seeds for optimizer, magpie, deeproot at tier
0 and deeproot at tier 6 as one BALANCE.md entry, "instrument v2
re-baseline".

### 7.3 Locked-kit lift sweep

Rewrite `sweep_combos.gd` around `Sweep.lift_row(base3, x, y, seeds, cfg,
bot)`. Every config locked with `{kit: K, pool: K}`; singles are 4-kits with
no filler (anchor_roots is not inert per the watch list); baseline is the
3-kit; `lift = pair - max(single_x, single_y)`, also `pair - additive`.
N at least 30, Wilson CI on every row, continuous secondaries (turns on
wins, damage taken, combo rate, signature share), `SWEEP_TIER` with a
documented headroom tier (deeproot 6, optimizer 0) and the note that a tier-6
lift is lift in a different economy, `SWEEP_MODE=drift` kept as a labelled
second question, `SWEEP_SHARD` for the 2.5-hour deeproot grid. Permanent
reference rows in `sweep_tiers` and BALANCE.md: `starter5`, `lance_free_A`
`[seed_bomb, mycelium_dash, sun_flare, water_jet, grow_spike]`,
`lance_free_B` `[seed_bomb, mycelium_dash, water_jet, vine_whip, grow_spike]`,
each with signature and terrain share. The single measurement that would
most change this review's conclusions is running this table with a
sequence-capable deeproot before any sim bump: if lift appears, "combos do
not fire" was an instrument artifact and Block C shrinks; if it stays flat,
the grammar work is justified.

### 7.4 Draft oracle and rollout drafting

`tests/draft_oracle.gd`: at every draft the policy bot faces, fork per
distinct pick plus skip, roll out to game end with a fresh instance of the
same persona, record `{seed, floor, kit_before, offers, chosen, pick_kind,
won, turns, dmg_taken}`. Aggregate P(win | pick) minus P(win | skip) per
offer with CI; kit-conditional value per (offer, co-held ability) where n is
at least 10; stakes per draft (max minus min) split into decisive versus
seed-decided drafts; policy regret. Optimizer about 2 minutes for 30 seeds;
deeproot about 40 minutes, an overnight shard. This is the direct build-depth
metric and it tests whether skip already equals the best pick before anyone
rewards skipping. Deeproot gains `draft_mode = rollout` shipped as a separate
persona `deeproot_rollout` so the legacy ceiling column survives; note that
rolling out with the heuristic policy values an offer by what the optimizer
can do with it.

### 7.5 `deeproot_plan`

A separate roster persona; legacy deeproot stays runnable through the whole
transition. Layer 1: option-value eval terms computed only for ops the kit
holds, read from Content so new content is covered (`damage` with
`enemy_near_growth`: +6 per enemy adjacent to growth, cap 3; ignite ops: +4
per oil tile in reach with an enemy on or adjacent, cap 3; push and pull ops:
+5 per enemy adjacent to a non-open tile along a pushable line, cap 2;
surge-ready: +6; roots adjacent to an enemy while a push op is held: +3).
Weights chosen against the existing scale so a 2-charge setup beats
`end_turn` but a realised 2-damage spike still dominates. Layer 2: plan mode
for candidates whose first op is a setup op (grow_radius, grow_wall,
convert_radius, apply_status, aoe_status, create_terrain, the push and pull
family, teleport, undim): after stepping the setup, enumerate follow-up
ability actions with a round-robin cap of 12, score after the forced
`end_turn`, take the max. Typical 2 to 3x runtime. Shrine routing:
`_refresh_field` treats the shrine as a secondary goal when bloom covers the
cheapest useful buy and no enemy is within 3. Graft weights come from a
bot-side table regenerated by `tests/sweep_grafts.gd` at 30 or more seeds
(the 24-seed ranking did not replicate); publish no weight before that run.
Acceptance at 30 seeds, tiers 0 and 6: wins within CI of legacy, timeouts
zero, shrine stands at least 1.5 per run, graft buys above zero, lift table
re-run. The measured delta between deeproot_plan and deeproot in combo rate
and lift is itself the answer to how much combo depth the content contains.

### 7.6 Regression corpus and CI gates

`tests/regressions/*.json` with schema `{seed, config, actions, expect:
{won, floor, events: [...minimal fields]}, note, sim_version}` and
`tests/test_regressions.gd` that replays each, fails on any illegal or error
event, asserts outcome and expected event patterns, keeps the full state hash
under `REGRESS_STRICT=1`, and regenerates with `REGEN=1` printing outcome
diffs. Seed it with the determinism seeds times six bots, one autopsy per
BALANCE.md degenerate line, and four hand-authored combo demonstrations on
`fixed_floor` configs: seed_bomb then grow_spike the same turn, root_wall
then water_jet collision, lance into oil then an environment-phase fire hit,
moss_filter then solar_lance+ dealing 4. These are the existence proofs the
combo-engine lens lacked. Add a golden-hash test (fixed seed, fixed config, N
actions, expected `state_hash`) that the Android build can print on its
settings screen, since the daily's "same for everyone" depends on Godot's
Array and String hashes agreeing across platforms and versions.

CI gates: playtest asserts each persona's BALANCE.md band against the Wilson
interval (fail only when the whole interval is outside) and zero timeouts and
illegal actions for optimizer and deeproot; wanderer at 100 seeds, zero
script errors, zero illegal, dies floor 1 to 2; `sweep_tiers` fails when the
deeproot upper bound at any tier is under 10%; `test_meta` structural asserts
as listed in 6.1 plus a second career that replays tier 0 and names
unreachable milestones, asserting unlock *sets* by run 40 rather than run
numbers; `test_invariants` validates `Game.floor_def(n)` for every tier and
mutator, not raw `Content.FLOORS`; `sweep_packages` prints offers per base
ability per run, P(any `+` offered per draft), and archetype-core completion
under a committed policy, asserting completion for pairs inside the committed
package.

### 7.7 Two runner questions the review could not answer

`measure_bosses` reports arrivals and conversions per boss but never per boss
by kit, so whether The Dredge already filters gardener kits and the Furnace's
`ignite_all` filters shover kits is unmeasured at any N (the critic's probe:
Dredge with garden kits 5/5 for the optimizer, n far too small). Extend it
with a kit column and `BOSS_KIT` so locked archetypes run against each boss at
30 seeds with deeproot. And no runner characterises the enemy roster as a
build filter (spiked, smokestack, magnet crane, leech, tar spitter are the
shipped "disruptors attack options"); a `weak_to` / `resist` by damage-source
family on `ENEMIES` is the cheapest "world reacts to build" surface and was
not considered by any lens.

---

## 8. Gaps the critic found

Recorded so the next round can see what this one could not.

- **The smog clock is slack for skilled play; stalls, not greed, kill.**
  Winning descents on floors 1 to 4 happen at smog 3 to 8 with roughly 30
  turns of choke slack; deaths occur 16 to 60 smog past choke, from being
  stuck on a floor for 20 to 120 turns. Every "setup turn" caveat about
  shrine dwell and two-step combos assumed a tight clock. The binding budget
  on combos is 3 charge per turn, and `deep_cells` and `sun_capsule` are the
  levers that relax it, unmeasured for that role.
- **Quota-unmet deaths cluster on the gate floors.** In the critic's probe 3
  of 5 optimizer floor-6 deaths and 3 of 10 fanatic floor-6 deaths ended with
  the quota unmet while corruption still existed. That is a different failure
  from the strand bug: bots cannot reach or afford the last quota tiles under
  pressure. The green gate is a live build filter (a kit with no spare charge
  for cleansing dies at the stairs), which the "no commitment payoff" finding
  said did not exist. Autopsy those seeds before any ash or quota change.
- **Vaults are never examined as a build surface.** Five terrain set-pieces
  stamped one per floor from a per-floor list by the main rng; `fuel_depot`
  appears only on floors 5 to 6, `old_garden` only on 2 to 3, no vault mixes
  terrain. A pyro cannot meet a fuel vault before floor 5. Vault weighting by
  kit tag is the cheapest "the world bends to the build" lever and was not
  considered.
- **Items as combo enablers.** The only free actions and the only in-turn
  charge burst (`sun_capsule` +3 is a second 3-charge combo the same turn),
  yet no finding measures combo turns enabled by items and no item writes
  terrain. Bots walk over pods while full 0.7 to 3.5 times per run.
- **Human-facing surfacing of builds is absent.** The tutorial never teaches
  the draft, drops, upgrades, grafts, or the dash; the draft screen shows
  offers but not the current kit. The 2026-08-11 degenerate line was found by
  a human. Every proposal above that adds tags, riders, or two-graft shops
  needs display, and a shell checklist belongs in each roadmap block.
- **The save layer is unexamined.** A version mismatch deletes the in-flight
  run with no message; no state hash is stored, so an un-bumped sim change
  diverges silently on replay; finished logs are deleted. Store
  `state_hash()` every N actions and verify on load; show a notice; keep the
  last N logs with an export path.
- **Unverified headline numbers.** Lance-free parity rests on 12 to 16 seeds
  at a saturated tier; only `thorn_shield` and `water_jet` exceed two standard
  errors among the tier-6 single deltas; the forge and `+` value figures are
  single 24-seed pairs; the loadout probe is 20 seeds with no script on
  record; the "9 of 11 abilities seen per run" and "21% to 36% `+` offers"
  figures come from the audit's Monte Carlo, not from a published table.
  Treat all of them as directions, not values, until the v2 instrument
  reproduces them at 30 seeds.

---

## Appendix A. Interaction matrix (condensed)

Rows are the primitive; columns say whether the sim reads or writes that
state. Full matrix with line citations in the primitives audit
(`scratchpad/wf/3_*.md`).

| primitive | exists | absent |
|---|---|---|
| lance | ignites oil, stops at smoke and wall, +1 at dim 0 (`+` only), blocked by the boss gate | passes roots; never reads growth, goo, fire, supply |
| pull | stops at wall, enemy, roots; fire on path damages; massive takes damage but does not move; staggers | never drags oil or ignites; goo, growth, supply ignored |
| push (line, all, wash) | collision into wall, enemy, roots damages both; pushed enemy entering fire burns; massive immune; staggers | oil and goo on the destination do nothing; the player as blocker takes nothing |
| wash | erases oil and fire in the line, then pushes the first enemy | goo, rich goo, growth, smoke, roots, supply untouched; a massive enemy truncates the wash |
| growth | discounts a 2-cost cast (consumed), heals 1, seals a vent (consumed), dash target, spike condition, boss-gate key, dredge food | fire never spreads to it; enemies ignore it; nothing overwrites it |
| fire | damages on stand and enter, spreads to oil one tile per turn, ttl 2 hardcoded five times | never touches growth, goo, smoke, roots; a burning tile cannot be cleansed |
| smoke | blocks the player's lance and whip line; cleared by gust and clear_air; blocks terrain writes incidentally | enemies have no line of sight; does not block movement or fire |
| roots | block pathing, player moves, pushes, spawn placement; silently skip a vent spawn | beams pass through; drag ignores them; never burn |
| stun | skips the intent; pauses summon, ooze, stoke timers | no op reads it; never stacks |
| root | blocks the `move` intent only, ticks only when it blocks | attack, drain, gum, drag, summon, advance proceed while rooted |
| spore | ticks 1 per turn | never stacks (max); nothing consumes it |
| thorns | reflect melee, slams within 2, quakes; fire even when fully shield-absorbed | not drag, gum, drain, spikes, fire; overwritten rather than maxed |
| shield | absorbs every player damage source | does not stop drain (drain hits bank) |
| drag | blocked by anchor; destination gets fire, goo, supply effects | can land on roots (uses `_tile` not `_open`) |

## Appendix B. Bot coverage of the 24 abilities (condensed)

"Cast" means measured casts when held, 60 seeds with all packages on
(deeproot 10 runs). Full matrix in the bot audit (`scratchpad/wf/4_*.md`).

| ability | sprout | optimizer / magpie | fanatic | deeproot |
|---|---|---|---|---|
| solar_lance | yes | yes | yes | yes |
| seed_bomb | never | rest and boss gate only | gardener, turtle (topmost tile) | rarely (heal after end_turn) |
| vine_whip | never | last-resort fallback | shover | 0 observed |
| water_jet | never | dodge only | shover | rarely, truncated |
| mycelium_dash | never | dodge only | inherits | heavily |
| root_wall | never | never (no branch) | turtle | not held |
| pollen_burst | never | branch unreachable (strike runs first) | shover | not observed |
| sun_flare | never | 2+ within 2 | pyro | rarely, truncated |
| thorn_shield | never | shield 0 and enemy near | turtle | yes (shield bias) |
| overgrowth | never | never (no branch) | gardener (converts in 17 of 111 casts) | 0 observed |
| sap_snare | never | dodge fallback (no-op vs adjacent) | turtle | not observed |
| grow_spike | never | unconditional when legal | gardener | yes |
| spore_cloud, geyser | never | branch unreachable or never | no build | 0 casts |
| gust | never | dodge only | parent dodge | yes |
| updraft | never | never | never | yes |
| fungal_ring, burrow, tide, steam_vent, clear_air | never | never | never | searched, 0 or 1 casts |
| bramble_coat | never | never drafted (sentinel) | turtle | no thorns term |
| anchor_roots | never | dragger within 5 | no build | no anchor term |
| moss_filter | never | dim 1+ | no build | via dim term |

## Appendix C. Provenance

All scripts live in the session scratchpad and are reproducible against
commit `eb4425f` with `godot --headless --path . --script <file>`:

- `telemetry.gd`, `telemetry_out.md`: event-stream tally, 40 seeds per
  heuristic bot, 20 deeproot, tier 0, 190 seconds.
- `lift.gd`, `lift2.gd`, `phase2.sh`, `analyze.py`, `lift_analysis.md`,
  shard `*.jsonl`: synergy lift, deeproot, locked kits, 24 seeds per config,
  tiers 0 and 6, plus drift controls.
- `audit.gd`, `probe.gd` (40 interaction checks), `gate_scan.gd`,
  `trunc.gd`, `trunc_probe.gd`, `uses_probe.gd`, `deep_probe.gd`,
  `fanatic_aim.gd`, `fanatic_buy.gd`, `base4_probe.log`, `base5_probe.log`,
  `order_probe.log`: audit probes for defects and bot coverage.
- `combo_probe.gd` (21 combo existence and absence checks),
  `refute_probe.gd`, `refute_bd.gd`, `bd_lock.gd`, `bd_arch.gd`,
  `econ/econ.gd`, `econ/graft_value.gd`, `econ/heavy_out.txt`,
  `draft_mc.gd`, `oracle_probe.gd`, `loadouts.gd`, `oppo.gd`,
  `clock_margin.gd`: lens and refuter probes.
- `wf/*.md`, `wf2/*.md`: the structured outputs of the four audits, the
  telemetry measurement, the 59 findings with verdicts, the 35 refuter
  additions, the three roadmaps, the judge, and the critic.

The workflow ran 20 agents (4 audits, 1 measurement, 5 finders, 5 refuters,
3 designers, 1 judge, 1 critic) plus the lift measurement completed out of
band after a usage-limit interruption.
