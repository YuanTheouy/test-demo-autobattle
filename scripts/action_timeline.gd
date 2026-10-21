extends RefCounted
## Integer-frame attack lifecycle. Each tick advances only the current stage.
## `phase`/`timer` in battle.gd are presentation adapters, not the clock.

const FPS := 60
const RELEASE_LOCK_FRAMES := 2
const WINDUP := "前摇"
const RELEASE := "释放硬直"
const RECOVERY := "后摇"

static func frames(seconds: float) -> int:
	return maxi(1, ceili(seconds * FPS - 0.000001))

static func clear(u: Dictionary) -> void:
	u.action_stage = ""
	u.stage_frames = 0
	u.stage_total = 0
	u.release_elapsed = 0
	u.action_paid = 0.0
	u.action_committed = false
	u.action_cd = 0.0

static func enter(u: Dictionary, stage: String, duration: int) -> void:
	u.action_stage = stage
	u.stage_frames = maxi(1, duration)
	u.stage_total = u.stage_frames
	u.timer = u.stage_frames / float(FPS)

static func begin(u: Dictionary, windup: float, paid: float, cooldown: float) -> void:
	clear(u)
	u.action_paid = paid
	u.action_cd = cooldown
	enter(u, WINDUP, frames(windup))

static func tick(u: Dictionary) -> bool:
	u.stage_frames = maxi(0, u.stage_frames - 1)
	u.timer = u.stage_frames / float(FPS)
	return u.stage_frames == 0

static func busy(u: Dictionary) -> bool:
	return not u.get("action_stage", "").is_empty()

static func refundable(u: Dictionary) -> float:
	if u.get("action_stage", "") == WINDUP and not u.get("action_committed", false):
		return float(u.get("action_paid", 0.0))
	return 0.0

static func can_dodge(u: Dictionary) -> bool:
	return u.get("action_stage", "") != RELEASE
