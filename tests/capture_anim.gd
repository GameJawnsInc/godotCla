extends SceneTree
## Filmstrips of the REAL shell animating, for eyes that cannot watch a
## screen: every staged scene in tests/anim_scenes.gd is stepped through the
## live shell (shell/main.gd _act), the shell's animation clock is pinned
## frame by frame (clock_override), each frame is rendered by Godot and the
## map is cropped into a grid, one PNG per scene.
##
## Needs a display, so run it under a virtual one with the GL renderer:
##   xvfb-run -a -s "-screen 0 540x1200x24" godot --rendering-driver opengl3 \
##     --path . --resolution 540x1200 --script tests/capture_anim.gd
## Env:
##   CAPTURE=all | ability:<id> | intent:<type> | x:<edge case> | <basic name>
##          | a,b,c (default all; "abilities", "intents", "extras" and
##          "basic" pick a group)
##   CAPTURE_OUT=<dir>        (default user://anim_frames)
##   CAPTURE_FRAMES=<n>       frames per strip (default 12)
##   CAPTURE_COLS=<n>         strip columns (default 4)
##   CAPTURE_SCALE=<f>        frame scale in the strip (default 0.75)
##   CAPTURE_SPEED=full|quick|off (default full)
##   CAPTURE_BANNERS=1        keep the full-map banners (default: suppressed)
## Prints one line per strip: name, reel length, frame times, path.

const Scenes := preload("res://tests/anim_scenes.gd")
const Content := preload("res://sim/content.gd")
const Anim := preload("res://shell/anim.gd")

var shell


func _init() -> void:
	call_deferred("_run")


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return d if v == "" else v


func _run() -> void:
	shell = load("res://shell/main.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	if shell._run_save != null:
		shell._run_save.close()
		shell._run_save = null
	shell._game_is_run = false
	shell.seen_intro = true
	shell.audio.sfx_on = false
	shell.audio.set_music(false)
	var out_dir := _env("CAPTURE_OUT", "user://anim_frames")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var names := _selected(_env("CAPTURE", "all"))
	var ok := 0
	for nm in names:
		var sc := _scene(nm)
		if sc.is_empty() or sc.get("action") == null:
			print("SKIP %s (no scene / no legal action)" % nm)
			continue
		if await _capture(sc, out_dir):
			ok += 1
	print("captured %d / %d strips into %s" % [ok, names.size(), ProjectSettings.globalize_path(out_dir)])
	quit()


func _selected(spec: String) -> Array:
	var out: Array = []
	for part in spec.split(",", false):
		match part:
			"all":
				for w in Scenes.BASIC:
					out.append(w)
				for aid in Content.ABILITIES:
					out.append("ability:" + aid)
				for v in Scenes.INTENT_SCENES:
					out.append("intent:" + v)
				out.append_array(Scenes.EXTRA)
			"extras":
				out.append_array(Scenes.EXTRA)
			"basic":
				out.append_array(Scenes.BASIC)
			"abilities":
				for aid in Content.ABILITIES:
					out.append("ability:" + aid)
			"intents":
				for v in Scenes.INTENT_SCENES:
					out.append("intent:" + v)
			_:
				out.append(part)
	return out


func _scene(nm: String) -> Dictionary:
	if nm.begins_with("ability:"):
		var aid := nm.substr(8)
		return Scenes.ability_scene(aid) if Content.ABILITIES.has(aid) else {}
	if nm.begins_with("intent:"):
		var v := nm.substr(7)
		return Scenes.intent_scene(v) if Scenes.INTENT_SCENES.has(v) else {}
	if nm.begins_with("x:"):
		return Scenes.extra_scene(nm)
	return Scenes.basic_scene(nm)


func _capture(sc: Dictionary, out_dir: String) -> bool:
	var frames := int(_env("CAPTURE_FRAMES", "12"))
	var cols := int(_env("CAPTURE_COLS", "4"))
	var scale := float(_env("CAPTURE_SCALE", "0.75"))
	shell.game = sc["game"]
	shell.screen = "game"
	shell.mode = "normal"
	shell.tooltip = []
	shell.flash = ""
	shell.log_lines = []
	shell.zoom_room = false
	shell.anim_mode = _env("CAPTURE_SPEED", "full")
	shell._reel = {}
	var t0 := 1000000
	shell.clock_override = t0
	shell._floor_fade_ms = -99999  # no floor-name splash over the scene
	shell._banner_ms = -99999
	shell._act(sc["action"])
	if _env("CAPTURE_BANNERS", "0") != "1":
		shell._banner = []  # a banner over the map hides the verb being judged
	var reel: Dictionary = shell._reel
	var total := int(reel.get("len", 0)) + 80
	var step := maxi(30, int(ceil(float(total) / float(maxi(1, frames - 1)))))
	var shots: Array = []
	var rect := Rect2i()
	for f in frames:
		var t := f * step
		shell.clock_override = t0 + t
		shell.capture_label = "%s  t=%dms" % [String(sc["name"]), t]
		shell.queue_redraw()
		await RenderingServer.frame_post_draw
		var img: Image = root.get_viewport().get_texture().get_image()
		if f == 0:
			var m: Dictionary = shell.game.map
			var x0 := int(shell._mox + shell._vx0 * shell._ts)
			var y0 := int(shell._moy + shell._vy0 * shell._ts)
			var w := int((shell._vx1 - shell._vx0 + 1) * shell._ts)
			var h := int((shell._vy1 - shell._vy0 + 1) * shell._ts)
			rect = Rect2i(x0, y0, w, h).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var crop := img.get_region(rect)
		if scale != 1.0:
			crop.resize(int(rect.size.x * scale), int(rect.size.y * scale), Image.INTERPOLATE_BILINEAR)
		shots.append(crop)
	shell.clock_override = -1
	shell.capture_label = ""
	if shots.is_empty():
		return false
	var fw: int = shots[0].get_width()
	var fh: int = shots[0].get_height()
	var rows := int(ceil(float(shots.size()) / float(cols)))
	var strip := Image.create(fw * cols + (cols - 1) * 4, fh * rows + (rows - 1) * 4, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.02, 0.02, 0.02))
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(im, Rect2i(0, 0, fw, fh), Vector2i((i % cols) * (fw + 4), (i / cols) * (fh + 4)))
	var fname := String(sc["name"]).replace(":", "_").replace("+", "-") + ".png"
	var path := out_dir.path_join(fname)
	strip.save_png(path)
	print("%-34s len=%4dms step=%3dms -> %s" % [sc["name"], int(reel.get("len", 0)), step, ProjectSettings.globalize_path(path)])
	return true
