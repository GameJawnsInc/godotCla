extends SceneTree
## Locked-kit lift sweep (review §7.3): does holding ability X and Y together
## win more than holding the better one alone?
##
## Every config is LOCKED ({kit: K, pool: K}): the bot never drafts, so a row
## measures the kit itself, not the draft policy. Configs per pair:
##   baseline  BASE3           = STARTING_KIT [solar_lance, seed_bomb, mycelium_dash]
##   single_x  BASE3 + X       (4-kit, NO filler: anchor_roots is not inert)
##   single_y  BASE3 + Y
##   pair      BASE3 + X + Y
##   lift = pair - max(single_x, single_y);  additive = sx + sy - base;
##   pair_minus_additive = pair - additive.
## Baseline and singles are measured once and shared across pairs (the
## arithmetic mirrors Sweep.lift_row exactly, see _lift_row_cached), so the
## full grid is 1 + 12 + 66 = 79 configs, not 66 x 4.
## Extras = DRAFT_POOL minus STARTING_KIT: 12 ids -> 66 pairs.
##
## A pair is FLAGGED only when the pair's Wilson CI excludes the max-single
## fraction AND the discordant-seed sign test has p < 0.05.
##
## Run: [SWEEP_BOT=optimizer] [SWEEP_SEEDS=30] [SWEEP_SEED_FROM=1] [SWEEP_TIER=0]
##      [SWEEP_MODE=lift|drift] [SWEEP_SHARD=i/n] [SWEEP_PAIRS=a+b,c+d]
##      godot --headless --path . --script tests/sweep_combos.gd
##   SWEEP_TIER   headroom tier: deeproot 6 (tier 0 is saturated for the
##                ceiling bot), optimizer 0. A tier-6 lift is lift in a
##                DIFFERENT economy (tier config changes hp/smog/shop) and must
##                not be compared with a tier-0 row.
##   SWEEP_MODE   lift (default) as above; drift = the OLD question kept as a
##                labelled second table: {kit: STARTING_KIT + X + Y} with the
##                DEFAULT open pool vs the open-pool baseline, flagged at
##                +-DRIFT_MARGIN percentage points. Drift measures how seeding
##                the kit shifts a drafting bot, not the pair's own value.
##   SWEEP_SHARD  i/n slices the sorted pair list (index % n == i), so the grid
##                can run in parallel shards and be concatenated.
##   SWEEP_PAIRS  explicit comma list of x+y pairs (ids must be extras).
## Runtime: optimizer ~0.2 s/run -> 79 configs x 30 seeds ~8 min. deeproot
## ~4 s/run -> 79 x 30 ~2.6 h (tier 6 ~10 s/run -> ~6.5 h): shard it, or use
## the optimizer for the full grid and deeproot for the flagged rows.

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Tally := preload("res://tests/tally.gd")

const SEEDS := 30
const DRIFT_MARGIN := 30  # percentage points from baseline (drift mode only)
const FLAG_P := 0.05

const CAVEAT_TIER := "a lift measured at SWEEP_TIER>0 is lift in a different economy (tier config changes hp, smog and shop); compare rows within one tier only"


func _init() -> void:
	var bot := Sweep.pick_bot()
	var bot_name := Sweep.pick_bot_name()
	var seeds := Sweep.seed_list(SEEDS)
	var mode := OS.get_environment("SWEEP_MODE")
	if mode == "":
		mode = "lift"
	var cfg := Sweep.tier_config({"tier": 0})
	print(Sweep.header("sweep_combos", bot_name, cfg, seeds))
	if bot == null:
		print("FAIL: unknown SWEEP_BOT")
		quit(1)
		return
	if mode != "lift" and mode != "drift":
		print("FAIL: SWEEP_MODE must be lift or drift, got '%s'" % mode)
		quit(1)
		return

	var extras := _extras()
	var all_pairs := _all_pairs(extras)
	var pairs := _select_pairs(all_pairs, extras)
	if pairs.is_empty():
		print("FAIL: no pairs selected (bad SWEEP_PAIRS or SWEEP_SHARD)")
		quit(1)
		return
	print("mode %s | extras %d -> %d pairs, %d selected%s%s" % [
		mode, extras.size(), all_pairs.size(), pairs.size(),
		"" if OS.get_environment("SWEEP_SHARD") == "" else " | shard " + OS.get_environment("SWEEP_SHARD"),
		"" if OS.get_environment("SWEEP_PAIRS") == "" else " | pairs " + OS.get_environment("SWEEP_PAIRS")])

	if mode == "drift":
		_run_drift(pairs, seeds, cfg, bot)
	else:
		_run_lift(pairs, seeds, cfg, bot)
	quit(0)


