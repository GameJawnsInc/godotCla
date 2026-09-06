extends RefCounted
## Shared runner for balance sweeps and every batch script (review §7.1):
## one run loop, one bot roster, one tally, one set of statistics helpers.
##
## Env vars honoured by every runner that goes through this library:
##   SWEEP_BOT       roster persona (default optimizer; unknown -> push_error)
##   SWEEP_SEEDS     seed count for runners that call seed_list()
##   SWEEP_SEED_FROM first seed (default 1) - out-of-sample checks
##   SWEEP_TIER      difficulty tier merged into configs via env_config()
##   SWEEP_LOADOUT   starting loadout id (Content.LOADOUTS), via env_config()
##   SWEEP_UNLOCK    unlock state, via env_config(): fresh | package:<id> | all

const Game := preload("res://sim/game.gd")
const Content := preload("res://sim/content.gd")
const Roster := preload("res://bots/roster.gd")
const Tally := preload("res://tests/tally.gd")

const MAX_ACTIONS := 4000
const MAX_TURNS := 400

## Locked-kit configs ({kit: K, pool: K}) pair with open-pool runs again since
## bump 2: the shrine's ability and graft draws moved to _side_rng, so mapgen
## is the only main-rng consumer at floor entry and any kit/pool/graft/bloom
## config starts a seed from the same map and rng state. Rows still diverge
## downstream through play, and numbers from either side of the bump never mix.
const CAVEAT_LOCKED := "locked configs {kit: K, pool: K} start a seed from the same floor-1 map and rng state as any other config (bump 2 moved the shop draws to _side_rng); rows diverge downstream through play, and pre-bump-2 numbers never pair with post-bump-2 ones"


# --- bot selection ------------------------------------------------------------

## Roster name resolved from SWEEP_BOT: "optimizer" when unset,
## "UNKNOWN:<value>" when the value is not on the roster (runner headers show
## the mistake instead of silently measuring the default bot).
static func pick_bot_name() -> String:
	var v := OS.get_environment("SWEEP_BOT")
	if v == "":
		return "optimizer"
	if Roster.has(v):
		return v
	return "UNKNOWN:" + v


## Bot script selected by SWEEP_BOT; null (after push_error) on an unknown
## name. Roster props (e.g. deeproot_rollout) are re-attached by _make_bot,
## which recognises the SWEEP_BOT entry when handed its script.
static func pick_bot() -> GDScript:
	var v := OS.get_environment("SWEEP_BOT")
	if v == "":
		return Roster.script("optimizer")
	return Roster.script(v)


## Instantiate a bot for a seed from a roster name (String), a raw script
## (GDScript) or null (optimizer). Falls back to the optimizer after a
## push_error on an unknown name so a runner still reaches quit().
static func _make_bot(bot_ref, seed_v: int) -> RefCounted:
	if bot_ref is String:
		var b := Roster.make(String(bot_ref), seed_v)
		return b if b != null else Roster.make("optimizer", seed_v)
	if bot_ref is GDScript:
		var env_name := OS.get_environment("SWEEP_BOT")
		if Roster.has(env_name) and Roster.BOTS[env_name]["script"] == bot_ref:
			return Roster.make(env_name, seed_v)
		return Roster.make_from(bot_ref, seed_v)
	return Roster.make("optimizer", seed_v)


## Display name for whatever run_one/measure was handed.
static func bot_label(bot_ref) -> String:
	if bot_ref is String:
		return bot_ref
	if bot_ref is GDScript:
		var env_name := OS.get_environment("SWEEP_BOT")
		if Roster.has(env_name) and Roster.BOTS[env_name]["script"] == bot_ref:
			return env_name
		var n := Roster.name_of(bot_ref)
		return n if n != "" else "custom"
	return "optimizer"


# --- the run loop --------------------------------------------------------------

