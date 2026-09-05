extends SceneTree
## Difficulty tier sweep: every tier must stay bot-winnable.
## Run: [SWEEP_BOT=deeproot] [SWEEP_SEEDS=20] [SWEEP_SEED_FROM=1] \
##   godot --headless --path . --script tests/sweep_tiers.gd
## Fails (exit 1) when the Wilson UPPER bound of the win rate at any judged
## tier is below 10%: tiers <= HEURISTIC_BAND for a heuristic bot, every tier
## when judged by a ceiling bot (SWEEP_BOT=deeproot / deeproot_rollout).
## SWEEP_REFERENCE_ROWS=1 appends the permanent locked reference kits
## (review §7.3: starter5, lance_free_A, lance_free_B as {kit: K, pool: K})
## at tier 0 and at SWEEP_TIER, with wins, CI, signature and terrain share.
## Reference rows are informational and never affect the exit code.

const Content := preload("res://sim/content.gd")
const Sweep := preload("res://tests/sweep_lib.gd")
const Tally := preload("res://tests/tally.gd")

const SEEDS := 20
const MIN_UPPER := 0.10

const HEURISTIC_BAND := 5  # tiers above this bind the ceiling; judge with SWEEP_BOT=deeproot

## Permanent locked reference kits (BALANCE.md rows); insertion order is the print order.
const REFERENCE_KITS := {
	"starter5": ["solar_lance", "seed_bomb", "mycelium_dash", "grow_spike", "sun_flare"],
	"lance_free_A": ["seed_bomb", "mycelium_dash", "sun_flare", "water_jet", "grow_spike"],
	"lance_free_B": ["seed_bomb", "mycelium_dash", "water_jet", "vine_whip", "grow_spike"],
}


func _init() -> void:
	var bot := Sweep.pick_bot()
	var bot_name := Sweep.pick_bot_name()
	var seeds := Sweep.seed_list(SEEDS)
	print(Sweep.header("sweep_tiers", bot_name, {}, seeds))
	if bot == null:
		print("FAIL: unknown SWEEP_BOT")
		quit(1)
		return
	var ceiling := bot_name.begins_with("deeproot")
	# the gate binds only when a zero-win tier's upper bound can dip under
	# MIN_UPPER: Wilson(0, n).y = z^2 / (n + z^2) < 0.10 needs n >= 35
	var zero_upper: float = Sweep.wilson(0, seeds.size()).y
	if zero_upper >= MIN_UPPER:
		print("note: at n=%d a 0-win tier has upper bound %.0f%%, so the %.0f%% gate cannot trigger; use SWEEP_SEEDS>=35 for a binding check" % [
			seeds.size(), 100.0 * zero_upper, 100.0 * MIN_UPPER])
	var unwinnable := 0
	for t in range(Content.TIERS.size() + 1):
		var m := Sweep.measure(seeds, {"tier": t}, bot)
		var label: String = "base" if t == 0 else Content.TIERS[t - 1]["name"]
		var ci: Vector2 = m["ci"]
		var judged: bool = t <= HEURISTIC_BAND or ceiling
		var flag := ""
		if judged and ci.y < MIN_UPPER:
			unwinnable += 1
			flag = "  << UNWINNABLE (upper bound %.1f%% < %.0f%%)" % [100.0 * ci.y, 100.0 * MIN_UPPER]
		print("tier %d (%-16s) %2d/%d wins, avg floor %.1f  CI %s  timeouts %d%s" % [
			t, label, m["wins"], m["n"], m["avg_floor"], Sweep.fmt_ci(ci), m["timeouts"], flag])
	if unwinnable > 0:
		print("WARNING: %d tier(s) have a win-rate upper bound under %.0f%% for %s" % [unwinnable, 100.0 * MIN_UPPER, bot_name])
	if OS.get_environment("SWEEP_REFERENCE_ROWS") == "1":
		_reference_rows(seeds, bot)
	quit(1 if unwinnable > 0 else 0)


## Locked reference kits at tier 0 and (when different) at SWEEP_TIER.
func _reference_rows(seeds: Array, bot) -> void:
	var tiers: Array = [0]
	var sweep_tier: int = int(Sweep.tier_config({"tier": 0})["tier"])
	if sweep_tier != 0:
		tiers.append(sweep_tier)
	print("\nreference rows (locked {kit: K, pool: K}, %d seeds):" % seeds.size())
	print(Sweep.CAVEAT_LOCKED)
	for t in tiers:
		for label in REFERENCE_KITS:
			var kit: Array = REFERENCE_KITS[label]
			var m := Sweep.measure(seeds, Sweep.locked_config(kit, {"tier": t}), bot)
			var kp := Tally.kpis(m["tally"], m["n"], m["kits"])
			print("  tier %d %-13s %2d/%d wins  CI %s  signature share %.2f  terrain share %.2f  combos/run %.2f  avg floor %.1f  timeouts %d  kit %s" % [
				t, label, m["wins"], m["n"], Sweep.fmt_ci(m["ci"]), kp["signature_share"], kp["terrain_share"],
				kp["combo_rate"], m["avg_floor"], m["timeouts"], str(kit)])
