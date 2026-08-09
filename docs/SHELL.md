# TENDER — the human shell

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