# --- pair selection ---------------------------------------------------------------

## DRAFT_POOL minus STARTING_KIT, sorted (deterministic order for sharding).
func _extras() -> Array:
	var out: Array = []
	for aid in Content.DRAFT_POOL:
		if not Content.STARTING_KIT.has(aid):
			out.append(String(aid))
	out.sort()
	return out


## All unordered pairs [x, y] with x < y, in sorted order.
func _all_pairs(extras: Array) -> Array:
	var out: Array = []
	for i in extras.size():
		for j in range(i + 1, extras.size()):
			out.append([extras[i], extras[j]])
	return out


## SWEEP_PAIRS (explicit list, validated) else SWEEP_SHARD slice of the full
## list, else the full list. Unknown ids and bad shard specs return [].
func _select_pairs(all_pairs: Array, extras: Array) -> Array:
	var explicit := OS.get_environment("SWEEP_PAIRS")
	if explicit != "":
		var out: Array = []
		for item in explicit.split(",", false):
			var parts: PackedStringArray = String(item).strip_edges().split("+", false)
			if parts.size() != 2:
				print("FAIL: SWEEP_PAIRS entry '%s' is not x+y" % String(item))
				return []
			var x := String(parts[0]).strip_edges()
			var y := String(parts[1]).strip_edges()
			if not extras.has(x) or not extras.has(y) or x == y:
				print("FAIL: SWEEP_PAIRS entry '%s' must name two distinct extras (%s)" % [String(item), ", ".join(extras)])
				return []
			out.append([x, y] if x < y else [y, x])
		return out
	var shard := OS.get_environment("SWEEP_SHARD")
	if shard != "":
		var parts: PackedStringArray = shard.split("/", false)
		if parts.size() != 2 or not String(parts[0]).is_valid_int() or not String(parts[1]).is_valid_int():
			print("FAIL: SWEEP_SHARD must be i/n, got '%s'" % shard)
			return []
		var i := int(parts[0])
		var n := int(parts[1])
		if n <= 0 or i < 0 or i >= n:
			print("FAIL: SWEEP_SHARD %s out of range" % shard)
			return []
		var out: Array = []
		for k in all_pairs.size():
			if k % n == i:
				out.append(all_pairs[k])
		return out
	return all_pairs.duplicate()


# --- lift mode --------------------------------------------------------------------

