# TENDER — the human shell

## Menu, settings, tutorial

The shell boots to a main menu: PLAY (fresh run), RESUME (when a run is
live), the run-setup rows (see *Setting up a run*), TUTORIAL, SETTINGS,
QUIT. Settings persist to `user://tender.cfg`: hold-to-inspect delay, run
seed mode (random / daily — everyone playing a daily gets the same run),
and intro-tips frequency, alongside the run choices the title screen makes
(difficulty, loadout, package, mutator). The sheet also prints where
finished run logs are kept. The `=` button in the status strip returns
to the menu mid-run without losing the run.

The tutorial is **entirely data** in `shell/tutorial.gd`: an ASCII-drawn
room, a fixed kit, and a step list (guide text + the action pattern that
advances each step). It runs on the real sim via the `fixed_floor` run
config, navigation is always free, and only the taught action advances the
script. To change the tutorial, edit that one file — and note that
`tests/test_shell.gd` plays every step through the sim headlessly, so a
sim or content change that breaks the script fails the suite instead of
shipping a broken tutorial.

A thin Godot scene over the sim (style guide §1/§4): it draws `snapshot()`
with runtime-rasterized SVG sprites and forwards input as `step()` actions.
The sim has no idea it exists.

## Running

```
godot --path .            # random-ish seed, shown in the HUD
SHELL_SEED=42 godot --path .   # pinned seed (fully deterministic run)
```

