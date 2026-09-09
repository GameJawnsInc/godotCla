extends SceneTree
## Package validation sweep: measure the bot with each tech package added to
## the draft pool, before that package ships to players. After each config's
## win line, pool-health numbers from the tally: offers per base ability per
## run, P(any plus-form offered | draft), and pick rate per base ability.
## Run: [SWEEP_BOT=deeproot] [SWEEP_SEEDS=20] godot --headless --path . --script tests/sweep_packages.gd

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Tally := preload("res://tests/tally.gd")

const SEEDS := 20


func _init() -> void:
	var bot := Sweep.pick_bot()
	var bot_name := Sweep.pick_bot_name()
	var seeds := Sweep.seed_list(SEEDS)
	print(Sweep.header("sweep_packages", bot_name, {}, seeds))
	var base := Sweep.measure(seeds, {}, bot)
	print("baseline pool: %d/%d wins, avg floor %.1f" % [base["wins"], base["n"], base["avg_floor"]])
	_pool_health(base)
	var configs := {}
	for pkg in Content.PACKAGES:
		configs[pkg] = {"packages": [pkg]}
	configs["all three"] = {"packages": Content.PACKAGES.keys()}
	for label in configs:
		var m := Sweep.measure(seeds, configs[label], bot)
		var drafted := {}
		for kit in m["win_kits"]:
			for aid in kit:
				var b: String = Tally.base_id(String(aid))
				if not Content.DRAFT_POOL.has(b) and not Content.STARTING_KIT.has(b):
					drafted[b] = drafted.get(b, 0) + 1
		print("+ %-10s %d/%d wins, avg floor %.1f, package abilities in winning kits: %s" % [
			label, m["wins"], m["n"], m["avg_floor"], str(drafted)])
		_pool_health(m)
	quit(0)


## Offers and picks aggregated by base id ("x" and "x+" together).
func _pool_health(m: Dictionary) -> void:
	var t = m["tally"]
	var n := maxf(1.0, float(m["n"]))
	var offers := {}
	var picks := {}
	for aid in t.offers_by_id:
		var b: String = Tally.base_id(String(aid))
		offers[b] = int(offers.get(b, 0)) + int(t.offers_by_id[aid])
	for aid in t.picks_by_id:
		var b: String = Tally.base_id(String(aid))
		picks[b] = int(picks.get(b, 0)) + int(t.picks_by_id[aid])
	var parts: Array = []
	for b in Tally.sorted_desc(offers):
		parts.append("%s %.2f/run %d%%" % [b, float(offers[b]) / n, int(round(100.0 * float(picks.get(b, 0)) / float(offers[b])))])
	var p_plus := 0.0 if t.drafts == 0 else float(t.drafts_with_plus) / float(t.drafts)
	print("    CI %s  drafts/run %.1f  P(plus offered|draft) %.2f  skips %d  kit entropy %.2f bits" % [
		Sweep.fmt_ci(m["ci"]), float(t.drafts) / n, p_plus, t.skips, Tally.kit_entropy_bits(m["kits"])])
	print("    offers/run and pick rate by base: %s" % (", ".join(parts) if not parts.is_empty() else "no drafts"))
