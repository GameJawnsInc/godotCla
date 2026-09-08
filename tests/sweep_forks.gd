extends SceneTree
## Block D6 fork acceptance sweep: are the two named variants of a base
## genuinely a CHOICE, or is one of them a strictly worse card?
##
## Every `+` row of the fifteen base-pool abilities forked into two named
## variants ("<base>+<word>"): variant A reproduces the pre-D6 `+` row exactly
## and variant B is the fork. The roadmap's acceptance clause for that block is
## "no strictly dominated sibling at 30 seeds", and this runner is the
## instrument that answers it.
##
## WHY LOCKED KITS AND NOT A PLAYTEST. No heuristic persona forges (BALANCE.md
## records 0/0 upcycles for every persona in every run), the descent draft
## deals a base's variant A on even floors and B on odd, and five of the
## fifteen bases (root_wall, overgrowth, bramble_coat, anchor_roots,
## pollen_burst) are cast by no persona at all in an open-pool run. Read off a
## playtest, the acceptance clause would pass VACUOUSLY on those pairs. So each
## sibling is measured as a LOCKED kit instead ({kit: K, pool: K}: the bot
## never drafts, so the row measures the card and not the draft policy), and a
## pair whose siblings are still never cast is reported UNREAD, never as a pass.
##
## Per base, three configs on the same seeds, all locked:
##   base      STARTING_KIT with `base` in place (or appended when the starter
##             does not hold it) - the un-upgraded reference
##   variant A same kit with A substituted for the base
##   variant B same kit with B substituted for the base
## For solar_lance / seed_bomb / mycelium_dash the kit stays 3 abilities and
## the base row IS the plain starter kit; for the twelve pool bases the kit is
## the 4-ability starter + base, exactly the shape tests/sweep_combos.gd uses
## for its singles.
##
## THE VERDICT, DEFINED PRECISELY AND IMPLEMENTED EXACTLY AS WRITTEN.
## Sibling S is STRICTLY DOMINATED by its sibling T when BOTH hold:
##   (1) separation: S's Wilson 95% interval lies entirely below T's -
##       ci_S.hi < ci_T.lo (no overlap at all, not "the point estimate is
##       lower"), AND
##   (2) pairing: the two-sided exact sign test over the discordant seeds
##       (seeds T won and S lost, against seeds S won and T lost) has
##       p < FLAG_P (0.05) AND favours T (more discordant seeds go to T).
## Anything else is "not separated at this N", which is a PASS - including a
## visible point-estimate gap. That is not a weak answer, it is the honest one:
## a Wilson half-width on 30 seeds is about +/-17 percentage points near 50%,
## so two siblings would have to differ by roughly 35 points before this rule
## can see it. Read the printed noise band before quoting any per-fork verdict.
## (BALANCE.md 2026-09-07g retired two gate lines in one block for being
## mis-specified; a gate line whose noise band has not been stated is not a
## gate line.)
##
## SECONDARY COLUMNS carried for the roadmap's solo-check clause ("solo-check
## every shield, thorns or growth-writing variant"): stall floors, timeouts,
## turns, damage taken, quota-unmet deaths and casts/run of the locked variant
## itself. Rows whose variant writes growth or roots, grants shield or grants
## thorns are marked `*` and repeated in a stall-vector block at the end, since
## a repeatable terrain or defence generator is a stall vector before it is a
## win-rate question.
##
## THREE PAIRS ARE STRUCTURALLY SKEWED ON EFFECTIVE CASTS and the runner says
## so: the ops `shield`, `anchor` and `undim` set no outcome counter, so
## thorn_shield+plate, anchor_roots+bedrock and moss_filter+sieve can NEVER be
## an effective cast while their siblings chaff / heave / prism always can.
## Read those three pairs on wins, damage taken and stall floors only.
##
## Run: [FORKS_BOT=deeproot] [FORKS_SEEDS=30] [FORKS_SEED_FROM=101]
##      [FORKS_BASES=solar_lance,seed_bomb]
##      [SWEEP_TIER=2] [SWEEP_LOADOUT=spiker] [SWEEP_UNLOCK=fresh]
##      godot --headless --path . --script tests/sweep_forks.gd
##   FORKS_BOT       roster persona (default optimizer; unknown -> push_error
##                   and the header says UNKNOWN, it never silently defaults)
##   FORKS_SEEDS     seed count (default 30), FORKS_SEED_FROM the first seed
##                   (default 1) - out-of-sample checks
##   FORKS_BASES     comma list of bases to measure (default: every base whose
##                   Content.variants_of returns 2 or more, in table order)
## SWEEP_TIER / SWEEP_LOADOUT / SWEEP_UNLOCK go through Sweep.env_config as in
## every other runner; the explicit `kit` always wins over a loadout, so
## SWEEP_LOADOUT changes only the config header here.
## Runtime: optimizer ~0.2 s/run -> 15 bases x 3 configs x 30 seeds ~5 min.
## deeproot is ~4 s/run: narrow with FORKS_BASES.

