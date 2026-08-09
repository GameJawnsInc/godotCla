# TENDER — the human shell

## Menu, settings, tutorial

The shell boots to a main menu: PLAY (fresh run), RESUME (when a run is
live), TUTORIAL, SETTINGS, QUIT. Settings persist to `user://tender.cfg`:
hold-to-inspect delay, run seed mode (random / daily — everyone playing a
daily gets the same run), and intro-tips frequency. The `=` button in the
status strip returns to the menu mid-run without losing the run.

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
| H / B / G | buy heal / ability / graft (standing on a shrine) |
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
- tap shop lines at a shrine, draft options between floors
- after a run: tap anywhere for the next seed

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

`tests/test_shell.gd` is the shell's headless smoke test (sprite
rasterization + input handlers driving the sim), part of the suite.

## Art

All sprites live in `shell/svg_art.gd` as hand-written 32×32 SVG strings,
rasterized at runtime via `Image.load_svg_from_string` — no import
pipeline, no binary assets, diffable art. Edit the string, rerun.
