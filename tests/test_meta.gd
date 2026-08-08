extends SceneTree
## Meta-progression checks:
## 1) a simulated optimizer career walks the unlock ladder (packages, tiers)
## 2) profile save/load roundtrips
## 3) every mutator runs without errors and stays sane
## Run: godot --headless --path . --script tests/test_meta.gd

const Content := preload("res://sim/content.gd")
const Profile := preload("res://meta/profile.gd")
const Sweep := preload("res://tests/sweep_lib.gd")

const CAREER_RUNS := 40


func _init() -> void:
	var failures := 0

	# 1) career simulation: always play the highest unlocked tier
	var profile = Profile.new()
	var unlock_log: Array = []
	for s in range(1, CAREER_RUNS + 1):
		var t: int = profile.unlocked_tier
		var r := Sweep.run_one(s, profile.game_config(t))
		var news: Array = profile.record_run({"won": r["won"], "floor": r["floor"], "tier": t})
		for id in news:
			unlock_log.append("run %d: %s" % [s, id])
	print("career: %d runs, %d wins, best floor %d, reached tier %d" % [
		profile.runs, profile.wins, profile.best_floor, profile.unlocked_tier])
	for line in unlock_log:
		print("  unlock at %s" % line)
	if profile.unlocked_packages.is_empty():
		failures += 1
		print("FAIL: no packages unlocked across %d runs" % CAREER_RUNS)
	if profile.unlocked_tier == 0 and profile.wins > 0:
		failures += 1
		print("FAIL: wins recorded but tier never unlocked")

	# 2) save/load roundtrip
	var path := "user://test_profile.json"
	profile.save(path)
	var loaded = Profile.load_from(path)
	if str(loaded.to_dict()) != str(profile.to_dict()):
		failures += 1
		print("FAIL: profile save/load mismatch")
	else:
		print("profile save/load roundtrip: OK")

	# 3) each mutator smoke-tested
	for mut in Content.MUTATORS:
		var m := Sweep.measure(8, {"mutators": [mut]})
		print("mutator %-10s %d/8 wins, avg floor %.1f" % [mut, m["wins"], m["avg_floor"]])

	if failures == 0:
		print("meta: OK")
	quit(1 if failures > 0 else 0)
