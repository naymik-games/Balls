class_name DamageModel
extends RefCounted
## How much block HP one ball removes per shot, as measured by DamageLog.
##
## Per-ball damage is noisy (about 1.4 to 14 in the first sample) and was only weakly
## related to board density or ball count, so it's modelled as one distribution
## instead of a lookup table. `samples` are per-shot averages (damage / balls)
## from unassisted shots; the analyzer bootstraps from them.

const MIN_SAMPLES := 20

## First sample: 49 unassisted shots, one player, 11-47 balls, 18-65 blocks on the board.
const DEFAULT_SAMPLES := [
	6.45, 3.43, 4.36, 1.40, 7.73, 11.50, 9.33, 2.95, 4.91, 7.00,
	10.31, 8.07, 2.35, 14.06, 6.63, 1.38, 5.50, 1.96, 5.26, 2.17,
	9.74, 4.64, 4.41, 5.25, 9.66, 6.72, 9.15, 6.24, 4.24, 5.50,
	2.81, 2.58, 7.47, 8.28, 11.35, 6.29, 7.07, 3.31, 2.23, 1.55,
	1.64, 2.82, 7.32, 3.34, 2.36, 4.15, 2.34, 2.09, 12.68,
]
## Total damage / total balls over those shots.
const DEFAULT_MEAN := 5.317

var samples: PackedFloat32Array
var mean_rate: float
var source: String


func _init(sample_values: PackedFloat32Array, mean: float, source_name := "") -> void:
	samples = sample_values
	mean_rate = mean
	source = source_name


static func default() -> DamageModel:
	return DamageModel.new(PackedFloat32Array(DEFAULT_SAMPLES), DEFAULT_MEAN, "embedded sample (49 shots)")


## Builds a model from a DamageLog CSV (unassisted shots only). Returns null if the
## file is missing, malformed, or has fewer than MIN_SAMPLES clean shots.
static func from_csv(path: String) -> DamageModel:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var header := f.get_csv_line()
	var i_balls := header.find("balls")
	var i_damage := header.find("damage")
	var i_per_ball := header.find("per_ball")
	var i_assisted := header.find("assisted")
	var widest := maxi(maxi(i_balls, i_damage), maxi(i_per_ball, i_assisted))
	if mini(mini(i_balls, i_damage), mini(i_per_ball, i_assisted)) < 0:
		return null

	var values := PackedFloat32Array()
	var total_damage := 0.0
	var total_balls := 0.0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() <= widest or row[i_assisted] != "0":
			continue
		values.append(row[i_per_ball].to_float())
		total_damage += row[i_damage].to_float()
		total_balls += row[i_balls].to_float()
	if values.size() < MIN_SAMPLES or total_balls <= 0.0:
		return null
	return DamageModel.new(values, total_damage / total_balls, "%s (%d shots)" % [path, values.size()])


## Per-ball damage rate at percentile p (0..1). 0.25 is a weak-ish shot.
func percentile(p: float) -> float:
	var s := samples.duplicate()
	s.sort()
	var idx := clampf(p, 0.0, 1.0) * float(s.size() - 1)
	var lo := int(idx)
	var hi := mini(lo + 1, s.size() - 1)
	return lerpf(s[lo], s[hi], idx - float(lo))


## One random per-ball rate for one shot (bootstrap draw).
func sample(rng: RandomNumberGenerator) -> float:
	return samples[rng.randi_range(0, samples.size() - 1)]
