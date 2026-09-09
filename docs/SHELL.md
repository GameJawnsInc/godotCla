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

Two things in that room are the way they are because of the cleanse steps.
The second slick sits **off the golem's row**: the guide teaches lancing
down that row two steps earlier, the lance ignites oil, and a burning tile
is not corruption — so CLEANSE refuses it until it burns down to ash, which
is the step's own instruction turned into a dead end. And the last cleanse
step says "the last of it" rather than "the last oil", because by then the
tile may be ash.

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
| R (shop sheet open) | reroll the shrine counter (Spinning Shrine mutator only) — outside the sheet R still restarts the seed |
| 1–5 / 0 (draft sheet) | take that offer / skip the draft — a skip arms one extra affinity offer on the next descent |
| SPACE / ENTER | end turn |
| ESC | back: close a sheet, cancel an aim, or leave the run for the menu (see *The Back button*) |
| R | restart the same seed |
| N | next seed |

Red-tinted tiles are telegraphed damage for the coming enemy turn (attack,
slam cross, quake ring) — the intent-visibility pillar, drawn. The right
panel lists every enemy's exact intent; the strip below the map is the
event log. Elites wear a gold ring, bosses show HP bars, your buffs ring
the player sprite (brown = anchored, green = thorns).

Holding an enemy adds an `avoids: fire` line when its `Content.ENEMIES` row
carries an avoid list — it paths around those tiles unless the way round is
far. When smoke swallows a telegraphed drain / gum / drag, the log says so
(`Tar Spitter's tar is lost in the smoke`), so a screened intent reads as
something you did rather than as the enemy skipping a turn.

## Touch controls (Android / any touchscreen)

Portrait layout: map on top, log + status in the middle, D-pad and action
buttons at the bottom. Everything is tappable — no keyboard needed:

- D-pad arrows: move (into an enemy = strike); center END button ends turn
- tap an adjacent tile: same as a D-pad press; tap your own tile: end turn
- **hold your finger on any tile**: tooltip naming what's there, its HP,
  and exactly what it will do next turn
- tap a kit line to cast — aim with the D-pad / adjacent tap for
  directional abilities, or tap a highlighted tile for tile abilities
- **cancelling an aim is free**: tap the same kit line again, press any
  D-pad arrow, or press Back. None of them move you, strike anything, or
  cost a turn, and the aim line on screen says so
- CLEANSE / DESCEND / HELP buttons bottom-right
- tap shop cards at a shrine, draft options between floors
- after a run: tap anywhere for the next seed

## Why CLEANSE refused

`CLEANSE` reaches a tile **beside** you, and only corruption. Its refusal
used to be "no corruption beside you" in every case, which is a lie in the
two that actually happen — and both read as a dead end, because a player
standing next to the thing the game just told them to clean is out of ideas.
`shell/main.gd` `_cleanse_hint` names the real reason:

| what is true | what it says |
| --- | --- |
| you are standing on the slick | `you're standing on it - step off first` |
| the slick is on fire | `still burning - wait for the ash` |
| nothing corrupt within reach | `no corruption beside you` |

Fire is not corruption; ash is. `tests/test_shell.gd` `_check_cleanse_hint`
drives all three and then checks that the ash the second one promises really
does open the aim.

## The Back button

Android's Back button and back gesture mean **up one level**, never "quit"
— `application/config/quit_on_go_back` is off and the shell handles
`NOTIFICATION_WM_GO_BACK_REQUEST` itself. `ESC` is the same handler
(`shell/main.gd` `_back`), so the keyboard and the touchscreen can never
disagree about what back means:

| where you are | what Back does |
|---|---|
| a held tooltip | drops the tooltip (and the hold with it, so it stays gone) |
| any sheet — legend, log, intro, shrine, settings | closes it, back to the map |
| the forge's keep / scrap / fork step | one step back, ending on the shrine sheet |
| the draft's drop sheet | back to the offer cards, nothing dropped |
| aiming an ability | cancels the aim — free, no turn, no strike |
| the room camera (zoom) | back out to the whole floor |
| normal play, the descent draft, the game-over sheet, the tutorial | the menu |
| the menu | quits (the root; `ESC` here does nothing) |

Leaving a live run for the menu costs nothing: every action is already on
disk and RESUME replays it byte-exact (*Run persistence* below).

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
| Smoke | `%` | blocks solar lances; on or beside you it screens tar, drain and grapple |
| Roots | `8` | blocks enemies for a while |
| Supply pod | `+` | walk over it to stock your satchel (2 slots) |

The ASCII column is `sim/ascii_view.gd` `TERRAIN_CH`, what the headless
views (`tests/autopsy.gd`, `tests/playtest.gd`) print.

## Building the APK

