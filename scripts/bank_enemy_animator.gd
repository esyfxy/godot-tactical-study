extends Node

# Source curves and timings are preserved; anatomical angle mapping is an
# approximation, not Unity's Avatar solver. No enemy AI is simulated here.
var model: Node3D
var skeleton: Skeleton3D
var clips: Dictionary
var state := "巡逻"
var moving := false
var elapsed := 0.0
var idle_phase := 0.0
var active_clip := "enemy_idle"
var rest: Dictionary = {}
var hip_rest := Vector3.ZERO
var start_rotations: Dictionary = {}

func configure(body: Node3D, source: Dictionary, phase: float) -> void:
	model = body
	clips = source
	idle_phase = phase
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for name in ["Spine", "Spine1", "Head", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			var basis := skeleton.get_bone_global_rest(bone).basis.orthonormalized()
			rest[name] = {"bone": bone, "rotation": skeleton.get_bone_rest(bone).basis.get_rotation_quaternion(),
				"x": basis.inverse() * Vector3.RIGHT, "z": basis.inverse() * Vector3.BACK}
	hip_rest = skeleton.get_bone_rest(skeleton.find_bone("Hips")).origin
	reset()

func reset() -> void:
	state = "巡逻"
	moving = false
	elapsed = 0.0
	start_rotations.clear()
	model.rotation = Vector3.ZERO
	model.position = Vector3.ZERO
	get_parent().visible = true
	_apply_pose(0.0, 0.0)

func set_state(next: String) -> void:
	if next == state:
		return
	start_rotations.clear()
	for name in rest:
		start_rotations[name] = skeleton.get_bone_pose_rotation(int(rest[name]["bone"]))
	state = next
	elapsed = 0.0
	if state != "逃离":
		get_parent().visible = true

func _process(delta: float) -> void:
	if skeleton == null:
		return
	elapsed += delta
	_apply_pose(elapsed, delta)
	# Ordinary enemies disappear after arrest in Enemy.ShouldDisappearWhenArrested.
	# Here a short restrained pose replaces the still-missing paired arrest sequence.
	if state == "已逮捕" and elapsed >= 1.35:
		get_parent().visible = false
	elif state == "逃离" and not moving:
		get_parent().visible = false

func _sample(clip: String, attribute: String, time: float) -> float:
	var data: Dictionary = clips[clip]
	var duration := float(data["duration"])
	var t := fposmod(time, duration) if bool(data["loop"]) else clampf(time, 0.0, duration)
	var values: Array = data["curves"][attribute]
	var frame := t / duration * float(values.size() - 1)
	var first := floori(frame)
	return lerpf(float(values[first]), float(values[mini(first + 1, values.size() - 1)]), frame - first)

func _offset(clip: String, attribute: String, time: float) -> float:
	return _sample(clip, attribute, time) - _sample("enemy_idle", attribute, 0.0)

func _pose(name: String, flex: float, side: float, blend: float) -> void:
	if not rest.has(name):
		return
	var entry: Dictionary = rest[name]
	var q: Quaternion = entry["rotation"]
	q = q * Quaternion(entry["x"], flex) * Quaternion(entry["z"], side)
	if start_rotations.has(name) and blend < 1.0:
		q = (start_rotations[name] as Quaternion).slerp(q, blend)
	skeleton.set_bone_pose_rotation(int(entry["bone"]), q)

func _apply_pose(time: float, delta: float) -> void:
	var clip := "walk_casual" if moving else "enemy_idle"
	var clip_time := time + (idle_phase if state == "巡逻" and not moving else 0.0)
	if state == "举手":
		clip = "surrender"
		if time >= float(clips[clip]["duration"]):
			clip_time = time - float(clips[clip]["duration"])
			clip = "surrender_idle"
	elif state == "昏迷":
		clip = "stun_start"
		if time >= float(clips[clip]["duration"]):
			clip_time = time - float(clips[clip]["duration"])
			clip = "stun_cycle"
	elif state == "倒地":
		clip = "dead_on_back"
	elif state == "已逮捕":
		clip = "arrested"
	active_clip = clip
	var blend := smoothstep(0.0, 0.22, time)
	var root_delta := _offset(clip, "RootT.y", clip_time)
	var kneel := clampf(-root_delta / 0.785, 0.0, 1.0) if state in ["举手", "已逮捕"] else 0.0
	var stunned := 1.0 if state == "昏迷" else 0.0
	var fallen := smoothstep(0.0, 0.65, time) if state == "倒地" else 0.0
	var target_tilt := Vector3(fallen * PI * 0.5, 0, 0)
	model.rotation = model.rotation.lerp(target_tilt, minf(1.0, delta * 12.0)) if delta > 0 else target_tilt
	model.position.y = fallen * 0.18
	var hip_offset := -0.45 * kneel if kneel > 0 else clampf(root_delta, -0.1, 0.04)
	if state == "倒地":
		hip_offset = 0.0
	var hips := skeleton.find_bone("Hips")
	var hip_target := hip_rest + Vector3(0, hip_offset, 0)
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips).lerp(hip_target, minf(1.0, delta * 10.0)) if delta > 0 else hip_target)
	_pose("Spine", clampf(_offset(clip, "Spine Front-Back", clip_time) * 0.4 + stunned * 0.25, -0.3, 0.65), _offset(clip, "Spine Left-Right", clip_time) * 0.3, blend)
	_pose("Spine1", clampf(_offset(clip, "Chest Front-Back", clip_time) * 0.3, -0.3, 0.4), _offset(clip, "Chest Left-Right", clip_time) * 0.3, blend)
	_pose("Head", stunned * 0.18, 0.0, blend)
	for side in ["Left", "Right"]:
		var sign_value := 1.0 if side == "Left" else -1.0
		var lift := clampf(_offset(clip, side + " Arm Down-Up", clip_time) / 0.82, -0.35, 1.0)
		var arm_angle := deg_to_rad(70.0 - 140.0 * lift) * sign_value
		var arm_forward := _offset(clip, side + " Arm Front-Back", clip_time) * 0.45
		if state == "昏迷":
			arm_angle = deg_to_rad(60.0) * sign_value
			arm_forward += 0.25
		_pose(side + "Arm", arm_forward, arm_angle, blend)
		var elbow := clampf(0.15 + absf(_offset(clip, side + " Forearm Stretch", clip_time)) * 0.9, 0.1, 1.6)
		_pose(side + "ForeArm", -elbow, 0.0, blend)
		var leg_swing := _offset(clip, side + " Upper Leg Front-Back", clip_time) * 0.9 if moving else 0.0
		_pose(side + "UpLeg", leg_swing + kneel * 1.2 + stunned * 0.12, 0.0, blend)
		_pose(side + "Leg", -kneel * 2.0 - stunned * 0.15 - (maxf(0.0, 0.8 - _sample(clip, side + " Lower Leg Stretch", clip_time)) * 0.6 if moving else 0.0), 0.0, blend)
		_pose(side + "Foot", _offset(clip, side + " Foot Up-Down", clip_time) * 0.3 if moving else 0.0, 0.0, blend)