## The one shared loop: drive `game` with `bot` until it ends or hits the
## action/turn cap, feeding every event to `tally` (a fresh Tally when null).
## `actions_out`, when an Array, receives every action taken (replay logs).
## `timeout` is its own outcome, never counted as a loss by callers.
static func run_loop(game, bot, tally = null, actions_out = null) -> Dictionary:
	if tally == null:
		tally = Tally.new()
	if bot.has_method("set_sim"):
		bot.set_sim(game)
	var actions := 0
	var dmg_taken := 0
	while not game.over and actions < MAX_ACTIONS and game.total_turns < MAX_TURNS:
		tally.begin_step(game)
		var act: Dictionary = bot.choose_action(game.snapshot(), game.legal_actions())
		if actions_out is Array:
			actions_out.append(act)
		var events: Array = game.step(act)
		for ev in events:
			tally.add(ev, act, game)
			if String(ev.get("t", "")) == "damage" and String(ev.get("who", "")) == "player":
				dmg_taken += int(ev.get("amt", 0))
		tally.end_step(game, act)
		actions += 1
	tally.finish(game)
	return {
		"won": game.won, "floor": game.floor_num, "turns": game.total_turns,
		"kit": game.player["kit"].duplicate(),
		"timeout": not game.over,
		"bloom_end": game.bloom, "smog_end": game.smog,
		"dmg_taken": dmg_taken,
		"quota_unmet": game.over and not game.won and game.greened < game.green_need,
		"cause": game.death_cause,
		"actions": actions,
		"tally": tally,
	}


static func run_one(seed_v: int, config: Dictionary = {}, bot_ref = null) -> Dictionary:
	var game = Game.new(seed_v, config)
	var bot := _make_bot(bot_ref, seed_v)
	var r := run_loop(game, bot)
	r["seed"] = seed_v
	if bot.has_method("get_build"):
		r["build"] = bot.get_build()
	return r


## `seeds`: an int (count, starting at SWEEP_SEED_FROM or 1) or an Array of
## seed values. Old keys (wins, n, avg_floor, win_kits) are preserved.
static func measure(seeds, config: Dictionary = {}, bot_ref = null) -> Dictionary:
	var seed_arr: Array = seeds if seeds is Array else seed_list_from(int(seeds), seed_from())
	var wins := 0
	var floors := 0
	var timeouts := 0
	var win_kits: Array = []
	var kits: Array = []
	var wins_by_seed: Array = []
	var turns_on_wins := 0
	var dmg := 0
	var runs: Array = []
	var tally := Tally.new()
	for s in seed_arr:
		var r := run_one(int(s), config, bot_ref)
		runs.append(r)
		tally.merge(r["tally"])
		kits.append(r["kit"])
		wins_by_seed.append(bool(r["won"]))
		floors += int(r["floor"])
		dmg += int(r["dmg_taken"])
		if r["won"]:
			wins += 1
			win_kits.append(r["kit"])
			turns_on_wins += int(r["turns"])
		elif r["timeout"]:
			timeouts += 1
	var n := seed_arr.size()
	return {
		"wins": wins, "n": n,
		"avg_floor": 0.0 if n == 0 else float(floors) / n,
		"win_kits": win_kits, "kits": kits,
		"wins_by_seed": wins_by_seed, "seeds": seed_arr,
		"timeouts": timeouts, "tally": tally,
		"mean_turns_on_wins": 0.0 if wins == 0 else float(turns_on_wins) / wins,
		"mean_dmg_taken": 0.0 if n == 0 else float(dmg) / n,
		"ci": wilson(wins, n),
		"runs": runs,
	}


# --- seeds and config ---------------------------------------------------------

static func seed_from() -> int:
	var v := OS.get_environment("SWEEP_SEED_FROM")
	return int(v) if v != "" else 1


static func seed_list_from(count: int, first: int) -> Array:
	var out: Array = []
	for s in range(first, first + count):
		out.append(s)
	return out


## Seeds for a runner: SWEEP_SEEDS (count, default `default_count`) starting
## at SWEEP_SEED_FROM (default 1).
static func seed_list(default_count: int) -> Array:
	var count := default_count
	var v := OS.get_environment("SWEEP_SEEDS")
	if v != "":
		count = int(v)
	return seed_list_from(count, seed_from())