`export_presets.cfg` holds an Android preset (arm64-v8a, non-gradle,
`com.gamejawns.tender`). `build/` is gitignored and absent, so:

```
mkdir -p build
godot --headless --path . --export-debug "Android" build/tender.apk
```

Measured on a fresh container: **29.2 MB, signed v2+v3, zipalign verified,
about 20 seconds.**

### What Godot 4.7.1 actually requires

Read off the export's own error output and `platform/android/export/
export_plugin.cpp`, not inferred — an earlier version of this section listed
two things that are not needed and omitted the one that is.

| Requirement | Note |
|---|---|
| `~/.local/share/godot/export_templates/4.7.1.stable/android_debug.apk` | `--export-debug` needs the debug template ALONE; validation passes on either |
| `<sdk>/platform-tools/adb` — must exist and execute | a hard validation blocker, and `dl.google.com` is 403 here. A stub script satisfies it: Godot only checks existence and runs it for device polling |
| `<sdk>/build-tools/<ver>/apksigner` — `--version` must exit 0 | pick a version dir in `[28, 36]`; `36.0.0` matches `DEFAULT_TARGET_SDK_VERSION` and silences a warning |
| a JDK | the system JDK 21 is fine; `editor_settings-4.7.tres` already points at it |
| the debug keystore | `~/.local/share/godot/keystores/debug.keystore`, alias `androiddebugkey` |

**`zipalign` is NOT a requirement** — Godot never invokes it on the
non-gradle path (`-Pperform_zipalign=` is a Gradle property), and
uber-apk-signer's jar bundles its own Linux zipalign anyway. **A specific
Temurin JDK is not a requirement** either.

### Getting the pieces without the 1.22 GB pack

`android_debug.apk` is the FIRST member of the export-template `.tpz`, so a
byte-range fetch of the first 125,820,716 bytes and one raw-inflate gets it
(127,243,229 bytes out) instead of the whole 1.22 GB release asset:

```
curl -sSL -r 0-125820715 -o /tmp/dbg.bin \
  https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz
# then strip the 30+name+extra local header and zlib.decompressobj(-15) the rest
```

Signing goes through an `apksigner` shim over patrickfav/uber-apk-signer.
The real `com.android.apksigner.ApkSignerTool` is NOT in that jar, so the
shim has to translate — Godot calls `apksigner --version`, then
`sign --verbose --ks <KS> --ks-pass pass:<PW> --ks-key-alias <ALIAS> <APK>`
(in place, no `--out`), then `verify --verbose <APK>`.

None of this is installed by `.claude/hooks/session-start.sh`, which fetches
only the Godot binary — so every fresh session starts unable to build until
the template is re-fetched.

## Screenshots without a display

`tests/render_frame.gd` composes the same sprites into a standalone SVG,
headless — the agent's way to see the shell:

```
FRAME_SEED=3 FRAME_BOT=deeproot FRAME_ACTIONS=215 FRAME_OUT=/tmp/frame.svg \
  godot --headless --path . --script tests/render_frame.gd
```

`FRAME_ASH=<n>` stamps n ash tiles beside the player before rendering, so
the burnt-oil tile can be seen without waiting for a fire to expire.

`tests/render_sheet.gd` does the same for the **sheets**, which is where the
reading happens — a shrine deals up to seven offers at once:

```
SHEET=shop SHEET_OUT=/tmp/shop.svg godot --headless --path . \
  --script tests/render_sheet.gd