func _run_lift(pairs: Array, seeds: Array, cfg: Dictionary, bot) -> void:
	var base3: Array = Content.STARTING_KIT.duplicate()
	var n := seeds.size()
	print("\n[lift] locked configs {kit: K, pool: K}; base3 %s" % str(base3))
	print(Sweep.CAVEAT_LOCKED)
	if int(cfg.get("tier", 0)) > 0:
		print(CAVEAT_TIER)

	var mb := Sweep.measure(seeds, Sweep.locked_config(base3, cfg), bot)
	var singles := {}  # id -> measure()
	var single_ids: Array = []
	for p in pairs:
		for aid in p:
			if not single_ids.has(aid):
				single_ids.append(aid)
	single_ids.sort()
	for aid in single_ids:
		var k4: Array = base3.duplicate()
		k4.append(aid)
		singles[aid] = Sweep.measure(seeds, Sweep.locked_config(k4, cfg), bot)

	print("\nbaseline (base3 locked): %s" % _single_line(mb, n))
	print("\nsingles (base3 + X locked, %d ids x %d seeds):" % [single_ids.size(), n])
	print("  %-14s %8s %-12s %10s %9s %8s" % ["ability", "wins", "CI", "combos/run", "turns(w)", "dmg"])
	for aid in single_ids:
		print("  %-14s %s" % [aid, _single_line(singles[aid], n)])

	var rows: Array = []
	for p in pairs:
		var x: String = p[0]
		var y: String = p[1]
		var kxy: Array = base3.duplicate()
		kxy.append(x)
		kxy.append(y)
		var mp := Sweep.measure(seeds, Sweep.locked_config(kxy, cfg), bot)
		rows.append(_lift_row_cached(base3, x, y, mb, singles[x], singles[y], mp))
	rows.sort_custom(_lift_order)

	print("\npairs (base3 + X + Y locked, %d pairs x %d seeds), sorted by lift:" % [rows.size(), n])
	print("  %-31s %5s %5s %5s %5s %5s %5s %6s %-13s %5s %4s" % [
		"pair", "sx", "sy", "pair", "max", "lift", "add", "p-add", "discordant", "cmb/r", "t/o"])
	var flagged := 0
	for r in rows:
		var flag := _flag(r)
		if flag != "":
			flagged += 1
		var d: Dictionary = r["discordant"]
		print("  %-31s %2d/%-2d %2d/%-2d %2d/%-2d %5d %+5d %5d %+6d %2d:%-2d p=%.2f  %5.2f %4d%s" % [
			"%s + %s" % [r["x"], r["y"]], r["single_x"], n, r["single_y"], n, r["pair"], n,
			maxi(r["single_x"], r["single_y"]), r["lift"], r["additive"], r["pair_minus_additive"],
			d["only_a"], d["only_b"], d["sign_p"], r["combo_rate_pair"], r["timeouts_pair"], flag])
	print("\n%d/%d pairs flagged (pair CI excludes the max-single fraction AND sign_p < %.2f); discordant = seeds won by pair only : by best single only; %s wins/%d" % [
		flagged, rows.size(), FLAG_P, "sx/sy/pair are", n])
	print("secondaries per pair (signature share / terrain share / turns on wins / dmg taken / avg floor):")
	for r in rows:
		print("  %-31s sig %.2f  terrain %.2f  turns(w) %.0f  dmg %.1f  floor %.1f" % [
			"%s + %s" % [r["x"], r["y"]], r["signature_share_pair"], r["terrain_share_pair"],
			r["turns_on_wins_pair"], r["dmg_taken_pair"], r["avg_floor_pair"]])
	print(Sweep.CAVEAT_LOCKED)
	if int(cfg.get("tier", 0)) > 0:
		print(CAVEAT_TIER)


## Same dict as Sweep.lift_row, built from measurements taken once and shared
## across pairs (lift_row re-measures base and both singles per call).
func _lift_row_cached(base3: Array, x: String, y: String, mb: Dictionary, mx: Dictionary, my: Dictionary, mp: Dictionary) -> Dictionary:
	var sx: int = mx["wins"]
	var sy: int = my["wins"]
	var best_single: Dictionary = mx if sx >= sy else my
	var kp := Tally.kpis(mp["tally"], mp["n"], mp["kits"])
	return {
		"x": x, "y": y, "base3": base3.duplicate(),
		"n": mp["n"],
		"base": mb["wins"], "single_x": sx, "single_y": sy, "pair": mp["wins"],
		"lift": mp["wins"] - maxi(sx, sy),
		"additive": sx + sy - mb["wins"],
		"pair_minus_additive": mp["wins"] - (sx + sy - mb["wins"]),
		"ci_pair": mp["ci"], "ci_x": mx["ci"], "ci_y": my["ci"], "ci_base": mb["ci"],
		"discordant": Sweep.paired(mp["wins_by_seed"], best_single["wins_by_seed"]),
		"combo_rate_pair": kp["combo_rate"],
		"signature_share_pair": kp["signature_share"],
		"terrain_share_pair": kp["terrain_share"],
		"turns_on_wins_pair": mp["mean_turns_on_wins"],
		"dmg_taken_pair": mp["mean_dmg_taken"],
		"timeouts_pair": mp["timeouts"],
		"avg_floor_pair": mp["avg_floor"],
		"tally_pair": mp["tally"],
	}


