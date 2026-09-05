extends SceneTree
## Draft oracle (review 7.4): the direct build-depth metric. Runs a policy
## bot and, at every draft it faces, forks the game once per distinct pick
## plus skip, rolls each fork out to game end with a FRESH instance of the
## same persona (Roster.make(name, seed), so its reset seed matches) through
## Sweep.run_loop, then lets the real game continue with the policy's actual
## choice. Aggregates P(win | pick) - P(win | skip) per offer with Wilson CI
## and a paired sign test, kit-conditional value per (offer, co-held base
## id), stakes per draft by floor (decisive vs seed-decided) and policy
## regret (wins of the best fork minus wins of the pick taken).
##
## Distinct picks: legal draft actions grouped by pick index. A full kit
## yields one action per drop slot; the fork uses the drop slot the policy
## itself would choose for that offer, obtained by asking the bot with the
## snapshot/legal pair reduced to that single offer (bot rng state saved and
## restored around the call, so rng-driven personas stay on their real
## sequence; deeproot's forward model is pointed at a matching clone). If the
## bot answers skip for the forced offer, the optimizer's least-used rule is
## mirrored instead (never drop mycelium_dash / seed_bomb; ties -> lowest
## slot). The action the policy really took is always a fork too, so regret
## is exact even when its drop differs from the canonical one.
##
## Rollout dmg_taken counts damage from the fork point onward. A fork that
## hits the run_loop caps is a timeout (counted, never a win).
##
## Run: ORACLE_BOT=optimizer ORACLE_SEEDS=30 godot --headless --path . --script tests/draft_oracle.gd
## Env: ORACLE_BOT (roster name, default optimizer), ORACLE_SEEDS (default 30),
##   ORACLE_SEED_FROM (default 1), ORACLE_TIER, ORACLE_SHARD=i/n (keep seeds
##   whose index mod n == i, i in 0..n-1), ORACLE_JSON=<path> dumps every
##   draft record so shards can be merged offline.
## Runtime: optimizer ~0.2 s per fork; deeproot ~3-5 s per fork (shard it).

const Game := preload("res://sim/game.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")
const Tally := preload("res://tests/tally.gd")

const MIN_N_CONDITIONAL := 10
const CAVEAT := "caveat: a rollout values an offer by what THIS persona does with it (and the persona's own later drafts); it is not the offer's ceiling."

var _records: Array = []


func _init() -> void:
	var bot_name := "optimizer"
	if OS.get_environment("ORACLE_BOT") != "":
		bot_name = OS.get_environment("ORACLE_BOT")
	if not Roster.has(bot_name):
		push_error("unknown bot '%s' (have: %s)" % [bot_name, ", ".join(Roster.names())])
		quit(1)
		return
	var count := 30
	if OS.get_environment("ORACLE_SEEDS") != "":
		count = int(OS.get_environment("ORACLE_SEEDS"))
	var first := 1
	if OS.get_environment("ORACLE_SEED_FROM") != "":
		first = int(OS.get_environment("ORACLE_SEED_FROM"))
	var cfg := {}
	if OS.get_environment("ORACLE_TIER") != "":
		cfg["tier"] = int(OS.get_environment("ORACLE_TIER"))
	var seeds := Sweep.seed_list_from(count, first)
	var shard := OS.get_environment("ORACLE_SHARD")
	if shard != "":
		var parts := shard.split("/")
		if parts.size() != 2 or int(parts[1]) <= 0 or int(parts[0]) < 0 or int(parts[0]) >= int(parts[1]):
			push_error("ORACLE_SHARD must be i/n with 0 <= i < n, got '%s'" % shard)
			quit(1)
			return
		var kept: Array = []
		for idx in seeds.size():
			if idx % int(parts[1]) == int(parts[0]):
				kept.append(seeds[idx])
		seeds = kept
	print(Sweep.header("draft_oracle", bot_name, cfg, seeds))
	if shard != "":
		print("shard %s" % shard)

	var real_wins := 0
	var agree := 0
	var t0 := Time.get_ticks_msec()
	for s in seeds:
		var before := _records.size()
		var r := _run_seed(int(s), bot_name, cfg)
		if r["won"]:
			real_wins += 1
		# self-check: the fork the policy really took, rolled out by a fresh
		# instance, should reproduce the real outcome for rng-free personas
		for idx in range(before, _records.size()):
			for f in _records[idx]["forks"]:
				if f["chosen"] and bool(f["won"]) == bool(r["won"]):
					agree += 1
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	print("policy runs: %d/%d wins  drafts seen %d  forks rolled %d  (%.1f s)" % [
		real_wins, seeds.size(), _records.size(), _fork_count(), secs])
	print("chosen-fork rollout agrees with the real outcome at %d/%d drafts (expect all for rng-free personas)" % [
		agree, _records.size()])

	_report()
	var json_path := OS.get_environment("ORACLE_JSON")
	if json_path != "":
		_dump_json(json_path, bot_name, cfg, seeds)
	quit(0)


