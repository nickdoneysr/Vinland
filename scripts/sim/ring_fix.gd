class_name RingFix
extends RefCounted
## Pure rules for the star ring fix (MiniGames MG1, Systems "Drift"). No drawing, no input.
## Angles are degrees. The sight reads the Pole Star's altitude above the horizon the player
## levelled on; that altitude is the latitude estimate.

enum Result { NONE, PARTIAL, CLEAN }

const CLEAN_ERR := 0.5      # degrees of latitude
const PARTIAL_ERR := 1.5
const SEAT_TIME := 1.2      # seconds the star must stay seated before a commit counts
const SEAT_RADIUS := 0.6    # degrees between the sight and the star that count as seated

var true_lat := 61.0
var seat_held := 0.0
var samples: Array[float] = []   # latitude readings while seated

func reset(lat: float) -> void:
	true_lat = lat
	seat_held = 0.0
	samples.clear()

## Call every frame. reading = sight altitude (deg) above the bar the player levelled.
## level_err = bar height above the TRUE horizon (deg); kept for telemetry only.
## aim_err = angular distance from the sight to the star (deg). visible = star not behind cloud.
func step(delta: float, reading: float, level_err: float, aim_err: float, visible: bool) -> float:
	var seated := visible and aim_err <= SEAT_RADIUS
	if seated:
		seat_held += delta
		# The instrument reports the reading. A mislevelled bar is already in it: levelling
		# above the true horizon makes the seated reading smaller, below makes it larger.
		samples.append(reading)
		if samples.size() > 240:
			samples.pop_front()
	else:
		seat_held = maxf(0.0, seat_held - delta * 2.0)
	return seat_quality(aim_err, visible)

## 0..1, drives the rim glow and the haptic pulse (they must always agree).
func seat_quality(aim_err: float, visible: bool) -> float:
	if not visible:
		return 0.0
	return clampf(1.0 - aim_err / (SEAT_RADIUS * 3.0), 0.0, 1.0)

func estimate() -> float:
	if samples.is_empty():
		return NAN
	var s := 0.0
	for v in samples:
		s += v
	return s / samples.size()

## A: commit. Needs a held seat.
func commit() -> Dictionary:
	if seat_held < SEAT_TIME or samples.is_empty():
		return _out(Result.NONE)
	return _grade()

## B: abort. Keeps what was seen, never better than partial.
func abort() -> Dictionary:
	if samples.size() < 20:
		return _out(Result.NONE)
	var g := _grade()
	if g.result == Result.CLEAN:
		g.result = Result.PARTIAL
	return g

func _grade() -> Dictionary:
	var err := absf(estimate() - true_lat)
	var r := Result.NONE
	if err <= CLEAN_ERR:
		r = Result.CLEAN
	elif err <= PARTIAL_ERR:
		r = Result.PARTIAL
	var o := _out(r)
	o.error = err
	o.estimate = estimate()
	return o

func _out(r: int) -> Dictionary:
	return {"result": r, "error": NAN, "estimate": NAN, "true_lat": true_lat}

## Systems "Drift": no fix walks downwind, partial halves it, clean refunds it.
static func drift_multiplier(r: int) -> float:
	match r:
		Result.CLEAN: return 0.0
		Result.PARTIAL: return 0.5
		_: return 1.0

static func result_name(r: int) -> String:
	return ["No fix", "Partial fix", "Clean fix"][r]
