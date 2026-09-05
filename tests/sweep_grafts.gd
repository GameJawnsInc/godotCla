extends SceneTree
## Graft validation sweep: measure the bot with each Content.GRAFTS entry
## pre-installed (config "grafts"), against the same seeds with no graft, plus
## an "all" row carrying every selected graft at once. Answers "what is this
## permanent worth?" without asking the bot to buy it first.
##
## Pre-installed grafts never touch the main rng (they are applied before
## _enter_floor(1)), so a row starts from the same floor-1 map and the same rng
## state as the base row on a seed - the paired sign test below is exact there
## and the rows diverge later only through play. They do raise the graft price
## (shop_cost("graft") is 4 + 2 per owned graft), so a graft row is "own it
## from turn 1, pay more for the next one" - not a free extra.
##
## Run: [SWEEP_BOT=deeproot] [SWEEP_SEEDS=30] [SWEEP_SEED_FROM=101]
##      [SWEEP_TIER=2] [SWEEP_GRAFTS=carapace,solar_core] [SWEEP_BLOOM=12]
##      godot --headless --path . --script tests/sweep_grafts.gd
## SWEEP_GRAFTS narrows the rows (comma list, unknown id -> push_error);
## SWEEP_BLOOM gives every config, base included, that much starting bloom.

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Tally := preload("res://tests/tally.gd")

const SEEDS := 30


func _init() -> void:
	var bot := Sweep.pick_bot()
	var bot_name := Sweep.pick_bot_name()
	var seeds := Sweep.seed_list(SEEDS)
	var gids := _graft_list()
	if gids.is_empty():
		quit(1)
		return
	var base_cfg := Sweep.tier_config({})
	var bloom := int(OS.get_environment("SWEEP_BLOOM"))
	if bloom > 0:
		base_cfg["bloom"] = bloom
	print(Sweep.header("sweep_grafts", bot_name, base_cfg, seeds))
	print("grafts: %s" % ", ".join(gids))

	var base := Sweep.measure(seeds, base_cfg, bot)
	_row("(no graft)", base, base)
	for gid in gids:
		var cfg := base_cfg.duplicate(true)
		cfg["grafts"] = [gid]
		_row(gid, Sweep.measure(seeds, cfg, bot), base)
	if gids.size() > 1:
		var all_cfg := base_cfg.duplicate(true)
		all_cfg["grafts"] = gids.duplicate()
		_row("all %d" % gids.size(), Sweep.measure(seeds, all_cfg, bot), base)
	quit(0)


## Graft ids to measure: SWEEP_GRAFTS (comma list) or every Content.GRAFTS key
## in declaration order.
func _graft_list() -> Array:
	var v := OS.get_environment("SWEEP_GRAFTS")
	if v == "":
		return Content.GRAFTS.keys()
	var out: Array = []
	for gid in v.split(","):
		var g := String(gid).strip_edges()
		if g == "":
			continue
		if not Content.GRAFTS.has(g):
			push_error("unknown graft '%s' (have: %s)" % [g, ", ".join(Content.GRAFTS.keys())])
			return []
		if not out.has(g):
			out.append(g)
	return out


## One table row: wins with its Wilson CI, the paired delta against the base
## row (same seeds, same maps), and the tally KPIs underneath.
func _row(label: String, m: Dictionary, base: Dictionary) -> void:
	var d := Sweep.paired(m["wins_by_seed"], base["wins_by_seed"])
	print("%-16s %2d/%d wins %s  avg floor %.1f  delta %+d  discordant %d:%d p=%.2f  timeouts %d" % [
		label, m["wins"], m["n"], Sweep.fmt_ci(m["ci"]), m["avg_floor"],
		int(m["wins"]) - int(base["wins"]), d["only_a"], d["only_b"], d["sign_p"], m["timeouts"]])
	_kpi_line(m)


func _kpi_line(m: Dictionary) -> void:
	var t = m["tally"]
	var n := maxf(1.0, float(m["n"]))
	var k := Tally.kpis(t, int(m["n"]), m["kits"])
	print("    combos/run %.2f  signature %.2f  terrain %.2f  bloom conv %.2f  dmg taken %.1f  turns(w) %.0f" % [
		k["combo_rate"], k["signature_share"], k["terrain_share"], k["bloom_conversion"],
		m["mean_dmg_taken"], m["mean_turns_on_wins"]])
	print("    shrine: buys %s  grafts bought %s  discarded %d  full-kit ability buys %d  quota reclamps %d  shrine turns/run %.2f" % [
		str(t.buys_by_kind), str(t.grafts_by_id), t.graft_discards, t.ability_drop_buys,
		t.quota_reclamps, float(t.shrine_turns) / n])
