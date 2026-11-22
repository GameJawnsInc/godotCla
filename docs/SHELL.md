# TENDER — the human shell

## Menu, settings, tutorial

The shell boots to a main menu: RESUME (when a run is live), PLAY (a fresh
career run), DAILY (see *Daily challenge*), the run-setup rows (see
*Setting up a run*), and TUTORIAL / SETTINGS / QUIT sharing the last line.
Settings persist to `user://tender.cfg`: hold-to-inspect delay, intro-tips
frequency and the sound toggles, alongside the run choices the title screen
makes (difficulty, loadout, package, mutator). (The old "Run seed" toggle is
gone: PLAY is always a career run and the daily has its own entry. A cfg
that still says daily keeps that key only until the next run starts — it
files a run saved before the change — and the menu says once that the daily
now has its own button.) The sheet also prints where
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
| R | restart the same seed (in the tutorial: restart the tutorial) |
| N | a new career run on the next seed (ignored in the tutorial) |

At the end of a run every key but ESC is ignored until the game-over sheet
has been up for a moment (see *The end of a run*); then R retries the seed
and N starts a career run on the next one, as in play.

Red-tinted tiles are telegraphed damage for the coming enemy turn (attack,
slam cross, quake ring), read straight from the sim's own `Game.telegraph()`
— the intent-visibility pillar, drawn. Each red tile carries the damage it
will take in its bottom-right corner (summed over every attacker aiming at
it; not on your own tile, where the context line speaks for it). Every enemy
wears an intent badge at its top-right corner: a glyph on a dark disc ringed
in the intent's colour (red: a hit, violet: drain / tar / grapple / advance,
amber: a countdown, orange: a world change), with its number beside it —
damage, the countdown, the steps, the drag count when above 1. A ring at
half strength is an intent not aimed at you where you stand. A BLOCKED
intent wears its block glyph instead (stars stunned, roots rooted, a slashed
cloud lost in the smoke, an anchor when your roots hold the grapple) and
paints no red tile — a stunned striker used to paint a false one. A grapple
draws a dashed blue tether from the crane to you with a ring on the tile it
will land you on (grey and ringless when blocked); a flood stripes the row it
will oil, an ignite-all pulses every oil tile that will catch, a dredge tints
the growth it will eat. Vents count down on the grate from 5 turns out, with a
red pulsing ring at 1 (green on a vent your growth has sealed). A tar shot
outlines the ability slot it will gum, in dashed brown. The legend (HELP) has
a row for every badge. The strip below the map is the event log. Elites wear
a gold ring, bosses show HP bars, your buffs ring the player sprite (brown =
anchored, green = thorns).

Holding an enemy adds an `avoids: fire` line when its `Content.ENEMIES` row
carries an avoid list — it paths around those tiles unless the way round is
far. When smoke swallows a telegraphed drain / gum / drag, the log says so
(`Tar Spitter's tar is lost in the smoke`), so a screened intent reads as
something you did rather than as the enemy skipping a turn.

## Danger readouts

`shell/danger.gd` turns the sim's three read-only forecasts into what the
screen says about what is about to hurt you. Nothing here changes a run.

- **The SKIES row.** Under the smog bar: `SKIES`, then up to three countdown
  chips — a skull and the end turns until the smog starts choking you, a vent
  and the end turns until the vents release, a dimming sun and the end turns
  until the sky dims (only within 9). The choke chip turns amber at 5 or
  fewer and red at 1 or while choking (it then counts to the next choke);
  the vent chip turns amber at 1, green when every free vent is sealed by
  growth and grey when every vent is occupied. The bar itself gets a pulsing
  amber outline in the choke's last 5 turns, red once it chokes. Every number
  is the soonest it can come — a cleanse, a kill or a stun can only push it
  later.
- **The context line** (above the D-pad) leads with danger: `! INCOMING 3 -
  LETHAL  ·  Drill Bot, smog` in pulsing red when ending the turn where you
  stand would kill you, `! INCOMING 2  ·  Drill Bot` in amber when it would
  hurt, `! INCOMING 2 - shield holds` when your shield takes it all; then the
  choke countdown (`Smog chokes in 3 - cleansing thins it`, or `- descend to
  escape it` once the stairs are awake; `NEXT TURN` in red); then `The vents
  release next turn`; then the floor's usual hint. The forecast is the real
  end turn played out on a copy, so the number is exact.
- **Lethal colours.** When the end turn would kill you, your outline pulses
  red (amber when something lands but you live), the HP chip and the screen
  edges go red, and END / END TURN get a red border. A satchel item that
  would save you pulses gold. The HP chip and the red edges share one rule:
  red at 3 HP or less (or a quarter of max HP, when that is more), or when
  the coming end turn kills.
