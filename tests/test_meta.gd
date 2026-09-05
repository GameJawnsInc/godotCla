extends SceneTree
## Meta-progression checks:
## 1) a simulated optimizer career walks the unlock ladder (packages, tiers)
##    and must own every package by run 40 (unlock SET, not run numbers)
## 2) profile save/load roundtrips
## 3) every mutator runs without errors and stays sane
## 4) structural asserts (review §6.1 / §7.6): each package lands in the draft
##    pool without touching the base pool; each mutator's declared invariant
##    holds on a fresh game (expectation table lives HERE, not in content);
##    game_config clamps unknown requests; a tier-0-only career names exactly
##    the milestones it can never reach; the roster covers the playtest personas
## Run: godot --headless --path . --script tests/test_meta.gd

const Content := preload("res://sim/content.gd")
const Game := preload("res://sim/game.gd")
const Profile := preload("res://meta/profile.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")

const CAREER_RUNS := 40
const TIER0_CAREER_RUNS := 20
const MUTATOR_SEEDS := 8
## Milestones a career that never leaves tier 0 cannot reach: everything
## gated on tier_wins (Content.MILESTONES).
const TIER0_UNREACHABLE := ["aeolian", "brittle", "parched"]


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
	# the unlock SET by run 40: every package must be owned; mutators are reported
	var missing_pkgs: Array = []
	for pkg in Content.PACKAGES:
		if not profile.unlocked_packages.has(pkg):
			missing_pkgs.append(pkg)
	if not missing_pkgs.is_empty():
		failures += 1
		print("FAIL: packages not unlocked by run %d: %s" % [CAREER_RUNS, str(missing_pkgs)])
	var missing_muts: Array = []
	for mut in Content.MUTATORS:
		if not profile.unlocked_mutators.has(mut):
			missing_muts.append(mut)
	print("career unlock set: packages %s, mutators %s%s" % [
		str(profile.unlocked_packages), str(profile.unlocked_mutators),
		"" if missing_muts.is_empty() else "  (mutators still locked: %s)" % str(missing_muts)])

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
		var m := Sweep.measure(MUTATOR_SEEDS, {"mutators": [mut]})
		print("mutator %-10s %d/%d wins, avg floor %.1f" % [mut, m["wins"], MUTATOR_SEEDS, m["avg_floor"]])

	# 4a) packages: ids land in the pool, the base pool is otherwise untouched
	for pkg in Content.PACKAGES:
		var pool: Array = Game.new(1, {"packages": [pkg]}).draft_pool
		var msg := _package_pool_problem(pkg, pool)
		if msg != "":
			failures += 1
			print("FAIL: package %s: %s" % [pkg, msg])
	print("package pools: OK (%d packages)" % Content.PACKAGES.size())

	# 4b) mutator invariant table (in the test, not in content)
	for mut in Content.MUTATORS:
		var msg := _mutator_invariant_problem(mut)
		if msg != "":
			failures += 1
			print("FAIL: mutator %s invariant: %s" % [mut, msg])
	print("mutator invariants: OK (%d mutators)" % Content.MUTATORS.size())

	# 4c) game_config clamps: tier to what is unlocked, unknown mutators dropped
	var clamped: Dictionary = profile.game_config(9, ["nonexistent"])
	if int(clamped["tier"]) != profile.unlocked_tier or int(clamped["tier"]) > Content.TIERS.size():
		failures += 1
		print("FAIL: game_config(9, ...) tier %d, unlocked %d" % [int(clamped["tier"]), profile.unlocked_tier])
	if not clamped["mutators"].is_empty():
		failures += 1
		print("FAIL: game_config(9, ['nonexistent']) returned mutators %s" % str(clamped["mutators"]))
	var fresh: Dictionary = Profile.new().game_config(9, ["kit_of_3"])
	if int(fresh["tier"]) != 0 or not fresh["mutators"].is_empty() or not fresh["packages"].is_empty():
		failures += 1
		print("FAIL: fresh profile game_config(9, ['kit_of_3']) = %s" % str(fresh))
	print("game_config clamp: OK (tier %d -> %d, mutators dropped)" % [9, int(clamped["tier"])])

	# 4d) a career that never leaves tier 0: the unreachable set is exact
	var p0 = Profile.new()
	for s in range(1, TIER0_CAREER_RUNS + 1):
		var r := Sweep.run_one(s, p0.game_config(0))
		p0.record_run({"won": r["won"], "floor": r["floor"], "tier": 0})
	var unreachable: Array = []
	for m in Content.MILESTONES:
		var id := String(m["id"])
		if not p0.unlocked_packages.has(id) and not p0.unlocked_mutators.has(id):
			unreachable.append(id)
	unreachable.sort()
	var want: Array = TIER0_UNREACHABLE.duplicate()
	want.sort()
	print("tier-0 career: %d runs, %d wins, best floor %d, locked milestones %s" % [
		p0.runs, p0.wins, p0.best_floor, str(unreachable)])
	if unreachable != want:
		failures += 1
		print("FAIL: tier-0 career locked set %s, expected %s" % [str(unreachable), str(want)])

	# 4e) the roster covers every persona playtest runs by default
	for name in Roster.LEGACY:
		if not Roster.has(name):
			failures += 1
			print("FAIL: playtest persona '%s' missing from Roster.BOTS" % name)
	print("roster: %d personas, legacy %s: OK" % [Roster.names().size(), str(Roster.LEGACY)])

	if failures == 0:
		print("meta: OK")
	quit(1 if failures > 0 else 0)