## `cfg` with the run-config env vars merged in - the axes every runner that
## calls this gains for free (docs/PROGRESSION_REVIEW.md 6.1 Block A):
##   SWEEP_TIER=<int>       difficulty tier
##   SWEEP_LOADOUT=<id>     starting loadout, a Content.LOADOUTS id
##   SWEEP_UNLOCK=<state>   unlock state: "fresh" (packages []),
##                          "package:<id>" (packages [id] - the one-package
##                          run-scoped commitment), "all" (every package)
## An unset var leaves `cfg` untouched, so a runner with no env vars behaves
## exactly as before. An unknown loadout id or SWEEP_UNLOCK value is a
## push_error and the key is left alone, so the printed header always names
## the config the runs actually used.
static func env_config(cfg: Dictionary) -> Dictionary:
	var out := cfg.duplicate(true)
	var v := OS.get_environment("SWEEP_TIER")
	if v != "":
		out["tier"] = int(v)
	var lo := OS.get_environment("SWEEP_LOADOUT")
	if lo != "":
		if Content.LOADOUTS.has(lo):
			out["loadout"] = lo
		else:
			push_error("unknown SWEEP_LOADOUT '%s' (have: %s)" % [lo, ", ".join(Content.LOADOUTS.keys())])
	var un := OS.get_environment("SWEEP_UNLOCK")
	if un != "":
		if un == "fresh":
			out["packages"] = []
		elif un == "all":
			out["packages"] = Content.PACKAGES.keys()
		elif un.begins_with("package:"):
			var pkg := un.substr(8)
			if Content.PACKAGES.has(pkg):
				out["packages"] = [pkg]
			else:
				push_error("unknown SWEEP_UNLOCK package '%s' (have: %s)" % [pkg, ", ".join(Content.PACKAGES.keys())])
		else:
			push_error("bad SWEEP_UNLOCK '%s' (want fresh | package:<id> | all)" % un)
	return out


## Runner header: bot, config, seed range.
static func header(script_name: String, bot_name: String, cfg: Dictionary, seeds: Array) -> String:
	var range_s := "none"
	if not seeds.is_empty():
		range_s = "%d..%d (%d)" % [int(seeds[0]), int(seeds[seeds.size() - 1]), seeds.size()]
	return "=== %s | bot %s | config %s | seeds %s ===" % [script_name, bot_name, str(cfg), range_s]


# --- statistics ---------------------------------------------------------------

## Wilson score interval for w wins in n runs, as (lo, hi) fractions.
static func wilson(w: int, n: int, z := 1.96) -> Vector2:
	if n <= 0:
		return Vector2(0.0, 1.0)
	var nf := float(n)
	var p := float(w) / nf
	var z2 := z * z
	var denom := 1.0 + z2 / nf
	var centre := (p + z2 / (2.0 * nf)) / denom
	var half := z * sqrt(p * (1.0 - p) / nf + z2 / (4.0 * nf * nf)) / denom
	return Vector2(maxf(0.0, centre - half), minf(1.0, centre + half))


## Paired outcome table for two same-seed win arrays plus the two-sided exact
## sign-test p-value on the discordant pairs (1.0 when there are none).
## Pairing is exact for the floor-1 map (bump 2 left mapgen as the only
## main-rng consumer at floor entry); later floors diverge through play.
static func paired(a: Array, b: Array) -> Dictionary:
	var both := 0
	var only_a := 0
	var only_b := 0
	var neither := 0
	for i in mini(a.size(), b.size()):
		var wa := bool(a[i])
		var wb := bool(b[i])
		if wa and wb:
			both += 1
		elif wa:
			only_a += 1
		elif wb:
			only_b += 1
		else:
			neither += 1
	return {
		"both": both, "only_a": only_a, "only_b": only_b, "neither": neither,
		"sign_p": sign_test_p(only_a, only_a + only_b),
	}


