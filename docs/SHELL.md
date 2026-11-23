# TENDER — the human shell

## Menu, settings, tutorial

The shell boots to a main menu: RESUME (when a run is live), PLAY (a fresh
career run), DAILY and CAREER sharing a line (see *Daily challenge* and
*Career sheet*), the run-setup rows (see *Setting up a run*), and TUTORIAL /
SETTINGS / QUIT sharing the last line.
Settings persist to `user://tender.cfg`: hold-to-inspect delay, intro-card
frequency, the sound toggles, vibration (see *Vibration*), animation speed
(full / quick / off, see *Animations*) and the camera's zoom (see *The
camera*), alongside the run choices the title screen makes (difficulty,
loadout, package, mutator). (The old "Run seed" toggle is gone: PLAY is
always a career run and the daily has its own entry. A cfg that still says
daily keeps that key only until the next run starts — it files a run saved
before the change — and the menu says once that the daily now has its own
button.) The sheet also prints where
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

## Text, briefly

The owner's ask: no walls of text, and a warm solarpunk voice. The rules
that keep it that way:

- **Say it where it is met.** The intro card is two lines of why and six
  rules with the thing each is about drawn beside it (`INTRO_STORY`,
  `INTRO_RULES` in `shell/main.gd`) - it used to be 18 rules at whatever size
  each could be squeezed to. Everything else is one hold away from the thing
  it explains: hold the health, charge or bloom readout, the skies bar, the
  green count, the elements strip, the camera or lens button
  (`_info_lines`), or any tile, card, ability or satchel slot.
- **Two lines, one size.** A guide step is at most two lines, drawn at one
  size (per-line shrinking read as two voices); the tutorial's last card is
  three. A legend blurb is one unshrunk line.
- **One line of news.** The log no longer fills the space under the map (the
  camera uses it): the context line carries the step's one notable event -
  a room blooming, a vent sealed, a drag, a drained charge, the graft or
  resonance that fired - for a couple of seconds (`TOAST_EVENTS`, plus the
  landed hook behind `COMBO_TOAST`), on the beat the animation reaches it,
  and the full log is a tap on that line. Damage and deaths are left to the
  animations, which already show every number. Danger that cannot wait - a
  blow coming at you, the smog stinging next turn - still outranks it (see
  *Danger readouts*).
- **The voice.** Machines are *scrapped*, never killed; a lost run *wilts*
  ("felled by a Drill Bot · Every sprout gets another spring"); the forge
  *recycles* the ability it scraps; refusals say what to do next ("out of
  charge - END refills it", "your kit is full", "not enough bloom yet",
  "Solar Lance needs 2 charge - END refills it") instead of listing every
  possible reason.

`tests/test_shell.gd` `_check_tutorial_text`, `_check_intro_text` and
`_check_legend_text` hold these on every phone shape the card gate sweeps.
`tests/capture_screens.gd` renders every one of these screens from the real
shell, for eyes:

```
SCREENS=intro,tutorial SCREENS_OUT=/tmp/screens \
  xvfb-run -a -s "-screen 0 540x1200x24" godot --rendering-driver opengl3 \
  --path . --resolution 540x1200 --script tests/capture_screens.gd
```

