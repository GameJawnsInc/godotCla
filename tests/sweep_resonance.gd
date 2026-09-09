extends SceneTree
## Resonance exposure and firing (Block D5, docs/BALANCE.md 2026-09-08).
## One block per `Content.RESONANCES` row, in two modes on the same seeds:
##   locked - a kit built to MEET the row's threshold ({kit: K, pool: K}), i.e.
##            the row at its own REACH ceiling - not its payoff ceiling: the
##            filler grafts are taken in Content.GRAFTS table order, and a
##            graft whose own hook fires on the same kind PRE-EMPTS the row,
##            because Game._hook scans grafts BEFORE resonances. cinder_grip
##            is exactly that case (see RESONANCE_GRAFTS below). It is still
##            the only way a search
##            persona ever sees one (deeproot's own drafting does not reach the
##            shipped threshold in 30 seeds)
##   free   - the run config as it ships, i.e. the reach the persona's own
##            drafting produces
## and reports, per row: runs that met the threshold, the floor it was first
## met on, the share of turns it was active, how many times a hook row FIRED,
## and how many of those firings LANDED.
##
## The last column is why this runner exists. `hook_uses` is charged BEFORE a
## hook row's effects run, so `hooks_by_resonance` counts TRIGGERS: a row that
## fires onto empty tiles all run looks identical to one that works. D5 shipped
## one row and cut two - one of them, the displace row, on the landed number -
## and every landed number in that entry came from a throwaway probe. Landing is read here as the event
## immediately after each `{t: "hook"}`, matched against what THAT row's own
## effects emit - `status_at` a `{t: "status"}` carrying its own status,
## `damage_at` a `{t: "damage"}` whose `src` is the resonance id, `terrain_at`
## a `{t: "terrain"}` of its own kind. The looser "any status, damage or
## terrain event" rule also counts the ENCLOSING effect's next event and
## over-reads by about 3x (286 cinder_grip hooks read 64 landings loose
## against 24 strict, and 24 is what the paired on/off control measured).
##
## Run: [RESONANCE_BOT=optimizer] [RESONANCE_SEEDS=30] [RESONANCE_SEED_FROM=1]
##      [RESONANCE_ROWS=a,b] [RESONANCE_MODE=both|locked|free]
##      [RESONANCE_GRAFTS=a,b - replace the locked mode's filler grafts, so a
##       row can be measured against a partner that does not pre-empt it;
##       the default is unchanged, so every number already recorded stands]
##      [RESONANCE_GATE=0] godot --headless --path . --script tests/sweep_resonance.gd
## The three `Sweep.env_config` axes (SWEEP_TIER / SWEEP_LOADOUT /
## SWEEP_UNLOCK) apply to the free mode; the locked mode names its own kit.
##
## Gate (RESONANCE_GATE=0 disables): a row with `hooks` must fire at least
## MIN_HOOKS_PER_RUN times a run on the kit built for it. That is the D5 design
## phase's own pre-registered cut line ("fewer than 30 over the 30 optimizer
## runs - under 1.0 per run - ... it should be cut rather than shipped as a
## fourth dead row"), which the cut `follow_through` row failed at 0.73 and the
## shipped `cinder_grip` clears at 9.53. A `stat` or `mod` row has no firing to
## count and is exposure-only; it is never gated here.

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Roster := preload("res://bots/roster.gd")
const Tally := preload("res://tests/tally.gd")

## Ops whose landing this runner can attribute exactly. An op outside the list
## makes the row's landed column approximate and says so.
const LANDING_OPS := ["status_at", "damage_at", "terrain_at"]
## Pre-registered D5 cut line, per run, on the locked kit (see the doc block).
const MIN_HOOKS_PER_RUN := 1.0
## Filler for a locked kit: every Content.LOADOUTS kit holds seed_bomb and one
## mobility ability, so a hand-built kit that holds neither is not a kit any
## run could have. Added only when the carriers leave room.
const KIT_FILLER := ["seed_bomb", "mycelium_dash"]
const KIT_MAX := 4