```

`SHEET=shop|draft|drop`, `SHEET_W`/`SHEET_H` (default 1080x2400, a phone),
`SHEET_SEED`/`SHEET_BLOOM`. It renders `shell/main.gd`'s own `_card_layout`
dict rather than a second copy of the layout, and it prints the smallest
description size on the sheet — the number the card gate below is about.
SVG only: Godot's own rasterizer drops `<text>`, so a PNG from here would be
the layout with every word missing.

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
upgraded `+` forms exist solely through the shrine press. (Item `+` ids keep
the plain `+` suffix - only abilities were forked into named variants.)

## Elements (resonances)

The status bar carries an **ELEMENTS** strip under the skies bar whenever the
run holds a card of any resonating element. Each entry is one
`Content.RESONANCES` row: `fire 2/3 Cinder Grip` while the element is short of
its threshold, `FIRE 3/3 Cinder Grip` in caps and gold once it resonates. A
run holding no card of any resonating element draws no strip and gives up no
space for it - and since fire is the only resonating element that ships, that
is an ORDINARY state, not a corner case: every run that starts without a fire
card (four of the six loadouts) sees no strip until it drafts one.

Whether an element is lit is read from `snapshot()["resonances"]` - the sim's
own answer, never re-derived in the shell. Only the *count* is computed
shell-side (`_resonance_state`), over the same two sources the sim counts: the
tags on the kit's ability rows and the tags on the held grafts.

The same readout appears on the three sheets where the count can move:

- **the descent draft** - the strip is repeated under the sheet head, and any
  card that touches a resonating element carries a clause of its own:
  `+fire 3/3 lights Cinder Grip` for the card that crosses the threshold,
  `+fire 2/3 Cinder Grip` for progress toward one, and nothing at all for a
  card of an element already lit. On a FULL kit the same card reads
  `+fire 3/3 would light Cinder Grip`: the draft is a swap and the drop is
  not chosen yet, so the offer sheet cannot promise the light
- **the drop sheet** (a full kit) - a card whose loss would put a lit element
  out is badged **BREAKS** and says which:
  `Cinder Grip out (fire 2/3)` (the badge carries the word, so the note does
  not repeat it). This sheet knows BOTH halves of the swap,
  so the count is netted against the card being taken: dropping one fire card
  to take another leaves the count where it was and is not badged. The
  strip itself is left off that sheet - it is the taller of the two (five kit
  cards) and the badges carry the same information. A forge scrap can break a
  row the same way; there the status strip is what shows it afterwards
- **the shrine** - a graft carries tags too, so its card gets the same clause
  (`+fire 3/3 - lights Cinder Grip` on an Ember Sap or Oil Tithe offer, the
  two fire-tagged grafts)

The game-over sheet names what the run ended up resonating
(`resonating: Cinder Grip`), and the intro card says the rule in one line.

## Choice cards

Every offer the game asks you to pick between — a shrine's seven, a draft's
three or four, the forge's two, the drop sheet's five — is drawn by one
function, `shell/main.gd` `_card`, over one layout dict, `_card_layout`. A
card is:

```
 [icon]  Sun Flare  ●●   +            AFFINITY   <- or a bloom price
         2 dmg within 2, +1 in fire, ignites oil
         · Growth: -1 cost, +1 radius