## Lift desc, then pair wins desc, then pair name asc (total order).
func _lift_order(a: Dictionary, b: Dictionary) -> bool:
	if a["lift"] != b["lift"]:
		return a["lift"] > b["lift"]
	if a["pair"] != b["pair"]:
		return a["pair"] > b["pair"]
	return "%s+%s" % [a["x"], a["y"]] < "%s+%s" % [b["x"], b["y"]]


## "<< LIFT" / "<< DRAG" only when the pair CI excludes the max-single win
## fraction and the discordant sign test is significant.
func _flag(r: Dictionary) -> String:
	var n := maxi(1, int(r["n"]))
	var best := float(maxi(r["single_x"], r["single_y"])) / float(n)
	var ci: Vector2 = r["ci_pair"]
	var d: Dictionary = r["discordant"]
	if float(d["sign_p"]) >= FLAG_P:
		return ""
	if ci.x > best:
		return "  << LIFT"
	if ci.y < best:
		return "  << DRAG"
	return ""


func _single_line(m: Dictionary, n: int) -> String:
	var kp := Tally.kpis(m["tally"], m["n"], m["kits"])
	return "%2d/%-5d %-12s %10.2f %9.0f %8.1f" % [
		m["wins"], n, Sweep.fmt_ci(m["ci"]), kp["combo_rate"], m["mean_turns_on_wins"], m["mean_dmg_taken"]]


# --- drift mode (the old question) --------------------------------------------------

## OLD sweep_combos behaviour: seed the kit with the pair, keep the DEFAULT
## open pool, compare with the open-pool baseline at +-DRIFT_MARGIN pp.
func _run_drift(pairs: Array, seeds: Array, cfg: Dictionary, bot) -> void:
	var n := seeds.size()
	print("\n[drift] {kit: STARTING_KIT + X + Y} with the default open pool vs the open-pool baseline; measures how seeding the kit shifts a DRAFTING bot, not the pair's locked value")
	var base := Sweep.measure(seeds, cfg, bot)
	var base_pct: float = 0.0 if n == 0 else 100.0 * base["wins"] / n
	print("baseline (standard kit, open pool): %d/%d (%.0f%%) %s, avg floor %.1f" % [
		base["wins"], n, base_pct, Sweep.fmt_ci(base["ci"]), base["avg_floor"]])
	var rows: Array = []
	for p in pairs:
		var kit: Array = Content.STARTING_KIT.duplicate()
		kit.append(p[0])
		kit.append(p[1])
		var c := cfg.duplicate(true)
		c["kit"] = kit
		var m := Sweep.measure(seeds, c, bot)
		rows.append({"pair": "%s + %s" % [p[0], p[1]], "wins": m["wins"], "ci": m["ci"], "avg_floor": m["avg_floor"], "timeouts": m["timeouts"]})
	rows.sort_custom(func(a, b):
		if a["wins"] != b["wins"]:
			return a["wins"] > b["wins"]
		return a["pair"] < b["pair"])
	print("\npair drift (%d pairs x %d seeds, standard kit + pair, open pool):" % [rows.size(), n])
	for r in rows:
		var pct: float = 0.0 if n == 0 else 100.0 * r["wins"] / n
		var flag := ""
		if pct >= base_pct + DRIFT_MARGIN:
			flag = "  << OVERPERFORMS"
		elif pct <= base_pct - DRIFT_MARGIN:
			flag = "  << UNDERPERFORMS"
		print("  %-31s %2d/%-2d %-12s avg floor %.1f  timeouts %d%s" % [r["pair"], r["wins"], n, Sweep.fmt_ci(r["ci"]), r["avg_floor"], r["timeouts"], flag])