func _init() -> void:
	var bot_name := "optimizer"
	if OS.get_environment("RESONANCE_BOT") != "":
		bot_name = OS.get_environment("RESONANCE_BOT")
	elif OS.get_environment("SWEEP_BOT") != "":
		bot_name = Sweep.pick_bot_name()
	if not Roster.has(bot_name):
		push_error("unknown bot '%s' (have: %s)" % [bot_name, ", ".join(Roster.names())])
		quit(1)
		return
	var n_seeds := 30
	if OS.get_environment("RESONANCE_SEEDS") != "":
		n_seeds = int(OS.get_environment("RESONANCE_SEEDS"))
	var first := Sweep.seed_from()
	if OS.get_environment("RESONANCE_SEED_FROM") != "":
		first = int(OS.get_environment("RESONANCE_SEED_FROM"))
	var seeds := Sweep.seed_list_from(n_seeds, first)
	var mode := OS.get_environment("RESONANCE_MODE")
	if mode == "":
		mode = "both"
	var rows: Array = Content.RESONANCES.keys()
	if OS.get_environment("RESONANCE_ROWS") != "":
		rows = Array(OS.get_environment("RESONANCE_ROWS").split(","))
		for rid in rows:
			if not Content.RESONANCES.has(rid):
				push_error("unknown resonance '%s' (have: %s)" % [rid, ", ".join(Content.RESONANCES.keys())])
				quit(1)
				return
	var free_cfg := Sweep.env_config({})
	print(Sweep.header("sweep_resonance", bot_name, free_cfg, seeds))
	print("landing = the event after each {t: \"hook\"} matched against that row's own effects"
		+ " (ops %s); `resisted` is a refused landing" % ", ".join(LANDING_OPS))

	var free_run := {}
	if mode != "locked":
		free_run = _run(seeds, free_cfg, bot_name)
	var failures: Array = []
	for rid in rows:
		var row: Dictionary = Content.RESONANCES[rid]
		var has_hooks: bool = row.has("hooks")
		var shape := "hooks on %s" % ", ".join(_hook_kinds(row)) if has_hooks else \
			("stat %s" % str(row.get("stat", {})) if row.has("stat") else "mod %s" % str(row.get("mod", {})))
		print("\n%s  %s >= %d  (%s)" % [rid, row["tag"], int(row["need"]), shape])
		if mode != "free":
			var cfg := _locked_config(row, free_cfg)
			if cfg.is_empty():
				print("  locked   SKIPPED: the table cannot build a kit that meets this row")
			else:
				print("  locked   kit %s  grafts %s" % [str(cfg["kit"]), str(cfg.get("grafts", []))])
				var m := _run(seeds, cfg, bot_name)
				for line in _report(rid, row, m, seeds.size()):
					print("           %s" % line)
				if has_hooks:
					var per_run := float(int(m["fired"].get(rid, 0))) / float(maxi(1, seeds.size()))
					if per_run < MIN_HOOKS_PER_RUN:
						failures.append("%s fires %.2f/run on its own kit (line: %.1f)"
							% [rid, per_run, MIN_HOOKS_PER_RUN])
		if mode != "locked":
			for line in _report(rid, row, free_run, seeds.size()):
				print("  free     %s" % line)

	if not failures.is_empty() and OS.get_environment("RESONANCE_GATE") != "0":
		print("\nFAIL (D5 cut line): %s" % "; ".join(failures))
		quit(1)
		return
	if not failures.is_empty():
		print("\ngate disabled (RESONANCE_GATE=0); would fail: %s" % "; ".join(failures))
	print("\nsweep_resonance: %d row(s), %d seeds, bot %s" % [rows.size(), seeds.size(), bot_name])
	quit(0)


## What one resonance row's hook effects emit when they LAND: one matcher dict
## per effect, every key of which must equal the event's. An effect whose op is
## outside LANDING_OPS yields a bare {"t": ""} matcher, which matches nothing
## and is reported as `approx` on the row.
func _landing_matchers(rid: String, row: Dictionary) -> Array:
	var out: Array = []
	for h in row.get("hooks", []):
		for eff in h.get("effects", []):
			match String(eff.get("op", "")):
				"status_at":
					out.append({"t": "status", "status": String(eff["status"])})
				"damage_at":
					out.append({"t": "damage", "src": rid})
				"terrain_at":
					out.append({"t": "terrain", "kind": String(eff["kind"])})
				_:
					out.append({"t": ""})
	return out


func _matches(ev: Dictionary, matcher: Dictionary) -> bool:
	if String(matcher["t"]) == "":
		return false
	for k in matcher:
		if String(ev.get(k, "")) != String(matcher[k]):
			return false
	return true


## Hook kinds a row fires on, for the header line only.
func _hook_kinds(row: Dictionary) -> Array:
	var kinds: Array = []
	for h in row.get("hooks", []):
		var k := String(h.get("on", ""))
		if not kinds.has(k):
			kinds.append(k)
	return kinds