(`SCREENS=all|menu,intro,tutorial,play,tooltip,camera,shop,draft,legend,log,won,died`,
`SCREENS_SEED`, `SCREENS_STEPS`.)

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
| H | open the shrine sheet (standing on a stocked shrine) |
| H / B (shop sheet open) | buy heal / ability |
| G / J (shop sheet open) | buy the first / second graft on offer |
| R (shop sheet open) | reroll the shrine counter (Spinning Shrine mutator only) — outside the sheet R still restarts the seed |
| 1–5 / 0 (draft sheet) | take that offer / skip the draft — a skip arms one extra affinity offer on the next descent |
| SPACE / ENTER | end turn |
| Z | peek at the whole floor (until your next action) |
| + / - , mouse wheel | zoom the camera in / out (saved) |
| drag on the map | look around (until your next action) |
| L | the legend (HELP) |
| I | inspect: while on, hovering or sliding over the map shows its tooltips instantly |
| ESC | back: close a sheet, cancel an aim, end a peek, or leave the run for the menu (see *The Back button*) |
| R | restart the same seed, as the same kind of run (a daily's R is another try; in the tutorial: restart the tutorial) |
| N | a new career run on the next seed (ignored in the tutorial) |

At the end of a run a key while the killing step still plays only finishes
it, and every key but ESC is then ignored until the game-over sheet has been
up for a moment (see *The end of a run*); then R retries the seed and N
starts a career run on the next one, as in play (after a tutorial death R
retries the tutorial and N does nothing).

Red-tinted tiles are telegraphed damage for the coming enemy turn (attack,
slam cross, quake ring), read straight from the sim's own `Game.telegraph()`
— and while a step plays, the red tiles are the ones being carried out (see
*Animations*) — the intent-visibility pillar, drawn. Each red tile carries
the damage it will take in its bottom-right corner (summed over every
attacker aiming at it; not on your own tile, where the context line speaks
for it). Every enemy wears an intent badge at its top-right corner: a glyph
on a dark disc ringed in the intent's colour (red: a hit, violet: drain /
tar / grapple / advance, amber: a countdown, orange: a world change), with
its number beside it — damage, the countdown, the steps, the drag count when
above 1. A ring at half strength is an intent not aimed at you where you
stand. A BLOCKED intent wears its block glyph instead (stars stunned, roots
rooted, a slashed cloud lost in the smoke, an anchor when your roots hold the
grapple) and paints no red tile — a stunned striker used to paint a false
one. With animations on, the status itself also loops over the machine
(stun stars, binding roots); with them off the glyph is the only cue. A
grapple draws a dashed blue tether from the crane to you with a ring on the
tile it will land you on (grey and ringless when blocked); a flood stripes
the row it will oil, an ignite-all pulses every oil tile that will catch, a
dredge tints the growth it will eat. Vents count down on the grate from 5
turns out, with a red pulsing ring at 1 (green on a vent your growth has
sealed, grey and ringless on one that Roots, a machine or you cover - it
releases nothing while covered, the same rule as the vent chip and the
vent's hold-tooltip). A tar shot outlines the ability slot it will gum, in
dashed brown. The legend (HELP) has a row for every badge. Holding an enemy
names its exact intent; the context line is also the event log's button
(the list mark at its end). Elites wear a gold ring, bosses show HP bars,
and your buffs are drawn on the tender itself (shield plates, a thorn crown,
anchoring roots).

Holding an enemy adds an `avoids fire when it can` line when its
`Content.ENEMIES` row carries an avoid list — it paths around those tiles
unless the way round is far. When smoke swallows a telegraphed drain / gum / drag, the log says so
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
  is the soonest it can come if nothing is relieved — a kill or a stun can only
  push it later, but a cleanse (or a clear-air pod) winds the smog back, and
  the counter then passes a vent release or a dim step a second time, so relief
  can bring one SOONER. Every number is recomputed after each action.
- **The context line** (above the D-pad; the whole line is the event log's
  button, the list mark at its end says so) is ONE priority chain,
  `shell/main.gd` `_context_msg`: what a mode asks of you first (aiming,
  cleansing, the forge's steps), then a flash (a refusal, the lethal guard's
  reason in red), then danger that cannot wait: `Incoming 3 - LETHAL  ·
  Drill Bot, smog` in pulsing red when ending the turn where you stand would
  kill you, `Incoming 2  ·  Drill Bot` in amber when it would hurt,
  `Incoming 2 - your shield holds` when your shield takes it all, and the
  pulsing `Smog stings NEXT TURN - ...`. Then the step's one piece of news
  (the toast, see *Text, briefly*: a room blooming, a vent sealed, the graft
  or resonance that fired) for a couple of seconds; then the rest of the
  danger line - the choke countdown (`Smog stings in 3 - cleansing thins
  it`, or `- descend to escape it` once the stairs are awake; on the boss
  floor, whose cleanses stop thinning the smog after four, `- cleanse it all
  to thin it` until the floor is restored and `- cleanses no longer thin it`
  after) and `Machines climb out next turn`; and last the floor's objective
  line (`Cleanse 4 more to wake the stairs`, `The stairs are awake - head
  down when ready`, `Defeat the boss to cool the Furnace`, with a career
  hint beside it on a career run - see *Career and difficulty*). The tutorial
  shows no danger line (the guide teaches the red tile) and no objective,
  only the toast. The forecast is the real end turn played out on a copy, so
  the number is exact; it is the turn to come, so while a step still plays
  out the line can already speak for the next one.
- **Lethal colours.** When the end turn would kill you, your outline pulses
  red (amber when something lands but you live), the HP chip and the screen
  edges go red, and END / END TURN get a red border. A satchel item that
  would save you pulses gold. The HP chip, the red edges and their pulse
  share one rule (`Danger.hp_state`): red at 3 HP or less (or a quarter of
  max HP, when that is more), or when the coming end turn kills - judged on
  the HP the chip SHOWS (`_hp_state_shown`), which holds until the reel lands
  the blow, and while the reel plays the "end turn kills" half is the
  verdict from before the step, so the edges never go red before the hit
  does. The outline, END's border and the gold item glow read that SAME
  verdict (`_verdict_danger`): while an enemy turn's reel plays they show
  the turn you ended, not the next one, so a survivable turn whose aftermath
  is lethal turns all of them red together when its reel ends - never an
  outline and END red beside a calm chip (only the Incoming line may already
  speak for the next turn). A player action's reel reads the live forecast
  everywhere. When the run ends the chip keeps the low-HP red on the HP it
  shows, through the killing blow and the wilt. On a death in the enemy
  turn, every danger readout - the chip, the red edges, your outline, END's
  border, the item glow, the SKIES chips and the Incoming line - keeps the
  board you ended the turn on until the killing blow lands (`_death_held`):
  a finished game has no forecast, and calm readouts between the tap and the
  blow would read as a reprieve.
- **Sounds and banners.** A double warning tick plays when the lethal
  forecast switches on and when the choke enters its last 5 turns; at 1 turn
  the banner THE SMOG THICKENS / it stings from next turn. Each fires once per
  new low on the floor: a cleanse that pushes the choke back, and the turns
  that bring it down again, do not replay them. A banner still waiting in the
  queue when you open the menu is dropped on RESUME once its beat is older
  than a banner's life (`_drop_stale_banners`) - never shown a minute late.
- **Tooltips.** Holding an enemy adds why its intent will not land (stunned,
  rooted, lost in the smoke, your anchor holds) and for a smokestack how many
  turns sooner it brings the choke (on its idle turns too; with two or more
  alive, "stokers bring the choke N turns sooner", since that is their total;
  when without them the choke would not come inside the 60-turn look-ahead
  at all, "brings the choke in N turns - none for 60+ without it"); holding yourself reads `ending here: 3
  incoming - LETHAL`; holding a vent names what it will release next and
  when — `releases a Rust Hound in 4 turns`, `releases a Drill Bot next turn`
  (each floor has its own reinforcement list and each vent takes its own turn
  through it, so two vents on one floor can release different machines; the
  shell asks the sim, through the smog forecast's wave and
  `Game.reinforce_kind`; with no wave inside the 60-turn look-ahead the
  vent shows no release line at all) — or `sealed - absorbs the next
  release` under growth, or `vent beneath - releases nothing while covered`
  under Roots (the sim releases nothing from a vent that a blocking tile, a
  machine or you are standing on, so the line names no machine; it follows
  the sim's own rule through `Danger.vent_state`).

## Touch controls (Android / any touchscreen)

Portrait layout: status on top, the map, the ability bar and the context
line in the middle, D-pad and action buttons at the bottom. Everything is
tappable — no keyboard needed:

- D-pad arrows: move (into an enemy = strike); center END button ends turn
- tap an adjacent tile: same as a D-pad press; tap your own tile: end turn
- a D-pad (or arrow-key) press or cleanse tap that ran out of charge, or a
  tap on yourself, asks for a second press when the forecast says that end
  turn would kill you: the line above the D-pad says `LETHAL (3) - step off,
  or tap again to end turn` (or `strike first` when only hitting the
  attacker saves you, or names the glowing satchel item, or the stairs; a
  blow that wins the run outright comes first of all: `strike to win` when
  that blow is the only strike you could make, `strike the Overseer to win`
  when another machine stands beside you too (the line names no direction,
  so it names the target), `the glowing item wins` with only
  the winning item glowing) and a second press within 1.5 s goes through. END TURN, the
  D-pad's END, SPACE and ENTER never ask — pressing END is a decision
- **hold your finger on any tile**: tooltip naming what's there, its HP,
  and exactly what it will do next turn. Holding a HUD readout (health,
  charge, bloom, the skies bar, the green count, the elements strip) or a
  button explains it
- **pinch** the map to zoom, **drag** it to look around; the camera button
  (top-left of the D-pad) peeks at the whole floor. A peek or a look ends on
  your next move (see *The camera*)
- tap a kit line to cast — aim with the D-pad / adjacent tap for
  directional abilities, or tap a highlighted tile for tile abilities
- **an armed aim previews its result**: damage, kills and statuses are
  labelled on the map before you commit (see "The aim preview")
- **cancelling an aim is free**: tap the same kit line again, press any
  D-pad arrow, or press Back. None of them move you, strike anything, or
  cost a turn, and the aim line on screen says so
- the right-hand column: DESCEND on awake stairs (or SHRINE SHOP on a
  stocked shrine), CLEANSE and END TURN; HELP (`?`) and the menu (`=`) sit
  at the right of the status strip
- tap shop cards at a shrine, draft options between floors
- after a run: the killing step plays out and the map holds for a beat (a
  tap during the wilt only finishes it), then the game-over sheet fades in
  with its buttons - NEW RUN, RETRY SEED (RETRY DAILY on a daily), MENU.
  Nothing else on the sheet starts a run: a stray tap does nothing. Tap the
  unlock rows to page through everything the run unlocked

## Feedback: callouts, kills, log and sound

`shell/feedback.gd` turns each step's events into what you read and hear; it
reads the event stream and never invents an outcome. What you SEE on the map
is the step animation (see *Animations*): the reel draws every number, the
status pops, the gold rider sparks, the surge, the hook's spark, the flares
and the small words it owns ("blocked", "+2 bloom", "resisted"). Two sources
of numbers would show each one twice, so the shell paints none of its own.

**Callouts** are DATA: `Feedback.callouts` names every payoff a step
resolved, deduped and sorted by priority. The combo chime (below) reads the
list; the log does not - `Feedback.callouts` and `Feedback.log_entries` both
build on the one claim table `Feedback.claims()` (which hook or then-rider
explains which event), so the log follows the claims, not the callout cap:

| callout | when |
|---|---|
| `CINDER GRIP`, `COMPOST`, `EMBER SAP`, `UNDERTOW` | a hook that actually landed |
| `GROWTH +1 dmg`, `CROWD +2 dmg` | a `per` rider |
| `BURNING +1 dmg` | a `bonus` rider |
| `ROOTED!` / `STUNNED!` | a `then` rider's status (`COMBO` if it claimed none) |
| `SURGE +1 dmg` / `+1 push` / `+1 reach` | a verdant surge (first stat) |
| `COLLISION` | a slam into a wall or a body |
| `SHIELDED` | a hit on a shielded boss core |
| `DOUBLE KILL`, `TRIPLE KILL`, `N KILLS` | kills in one player turn |
| `ROOM CLEAR` | the last machine in your room fell |
| `STREAK N` | first kill of the Nth turn running |
| `BOUNTY +4`, `BLOCKED N`, `IGNITE`, `TITHE -1`, `VERDANT` | the rest |

**Three words on the map.** The multi-kill, ROOM CLEAR and STREAK N come
from the run's own fold (`meta/run_stats.gd`), which the reel cannot know,
so the shell adds exactly those three to the reel as ordinary float clips
(`Feedback.ctx_words` -> `_reel_word`): gold, green and orange, 160 ms after
the step's last death lands (ROOM CLEAR 320 ms), drawn, carried into the
next step and sped up or slowed down by the reel's own painter like any
other word. A word is about two tiles wide and lands after the number that
set it off, so it takes two rows over the highest float still rising on its
own tile or either neighbour in its row - never level with the kill number
of the machine struck from the next tile. With animations off they appear
at once.

**The graft that fired.** The reel's hook spark cannot say WHICH graft or
resonance fired, so the step's first hook that landed reaches the context
line as its toast ("Cinder Grip roots the Coal Golem"), on that hook's beat
(`Feedback.combo_line`, behind the one const `COMBO_TOAST`). A hook that
landed nothing says nothing. Riders and surges are never toasted - you just
cast that ability - and their amounts live in the log's violet lines.

**Kills.** The reel lands them: the strike's lunge and slash, the machine
tipping away, its debris and its ghost, the board's shake. A flame with a
number beside the tender is your kill streak (two or more turns running with
a kill); it dims while this turn's kill is still owed - end the turn without
one and it breaks. Like the ghost and the STREAK word, it moves when the reel
gets there: up on the kill's death beat, and broken once the enemy turn has
played out, never on the tap (`_streak_shown`).

**Boss.** A shielded core shows a pulsing cyan ring on the map and `SHIELDED`
in cyan on the boss bar before a hit is wasted, and the log says "Core
shielded - cleanse or grow beside it"; a phase change shows a banner saying
what changed (the Furnace Core's "a coal golem joins" only when a golem
really came: with every vent covered none does, and the banner says "now
ignites all oil" alone). The floor-7 title card reads "defeat the Overseer".

**Crews.** Every generated floor fields one of several named crews (Block E
encounter packs — the boss floor and the tutorial's scripted floor have
none). The floor's title card says which under its number, `floor 3 of 7  ·
Golem Picket` (shrunk to fit the width rather than clipped), and the floor
line in the log reads `— Strip Mine I · Hound and Handler —` - the floor a
run starts on included (its card waits for the intro card to close).

**Banners** share one queue (boss phase, the smog's warning, a resonance
awakening, floor restored, stairs awaken, career pings last); one shows at a
time, at most three wait, and each rises on the beat of the event that
earned it - FLOOR RESTORED after the scrub that restored the floor, not when
you tapped. A career ping is due on the step's last beat, so it rises after
everything the step itself announced, and it also waits out the floor's
title card.

**Log.** Names, never ids, in the shell's voice ("Cinder Grip roots the Coal
Golem", "A Coal Golem climbs out of a vent"; a reinforcement names the
machine the sim says came out — its event's kind, the boss's phase-2 golem
included — and a wave that releases different machines at different vents
reads one line per kind, "2 Rust Hounds climb out of the vents" beside "A
Drill Bot climbs out of a vent"); machines are scrapped and you wilt;
repeats count up ("Oil ignites x3"); each line is coloured by kind (hurt
red, rewards gold, heals green, combos violet, boss orange). A cleanse says
what it paid: "Cleansed +1 bloom · green 3/5", or "Cleansed - enemy-made oil
pays no bloom". The log is the sheet behind the context line's list mark
(and fills the slack under a floor shorter than the view).

**Sound.** At most three sounds a step, worst first (win/death, boss, hurt,
multi-kill, shielded, kill, ...), then a bell chime climbing a step for each
combo callout, with an octave on a room clear. Repeated sounds vary slightly
in pitch on a fixed cycle. Sounds fire when the step is taken, as the buzz
does (*Vibration*): one buzz a step.

All of this is tested as data (`tests/test_shell.gd` `_check_feedback`, and
`_check_reel_words`, `_check_toast` and `_check_banner_beats` for the beats),
and drawn for real, frame by frame, by `tests/test_draw.gd`.

## The aim preview

Arming an aim shows what each legal cast **would do, before the charge is
spent**. `shell/main.gd` `_preview_aim` steps every legal action of the armed
slot on a `clone()` of the sim and folds the cast's own events per enemy; the
map then draws a label over each result:

| aim | where the label sits | what it says |
| --- | --- | --- |
| direction (lance, jet, whip, rake) | on each **enemy** a direction reaches | `-3`, `KILL`, `-2 rooted` |
| tile (bombs, flares, snares) | on each **target tile** | the total it deals from there, or `KILL x2` |

It is exact, not an estimate - riders, surges, collisions and hooks all run
on the copy - and it reveals nothing the player could not work out, because
a cast draws no rng and never resolves the turn. A direction that reaches
nobody, or a tile that deals nothing (a seed bomb), carries no label.
`tests/test_shell.gd` `_check_aim_preview` holds it to the truth: the label
must equal what the cast then deals, a lethal cast must read `KILL`, and
arming an aim must leave the live game's `state_hash()` untouched.

## Vibration

On a phone a step buzzes (`Input.vibrate_handheld`, the `VIBRATE` permission
in `export_presets.cfg`): ONE vibration per step - the strongest any of its
events asks for - from a 20 ms combo tick, through a kill or a wall-slam, to
250 ms for the tender's death (`shell/main.gd` `_buzz_events`, called once
from `_feedback` on a run and in the tutorial alike; a chained second step
keeps a stronger first buzz). It fires when the step is taken, not on each
beat of the animation. **Settings -> Vibration** turns it off.
`tests/test_shell.gd` `_check_haptics` and `_check_haptics_paths` hold both
paths to one buzz.

## Why CLEANSE refused

`CLEANSE` reaches a tile **beside** you, and only corruption. Its refusal
used to be "no corruption beside you" in every case (it now says "nothing to
cleanse beside you" when that is the truth), which is a lie in the
two that actually happen — and both read as a dead end, because a player
standing next to the thing the game just told them to clean is out of ideas.
`shell/main.gd` `_cleanse_hint` names the real reason:

| what is true | what it says |
| --- | --- |
| you are standing on the slick | `you're standing on it - step off first` |
| the slick is on fire | `still burning - wait for the ash` |
| nothing corrupt within reach | `nothing to cleanse beside you` |

Fire is not corruption; ash is. `tests/test_shell.gd` `_check_cleanse_hint`
drives all three and then checks that the ash the second one promises really
does open the aim.

## The end of a run

A run never ends on a cut. When the tender dies (or the Furnace falls) the
killing step's animation plays out on the map - the tender wilts, the boss
tips away - and around it the end BEAT: the map tints smog-brown on a death
or washes gold on a win (where three gold bursts land on the boss's last
tile, as reel clips on its death's beat), the controls dim behind a veil,
and a banner names the moment in two lines - `YOU WILTED` in rose over what
ended it (`felled by a Drill Bot`, `lost in the smog`, `caught in the fire`,
`stuck in the goo`, `worn down by a Welded Hulk's spikes`, `caught by your
own Ember Sap`), or `THE FURNACE IS COLD` over `the valley breathes again`.
The follow camera keeps the tender in the middle of the map, so the banner
steps just below (or above) the tender's tile rather than covering the wilt.
The beat lasts 1.2 s (`OVER_BEAT_MS`) and is shifted so it never starts
before the killing blow lands (at Animations "quick" too) and never ends
before the death reel does (`_begin_over`); a tap or key while the reel still
plays only finishes the reel (the reel's own skip rule), and a beat that had not begun yet
starts at that tap, while one already under way runs on. A wilted tender
stays gone once its reel has ended (`_tender_pose`), through the rest of the
beat and the fade. Then the sheet fades in over 0.4 s (`OVER_FADE_MS`),
over the beat's tint and veil, so the dimmed controls never flash back.
Taps and keys are ignored until 1.9 s after the beat began (`OVER_LOCK_MS`,
0.3 s after the sheet is opaque), so a finger still hammering the D-pad
cannot skip the death or start a run by accident; while locked the buttons
draw dim. Back and ESC are never locked - they go straight to the menu, and
the run is already recorded. A game that ended some other way (a resumed
save, a test that sets it over) goes straight to the sheet, unlocked.

There is no "tap anywhere for a new run": a run starts only from the sheet's
buttons - NEW RUN (a career run on a new seed), RETRY SEED (RETRY DAILY on a
daily) and MENU; TUTORIAL AGAIN and MENU after a tutorial death - so a stray
tap never throws a result away, and every run start goes through the same
path the menu uses.

The sheet, top to bottom (`shell/main.gd` `_over_layout`, words from
`shell/run_end.gd`):

| row | example |
|---|---|
| title | `YOU WILTED` in rose, over a drooping sprout / `THE FURNACE IS COLD` under a clear sun |
| cause | `felled by a Drill Bot · Pipeworks`, `The Furnace Core is scrap · the valley breathes again` |
| spring | `Every sprout gets another spring.` (a death only, the tutorial's included) |
| near miss | `The Dredge had 3 HP left`, `the stairs were 4 steps away`, `2 cleanses short of waking the stairs`, `one floor short of your best (floor 6)`, `1 more HP would have saved you` (only when true: the shell replays the killing step on a copy with one more HP, since a blow at exactly 0 HP can hide a second one still due); on a win `closest call: 1 HP on Furnace Approach` (the lowest HP inside a turn, so a hit to 1 that growth heals back to 2 counts) |
| stats | `floor 5 of 7 · 63 turns · 24 kills · 41 bloom earned` - the run's total turns, not the floor's |
| kit | each ability's icon with its effective casts (`x12`), a gold `+` on an upgrade |
| grafts | `grafts  Compost · Ember Sap` |
| chips | up to three highlights: a floor restored, a resonance lit, a record beaten (`record · most machines felled 41 (was 30)`), a multi-kill, the biggest hit (`biggest hit 6 · Solar Lance fire`), a streak, rooms bloomed... |
| score | `SCORE 1234` |
| best | `NEW BEST · was 1100`, `NEW BEST FOR TIDEWARDEN · was 900`, `best 1449 · this run 85%`, `your first score · beat it next run`; on a daily `RANKED · your first finish today`, `NEW DAILY BEST · was floor 3`, `today's best: floor 4 · 3 tries` |
| floor best | `YOUR FIRST WIN`, `DEEPEST YET · floor 5 (was 3)` |
| score parts | every non-zero part (`floor 500 · kills 120 · bloom 82`), then `x1.5 difficulty 2` |
| unlocks | `NEW DIFFICULTY · Thicker Smog`, `UNLOCKED · Hydraulics package`, `UNLOCKED · Skyrunner loadout (needs Aeolian)`, `UNLOCKED · Slick Combine mutator`, then the run's new feats (`FEAT · Green Thumb`), then `+2 more · tap for all` - the rows are one tap target that opens the unlock pager |
| next | `NEXT · Land 30 Grow Spikes · 17/30 (+9 this run) · unlocks Wide Draft` (numbers only when the goal needs more than one); once every goal is owned, the nearest feat: `NEXT · Fell 250 machines across your career · 180/250 (+31 this run) · feat Scrap Heap` |
| seed | `seed 123456 · Tender · Mycology`, plus `difficulty 2` and `daily` |

Every "was" on the sheet is the career's best from BEFORE the run
(`profile.bests_snapshot`, taken before the run is recorded). A daily shows
no unlock rows and no NEXT; a tutorial death shows no score, best, unlocks,
goal or seed and offers TUTORIAL AGAIN / MENU. When a phone is too short for
every row, the least important present row is dropped first (the spring
line, then the seed line, then the third chip, then the score parts...), and the title, cause, score
and best never go; when that takes an unlock row, the last one kept becomes
`+n more · tap for all` with the number really hidden; `tests/test_shell.gd` `_check_over_text` holds every row
to the card text floor at every phone shape.

**The unlock pager.** Once the sheet is live, tapping its unlock rows (they
draw a thin gold frame) opens NEW THIS RUN: every unlock and feat the run
earned as a card, five to a page, the difficulty first. Each card names the
thing in words with its kind on the badge (TIER 1, LOADOUT, PACKAGE,
MUTATOR, FEAT) and says where to find it (`pick it under LOADOUT`); a
loadout still waiting on its package reads `Skyrunner (needs Aeolian)` with
what opens the package, and a package that makes an owned loadout playable
ends `opens Skyrunner`. `<` / `>` page it (LEFT / RIGHT on a keyboard) with
`2 / 3` above the row; DONE, ENTER or Back return to the sheet, and only the
next Back leaves for the menu. The pager takes only its own buttons - a tap
anywhere else, or R / N, does nothing, so it can never throw the result away.

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
| the settings, DAILY or CAREER sheet on the menu | closes it, back to the menu |
| the forge's keep / scrap / fork step | one step back, ending on the shrine sheet |
| the draft's drop sheet | back to the offer cards, nothing dropped |
| the unlock pager (NEW THIS RUN) | back to the game-over sheet |
| aiming an ability | cancels the aim — free, no turn, no strike |
| a whole-floor peek, or a look-around (drag) | back to the tender |
| normal play, the descent draft, the end-of-run beat and the game-over sheet, the tutorial | the menu |
| the menu | quits (the root; `ESC` here does nothing) |

Leaving a live run for the menu costs nothing: every action is already on
disk and RESUME replays it byte-exact (*Run persistence* below).

## The camera

There is ONE view, and it is never a mode to toggle. There used to be two -
the whole floor, and a crop of the current room behind the camera button -
and play was a steady back-and-forth between them: the floor view's tiles
were too small to read or tap, the room crop lost the stairs and the next
room, and every switch was a jump in scale.

- **It follows.** The camera frames the room you stand in (its walls and
  doorways included) when the room fits, else it centres on you, and it
  **glides** there (`CAM_GLIDE_MS`) instead of jumping. It never shows past
  the floor's edge; a floor shorter than the view sits at the top so the
  slack under it still shows the log.
- **Zoom is yours.** Pinch (or the mouse wheel, or `+`/`-`) anywhere from
  close - seven tiles across - out to the whole floor, or step through
  SETTINGS → Camera (near / normal / far / whole floor). The choice is saved
  (`cam_cols` in `tender.cfg`), so a player who liked the old whole-floor view
  picks it once and keeps it.
- **Looking is free.** Drag the map to look around; tap the camera button
  (or `Z`) to **peek** at the whole floor. Both end on your next action, and
  on Back - so a look never has to be switched back off.
- **It helps you aim.** A tile ability's aim frames every tile it can land
  on, zooming out as far as the whole floor if it must.
- **Off screen is not out of mind.** The stairs, a stocked shrine, the
  nearest corruption (while the floor still needs greening and none is in
  view) and the machines near you get a marker on the view's edge pointing
  at them. Markers never take a tap; the tile under one still answers.

The rules live in `shell/main.gd` `_cam_target` - a pure read of the shell's
state, so `tests/test_shell.gd` `_check_camera` asks it directly over real
optimizer play on four seeds: the tender is on screen at every step, the view
never passes the floor's edge, and every room that fits is framed whole.
`_check_camera_gestures` drives pinch, drag and wheel through the real input
handler, the way Android delivers them (touch 0 also arrives as an emulated
mouse press), and asserts the release of a pinch or a drag is never read as a
tap. Map sprites are rasterised at `_raster` and drawn scaled to the live
tile size: exact at rest, a fixed ladder of sizes during a pinch, so zooming
never rasterises (and caches) every size in between.

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
then reads TAP AGAIN: ABANDON TODAY'S TRY on the first tap, because a career
start overwrites the one run save and the try is already counted (an older
unfinished daily — yesterday's, or a save from before the daily had its own
button — reads TAP AGAIN: ABANDON YOUR DAILY TRY: it is not today's); any other
tap, on a button or not, and Back / ESC disarm it. Every start
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
blocked-intent glyph and the two SKIES countdown chips: 50 rows on four
pages, each blurb one line drawn unshrunk (`_check_legend_text`). The table
below says what each terrain kind is; the sheet's own blurbs are shorter
("stand on it to heal 1 a turn"). The terrain rows:

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
tools/setup_android_export.sh   # once per fresh container, about a minute
mkdir -p build
godot --headless --path . --export-debug "Android" build/tender.apk
```

`tools/setup_android_export.sh` does everything the two sections below
describe - the range-fetched debug template, an SDK-shaped directory, a debug
keystore and the editor settings - and signs with **Ubuntu's own `apksigner`
package** (`apt-get install apksigner`, 31.0.2), which is the real tool and
needs no shim. The keystore is generated per container, so an APK built in
one session will not install over one built in another: uninstall first.

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

**Superseded by the apt package above** - kept as the fallback if the distro
ever drops it. Signing went through an `apksigner` shim over patrickfav/uber-apk-signer.
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
reading happens — a shrine deals up to eight offers at once (seven without
the Spinning Shrine's reroll card):

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
in a `SubViewport` at real phone and desktop sizes (four named shapes plus
every card-gate viewport) with animations at full, so the step reel paints
under the gate on every step, and renders frames of every screen: the menu,
settings, the career menu and the DAILY and CAREER sheets, the tutorial, a
bot game with tooltips on everything the camera shows and a whole-floor
peek every 25 actions, lethal, an enemy turn frozen mid-reel (the held
telegraph), a chained out-of-charge move, the reel at quick and off, two
kills in one turn (ghosts, the DOUBLE KILL word, the streak flame), a kill's
flame still on the held count before its death beat, the camera's peek and
edge markers, armed aims with their preview labels, a toast, the boss floor,
every sheet, help, the death reel playing under the end beat, a first win's
beat with its bursts, the over sheet and the unlock pager. A phase that needs one exact frame of an animation pins the
shell's clock (`clock_override`) for its frames. Its reel checks read what
`_draw_map` actually handed the painter (`_reel_draws`, the clip kinds,
layers and words live on those frames - recorded by `_paint_reel`, the one
call that paints a layer, which hands the painter a recording visibility
test: a clip with a tile is recorded only once the painter itself asked
about that tile, so a pass or a painter that stops painting stops being
recorded; a tileless clip such as a beam is recorded by the mirror beside
it - `_flame_draws`, and `_tele_drawn`, the red tiles of the telegraph
view a frame used - the held one mid-reel - with the tile numbers, tethers
and badges it drew from that view and the HP verdicts the chip and the
vignette drew), never the shell's reel state; the death reel's phase reads
the tender's tile the beat's lines stepped off and the lines it drew, the
phases after the wilt that the tender was not drawn (`_tender_drawn`), the
killing-blow phase the chip, edges, outline, END border, item glow, SKIES
chips and context line it drew, the survived-enemy-turn phase the chip,
edges, outline and END border it drew mid-reel (the turn ended, not the
next), the held flame's count, and the win's beat the gold bursts it
painted and, after its reel, the winner it still drew. It fails on any engine error, push_error or script error
an `OS` logger sees.

## Animations

Every step is animated, and none of it is a rule. The sim resolves a
`step()` instantly; `shell/anim.gd` (the **director**) turns what that step
did into a short **reel** the shell plays back, from four things only: the
snapshot before, the action, the step's events and the snapshot after. It is
pure data — it never touches the Game object, the clock or the scene tree,
never mutates its inputs, and the same inputs always plan the same reel — so
the sim stays unaware that anything animates, and every reel ends exactly on
the board the post snapshot holds (a backstop walks any creature whose last
drawn tile is not its post tile onto it).

A reel is `{clips, tracks, ghosts, spawns, shakes, tswap, hp, ev_t, dim,
bloomed, hud, len}`, every time an integer ms from the step:

| part | what it is |
|---|---|
| clips | painted effects `{kind, t0, dur, span, layer, pal, at, ...}` in tile space: a beam, a cloud, a number. `span` is the clip's length at full speed (stamped by `anim_lib.clip`); painters read time as `k * span`, so a clip draws the same thing at every speed. `read: true` marks a word that keeps its reading time (quick) and survives `off` |
| tracks | per creature (`"player"` or an enemy id) motion segments — `path` (slide or hop along points), `lunge`, `recoil`, `cast`, `squash`, `struggle`, `shake`, `tint` (with `hold`: the hurt red laid over the body, then snapped back), `flash`, `die` (style `wilt` for the tender), `pop`, `hide` (the body is drawn by a clip instead, as a teleport's sink and rise are); `Anim.pose()` folds them into where and how to draw it at time t |
| ghosts | enemies that left the board, drawn where they fell until their death plays out |
| spawns | enemies that joined it, hidden until they pop in |
| shakes | `{t0, mag}` screen shakes (strongest wins, 320 ms decay) |
| tswap | tiles whose terrain changed: they show the old kind until the verb reaches them (a seed bomb's growth appears ring by ring, a slick burns as the lance passes) |
| hp | HP changes by time, so a bar (and the HP chip) drops when the blow lands, not when you tapped |
| ev_t | when each of the step's events lands; the shell holds every banner, the context line's toast and its own three words (*Feedback*) until theirs |
| dim, bloomed, hud | the haze stage, the bloomed rooms and the shield / bloom / max-HP chips, each changing on the beat that changes it (a moss filter parts the haze as its beam lands; a room dresses when its bloom lands) |
| len | the reel's length |

**How a step becomes a reel.** One planner per action kind. A move is a hop;
a strike a lunge and a slash; a cleanse a scrub; an item pops out of the
satchel. An **ability** winds up in its element's colour (palette = the
first of its tags in `anim_lib.ELEMENT_ORDER`), then each effect is built by
the **verb family** that owns its op — `shell/fx_lines.gd` (lance, pulls,
jets, gusts, dash), `shell/fx_areas.gd` (novas, clouds, tide, shock,
whirlwind, conversion, seed bombs), `shell/fx_self.gd` (lobbed terrain,
root walls, sap globs, spikes, teleports, bark, thorns, anchors, sunbeams) —
and the next effect starts when the previous one's motion ends. Builders read
data, never ids: a variant with a bigger number looks bigger, `pierce`
punches through, `center: target` is thrown first, `kind: roots` rewrites in
bark, a `growth` teleport travels through the mycelium where a `tile` one
digs.

`end_turn` gives every enemy that ACTS a **slot** — one with a non-idle
telegraph, an event of its own, or a changed tile — in the sim's own
execution order (`shell/fx_enemy.gd` draws each intent: bites, slams,
quakes, floods, chains, siphons, tar globs, portals, welds...). The event
stream is attributed to slots over the pre-step enemy list with a monotone
cursor, and each machine is credited ONE blow a phase: a pack of one kind is
credited bite by bite, a blow the shield soaked goes with the damage after
it, and what a haul drops the tender onto (goo, fire, a supply) stays with
the machine hauling. `fx_enemy` then spaces impacts a beat (`BEAT_MS`)
apart, holds verbs aimed at the tender until a crane's haul lands (capped by
`BEAT_LATEST` / `HAUL_LATEST`), and draws nothing for a machine that was
gone before its turn (welded into a partner, killed earlier). The
environment phase (hazard ticks, the smog clock, vents, regen) plays last.
A machine's walking gait follows its idle style (`fx_enemy.GAIT_BY_IDLE`).

A generic pass turns every event into its standard feedback at the moment it
was given — damage numbers, a white hit flash and recoil away from the blow,
deaths, spawns, status pops, screen shake. An event no builder claimed that
follows from the one before it (a death, a status a hook landed, a bounty)
lands right after its cause. Numbers and words that land on one tile
together take separate rows, and paint after every other clip, so no puff
covers the number it explains. The shell adds only what the director cannot
know: the multi-kill, ROOM CLEAR and STREAK N words, appended as ordinary
float clips on the step's last death beat (`_reel_word`), and a win's three
gold bursts on the boss's death beat (`_begin_over`).

**Playback.** `shell/main.gd` snapshots before and after each `_act`, plans
the reel and plays it from `_reel_ms`; the map only ever draws poses from a
reel that is still playing, and a new game starts with none. Input is never
blocked: a new action simply starts a new reel, and nothing the old one was
still doing snaps (`Anim.carry`): numbers still in the air keep flying, and
every machine the new step leaves alone finishes its walk, its death or its
pop-in on the beat it had. A machine the new step touches (hits, pushes,
statuses), or one walking through the tender's new path, glides the rest of
its walk in at most 140 ms before the new step reaches it, and snaps only
when there is less than 40 ms to spare. Only MOTION carries: a lunge, a flash
or a beam aimed at the tile the tender just left would read as aimed at
nothing, so those end, and the old reel's terrain flips, bars, chips and haze
show their end state at once. The tender's own old track ends too — the new
step is the tender's — except the second step of ONE input (an out-of-charge tap ends
the turn, then moves, strikes or cleanses), whose reel is chained INTO the
enemy turn's (`Anim.chain`). The chain is per track, not per reel:
`Anim.chain_offset` starts the second step as soon as nothing it shares with
the enemy turn is still playing — the tender's own business (a blow landing
on it, a haul, a spike, and a word worn on its tile such as a shield's
"blocked", each until it lands), the whole track of any machine the step touches, a
machine walking through or falling on a tile the tender's path uses, a tile
both steps change, the haze when both change it — and never later than the
enemy turn's end. The rest of the enemy turn plays on around the tender, so
running out of charge mid-stride no longer freezes the tender while every
machine takes its turn. The tender's regen glow (a heal standing on growth)
is **soft**: it never holds the step back, and a soft glow that had not
started yet is moved onto the tender's new tile, after its hop. A descent has no reel —
the floor fade is its animation. The killing blow plays out inside the end
beat (*The end of a run*), which is shifted so it never starts before the
killing blow and never ends before the reel; a tap or key during the reel
finishes the reel instead of moving on, and a beat that had not begun yet
starts at that tap (one already under way runs on).

While a reel plays, nothing it changes shows early: the telegraphs on the
map - red tiles and their numbers, badges, tethers, the gum slot - are the
ones being carried out: the pre-step board minus attackers whose death or
stagger has landed - a death on its ghost's death beat, or with Animations
off (no ghosts, every beat at 0) at once (the gum slot is that board's own, never the slot the
live board has already re-rolled for next turn), read from the telegraph the sim gave BEFORE the step
(`_threat_snap` marks the held board, `_tele_view` cuts `_reel_tele` down
to it through `Danger.tele_subset`), and the next turn's appear when the
reel ends; status and buff overlays keep their pre-step value until each
pop reaches its hand-off (`Paint.HANDOFF`), and a status spent during the
step is held by a `status_hold` clip until the moment it is spent; the HP
chip holds until the blow lands, and the red edges with it
(`_hp_state_shown`, whose "end turn kills" half is also the pre-step one,
`_verdict_danger`, until an enemy turn's reel ends - the outline, END's
border and the item glow with it; a player action's reel reads the live
forecast, so a step off a red tile is safe at once); the haze, the bloomed rooms, the HUD
chips, the banners, the toast and the shell's words wait for their events. (The
context line's danger line is the forecast for the turn to come, so it can
already speak for the next turn while the reel plays.)

Between steps creatures loop an **idle** chosen from their traits
(`anim_lib.IDLE_BY_TRAIT`: bosses heave, drones hover, hounds pant, sludges
ooze, emitters chug, igniters skitter, cranes sway, spitters gulp, spiked
machines lumber; anything else bobs), redrawn at about 20 fps like the smog
haze and the amber / red SKIES bar pulse of a near choke (`IDLE_FRAME_MS`;
only a low-HP or lethal pulse, a reel, a banner (shown or still queued), a
delayed sound still queued (the combo chime), the floor fade, a gliding
camera, the end-of-run screens or the title menu redraw every frame);
statuses loop over the enemies they hold (stun
stars, binding roots, drifting spores) and the tender wears its buffs
(shield plates, a thorn crown, anchoring roots). The hit flash, the hurt
wash and a cast's glow are the sprite's white silhouette
(`Paint.silhouette`: the SVG re-rasterised with its colours rewritten to
white, cached per sprite and size and prewarmed when the tile size changes)
drawn over it.

**The setting.** SETTINGS → Animations cycles **full** (the reel as
planned), **quick** (every motion at 0.55× length; numbers and words keep
their reading time) and **off** (no reel motion, no idle loops and no enemy
status overlays; the step's numbers and words appear at once — the tender's
buffs and the floor's ambient haze still draw). It is saved in
`user://tender.cfg` as `anim`.

**Tests.** `tests/test_anim.gd` (part of the suite) checks that every
effect op and every enemy intent type has a builder — a new op with no
animation fails it, the way the content lint fails an unknown op — that
every builder op is a real op and every clip kind has exactly one painter.
It plans a reel for every staged scene in `tests/anim_scenes.gd` (the
tender's own verbs, every `Content.ABILITIES` row, every intent and both
ways an intent fails, and the `x:` edge cases the reviews found bugs in —
packs, shields, fused partners, graft hooks mid-verb, hauls, rakes through
fire, thrown and surged areas): inputs untouched, deterministic, every
creature lands on its post tile, the dead vanish and the new appear, every
changed tile flips inside the reel, each ability op draws its verb, every
clip paints finite geometry through a recording canvas and paints the SAME
thing at quick speed, concurrent numbers on a tile take different rows, HP
holds until the blow, poses stay sane, and the reel fits its budget at every
speed while `off` keeps every number and word. It also checks the idle
loops' bounds, the one-blow-per-machine attribution (`x:pack`,
`x:shielded`, `x:haul_goo`), the holds (telegraphs, HUD chips, room
dressing, the cleanse float saying the gain), the shell's playback (a step
starts a reel that ends, numbers carry over, an out-of-charge move chains,
the chained step waits only for its own tracks - a free tender hops during
the enemy turn, a bitten one after the bite, and the regen glow follows it -
a step cut into another carries each machine's motion (a walking machine does
not snap, a machine the step hits glides in before the hit, one crossing the
tender's path is out of it before the tender sets off, a dying one keeps dying,
and the soak cuts every real step into the one before it at a quarter, half
and three quarters and checks everyone still lands and picks up where it was) -
a tap during the death reel does not start a new run, a new game has no
reel, a descent has none, the setting cycles and persists), runs a soak over
real optimizer and wanderer games (`ANIM_SOAK_SEEDS`, default 4), and fails
on ANY engine or script error raised while planning and painting (a
`Logger` counts them — a GDScript runtime error aborts only the function it
happens in, so without it a builder that died mid-reel would still pass).
Its shells keep their career, run save and settings on scratch paths, so a
run of it never touches the player's own files. `tests/test_draw.gd` then
renders the reel through the real `_draw` at every phone shape under the
same kind of gate (see *Screenshots without a display*).

### Watching the animations

`tests/capture_anim.gd` renders the **real** shell frame by frame and
composes each staged scene into a filmstrip PNG. It needs a display, so run
it under a virtual one with the GL renderer:

```
CAPTURE=ability:solar_lance,intent:slam CAPTURE_OUT=/tmp/strips \
  xvfb-run -a -s "-screen 0 540x1200x24" godot --rendering-driver opengl3 \
  --path . --resolution 540x1200 --script tests/capture_anim.gd
```

`CAPTURE=all|basic|abilities|intents|extras|<name>,<name>` (names:
`ability:<id>`, `intent:<type>`, `x:<edge case>` from `Scenes.EXTRA`, or a
basic scene — `move`, `strike`, `strike_spiked`, `kill`, `cleanse`, `item`,
`heal_item`, `surge`, `death`), `CAPTURE_OUT=<dir>` (default
`user://anim_frames`), `CAPTURE_FRAMES` (12), `CAPTURE_COLS` (4),
`CAPTURE_SCALE` (0.75), `CAPTURE_SPEED=full|quick|off`, `CAPTURE_BANNERS=1`
(keep the full-map banners, suppressed by default). Each frame is stamped
`<scene>  t=<ms>` and cropped to the visible map; a strip is named after its
scene with `:` → `_` and `+` → `-` (`ability:clear_air+` →
`ability_clear_air-.png`). The shell's animation clock is pinned per frame
(`clock_override`), so a strip is exact and repeatable.

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
with what this run added; once every goal is owned, the next feat stands in).
The game-over sheet lists newly unlocked tiers/packages/mutators and the feats
the run earned ("FEAT · Green Thumb"), and the menu footer shows runs / wins /
best floor / feats. The CAREER sheet (below) is where all of it can be read
back. Daily runs are scored but never counted
toward the career: a finished daily is filed as that seed's best result
(won, floor, turns) and unlocks nothing.

**In-run pings.** A career run knows, from the moment it starts, what it can
still earn, and says so as it happens with a gold banner (queued behind any
other banner, never on the step that ends the run): `FLOOR 3 · Tidewarden
unlocks when this run ends` on reaching a milestone floor (a first-ever run
too), `DEEPEST YET · floor 5 · Pipeworks` past your best floor (from your
second run on; on a milestone floor the two share one banner), and
`GROW SPIKE 30/30 · Spiker unlocks when this run ends` when this run's
effective casts complete a count. Each fires once a run, a resumed run never
repeats one it already showed, and the tutorial and the daily ping nothing.
The unlock is real either way - a death records the floor and the casts just
as a win does; only an abandoned run is never recorded.

**The objective line** is the context line's last arm, when no mode, flash,
danger line or toast holds it: the floor's goal (`Cleanse 3 more to wake the
stairs`, `The stairs are awake - head down when ready`, `Defeat the boss to
cool the Furnace`), then on a career run whose next floor is a milestone
floor not yet reached, the career hint - `The stairs are awake  ·  floor 5
unlocks Mycology`, the goal shortening to `Cleanse 3 more` or `The stairs
are awake` beside it. Parts drop from the hint backwards until the line
draws at 1.3% of the screen height or more, so a long hint goes rather than
shrinking the line - and the goal it leaves alone gets its whole sentence
back. The line is the log's button; the list mark at its end says so.

## Career sheet

CAREER on the menu opens a sheet with three tabs, five cards a page. Its head
line reads `runs · wins · best floor · feats n/m`; a thin gold bar under a
card shows how far along it is. The page count rides in the BACK button
(`BACK · 2/4`), with `<` and `>` either side when there is a page that way;
LEFT / RIGHT page it from a keyboard, and Back or ESC closes it.

- **GOALS** starts with the **difficulty ladder** ("next: win at difficulty 2
  to open Rich Veins"), then every unlock the career has not earned, closest
  first, each with its count ("4/5", "17/30") or, for a "win holding / win
  without" goal, what the history says ("held it in 3 runs (best floor 5)").
  Earned unlocks follow as DONE; a loadout earned before its package says so
  ("Skyrunner (needs Aeolian)").
- **FEATS** lists every feat: cosmetic feats of play such as *Two for One*
  (fell two machines in one turn), *By a Thread* (win a run in which you fell
  to 1 HP) or *Six Ways Home* (win with every loadout). An earned feat names
  the run that earned it and reads NEW until the tab has been opened once
  (which is also what clears the CAREER button's NEW badge); one still open
  shows its progress where it has a number to chase. Feats are earned by
  career runs only - a daily never earns one - and they buy nothing. A career
  older than feats gets every one-run feat its RECORDS already show (a
  biggest hit of 9 is Heavy Hand) when it loads, quietly, with no NEW badge.
- **RECORDS** shows the career's bests (score, machines felled, biggest hit,
  most felled in one turn, rooms bloomed, bloom earned, combos, fastest win)
  with the run, loadout and difficulty that set each, then one card per
  loadout (LOCKED, or how it has gone: WON D3, WON, FLOOR 5) and the daily
  streak.

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
  (`+fire 3/3 lights Cinder Grip` on an Ember Sap or Oil Tithe offer, the
  two fire-tagged grafts)

The game-over sheet names the first resonance the run lit as a highlight chip
(`Cinder Grip lit on floor 3`), and holding the elements strip explains the rule.

## Choice cards

Every offer the game asks you to pick between — a shrine's up to eight, a draft's
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

The skip button is the draft's answer to a bad hand - it reads **SKIP**
(**SKIP AGAIN** on a sheet whose roll spent a focus) over a small
`+1 FOCUS offer next floor`: the whole sentence used to be squeezed into
the button at a third of the size. Skipping pays no Bloom: it arms one extra
build-matching offer on the next descent, spent by that draft whether you
take a card or not, and the log line
(`Skipped - next draft adds a focus offer`) is what carries that promise
across the floor.

A focus slot can find nothing left to offer - under Upgrades Only a
three-ability kit has exactly three upgrade candidates and the ordinary slots take
them all - and then the roll spends the focus and deals no FOCUS card. The
sheet says so ("Nothing left to focus on this time") rather than
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
  through all three steps: an arrow says "finish the forge choice, or step
  back" instead of walking you off the shrine for a charge and a turn). The
  forge is the way to reach the sibling the current floor's draft cannot
  deal - the descent draft offers only one variant per base, alternating by
  floor.
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
grate) absorb their next reinforcement. Removing the last corruption tile
by any action of yours - a cleanse, a Reclaimer Bomb's conversion, a Water
Jet's wash; never the enemies' turn - restores the floor: banner, skies
clear, bonus bloom (and a room emptied the same way blooms).

## Run persistence

Live runs survive the OS killing the app: every action is appended to
`user://tender_run.save` (header = seed/config/tier/kind + RUN_SAVE_VERSION,
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