- **Sounds and banners.** A double warning tick plays when the lethal
  forecast switches on and when the choke enters its last 5 turns; at 1 turn
  the banner THE SMOG THICKENS / it chokes from next turn. Each fires once per
  new low on the floor: a cleanse that pushes the choke back, and the turns
  that bring it down again, do not replay them.
- **Tooltips.** Holding an enemy adds why its intent will not land (stunned,
  rooted, lost in the smoke, your anchor holds) and for a smokestack how many
  turns sooner it brings the choke (on its idle turns too; with two or more
  alive, "stokers bring the choke N turns sooner", since that is their total); holding yourself reads `ending here: 3
  incoming - LETHAL`; holding a vent reads `releases in 4 turns` or `sealed -
  absorbs the next release`.

## Touch controls (Android / any touchscreen)

Portrait layout: map on top, log + status in the middle, D-pad and action
buttons at the bottom. Everything is tappable — no keyboard needed:

- D-pad arrows: move (into an enemy = strike); center END button ends turn
- tap an adjacent tile: same as a D-pad press; tap your own tile: end turn
- a D-pad (or arrow-key) press or cleanse tap that ran out of charge, or a
  tap on yourself, asks for a second press when the forecast says that end
  turn would kill you: the line above the D-pad says `LETHAL (3) - step off,
  or tap again to end turn` (or `strike first` when only hitting the
  attacker saves you, or names the glowing satchel item, or the stairs) and a second press within 1.5 s goes through. END TURN, the
  D-pad's END, SPACE and ENTER never ask — pressing END is a decision
- **hold your finger on any tile**: tooltip naming what's there, its HP,
  and exactly what it will do next turn
- tap a kit line to cast — aim with the D-pad / adjacent tap for
  directional abilities, or tap a highlighted tile for tile abilities
- **cancelling an aim is free**: tap the same kit line again, press any
  D-pad arrow, or press Back. None of them move you, strike anything, or
  cost a turn, and the aim line on screen says so
- CLEANSE / DESCEND / HELP buttons bottom-right
- tap shop cards at a shrine, draft options between floors
- after a run: the map holds for a beat, then the game-over sheet fades in
  with its buttons - NEW RUN, RETRY SEED (RETRY DAILY on a daily), MENU.
  Nothing else on the sheet starts a run: a stray tap does nothing

## Feedback: callouts, kills, log and sound

`shell/feedback.gd` turns each step's events into what you see and hear; it
reads the event stream and never invents an outcome.

**Callouts** are short bold words over the tile where something paid off:

| word | when | colour |
|---|---|---|
| `CINDER GRIP`, `COMPOST`, `EMBER SAP`, `UNDERTOW` | a hook that actually landed | gold |
| `GROWTH +1 dmg`, `CROWD +2 dmg` | a `per` rider | gold |
| `BURNING +1 dmg` | a `bonus` rider | gold |
| `ROOTED!` / `STUNNED!` | a `then` rider's status (`COMBO` if it claimed none) | gold |
| `SURGE +1 dmg` / `+1 push` / `+1 reach` | a verdant surge (first stat) | gold |
| `COLLISION` | a slam into a wall or a body | gold |
| `SHIELDED` | a hit on a shielded boss core | cyan |
| `DOUBLE KILL`, `TRIPLE KILL`, `N KILLS` | kills in one player turn (big) | gold |
| `ROOM CLEAR` | the last machine in your room fell (big) | green |
| `STREAK N` | first kill of the Nth turn running | orange |
| `BOUNTY +4`, `BLOCKED N`, `IGNITE`, `TITHE -1`, `VERDANT` | the rest | own colours |
| `ROOTED`, `STUNNED`, `SPORED`, `IMMUNE`, `RESISTED` | plain statuses | status colours |

One per word and tile, sorted by priority, every big one plus four regular
ones; a dropped word still gets its log line.

**Kills.** The killing number is gold, bold and half again as large; every
number grows with its damage. A kill (or any hit of 4+) is a 70 ms hit-stop -
the effects clock freezes while the dead machine flashes white - the tender
leans a quarter tile into a strike, and kills shake the screen. A flame with a
number beside the tender is your kill streak (two or more turns running with
a kill); it dims while this turn's kill is still owed - end the turn without
one and it breaks.

**Boss.** A shielded core shows a pulsing cyan ring on the map and `SHIELDED`
in cyan on the boss bar; a phase change shows a banner saying what changed.
The floor-7 title card reads "defeat the Overseer".

**Banners** share one queue (boss phase, then a resonance awakening, floor
restored, stairs awaken); one shows at a time.