Requires a desktop Godot 4.7 (the repo's headless binary has no display).
Clone the repo, open the project, hit play — `shell/main.tscn` is the main
scene.

## Controls

| key | action |
|---|---|
| arrows / WASD | move; moving into an adjacent enemy strikes it |
| 1–5 | cast that kit slot — direction abilities then take an arrow key, tile abilities highlight legal tiles to click |
| C + direction | cleanse an adjacent corrupted tile |
| E | descend (on the stairs) |
| H / B | buy heal / ability (standing on a shrine) |
| G / J | buy the first / second graft on offer |
| SPACE / ENTER | end turn |
| ESC | cancel targeting |
| R | restart the same seed |
| N | next seed |

Red-tinted tiles are telegraphed damage for the coming enemy turn (attack,
slam cross, quake ring) — the intent-visibility pillar, drawn. The right
panel lists every enemy's exact intent; the strip below the map is the
event log. Elites wear a gold ring, bosses show HP bars, your buffs ring
the player sprite (brown = anchored, green = thorns).

## Touch controls (Android / any touchscreen)

Portrait layout: map on top, log + status in the middle, D-pad and action
buttons at the bottom. Everything is tappable — no keyboard needed:

- D-pad arrows: move (into an enemy = strike); center END button ends turn
- tap an adjacent tile: same as a D-pad press; tap your own tile: end turn
- **hold your finger on any tile**: tooltip naming what's there, its HP,
  and exactly what it will do next turn
- tap a kit line to cast — aim with the D-pad / adjacent tap for
  directional abilities, or tap a highlighted tile for tile abilities
- CLEANSE / DESCEND / HELP buttons bottom-right
- tap shop cards at a shrine, draft options between floors
- after a run: tap anywhere for the next seed

## Setting up a run

Under PLAY (and under DIFFICULTY, once a win has opened the ladder) the
title screen carries three cycling rows — tap one to step to the next
choice. They persist in `user://tender.cfg` alongside the difficulty, and
every one of them is clamped to what the career has actually unlocked, so
a profile that unlocked nothing shows `tender / none / none`:

| row | cycles through | comes from |
|---|---|---|
| LOADOUT | Tender plus every unlocked loadout whose package requirement is met | `Content.LOADOUTS`, filtered by `profile.available_loadouts()` |
| PACKAGE | none, then each unlocked tech package | `profile.unlocked_packages` |
| MUTATOR | none, then each unlocked mutator | `profile.unlocked_mutators` |

A **loadout** is the starting kit: Tender is the familiar lance / seed
bomb / dash, and each of the others swaps one ability for another way to
open a fight (every loadout keeps a seed bomb and a mobility ability).
A **package** is now a run-scoped commitment, not a permanent pool
addition: a run drafts from the base pool plus at most one package (14 or
17 ids), and the old draft-from-everything pool is a deliberate choice
again — the `open_pool` mutator, unlocked by the first win.

PLAY builds the run config with `profile.game_config(tier, [mutator],
loadout, package)`, so the career gate lives in one place: a locked
loadout falls back to Tender and a locked package to none, however the
cfg file got written.

In daily seed mode the three rows are replaced by a single line —
`TODAY: <loadout> · <package> · <mutator>` — and PLAY uses exactly that.
A daily's config is `Profile.daily_config(seed)`, derived from the seed
alone over frozen lists in the profile, so today's challenge is the same
for everyone and a content table that grows later cannot move an earlier
date's run. Dailies ignore career unlocks entirely, and still score only
to the daily board.

The status strip names the live run's config under the skies bar —
loadout, then package, then mutator (`Tidewarden · Aeolian · Brittle`) —
read straight off the sim's snapshot, so a run never hides what it was
set up as. Run saves already carry the whole config in their header, so
none of this changes the save format.

## Legend

HELP opens the legend sheet; holding a tile shows the same row as a
tooltip. The rows are `shell/main.gd` `LEGEND` (sprite id, name, blurb) —
one row per drawable thing, and every `Content.TERRAIN` kind must have
one (`tests/test_shell.gd` checks it). The terrain rows:

| tile | ASCII | what it is |
|---|---|---|
| Oil | `~` | corruption - cleanse it (adjacent) for bloom; burns |
| Goo | `;` | corruption - cleansing yields bloom |
| Rich goo | `&` | corruption - cleanses for extra bloom |
| Ash | `,` | burnt oil - still corruption, cleanse it for bloom; it never shields the boss core |
| Growth | `"` | heals 1 HP per turn while you stand on it |
| Fire | `*` | burns whoever stands in it; burns out into ash |
| Smoke | `%` | blocks solar lances |
| Roots | `8` | blocks enemies for a while |
| Supply pod | `+` | walk over it to stock your satchel (2 slots) |

The ASCII column is `sim/ascii_view.gd` `TERRAIN_CH`, what the headless
views (`tests/autopsy.gd`, `tests/playtest.gd`) print.

## Building the APK

`export_presets.cfg` holds an Android preset (arm64, non-gradle). With
export templates, a JDK, zipalign, and an apksigner on the SDK path:

```
godot --headless --path . --export-debug "Android" build/tender.apk
```

This container builds it with GitHub-sourced pieces only: Temurin JDK 17,
lzhiyong/android-sdk-tools (zipalign), and an `apksigner` shim over
patrickfav/uber-apk-signer for signing — no Google SDK download needed.

## Screenshots without a display

`tests/render_frame.gd` composes the same sprites into a standalone SVG,
headless — the agent's way to see the shell:

```
FRAME_SEED=3 FRAME_BOT=deeproot FRAME_ACTIONS=215 FRAME_OUT=/tmp/frame.svg \
  godot --headless --path . --script tests/render_frame.gd
```

`FRAME_ASH=<n>` stamps n ash tiles beside the player before rendering, so
the burnt-oil tile can be seen without waiting for a fire to expire.

`tests/test_shell.gd` is the shell's headless smoke test (sprite
rasterization, input handlers driving the sim, the whole tutorial script,
the shrine sheet's choice sinks, run restore, log retention and import),
part of the suite. `SHELL_EXPORT_SAVE=<path>` also drops a real run log
there, which is how you get a save to feed `tests/import_run.gd`.

## Art

All sprites live in `shell/svg_art.gd` as hand-written 32×32 SVG strings,
rasterized at runtime via `Image.load_svg_from_string` — no import
pipeline, no binary assets, diffable art. Edit the string, rerun.

## Career and difficulty

The shell persists a career profile (`user://tender_profile.json`,
`meta/profile.gd`). Finished runs are recorded automatically; the first
win unlocks the difficulty ladder and a DIFFICULTY cycler appears on the
menu (tiers from `Content.TIERS`, clamped to what is unlocked). Milestones
also unlock packages, mutators and **loadouts** — the LOADOUT / PACKAGE /
MUTATOR rows above are what a career spends its unlocks on. The win
screen lists newly unlocked tiers/packages/mutators, and the menu footer
shows runs / wins / best floor. Daily runs are scored but never counted
toward the career: a finished daily is filed as that seed's best result
(won, floor, turns) and unlocks nothing.

## Satchel

The two free D-pad corner slots are the satchel: tap a stocked item to
use it (free action - the turn does not advance), hold it to read what
it does. Supply pods drop when a room blooms and shrines always stock
one consumable. Pods and shrines only ever hand out **base** items: the
upgraded `+` forms exist solely through the shrine press.

## The shrine

Standing on the shrine opens the sheet. Every card resolves to one action
out of `legal_actions()` - the shell never sends a purchase the sim would
refuse. A card that is spent or boarded is not drawn; the press and forge
rows appear only while they are legal; an unaffordable heal, ability, graft
or item card is still shown with its price and flashes when tapped:

- **heal** - 4 HP, once per shrine
- **ability** - one draw from the run's pool, buyable only while you have a
  free kit slot. With a full kit the card is not for sale: the sim stops
  offering the action and the card flashes when tapped.
- **two grafts** - the shrine offers two and sells **one**; taking either
  closes the counter and the other offer is lost. Prices rise as you stack
  grafts, so the pair is a choice, not a shopping list.
- **item** - one base consumable
- **press** - two held items become the `+` form of the one you keep
- **forge** - one kit ability becomes its `+` form and another is scrapped
  for parts. Once per floor: using it closes the forge until the next
  shrine, and a mobility ability can never be the scrap.

The Boarded mutator (and floor 7, which has no shrine) closes the whole
sheet - press and forge included.

## The green gate

Each floor's stairs start dormant (grey ring, vines) and awaken when
the floor's green quota is met - the status row shows "green x/y" and
the objective line tracks it. Overgrown vents (growth planted on the
grate) absorb their next reinforcement. Cleansing every last corruption
tile restores the floor: banner, skies clear, bonus bloom.

## Run persistence

Live runs survive the OS killing the app: every action is appended to
`user://tender_run.save` (header = seed/config/tier + RUN_SAVE_VERSION,
then one action per line, flushed immediately). On boot the shell
replays the log through the pure sim - determinism makes the restore
byte-exact. RESUME can also recover the run from disk after the tutorial
displaces it.

`RUN_SAVE_VERSION` is not a number the shell owns any more: it *is*
`Game.SIM_VERSION`, the sim's single source of truth (regression records
and autopsy dumps stamp the same value). Bump it in `sim/game.gd` whenever
a sim change alters replay behaviour, or stale logs replay into divergence.
When the shell finds a save from another version it discards it - and says
so: the title screen carries one line, *"your saved run was lost to an
update"*, until the next new run.

### Finished runs are kept

A finished log is a replayable `(seed, config, actions)` pair, so it is
archived instead of deleted: it moves to
`user://runs/run_<seed>_<yyyymmdd>_<won|died>.save`, and only the newest 10
are kept (oldest by modified time go first). The settings sheet prints the
folder's real path. In-flight saves are still deleted, exactly as before.

### Importing a run as a regression pair

`tests/import_run.gd` replays one of those logs through the pure sim and
writes the `tests/regressions/*.json` record it proves - the way a bug that
only happened on the phone becomes a test:

```
IMPORT_RUN=~/.local/share/godot/app_userdata/TENDER/runs/run_708906_20260905_died.save \
  IMPORT_OUT=tests/regressions/phone_death.json \
  IMPORT_NOTE="floor 3 death: the gate never re-clamped" \
  godot --headless --path . --script tests/import_run.gd
```

It prints the replayed outcome (`won / floor / turns / timeout / illegal /
errors / hash`) and refuses a save whose header version is not the current
`Game.SIM_VERSION` - importing one would mint a record of a game that never
happened.