## "" when `pool` is DRAFT_POOL followed by the package's ids (each present
## exactly once), else a description of the problem.
func _package_pool_problem(pkg: String, pool: Array) -> String:
	var ids: Array = Content.PACKAGES[pkg]
	for aid in ids:
		if not pool.has(aid):
			return "id %s missing from draft_pool %s" % [aid, str(pool)]
	var base: Array = []
	for aid in pool:
		if not ids.has(aid):
			base.append(aid)
	if base != Content.DRAFT_POOL:
		return "pool minus package ids %s != DRAFT_POOL" % str(base)
	if pool.size() != Content.DRAFT_POOL.size() + ids.size():
		return "pool size %d, expected %d" % [pool.size(), Content.DRAFT_POOL.size() + ids.size()]
	return ""


## Declared invariant per mutator on a fresh game; "" when it holds. A
## mutator without a row here fails: new content must add its expectation.
## `_kit_max` is a sim-private helper; reading it from a test is fine (the
## sim exposes no public cap and the test never writes state).
func _mutator_invariant_problem(mut: String) -> String:
	var cfg := {"mutators": [mut]}
	match mut:
		"kit_of_3":
			var g = Game.new(1, cfg)
			if g._kit_max() != 3:
				return "_kit_max() == %d, expected 3" % g._kit_max()
			if Game.new(1)._kit_max() != Content.KIT_MAX:
				return "base game _kit_max() != KIT_MAX"
		"boarded":
			var g = Game.new(1, cfg)
			if not g.shop.is_empty():
				return "floor-1 shop is %s, expected {}" % str(g.shop)
			if Game.new(1).shop.is_empty():
				return "base game floor-1 shop is empty too (check proves nothing)"
		"parched":
			# end a turn with the full 3 charge left: nothing may carry over
			var g = Game.new(1, cfg)
			var before: int = g.player["charge"]
			g.step({"type": "end_turn"})
			var regen: int = maxi(1, Content.BASE_REGEN - g.dim)
			if g.player["bank"] != 0 or g.player["charge"] != regen:
				return "after end_turn with %d charge: bank %d charge %d, expected bank 0 charge %d" % [
					before, g.player["bank"], g.player["charge"], regen]
			var base = Game.new(1)
			base.step({"type": "end_turn"})
			if base.player["charge"] <= regen:
				return "base game did not bank charge (%d), check proves nothing" % base.player["charge"]
		"brittle":
			var g = Game.new(1, cfg)
			if g.player["max_hp"] != Content.PLAYER_HP - 3 or g.player["hp"] != Content.PLAYER_HP - 3:
				return "hp %d/%d, expected %d/%d" % [g.player["hp"], g.player["max_hp"], Content.PLAYER_HP - 3, Content.PLAYER_HP - 3]
		"double_oil":
			for s in range(1, 6):
				var g = Game.new(s, cfg)
				var base = Game.new(s)
				if int(g.floor_def(1)["oil"]) != int(Content.FLOORS[0]["oil"]) * 2:
					return "floor_def(1).oil %d, expected %d" % [int(g.floor_def(1)["oil"]), int(Content.FLOORS[0]["oil"]) * 2]
				if _oil_count(g) < _oil_count(base):
					return "seed %d: %d oil tiles < base game's %d" % [s, _oil_count(g), _oil_count(base)]
		"overtime":
			var g = Game.new(1, cfg)
			var fdef: Dictionary = g.floor_def(1)
			var base_enemies: Dictionary = Content.FLOORS[0]["enemies"]
			var common := ""
			var common_n := 0
			for kind in base_enemies:
				if int(base_enemies[kind]) > common_n:
					common_n = int(base_enemies[kind])
					common = kind
			if int(fdef["enemies"][common]) != common_n + 1:
				return "floor_def(1).enemies[%s] == %d, expected %d" % [common, int(fdef["enemies"][common]), common_n + 1]
			if g.floor_def(Content.FLOORS.size())["enemies"] != Content.FLOORS[Content.FLOORS.size() - 1]["enemies"]:
				return "boss floor enemies changed by overtime"
		_:
			return "no invariant row in tests/test_meta.gd for mutator '%s'" % mut
	return ""


func _oil_count(g) -> int:
	var n := 0
	for t in g.terrain:
		if g.terrain[t]["kind"] == "oil":
			n += 1
	return n