# --- one seed -----------------------------------------------------------------

## Runs the policy bot on one seed, forking at every draft. The real loop
## mirrors Sweep.run_loop's caps so the policy run is the same run any other
## runner would see for this (seed, config, persona).
func _run_seed(seed_v: int, bot_name: String, cfg: Dictionary) -> Dictionary:
	var game = Game.new(seed_v, cfg)
	var bot = Roster.make(bot_name, seed_v)
	if bot.has_method("set_sim"):
		bot.set_sim(game)
	var actions := 0
	while not game.over and actions < Sweep.MAX_ACTIONS and game.total_turns < Sweep.MAX_TURNS:
		var snap: Dictionary = game.snapshot()
		var legal: Array = game.legal_actions()
		var act: Dictionary = bot.choose_action(snap, legal)
		if String(snap["phase"]) == "draft" and String(act.get("type", "")) == "draft":
			_records.append(_oracle_draft(game, bot, bot_name, seed_v, snap, legal, act))
		game.step(act)
		actions += 1
	return {"won": game.won, "floor": game.floor_num, "turns": game.total_turns}


## Fork every distinct pick plus skip (plus the real choice when its drop
## differs), roll each out with a fresh persona instance and record.
func _oracle_draft(game, bot, bot_name: String, seed_v: int, snap: Dictionary, legal: Array, chosen: Dictionary) -> Dictionary:
	var offers: Array = snap["draft_offers"]
	var forks := _distinct_forks(game, bot, snap, legal)
	var have_chosen := false
	for f in forks:
		if f == chosen:
			have_chosen = true
	if not have_chosen:
		forks.append(chosen)
	var kit_before: Array = []
	for aid in snap["player"]["kit"]:
		kit_before.append(Tally.base_id(String(aid)))
	kit_before.sort()
	var fork_rows: Array = []
	for f in forks:
		var g = game.clone()
		g.step(f)
		var fresh = Roster.make(bot_name, seed_v)
		var r := Sweep.run_loop(g, fresh)
		var pick := int(f.get("pick", -1))
		fork_rows.append({
			"pick": pick,
			"drop": int(f.get("drop", -1)),
			"id": String(offers[pick]) if pick >= 0 else "skip",
			"won": bool(r["won"]),
			"timeout": bool(r["timeout"]),
			"turns": int(r["turns"]),
			"floor": int(r["floor"]),
			"dmg_taken": int(r["dmg_taken"]),
			"chosen": f == chosen,
		})
	var cpick := int(chosen.get("pick", -1))
	var kind := "skip"
	if cpick >= 0:
		kind = "upgrade" if String(offers[cpick]).ends_with("+") else "new"
	return {
		"seed": seed_v,
		"floor": int(snap["floor"]) + 1,  # the floor this draft leads into
		"kit_before": kit_before,
		"offers": offers.duplicate(),
		"chosen": cpick,
		"chosen_id": String(offers[cpick]) if cpick >= 0 else "skip",
		"chosen_drop": int(chosen.get("drop", -1)),
		"pick_kind": kind,
		"forks": fork_rows,
	}