## A locked config whose kit meets `row`: the draft-pool bases carrying the tag
## first (a run can hold those), then tag-carrying grafts if the bases run out.
## Returns {} when the table cannot reach `need` at all - the same condition
## tests/test_content.gd's reach lint fails on, checked here against ONE run's
## holdings rather than against the table.
func _locked_config(row: Dictionary, base: Dictionary) -> Dictionary:
	var tag := String(row["tag"])
	var need := int(row["need"])
	var kit: Array = []
	for aid in Content.DRAFT_POOL:
		if kit.size() >= mini(need, KIT_MAX):
			break
		if Content.ABILITIES.get(aid, {}).get("tags", []).has(tag):
			kit.append(aid)
	var grafts: Array = []
	var held := kit.size()
	var forced := OS.get_environment("RESONANCE_GRAFTS")
	if forced != "":
		# Measure the row against a named partner instead of whichever tagged
		# graft comes first in the table. Unknown ids are dropped by Game.new
		# with a warning, so a typo cannot silently change the threshold.
		for gid in forced.split(","):
			if Content.GRAFTS.has(gid) and not grafts.has(gid):
				grafts.append(gid)
				held += 1
	else:
		for gid in Content.GRAFTS:
			if held >= need:
				break
			if Content.GRAFTS[gid].get("tags", []).has(tag):
				grafts.append(gid)
				held += 1
	if held < need:
		return {}
	for aid in KIT_FILLER:
		if kit.size() < KIT_MAX and not kit.has(aid):
			kit.append(aid)
	var cfg := Sweep.locked_config(kit, base)
	if not grafts.is_empty():
		cfg["grafts"] = grafts
	return cfg


## One measured config: wins, the tally (for the exposure columns the sim
## itself samples) and the fired/landed/refused counters this runner adds.
## The loop mirrors Sweep.run_loop; it is spelled out here because run_loop
## consumes the event stream and this runner needs to look at the event AFTER
## a hook.
func _run(seeds: Array, cfg: Dictionary, bot_name: String) -> Dictionary:
	var matchers := {}
	for rid in Content.RESONANCES:
		matchers[rid] = _landing_matchers(String(rid), Content.RESONANCES[rid])
	var tally := Tally.new()
	var wins := 0
	var timeouts := 0
	var fired := {}
	var landed := {}
	var refused := {}
	for s in seeds:
		var game = Game.new(int(s), cfg)
		var bot := Roster.make(bot_name, int(s))
		if bot.has_method("set_sim"):
			bot.set_sim(game)
		var actions := 0
		while not game.over and actions < Sweep.MAX_ACTIONS and game.total_turns < Sweep.MAX_TURNS:
			tally.begin_step(game)
			var act: Dictionary = bot.choose_action(game.snapshot(), game.legal_actions())
			var events: Array = game.step(act)
			for i in events.size():
				var ev: Dictionary = events[i]
				tally.add(ev, act, game)
				if String(ev.get("t", "")) != "hook":
					continue
				var rid := String(ev.get("id", ""))
				if not Content.RESONANCES.has(rid):
					continue
				fired[rid] = int(fired.get(rid, 0)) + 1
				if i + 1 >= events.size():
					continue
				var nxt: Dictionary = events[i + 1]
				if String(nxt.get("t", "")) == "resisted":
					refused[rid] = int(refused.get(rid, 0)) + 1
					continue
				for matcher in matchers.get(rid, []):
					if _matches(nxt, matcher):
						landed[rid] = int(landed.get(rid, 0)) + 1
						break
			tally.end_step(game, act)
			actions += 1
		tally.finish(game)
		if game.won:
			wins += 1
		elif not game.over:
			timeouts += 1
	return {"wins": wins, "timeouts": timeouts, "tally": tally,
		"fired": fired, "landed": landed, "refused": refused}


## Exposure + firing lines for one row of one measured config.
func _report(rid: String, row: Dictionary, m: Dictionary, n: int) -> Array:
	if m.is_empty():
		return []
	var t = m["tally"]
	var nf := float(maxi(1, n))
	var reached := int(t.resonance_runs.get(rid, 0))
	var out: Array = []
	if reached == 0:
		out.append("met 0/%d runs" % n)
	else:
		out.append("met %d/%d runs from floor ~%.1f, %.0f%% of turns, %d break(s)" % [
			reached, n, float(t.resonance_first_floor.get(rid, 0)) / float(reached),
			100.0 * float(t.resonance_turns.get(rid, 0)) / float(maxi(1, t.end_turn_count)),
			int(t.resonance_breaks.get(rid, 0))])
	if row.has("hooks"):
		var f := int(m["fired"].get(rid, 0))
		var l := int(m["landed"].get(rid, 0))
		var approx := ""
		for matcher in _landing_matchers(rid, row):
			if String(matcher["t"]) == "":
				approx = "  (approx: an op outside %s)" % ", ".join(LANDING_OPS)
		out.append("fired %d (%.2f/run)  landed %d (%.2f/run = %.1f%%)  refused %d  enemy dmg %d%s" % [
			f, float(f) / nf, l, float(l) / nf, 100.0 * float(l) / float(maxi(1, f)),
			int(m["refused"].get(rid, 0)), int(t.enemy_dmg_by_src.get(rid, 0)), approx])
	else:
		out.append("no hooks: exposure only (a %s row pays on the turns it is active)"
			% ("stat" if row.has("stat") else "mod"))
	out.append("wins %d/%d %s  timeouts %d" % [
		int(m["wins"]), n, Sweep.fmt_ci(Sweep.wilson(int(m["wins"]), n)), int(m["timeouts"])])
	return out
