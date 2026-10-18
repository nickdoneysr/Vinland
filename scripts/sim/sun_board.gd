class_name SunBoard
extends RefCounted
## Rules for MG2 the sun board (Backlog F04): a wooden disk floated in a bowl of water, a gnomon peg at its
## centre, a noon line and the home curve cut into the wood. At noon the shadow tip should fall on the curve
## and along the noon line. LS turns the disk · RS up/down sets the peg · RT holds the bowl steady through
## the roll · A takes the reading · B gives up. A reading taken before it has steadied is a snatched shadow:
## at best partial, and yesterday's error carries.

enum Phase { READING, DONE }

var c: Dictionary
var rng := RandomNumberGenerator.new()
var phase := Phase.READING
var t := 0.0
var disk := 0.0            # degrees the player has turned the disk
var peg := 0.5             # gnomon height, 0.2 .. 1.0
var brace := 0.0           # 0 loose .. 1 held steady with RT
var sun_az := 0.0          # where the shadow points before the disk is turned, degrees
var shadow_k := 1.0        # shadow length per unit of peg: the sun's height today
var seat_held := 0.0
var best_seat := 0.0
var sun_visible := true
var cloud_t := 0.0
var cloudy := false
var result := -1           # RingFix.Result once done
var snatched := false
const CURVE := 0.55        # radius of the home curve on the disk (disk radius 1)

func setup(cfg: Dictionary, seed: int = 0, partly_cloudy: bool = false) -> void:
	c = cfg
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	sun_az = rng.randf_range(-float(c.start_offset_deg), float(c.start_offset_deg))
	if absf(sun_az) < 20.0:
		sun_az = 20.0 * signf(sun_az + 0.001)
	shadow_k = rng.randf_range(0.75, 1.35)
	peg = rng.randf_range(0.3, 0.9)
	cloudy = partly_cloudy
	cloud_t = rng.randf_range(c.cloud_gap[0], c.cloud_gap[1])

func wrap180(a: float) -> float:
	return fposmod(a + 180.0, 360.0) - 180.0

## The ship's roll as the board sees it: a yaw that swings the shadow and a pitch that stretches it.
func yaw() -> float:
	return float(c.roll_amp_deg) * (1.0 - brace * float(c.brace_cut)) * sin(t * float(c.get("roll_rate", 1.3))) \
		+ float(c.wander_deg) * sin(t * float(c.wander_speed))

func pitch() -> float:
	return float(c.roll_len) * (1.0 - brace * float(c.brace_cut)) * sin(t * 0.9 + 1.1)

## Shadow direction on the disk, degrees; 0 is along the noon line toward the north mark.
func shadow_dir() -> float:
	return wrap180(sun_az + yaw() - disk)

func shadow_len() -> float:
	return peg * shadow_k * (1.0 + pitch())

func dir_err() -> float:
	return shadow_dir()

func len_err() -> float:
	return shadow_len() - CURVE

func on_mark(scale: float = 1.0) -> bool:
	return sun_visible and absf(dir_err()) <= float(c.dir_tol) * scale and absf(len_err()) <= float(c.len_tol) * scale

## The peg height that puts the shadow tip on the curve with the board still.
func ideal_peg() -> float:
	return CURVE / shadow_k

func step(dt: float, turn: float, peg_move: float, hold: bool, take: bool, abort: bool) -> Array:
	var ev: Array = []
	if phase == Phase.DONE:
		return ev
	t += dt
	disk += turn * float(c.turn_speed) * dt
	peg = clampf(peg + peg_move * float(c.peg_speed) * dt, 0.2, 1.0)
	if hold:
		brace = minf(1.0, brace + dt / float(c.brace_time))
	else:
		brace = maxf(0.0, brace - dt * 3.0)
	if cloudy:
		cloud_t -= dt
		if cloud_t <= 0.0:
			sun_visible = not sun_visible
			var span: Array = c.cloud_gap if sun_visible else c.cloud_cover
			cloud_t = rng.randf_range(span[0], span[1])
			ev.append("sun" if sun_visible else "cloud")
	if on_mark():
		seat_held += dt
		if seat_held >= float(c.seat_time) and best_seat < float(c.seat_time):
			ev.append("steady")
	else:
		seat_held = maxf(0.0, seat_held - dt * float(c.seat_decay))
	best_seat = maxf(best_seat, seat_held)
	if abort:
		_finish(RingFix.Result.NONE)
		ev.append("done")
	elif take:
		if seat_held >= float(c.seat_time):
			_finish(RingFix.Result.CLEAN)
		elif on_mark(2.0):
			snatched = true
			_finish(RingFix.Result.PARTIAL)
		else:
			_finish(RingFix.Result.NONE)
		ev.append("done")
	elif t >= float(c.session_seconds):
		_finish(RingFix.Result.PARTIAL if best_seat >= float(c.seat_time) * 0.5 else RingFix.Result.NONE)
		ev.append("done")
	return ev

func _finish(r: int) -> void:
	result = r
	phase = Phase.DONE