**Log.** Names, never ids ("Cinder Grip roots the Coal Golem", "A vent
releases a Coal Golem"); repeats count up ("Oil ignites x3"); each line is
coloured by kind (hurt red, rewards gold, heals green, combos violet, boss
orange) and long lines shrink to fit. A cleanse says what it paid: "Cleansed
+1 bloom · green 3/5", or "Cleansed - enemy-made oil pays no bloom".

**Sound.** At most three sounds a step, worst first (win/death, boss, hurt,
multi-kill, shielded, kill, ...), then a bell chime climbing a step for each
combo word, with an octave on a room clear. Repeated sounds vary slightly in
pitch on a fixed cycle.

`tests/render_frame.gd` draws no effects, so all of this is tested as data
(`tests/test_shell.gd` `_check_feedback`), and drawn for real, frame by
frame, by `tests/test_draw.gd`.

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

## The end of a run

A run never ends on a cut. When the tender dies (or the Furnace falls) the
map stays on screen for 1.2 s (`OVER_BEAT_MS`): it tints smog-brown on a
death or washes gold on a win, three bursts land on the tender (on a win, on
the boss's last tile), the controls dim behind a veil, and a banner names
the moment - `THE SMOG TAKES YOU`, `THE DRILL BOT TAKES YOU`, `THE SPIKES
TAKE YOU`, `YOUR EMBER SAP TAKES YOU`, `THE FURNACE FALLS`. Then the sheet
fades in over 0.4 s (`OVER_FADE_MS`). Taps and keys are ignored until 1.9 s
after the end (`OVER_LOCK_MS`, 0.3 s after the sheet is opaque), so a finger
still hammering the D-pad cannot skip the death or start a run by accident;
while locked the buttons draw dim. Back and ESC are never locked - they go
straight to the menu, and the run is already recorded. A game that ended
some other way (a resumed save, a test that sets it over) goes straight to
the sheet, unlocked.

The sheet, top to bottom (`shell/main.gd` `_over_layout`, words from
`shell/run_end.gd`):

| row | example |
|---|---|
| title | `YOU DIED` / `THE FURNACE IS COLD` |
| cause | `struck down by a Drill Bot · Pipeworks`, `The Furnace Core is scrap · the valley breathes again` |
| near miss | `The Dredge had 3 HP left`, `the stairs were 4 steps away`, `2 cleanses short of waking the stairs`, `one floor short of your best (floor 6)`, `1 more HP would have saved you`; on a win `closest call: 1 HP on Furnace Approach` |
| stats | `floor 5 of 7 · 63 turns · 24 kills · 41 bloom earned` - the run's total turns, not the floor's |
| kit | each ability's icon with its effective casts (`x12`), a gold `+` on an upgrade |
| grafts | `grafts  Compost · Ember Sap` |
| chips | up to three highlights: a floor restored, a resonance lit, a record beaten (`record · most machines felled 41 (was 30)`), a multi-kill, the biggest hit (`biggest hit 6 · Solar Lance fire`), a streak, rooms bloomed... |
| score | `SCORE 1234` |
| best | `NEW BEST · was 1100`, `NEW BEST FOR TIDEWARDEN · was 900`, `best 1449 · this run 85%`, `your first score · beat it next run`; on a daily `RANKED · your first finish today`, `NEW DAILY BEST · was floor 3`, `today's best: floor 4 · 3 tries` |
| floor best | `YOUR FIRST WIN`, `DEEPEST YET · floor 5 (was 3)` |
| score parts | every non-zero part (`floor 500 · kills 120 · bloom 82`), then `x1.5 difficulty 2` |
| unlocks | `NEW DIFFICULTY · Thicker Smog`, `UNLOCKED · Hydraulics package`, `UNLOCKED · Skyrunner loadout (needs Aeolian)`, `UNLOCKED · Slick Combine mutator`, then `+2 more` |
| next | `NEXT · Land 30 Grow Spikes · 17/30 (+9 this run) · unlocks Wide Draft` (numbers only when the goal needs more than one) |
| seed | `seed 123456 · Tender · Mycology`, plus `difficulty 2` and `daily` |

Every "was" on the sheet is the career's best from BEFORE the run
(`profile.bests_snapshot`, taken before the run is recorded). A daily shows
no unlock rows and no NEXT; a tutorial death shows no score, best, unlocks,
goal or seed and offers TUTORIAL AGAIN / MENU. When a phone is too short for
every row, the least important present row is dropped first (the seed line,
then the third chip, then the score parts...), and the title, cause, score
and best never go; `tests/test_shell.gd` `_check_over_text` holds every row
to the card text floor at every phone shape.

The score is cosmetic and transparent: `Content.RUN_SCORE` (100 a floor,
500 a win, 5 a kill, 2 a bloom earned, 3 a combo, 10 a room bloomed, 50 a
floor restored), plus a quarter per difficulty tier. It buys nothing.

## The Back button

Android's Back button and back gesture mean **up one level**, never "quit"
— `application/config/quit_on_go_back` is off and the shell handles
`NOTIFICATION_WM_GO_BACK_REQUEST` itself. `ESC` is the same handler
(`shell/main.gd` `_back`), so the keyboard and the touchscreen can never
disagree about what back means:

| where you are | what Back does |
|---|---|
| a held tooltip | drops the tooltip (and the hold with it, so it stays gone) |
| any sheet — legend, log, intro, shrine | closes it, back to the map |
| the settings or DAILY sheet on the menu | closes it, back to the menu |
| the forge's keep / scrap / fork step | one step back, ending on the shrine sheet |
| the draft's drop sheet | back to the offer cards, nothing dropped |
| aiming an ability | cancels the aim — free, no turn, no strike |
| the room camera (zoom) | back out to the whole floor |
| normal play, the descent draft, the end-of-run beat and the game-over sheet, the tutorial | the menu |
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

The menu is data first (`_menu_rows` -> `_menu_layout`), 0.80 of the
screen wide, and every label is held to at least 1.5% of the screen height
at every phone shape the card gate sweeps. A row with something new on it
carries a small gold **NEW** badge until you cycle onto that thing: a
difficulty, loadout, package or mutator the career just unlocked (a loadout
still waiting on its package, like Skyrunner before Aeolian, earns none —
there is nothing to cycle onto yet). The LOADOUT row instead reads **WON**
or **WON D2** when the selected loadout has won (at that difficulty). The
footer reads `runs · wins · best floor` once the career has a run.

## Daily challenge

DAILY opens the daily sheet: today's date, the day's loadout, package and
mutator as cards, and what you have done with it — "No finish yet", "2
tries, no finish yet", or "ranked: floor 4 · best: won in 133 turns · 3
tries". The **first finish** of the day is the ranked one (kept in
`daily_first`); later finishes only improve the day's best, so the sheet's
button reads PLAY TODAY'S RUN until you finish and PLAY AGAIN · unranked
after. While a try of today's daily is still in progress (you left it for
the menu, or the tutorial displaced it) the button reads RESUME TODAY'S TRY
and takes you back into that try instead of starting over; the menu's PLAY
then reads TAP AGAIN TO ABANDON on the first tap, because a career start
overwrites the one run save and the try is already counted. Every start
counts as a try, a retry included. A streak line counts
the days in a row you finished a daily (it stays alive until a whole day is
missed) next to your longest, re-derived from the dates themselves.