const Content := preload("res://sim/content.gd")
const Roster := preload("res://bots/roster.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Tally := preload("res://tests/tally.gd")

const SEEDS := 30
const FLAG_P := 0.05

## Ops whose presence makes a variant a stall-vector solo check: it writes
## terrain that can be stood on or hidden behind, or it grants shield/thorns.
## Read off the shipped effects, never a hand-listed id set.
const STALL_OPS := ["grow_radius", "grow_wall", "plant_origin", "convert_radius",
	"create_terrain", "shield", "thorns"]

const CAVEAT_SKEW := "effective casts are NOT comparable within the plate/chaff, bedrock/heave and sieve/prism pairs: shield, anchor and undim set no outcome counter, so the A sibling can never register one - read those three on wins, damage taken and stall floors"


func _init() -> void:
	var bot_name := _bot_name()
	var bot = _bot()
	var seeds := _seeds()
	var cfg := Sweep.env_config({})
	var bases := _base_list()
	print(Sweep.header("sweep_forks", bot_name, cfg, seeds))
	if bot == null or bot_name.begins_with("UNKNOWN"):
		print("FAIL: unknown FORKS_BOT '%s' (roster: %s)" % [OS.get_environment("FORKS_BOT"), ", ".join(Roster.names())])
		quit(1)
		return
	if bases.is_empty():
		print("FAIL: no forked bases selected (bad FORKS_BASES?)")
		quit(1)
		return
	var n := seeds.size()
	print("bases %d | %s" % [bases.size(), ", ".join(bases)])
	print(CAVEAT_SKEW)
	print(Sweep.CAVEAT_LOCKED)
	print("noise band: a Wilson 95%% half-width at %d seeds is about %.0f points near 50%% and %.0f points near 20%% - two siblings must differ by roughly twice that before DOMINATED can fire" % [
		n, 100.0 * _half_width(int(round(n * 0.5)), n), 100.0 * _half_width(int(round(n * 0.2)), n)])
	print("DOMINATED = the loser's Wilson interval lies entirely below the winner's AND the paired sign test favours the winner at p < %.2f; everything else is 'not separated at this N', which is a PASS" % FLAG_P)

	var rows: Array = []
	for base in bases:
		rows.append(_pair_row(String(base), seeds, cfg, bot))
	_print_table(rows, n)
	_print_stall_block(rows, n)
	_print_verdict(rows, n)
	print(Sweep.CAVEAT_LOCKED)
	quit(0)


# --- selection ---------------------------------------------------------------

func _bot_name() -> String:
	var v := OS.get_environment("FORKS_BOT")
	if v == "":
		return Sweep.pick_bot_name()
	if Roster.has(v):
		return v
	return "UNKNOWN:" + v


func _bot():
	var v := OS.get_environment("FORKS_BOT")
	if v == "":
		return Sweep.pick_bot()
	if not Roster.has(v):
		push_error("unknown FORKS_BOT '%s' (roster: %s)" % [v, ", ".join(Roster.names())])
		return null
	return v


## FORKS_SEEDS / FORKS_SEED_FROM, falling back to the SWEEP_* pair every other
## runner honours.
func _seeds() -> Array:
	var count := SEEDS
	var cv := OS.get_environment("FORKS_SEEDS")
	if cv != "":
		count = int(cv)
	elif OS.get_environment("SWEEP_SEEDS") != "":
		count = int(OS.get_environment("SWEEP_SEEDS"))
	var first := Sweep.seed_from()
	var fv := OS.get_environment("FORKS_SEED_FROM")
	if fv != "":
		first = int(fv)
	return Sweep.seed_list_from(count, first)


## Every base carrying two or more variants, in ABILITIES table order, or the
## FORKS_BASES subset. A base with a single variant (the nine package
## abilities, which are deliberately not forked) has no pair to compare and is
## never selected: variants_of returns a 1-list there and the question does
## not arise.
func _base_list() -> Array:
	var forked: Array = []
	for aid in Content.ABILITIES.keys():
		var key := String(aid)
		if Content.is_upgrade(key):
			continue
		if Content.variants_of(key).size() >= 2:
			forked.append(key)
	var v := OS.get_environment("FORKS_BASES")
	if v == "":
		return forked
	var out: Array = []
	for item in v.split(",", false):
		var b := String(item).strip_edges()
		if b == "":
			continue
		if not forked.has(b):
			push_error("FORKS_BASES entry '%s' is not a forked base (have: %s)" % [b, ", ".join(forked)])
			return []
		if not out.has(b):
			out.append(b)
	return out


## STARTING_KIT with `base` replaced by `aid` in place, or `aid` appended when
## the starter does not hold the base. In-place replacement matters: for a
## starter base the reference row is then byte-identical to the plain starter
## kit, slot order included.
func _kit_for(base: String, aid: String) -> Array:
	var out: Array = Content.STARTING_KIT.duplicate()
	var idx := out.find(base)
	if idx >= 0:
		out[idx] = aid
	else:
		out.append(aid)
	return out


# --- one pair -----------------------------------------------------------------

func _pair_row(base: String, seeds: Array, cfg: Dictionary, bot) -> Dictionary:
	var vs: Array = Content.variants_of(base)
	var a := String(vs[0])
	var b := String(vs[1])
	var m_base := Sweep.measure(seeds, Sweep.locked_config(_kit_for(base, base), cfg), bot)
	var m_a := Sweep.measure(seeds, Sweep.locked_config(_kit_for(base, a), cfg), bot)
	var m_b := Sweep.measure(seeds, Sweep.locked_config(_kit_for(base, b), cfg), bot)
	# discordant: seeds A won and B lost (only_a) against B won and A lost
	var d := Sweep.paired(m_a["wins_by_seed"], m_b["wins_by_seed"])
	return {
		"base": base, "a": a, "b": b,
		"n": seeds.size(),
		"m_base": m_base, "m_a": m_a, "m_b": m_b,
		"discordant": d,
		"verdict": _verdict(a, b, m_a, m_b, d),
		"stall_check": _stall_ids(a, b),
	}


## The DOMINATED rule, exactly as the header defines it. Returns
## "A DOMINATED", "B DOMINATED" or "not separated".
func _verdict(a: String, b: String, m_a: Dictionary, m_b: Dictionary, d: Dictionary) -> String:
	var ci_a: Vector2 = m_a["ci"]
	var ci_b: Vector2 = m_b["ci"]
	var p := float(d["sign_p"])
	if p >= FLAG_P:
		return "not separated"
	if ci_a.y < ci_b.x and int(d["only_b"]) > int(d["only_a"]):
		return "%s DOMINATED" % a
	if ci_b.y < ci_a.x and int(d["only_a"]) > int(d["only_b"]):
		return "%s DOMINATED" % b
	return "not separated"


## Which of the two variants are stall-vector solo checks: any variant whose
## effects carry a STALL_OPS op (writes standable terrain, grants shield or
## grants thorns). Derived from the shipped rows, never a hand-listed set.
func _stall_ids(a: String, b: String) -> Array:
	var out: Array = []
	for aid in [a, b]:
		if _writes_stall(String(aid)):
			out.append(String(aid))
	return out


func _writes_stall(aid: String) -> bool:
	var adef: Dictionary = Content.ABILITIES.get(aid, {})
	for eff in adef.get("effects", []):
		if STALL_OPS.has(String(eff.get("op", ""))):
			return true
		for sub in eff.get("then", []):
			if STALL_OPS.has(String(sub.get("op", ""))):
				return true
	return false


# --- printing -------------------------------------------------------------------

func _print_table(rows: Array, n: int) -> void:
	print("\nfork acceptance table (%d bases x 3 locked configs x %d seeds); base row = the un-upgraded reference kit" % [rows.size(), n])
	print("  %-24s %8s %-14s %7s %6s %5s %5s %6s %6s %6s" % [
		"config (kit id)", "wins", "CI", "casts/r", "eff/r", "stall", "t/o", "turns", "dmg", "floor"])
	for r in rows:
		var d: Dictionary = r["discordant"]
		print("  %s" % r["base"])
		print("    %-22s %s" % ["(base)", _row_line(r["m_base"], r["base"], n)])
		print("    %-22s %s%s" % [_short(r["a"]), _row_line(r["m_a"], r["a"], n), _mark(r, r["a"])])
		print("    %-22s %s%s" % [_short(r["b"]), _row_line(r["m_b"], r["b"], n), _mark(r, r["b"])])
		print("    A vs B: %+d wins, discordant %d:%d (A only : B only) p=%.2f  ->  %s" % [
			int(r["m_a"]["wins"]) - int(r["m_b"]["wins"]), d["only_a"], d["only_b"], d["sign_p"], r["verdict"]])


func _row_line(m: Dictionary, aid: String, n: int) -> String:
	var t = m["tally"]
	var k := Tally.kpis(t, int(m["n"]), m["kits"])
	var casts := float(int(k["casts_by_id"].get(aid, 0))) / maxf(1.0, float(n))
	var eff := float(int(k["effective_casts_by_id"].get(aid, 0))) / maxf(1.0, float(n))
	# turns is the mean over WINS only, so it reads 0 for a config that never
	# won - read avg floor beside it, never alone.
	return "%2d/%-4d %-14s %7.2f %6.2f %5d %5d %6.0f %6.1f %6.1f" % [
		m["wins"], n, Sweep.fmt_ci(m["ci"]), casts, eff,
		t.stall_floors, m["timeouts"], m["mean_turns_on_wins"], m["mean_dmg_taken"], m["avg_floor"]]


func _mark(r: Dictionary, aid: String) -> String:
	return "  *" if r["stall_check"].has(aid) else ""


func _short(aid: String) -> String:
	return aid


## The roadmap's solo-check clause, read off the same runs: every variant that
## writes standable terrain or grants shield/thorns, with the stall columns
## beside its sibling's.
func _print_stall_block(rows: Array, n: int) -> void:
	print("\nstall-vector solo checks (* rows: a variant whose effects write growth/roots/smoke or grant shield/thorns)")
	print("  %-24s %8s %6s %5s %5s %6s %6s %6s" % ["variant", "wins", "stall", "t/o", "qu", "turns", "dmg", "floor"])
	var any := false
	for r in rows:
		for aid in r["stall_check"]:
			any = true
			var m: Dictionary = r["m_a"] if aid == r["a"] else r["m_b"]
			var sib: Dictionary = r["m_b"] if aid == r["a"] else r["m_a"]
			var sib_id: String = String(r["b"]) if aid == r["a"] else String(r["a"])
			print("  %-24s %2d/%-4d %6d %5d %5d %6.0f %6.1f %6.1f   (sibling %s: stall %d, t/o %d, turns %.0f)" % [
				aid, m["wins"], n, m["tally"].stall_floors, m["timeouts"],
				m["tally"].quota_unmet_deaths, m["mean_turns_on_wins"], m["mean_dmg_taken"], m["avg_floor"],
				sib_id, sib["tally"].stall_floors, sib["timeouts"], sib["mean_turns_on_wins"]])
	if not any:
		print("  (none selected)")


func _print_verdict(rows: Array, n: int) -> void:
	var dominated: Array = []
	var unread: Array = []
	var timeouts := 0
	for r in rows:
		if String(r["verdict"]).ends_with("DOMINATED"):
			dominated.append("%s: %s" % [r["base"], r["verdict"]])
		var ka := _casts(r["m_a"], String(r["a"]))
		var kb := _casts(r["m_b"], String(r["b"]))
		if ka == 0 and kb == 0:
			unread.append(r["base"])
		timeouts += int(r["m_a"]["timeouts"]) + int(r["m_b"]["timeouts"]) + int(r["m_base"]["timeouts"])
	print("\n=== fork acceptance: %d pairs at %d seeds ===" % [rows.size(), n])
	print("dominated siblings: %s" % ("none" if dominated.is_empty() else ", ".join(dominated)))
	print("UNREAD pairs (0 casts of BOTH siblings - the acceptance clause cannot be evaluated for these, they are not passes): %s" % (
		"none" if unread.is_empty() else ", ".join(unread)))
	print("timeouts across every config: %d" % timeouts)
	print("verdict: %s" % ("PASS - no strictly dominated sibling at this N" if dominated.is_empty() else "HOLD - " + ", ".join(dominated)))


func _casts(m: Dictionary, aid: String) -> int:
	return int(m["tally"].casts_by_id.get(aid, 0))


## Wilson half-width for w wins in n runs, as a fraction - the printed noise
## band, computed with the same helper the table's intervals use.
func _half_width(w: int, n: int) -> float:
	var ci: Vector2 = Sweep.wilson(w, n)
	return 0.5 * (ci.y - ci.x)