## One action per offer (canonical drop for a full kit) plus skip, in offer
## order with skip last.
func _distinct_forks(game, bot, snap: Dictionary, legal: Array) -> Array:
	var out: Array = []
	var offers: Array = snap["draft_offers"]
	for i in offers.size():
		var group: Array = []
		for a in legal:
			if int(a.get("pick", -2)) == i:
				group.append(a)
		if group.is_empty():
			continue
		if group.size() == 1:
			out.append(group[0])
		else:
			out.append(_drop_choice(game, bot, snap, group, i))
	for a in legal:
		if int(a.get("pick", -2)) == -1:
			out.append(a)
			break
	return out


## The drop action the policy would take for offer `i` if it were the only
## offer: ask the bot on a reduced snapshot/legal pair (rng state and forward
## model restored afterwards); fall back to the mirrored optimizer rule when
## the bot declines the forced offer.
func _drop_choice(game, bot, snap: Dictionary, group: Array, i: int) -> Dictionary:
	var sub_snap := snap.duplicate()
	sub_snap["draft_offers"] = [snap["draft_offers"][i]]
	var sub_legal: Array = []
	for a in group:
		var b: Dictionary = a.duplicate()
		b["pick"] = 0
		sub_legal.append(b)
	sub_legal.append({"type": "draft", "pick": -1})
	var rng_state: int = bot.rng.state
	var uses_sim: bool = bot.has_method("set_sim")
	if uses_sim:
		var g = game.clone()
		g.draft_offers = [snap["draft_offers"][i]]
		bot.set_sim(g)
	var ans: Dictionary = bot.choose_action(sub_snap, sub_legal)
	bot.rng.state = rng_state
	if uses_sim:
		bot.set_sim(game)
	if int(ans.get("pick", -1)) == 0:
		for a in group:
			if int(a.get("drop", -1)) == int(ans.get("drop", -1)):
				return a
	return _least_used_drop(snap, group)


## Mirror of optimizer._draft_choice's drop rule: least-used slot, never
## mycelium_dash or seed_bomb, ties and all-protected -> first candidate.
func _least_used_drop(snap: Dictionary, group: Array) -> Dictionary:
	var uses: Dictionary = snap["player"]["uses"]
	var kit: Array = snap["player"]["kit"]
	var best: Dictionary = group[0]
	var best_u := 1 << 30
	for a in group:
		var slot := int(a["drop"])
		var base := Tally.base_id(String(kit[slot]))
		if base == "mycelium_dash" or base == "seed_bomb":
			continue
		var u := int(uses.get(kit[slot], 0))
		if u < best_u:
			best_u = u
			best = a
	return best


# --- aggregation --------------------------------------------------------------

func _fork_count() -> int:
	var n := 0
	for rec in _records:
		n += rec["forks"].size()
	return n


func _skip_fork(rec: Dictionary) -> Dictionary:
	for f in rec["forks"]:
		if int(f["pick"]) == -1:
			return f
	return {}


## Canonical fork for offer index i (the first fork with that pick, which is
## the canonical-drop one; the real choice is appended after it).
func _offer_fork(rec: Dictionary, i: int) -> Dictionary:
	for f in rec["forks"]:
		if int(f["pick"]) == i:
			return f
	return {}


func _report() -> void:
	if _records.is_empty():
		print("no drafts recorded")
		print(CAVEAT)
		return
	_report_per_offer()
	_report_conditional()
	_report_stakes()
	_report_regret()
	print(CAVEAT)


