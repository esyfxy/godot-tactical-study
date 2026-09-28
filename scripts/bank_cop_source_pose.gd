extends RefCounted

# Original Humanoid curves and event times; approximate anatomical retarget.
# Do not call these baked Unity bone animations: this two-bone IK is not Unity's Avatar solver.
static func sample(clips: Dictionary, clip: String, attr: String, time: float) -> float:
	var data: Dictionary = clips[clip]
	var duration := float(data["duration"])
	var t := fposmod(time, duration) if data["loop"] else clampf(time, 0.0, duration)
	var values: Array = data["curves"][attr]
	var frame := t / duration * float(values.size() - 1)
	var first := floori(frame)
	return lerpf(float(values[first]), float(values[mini(first + 1, values.size() - 1)]), frame - first)

static func offset(clips: Dictionary, clip: String, attr: String, time: float) -> float:
	return sample(clips, clip, attr, time) - sample(clips, "idle_1", attr, 0.0)

static func apply(skeleton: Skeleton3D, rest: Dictionary, axes: Dictionary, hips_rest: Vector3,
		clips: Dictionary, clip: String, time: float, weight: float) -> void:
	var hips := skeleton.find_bone("Hips")
	skeleton.set_bone_pose_rotation(hips, skeleton.get_bone_rest(hips).basis.get_rotation_quaternion())
	var body_delta := body_rotation(clips, clip, time) * body_rotation(clips, "idle_1", 0.0).inverse()
	var hips_global := skeleton.get_bone_global_pose(hips).basis.orthonormalized().get_rotation_quaternion()
	var parent := skeleton.get_bone_parent(hips)
	var parent_q := skeleton.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	skeleton.set_bone_pose_rotation(hips, parent_q.inverse() * Quaternion.IDENTITY.slerp(body_delta, weight) * hips_global)
	var height := offset(clips, clip, "RootT.y", time) * 1.1010896
	skeleton.set_bone_pose_position(hips, hips_rest + Vector3.UP * height * weight)
	for bone_name in rest:
		var flex := 0.0
		var spread := 0.0
		var twist := 0.0
		var side := "Left" if str(bone_name).begins_with("Left") else "Right"
		var sign_side := 1.0 if side == "Left" else -1.0
		if str(bone_name).ends_with("UpLeg"):
			flex = -offset(clips, clip, side + " Upper Leg Front-Back", time) * 1.5
			spread = offset(clips, clip, side + " Upper Leg In-Out", time) * sign_side * 0.4
		elif str(bone_name).ends_with("Leg"):
			flex = -clampf(1.0 - sample(clips, clip, side + " Lower Leg Stretch", time), 0.0, 1.8) * 1.3
		elif str(bone_name).ends_with("Foot"):
			flex = offset(clips, clip, side + " Foot Up-Down", time) * 0.6
		elif str(bone_name).ends_with("ForeArm"):
			flex = clampf(1.0 - sample(clips, clip, side + " Forearm Stretch", time), 0.0, 1.7) * 1.5
		elif str(bone_name).ends_with("Arm"):
			flex = -offset(clips, clip, side + " Arm Front-Back", time) * 1.2
			spread = -offset(clips, clip, side + " Arm Down-Up", time) * sign_side * 1.3
		elif bone_name in ["Spine", "Spine1"]:
			var prefix := "Spine" if bone_name == "Spine" else "Chest"
			flex = -offset(clips, clip, prefix + " Front-Back", time) * 0.65
			spread = offset(clips, clip, prefix + " Left-Right", time) * 0.45
			twist = offset(clips, clip, prefix + " Twist Left-Right", time) * 0.65
		var q: Quaternion = rest[bone_name]
		var axis: Array = axes[bone_name]
		skeleton.set_bone_pose_rotation(skeleton.find_bone(bone_name), q * Quaternion(axis[0], flex * weight) * Quaternion(axis[1], spread * weight) * Quaternion(axis[2], twist * weight))
	# The extracted clips also contain body-relative hand/foot IK goals. Use
	# them to constrain endpoints instead of guessing all limb joint angles.
	# Human scale comes from prefab-linked CopMaleAvatar_0.m_Human.data.m_Scale.
	for side in ["Left", "Right"]:
		var foot := goal(clips, clip, side + "FootT", time)
		var hand := goal(clips, clip, side + "HandT", time)
		var ankle := skeleton.find_bone(side + "Foot")
		foot.y += skeleton.get_bone_global_rest(ankle).origin.y
		var wrist := skeleton.find_bone(side + "Hand")
		foot = skeleton.get_bone_global_pose(ankle).origin.lerp(foot, weight)
		hand = skeleton.get_bone_global_pose(wrist).origin.lerp(hand, weight)
		solve_limb(skeleton, side + "UpLeg", side + "Leg", side + "Foot", foot, Vector3.FORWARD)
		var elbow_pole := Vector3(-1 if side == "Left" else 1, -0.3, 0.6)
		solve_limb(skeleton, side + "Arm", side + "ForeArm", side + "Hand", hand, elbow_pole)