```

- the **name** is the head row, at `0.28` of the card height
- the **charge cost** is pips, the same gold dots the ability bar draws under
  every slot, so the number is never also spelled out in words
- a **`+`** in gold marks an upgrade, again matching the bar
- the right edge carries EITHER the draft's slot label (AFFINITY / UPGRADE /
  WILD / FOCUS / BREAKS) OR the shrine's price beside the bloom sprite, drawn
  **red when your purse cannot meet it** — never both
- the **description** gets the card's full width and wraps onto two lines

The wrap is the point. Descriptions used to be a single `_txt_fit` line, and
`_fit_size` shrinks a font to as little as 9px to make a long line fit: on a
1080x2400 phone the worst shrine card rendered its description at **11px**.
Wrapping alone was not enough — the strings had to come down too, from a
longest of 144 characters to 81.

`tests/test_shell.gd` `_check_card_text` holds both halves, and it is worth
knowing why it looks the way it does. Its first version measured ONE card at
ONE viewport — the seven-offer shrine, on the reasoning that the shortest card
is the tightest. That is wrong: a description's budget is set by WIDTH, while
the nominal it is compared against is `int(h * 0.19)`, which falls with
height. At seven offers the two happen to meet, so "nothing shrinks" was free,
and the gate passed while the eight-offer shrine drew 29px text and 19 of the
39 upgrade cards drew their `+` straight through the slot badge.

So the gate sweeps every card geometry a sheet can produce — the shrine at
**1 to 8** offers (heal + ability + 2 grafts + 2 press + forge + reroll; the
item card cannot coexist with the press cards, so 8 is the ceiling), the draft
and drop sheets, the forge — across eight viewports from 540x1200 to a
portrait tablet and one landscape shape, over the strings the sheets
**compose** rather than the raw table rows. It checks three things:

- apparent size: no description below **1.15% of viewport height**. A fraction,
  not a pixel count, because pixels are not a fixed size — the measured worst
  is the eight-offer shrine at 1.167%
- no description needing more than two lines (`_wrap` never truncates, so this
  would be a font drop, not lost text)
- the head row clearing whatever sits on the right edge, **with the upgrade
  `+` drawn**, against both the badge and the price

That last one is the one that had a live bug. `_fit_size` grows a name until
it meets its allowance, and the pips and the `+` are drawn *after* it, so the
allowance has to reserve them. It reserved `pips * h*0.15` and nothing else —
not the leading gap, not the `+`. Because that tail is sized in card height
and `h/vw` grows with the aspect ratio, the overrun was absent at 16:9 and
present from 18:9 up: 19 of 39 upgrade cards at 1080x2400, 30 at 1080x2640,
by as much as 54px. Restoring the old allowance fails the gate with 1611
collisions.

`_shop_cards`, `_draft_cards` and `_drop_cards` return those cards as data
(`[icon, name, desc, tag, ...]`) before anything is drawn, which is how the
headless test asserts what a sheet offers and how `tests/render_sheet.gd`
draws the same sheet as an SVG.

Two rules the same pass bought elsewhere. The **hold-tooltip** wraps now too
(`_draw_tooltip`): it fitted each line to one `_txt_fit` line, so the same
`ABILITY_DESC` row a card shows at 34px landed there at **25px** — and because
the lines share one size, the widest dragged the enemy's name and HP down with
it. And a sheet's trailing button goes through `_sheet_button_y`, which keeps
it inside the sheet's own panel: a button whose `y` accumulates behind a
variable card count walks off the bottom, and the drop sheet's BACK (five kit
cards, the only shape that sheet has) landed **32px below the frame and 52px
from the screen edge** — inside Android's home-gesture strip, on the one
control that leaves a sheet the player is forced to resolve. The shrine's
CLOSE never moved because it is pinned at a constant `vh*0.885`.

## The descent draft

Each descent opens the draft sheet: tap a card to take it (`1`-`5`, or
`0` to skip; a full kit then asks which ability to drop). Every card
carries the **slot** that rolled it, gold on its right edge, straight off
`snapshot().draft_slots`:

- **AFFINITY** - shares a tag with what you already carry (kit *and*
  grafts), so it feeds the build you are on
- **UPGRADE** - an upgrade of an ability in your kit (one of its two named
  variants; which one is decided by the floor you are entering, and the forge
  sells the other)
- **WILD** - anything in the run's pool, build or no build
- **FOCUS** - the extra affinity offer a previous skip bought

The three slots are always dealt in that order (Wide Draft adds a fourth,
wild; Upgrades Only makes every card an upgrade), so the sheet asks the
same three questions every floor and the labels say which is which.

The skip button is the draft's answer to a bad hand - it reads
`skip - next draft: +1 affinity offer` (and `skip - focus armed again`
on a sheet whose roll spent a focus). Skipping pays no Bloom:
it arms one extra build-matching offer on the next descent, spent by that
draft whether you take a card or not, and the log line
(`Took nothing - the next draft adds a focus offer`) is what carries that
promise across the floor.

A focus slot can find nothing left to offer - under Upgrades Only a
three-ability kit has exactly three upgrade candidates and the ordinary slots take
them all - and then the roll spends the focus and deals no FOCUS card. The
sheet says so ("Your skip found nothing left to focus on") rather than
reading as an ordinary draft: it takes that from the `draft_offer` event's
`focus` flag, since the cards alone cannot tell the two apart.

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
  closes the counter and the other offer is lost. Each graft carries its own
  price - a lever like Solar Core costs more than a stat graft, and the card
  shows that price - and every graft you own raises the next one, so the pair
  is a choice, not a shopping list.
- **item** - one base consumable
- **press** - two held items become the `+` form of the one you keep
- **forge** - one kit ability grows into an upgrade of itself and another is
  scrapped for parts. Once per floor: using it closes the forge until the next
  shrine, and a mobility ability can never be the scrap. Since Block D6 the
  forge is a **three-tap** choice: tap what to keep, tap what to scrap, then
  pick which of the two named variants that ability grows into off a card
  sheet that shows both in full (a package ability has only one upgrade and
  forges straight away on the second tap; Back — or `ESC` — steps back one
  tap at a time, fork sheet to scrap tap to keep tap to the shrine sheet,
  and the fork sheet's own BACK button does the same. On a touchscreen the
  SHRINE SHOP button stays on screen through both selection taps and is the
  same free way out - and because it is, the D-pad next to it is inert
  through all three steps: an arrow says "the forge has the screen" instead
  of walking you off the shrine for a charge and a turn). The forge is the way to
  reach the sibling the current floor's draft cannot deal - the descent draft
  offers only one variant per base, alternating by floor.
- **reroll** (only under the Spinning Shrine mutator; a default run's sheet
  has no reroll card) - "Reroll (price) - n left": redraws the ability, graft and
  item cards in one go, each from the same table the floor stocked them
  from and never the offer already on the counter. Bought cards stay bought
  (a counter with nothing re-drawable left has no reroll card at all) and
  heal / press / forge are untouched. It costs bloom, not a charge, gets one
  bloom dearer every spin (2, 3, 4 at tier 0) and is capped at three spins
  per shrine, so it is a choice sink, not a slot machine: rerolling the
  counter twice is a graft you did not buy. The card is drawn whenever a
  re-drawable slot is stocked and says why it is dead (out of spins, or too
  little bloom); tapping it then just flashes. `R` with the sheet open is
  the same button.

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