## Per offer id: paired P(win|pick) - P(win|skip) over the drafts offering it.
func _report_per_offer() -> void:
	var by_id := {}  # id -> {pick: Array[bool], skip: Array[bool], to: int}
	for rec in _records:
		var sk := _skip_fork(rec)
		if sk.is_empty():
			continue
		for i in rec["offers"].size():
			var f := _offer_fork(rec, i)
			if f.is_empty():
				continue
			var id := String(f["id"])
			if not by_id.has(id):
				by_id[id] = {"pick": [], "skip": [], "to": 0}
			by_id[id]["pick"].append(bool(f["won"]))
			by_id[id]["skip"].append(bool(sk["won"]))
			if f["timeout"]:
				by_id[id]["to"] += 1
	var ids: Array = by_id.keys()
	# n desc, id asc
	ids.sort_custom(func(a, b):
		var na: int = by_id[a]["pick"].size()
		var nb: int = by_id[b]["pick"].size()
		return na > nb if na != nb else a < b)
	print("--- per offer: P(win|pick) - P(win|skip), paired within draft ---")
	print("%-16s %4s %7s %7s %7s  %-12s %-12s %5s %s" % [
		"offer", "n", "P(pick)", "P(skip)", "delta", "CI(pick)", "CI(skip)", "+/-", "sign_p"])
	for id in ids:
		var d: Dictionary = by_id[id]
		var n: int = d["pick"].size()
		var wp := _count_true(d["pick"])
		var ws := _count_true(d["skip"])
		var pr := Sweep.paired(d["pick"], d["skip"])
		var to_s := ("  timeouts %d" % d["to"]) if d["to"] > 0 else ""
		print("%-16s %4d %6.0f%% %6.0f%% %+6.0f%%  %-12s %-12s %2d/%-2d %.3f%s" % [
			id, n, 100.0 * wp / n, 100.0 * ws / n, 100.0 * (wp - ws) / n,
			Sweep.fmt_ci(Sweep.wilson(wp, n)), Sweep.fmt_ci(Sweep.wilson(ws, n)),
			pr["only_a"], pr["only_b"], pr["sign_p"], to_s])
	print("           +/- = drafts where only the pick won / only skip won")


## Kit-conditional value per (offer, co-held base id), n >= MIN_N_CONDITIONAL.
func _report_conditional() -> void:
	var by_key := {}  # "offer|held" -> {pick: int, skip: int, n: int}
	for rec in _records:
		var sk := _skip_fork(rec)
		if sk.is_empty():
			continue
		for i in rec["offers"].size():
			var f := _offer_fork(rec, i)
			if f.is_empty():
				continue
			for held in rec["kit_before"]:
				var key := "%s|%s" % [String(f["id"]), String(held)]
				if not by_key.has(key):
					by_key[key] = {"pick": 0, "skip": 0, "n": 0}
				by_key[key]["n"] += 1
				by_key[key]["pick"] += 1 if f["won"] else 0
				by_key[key]["skip"] += 1 if sk["won"] else 0
	var rows: Array = []
	for key in by_key:
		var d: Dictionary = by_key[key]
		if d["n"] >= MIN_N_CONDITIONAL:
			rows.append([key, d["n"], float(d["pick"] - d["skip"]) / float(d["n"]), d["pick"], d["skip"]])
	# delta desc, then n desc, then key asc
	rows.sort_custom(func(a, b):
		if a[2] != b[2]:
			return a[2] > b[2]
		if a[1] != b[1]:
			return a[1] > b[1]
		return a[0] < b[0])
	print("--- kit-conditional value: (offer | co-held base) with n >= %d ---" % MIN_N_CONDITIONAL)
	if rows.is_empty():
		print("           none reach n >= %d (raise ORACLE_SEEDS)" % MIN_N_CONDITIONAL)
		return
	print("%-30s %4s %7s %6s %6s" % ["offer | held", "n", "delta", "w_pick", "w_skip"])
	for r in rows:
		print("%-30s %4d %+6.0f%% %6d %6d" % [r[0], r[1], 100.0 * r[2], r[3], r[4]])