static func goal(clips: Dictionary, clip: String, prefix: String, time: float) -> Vector3:
	var body_q := Quaternion(sample(clips, clip, "RootQ.x", time), sample(clips, clip, "RootQ.y", time), sample(clips, clip, "RootQ.z", time), sample(clips, clip, "RootQ.w", time)).normalized()
	var endpoint := Vector3(sample(clips, clip, prefix + ".x", time), sample(clips, clip, prefix + ".y", time), sample(clips, clip, prefix + ".z", time))
	var body := Vector3(sample(clips, clip, "RootT.x", time), sample(clips, clip, "RootT.y", time), sample(clips, clip, "RootT.z", time))
	# Root forward travel is consumed by the verified grid path, not added twice.
	var root_z := sample(clips, clip, "RootT.z", time if clip == "climbing_low" else 0.0)
	var p := (body + body_q * endpoint - Vector3(sample(clips, clip, "RootT.x", 0.0), 0, root_z)) * 1.1010896
	return Vector3(p.x, p.y, -p.z)

static func body_rotation(clips: Dictionary, clip: String, time: float) -> Quaternion:
	# Same left-handed -> right-handed reflection as the original rig exporter.
	return Quaternion(-sample(clips, clip, "RootQ.x", time), -sample(clips, clip, "RootQ.y", time), sample(clips, clip, "RootQ.z", time), sample(clips, clip, "RootQ.w", time)).normalized()

static func rotate_to(skeleton: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var current := skeleton.get_bone_global_pose(bone)
	var v := skeleton.get_bone_global_pose(child).origin - current.origin
	var desired := target - current.origin
	if v.length_squared() < 0.00001 or desired.length_squared() < 0.00001: return
	var delta := Quaternion(v.normalized(), desired.normalized())
	var global_q := delta * current.basis.orthonormalized().get_rotation_quaternion()
	var parent := skeleton.get_bone_parent(bone)
	var parent_q := skeleton.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	skeleton.set_bone_pose_rotation(bone, parent_q.inverse() * global_q)

static func solve_limb(skeleton: Skeleton3D, upper_name: String, lower_name: String, end_name: String, target: Vector3, pole: Vector3) -> void:
	var upper := skeleton.find_bone(upper_name)
	var lower := skeleton.find_bone(lower_name)
	var end := skeleton.find_bone(end_name)
	var a := skeleton.get_bone_global_pose(upper).origin
	var b := skeleton.get_bone_global_pose(lower).origin
	var c := skeleton.get_bone_global_pose(end).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var direction := (target - a).normalized()
	var distance := clampf(a.distance_to(target), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var along := (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
	var perpendicular := pole - direction * pole.dot(direction)
	if perpendicular.length_squared() < 0.0001: perpendicular = direction.cross(Vector3.RIGHT)
	var bend := a + direction * along + perpendicular.normalized() * sqrt(maxf(0.0, l1 * l1 - along * along))
	rotate_to(skeleton, upper, lower, bend)
	rotate_to(skeleton, lower, end, target)