## Two-sided exact binomial(m, 0.5) p-value for k successes.
static func sign_test_p(k: int, m: int) -> float:
	if m <= 0:
		return 1.0
	var pmf: Array = []
	var p := pow(0.5, m)
	for i in range(m + 1):
		pmf.append(p)
		p = p * float(m - i) / float(i + 1)
	var lo := 0.0
	for i in range(0, k + 1):
		lo += pmf[i]
	var hi := 0.0
	for i in range(k, m + 1):
		hi += pmf[i]
	return minf(1.0, 2.0 * minf(lo, hi))


static func fmt_ci(ci: Vector2) -> String:
	return "[%.0f%%, %.0f%%]" % [100.0 * ci.x, 100.0 * ci.y]


# --- locked-kit lift ----------------------------------------------------------

static func locked_config(kit: Array, cfg: Dictionary) -> Dictionary:
	var out := cfg.duplicate(true)
	out["kit"] = kit.duplicate()
	out["pool"] = kit.duplicate()
	return out


## One row of the locked-kit lift table (review §7.3): base3, base3+x,
## base3+y and base3+x+y each run LOCKED ({kit: K, pool: K}, see
## CAVEAT_LOCKED) on the same seeds; lift = pair - max(single); additive =
## sx + sy - base; discordant pairs the pair config against the better single.
static func lift_row(base3: Array, x: String, y: String, seeds: Array, cfg: Dictionary, bot_ref) -> Dictionary:
	var kx: Array = base3.duplicate()
	kx.append(x)
	var ky: Array = base3.duplicate()
	ky.append(y)
	var kxy: Array = kx.duplicate()
	kxy.append(y)
	var mb := measure(seeds, locked_config(base3, cfg), bot_ref)
	var mx := measure(seeds, locked_config(kx, cfg), bot_ref)
	var my := measure(seeds, locked_config(ky, cfg), bot_ref)
	var mp := measure(seeds, locked_config(kxy, cfg), bot_ref)
	var sx: int = mx["wins"]
	var sy: int = my["wins"]
	var best_single: Dictionary = mx if sx >= sy else my
	var kp := Tally.kpis(mp["tally"], mp["n"], mp["kits"])
	return {
		"x": x, "y": y, "base3": base3.duplicate(),
		"n": seeds.size(),
		"base": mb["wins"], "single_x": sx, "single_y": sy, "pair": mp["wins"],
		"lift": mp["wins"] - maxi(sx, sy),
		"additive": sx + sy - mb["wins"],
		"pair_minus_additive": mp["wins"] - (sx + sy - mb["wins"]),
		"ci_pair": mp["ci"], "ci_x": mx["ci"], "ci_y": my["ci"], "ci_base": mb["ci"],
		"discordant": paired(mp["wins_by_seed"], best_single["wins_by_seed"]),
		"combo_rate_pair": kp["combo_rate"],
		"signature_share_pair": kp["signature_share"],
		"terrain_share_pair": kp["terrain_share"],
		"turns_on_wins_pair": mp["mean_turns_on_wins"],
		"dmg_taken_pair": mp["mean_dmg_taken"],
		"timeouts_pair": mp["timeouts"],
		"avg_floor_pair": mp["avg_floor"],
		"tally_pair": mp["tally"],
	}


## One-line rendering of a lift_row result.
static func fmt_lift_row(r: Dictionary) -> String:
	var d: Dictionary = r["discordant"]
	return "%-14s + %-14s pair %2d/%d %s  singles %2d/%2d  base %2d  lift %+d  vs additive %+d  discordant %d:%d p=%.2f  combos/run %.2f  turns(w) %.0f  dmg %.1f  timeouts %d" % [
		r["x"], r["y"], r["pair"], r["n"], fmt_ci(r["ci_pair"]), r["single_x"], r["single_y"], r["base"],
		r["lift"], r["pair_minus_additive"], d["only_a"], d["only_b"], d["sign_p"],
		r["combo_rate_pair"], r["turns_on_wins_pair"], r["dmg_taken_pair"], r["timeouts_pair"]]