## Stakes per draft (max - min won across forks) by floor entered.
func _report_stakes() -> void:
	var by_floor := {}  # floor -> {n, decisive, all_won, all_lost, turn_spread}
	for rec in _records:
		var fl := int(rec["floor"])
		if not by_floor.has(fl):
			by_floor[fl] = {"n": 0, "decisive": 0, "all_won": 0, "all_lost": 0, "spread": 0}
		var won_max := 0
		var won_min := 1
		var t_min := 1 << 30
		var t_max := 0
		for f in rec["forks"]:
			var w := 1 if f["won"] else 0
			won_max = maxi(won_max, w)
			won_min = mini(won_min, w)
			t_min = mini(t_min, int(f["turns"]))
			t_max = maxi(t_max, int(f["turns"]))
		var d: Dictionary = by_floor[fl]
		d["n"] += 1
		d["spread"] += t_max - t_min
		if won_max != won_min:
			d["decisive"] += 1
		elif won_max == 1:
			d["all_won"] += 1
		else:
			d["all_lost"] += 1
	var floors: Array = by_floor.keys()
	floors.sort()
	print("--- stakes per draft by floor entered (won: max - min across forks) ---")
	print("%-6s %4s %8s %9s %9s %9s %11s" % ["floor", "n", "stakes", "decisive", "all_won", "all_lost", "turn spread"])
	var tot_n := 0
	var tot_dec := 0
	var tot_w := 0
	var tot_l := 0
	for fl in floors:
		var d: Dictionary = by_floor[fl]
		tot_n += d["n"]
		tot_dec += d["decisive"]
		tot_w += d["all_won"]
		tot_l += d["all_lost"]
		print("%-6d %4d %7.2f %9d %9d %9d %11.1f" % [
			fl, d["n"], float(d["decisive"]) / float(d["n"]), d["decisive"], d["all_won"], d["all_lost"],
			float(d["spread"]) / float(d["n"])])
	print("%-6s %4d %7.2f %9d %9d %9d" % ["all", tot_n, _safe_div(tot_dec, tot_n), tot_dec, tot_w, tot_l])
	print("           decisive = some fork wins and some loses; all_won/all_lost = seed-decided")


## Policy regret: wins(best fork) - wins(fork the bot took), summed; plus
## how often skip already matches the best fork.
func _report_regret() -> void:
	var best_wins := 0
	var chosen_wins := 0
	var skip_wins := 0
	var chosen_is_best := 0
	var skip_is_best := 0
	var skip_strict_best := 0
	var kinds := {"new": 0, "upgrade": 0, "skip": 0}
	var regret_by_kind := {"new": 0, "upgrade": 0, "skip": 0}
	var n := 0
	for rec in _records:
		var sk := _skip_fork(rec)
		var chosen := {}
		var bw := 0
		var pick_won_any := false
		for f in rec["forks"]:
			if f["chosen"]:
				chosen = f
			if f["won"]:
				bw = 1
				if int(f["pick"]) >= 0:
					pick_won_any = true
		if chosen.is_empty():
			continue
		n += 1
		var cw := 1 if chosen["won"] else 0
		var sw := 1 if (not sk.is_empty() and sk["won"]) else 0
		best_wins += bw
		chosen_wins += cw
		skip_wins += sw
		if cw == bw:
			chosen_is_best += 1
		if sw == bw:
			skip_is_best += 1
		if sw == 1 and not pick_won_any:
			skip_strict_best += 1
		var k := String(rec["pick_kind"])
		kinds[k] += 1
		regret_by_kind[k] += bw - cw
	print("--- policy regret over %d drafts ---" % n)
	print("           wins: best fork %d  bot pick %d  skip %d   regret %d (%.2f per draft)" % [
		best_wins, chosen_wins, skip_wins, best_wins - chosen_wins, _safe_div(best_wins - chosen_wins, n)])
	print("           bot pick matched best fork %d/%d   skip matched best %d/%d   skip strictly best (every pick lost) %d" % [
		chosen_is_best, n, skip_is_best, n, skip_strict_best])
	print("           picks taken: new %d  upgrade %d  skip %d   regret by kind: new %d  upgrade %d  skip %d" % [
		kinds["new"], kinds["upgrade"], kinds["skip"], regret_by_kind["new"], regret_by_kind["upgrade"], regret_by_kind["skip"]])


func _count_true(arr: Array) -> int:
	var n := 0
	for v in arr:
		if v:
			n += 1
	return n


func _safe_div(a: int, b: int) -> float:
	return float(a) / float(b) if b > 0 else 0.0


func _dump_json(path: String, bot_name: String, cfg: Dictionary, seeds: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return
	f.store_string(JSON.stringify({
		"bot": bot_name, "config": cfg, "seeds": seeds, "records": _records,
	}, "", false))
	f.close()
	print("records written to %s (%d drafts)" % [path, _records.size()])