A daily's config is `Profile.daily_config(seed)`, derived from the seed
alone over frozen lists in the profile, so today's challenge is the same
for everyone and a content table that grows later cannot move an earlier
date's run; the seed is `Profile.daily_seed_for(date)`, the one formula
(`tests/daily_run.gd` uses it too). Dailies ignore career unlocks entirely
and still score only to the daily board — no runs, records, unlocks or NEW
badges. The run remembers what it is: its run save carries `"kind"`, so a
resumed daily is filed as a daily, and R on the over sheet (or in a run)
replays the same kind and seed while N starts a career run on the next seed.
A finished daily's over sheet offers NEW RUN (a career run, never another
daily try), RETRY DAILY (another try) and MENU. BACK or the Back button closes
the sheet; ENTER plays (or resumes).

The status strip names the live run's config under the skies bar,
right-aligned after the countdown chips — loadout, then package, then
mutator (`Tidewarden · Aeolian · Brittle`) — read straight off the sim's
snapshot, so a run never hides what it was set up as. Run saves already carry the whole config in their header, so
none of this changes the save format.

## Legend

HELP opens the legend sheet; holding a tile shows the same row as a
tooltip. The rows are `shell/main.gd` `LEGEND` (sprite id, name, blurb) —
one row per drawable thing, and every `Content.TERRAIN` kind must have
one (`tests/test_shell.gd` checks it), as must every intent badge, every
blocked-intent glyph and the two SKIES countdown chips (four pages). The terrain rows:

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

`tests/test_draw.gd` is the only test that runs `_draw`: it hosts the shell
in a `SubViewport` at real phone and desktop sizes and renders frames of
every screen (menu, tutorial, a bot game with tooltips, lethal, the boss
floor, every sheet, help, game over), failing on any engine error, push_error
or script error an `OS` logger sees.

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
MUTATOR rows above are what a career spends its unlocks on, and each one
carries a NEW badge until the new thing is cycled onto. Unlocks are named by
`Profile.unlock_name` (never a raw id), and after a career run the profile
works out the next goal (`Profile.next_goals`: "Land 30 Grow Spikes · 17/30",
with what this run added). The win
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

The game-over sheet names the first resonance the run lit as a highlight chip
(`Cinder Grip lit on floor 3`), and the intro card says the rule in one line.

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
