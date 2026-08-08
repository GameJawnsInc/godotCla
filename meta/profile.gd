extends RefCounted
## Career profile: persistent meta-progression across runs. Lives outside the
## sim (the sim stays pure); the app layer records finished runs here and asks
## for the next run's config. Milestones are data in Content.MILESTONES.

const Content := preload("res://sim/content.gd")

var runs := 0
var wins := 0
var tier_wins := 0
var best_floor := 0
var unlocked_tier := 0
var unlocked_packages: Array = []
var unlocked_mutators: Array = []


## Record a finished run ({won, floor, tier}) and return newly unlocked ids.
func record_run(result: Dictionary) -> Array:
	runs += 1
	best_floor = maxi(best_floor, int(result["floor"]))
	if result["won"]:
		wins += 1
		if int(result["tier"]) >= 1:
			tier_wins += 1
		var next_tier: int = int(result["tier"]) + 1
		if next_tier > unlocked_tier and next_tier <= Content.TIERS.size():
			unlocked_tier = next_tier
	var news: Array = []
	for m in Content.MILESTONES:
		var id := String(m["id"])
		var owned: bool = unlocked_packages.has(id) or unlocked_mutators.has(id)
		if owned or not _meets(m["requires"]):
			continue
		if m["kind"] == "package":
			unlocked_packages.append(id)
		else:
			unlocked_mutators.append(id)
		news.append(id)
	return news


func _meets(req: Dictionary) -> bool:
	if best_floor < int(req.get("best_floor", 0)):
		return false
	if wins < int(req.get("wins", 0)):
		return false
	if tier_wins < int(req.get("tier_wins", 0)):
		return false
	return true


## Config for the next run at the requested tier (clamped to what is unlocked).
func game_config(req_tier: int = 0, req_mutators: Array = []) -> Dictionary:
	var muts: Array = []
	for m in req_mutators:
		if unlocked_mutators.has(m):
			muts.append(m)
	return {
		"packages": unlocked_packages.duplicate(),
		"tier": clampi(req_tier, 0, unlocked_tier),
		"mutators": muts,
	}


func to_dict() -> Dictionary:
	return {
		"runs": runs, "wins": wins, "tier_wins": tier_wins, "best_floor": best_floor,
		"unlocked_tier": unlocked_tier,
		"unlocked_packages": unlocked_packages.duplicate(),
		"unlocked_mutators": unlocked_mutators.duplicate(),
	}


func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(to_dict()))
	f.close()


static func load_from(path: String):  # -> Profile (or fresh if missing)
	var profile = new()
	if not FileAccess.file_exists(path):
		return profile
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data == null:
		return profile
	profile.runs = int(data.get("runs", 0))
	profile.wins = int(data.get("wins", 0))
	profile.tier_wins = int(data.get("tier_wins", 0))
	profile.best_floor = int(data.get("best_floor", 0))
	profile.unlocked_tier = int(data.get("unlocked_tier", 0))
	profile.unlocked_packages = data.get("unlocked_packages", [])
	profile.unlocked_mutators = data.get("unlocked_mutators", [])
	return profile
