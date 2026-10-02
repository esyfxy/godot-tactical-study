extends Node

# Original run muscle curves, mapped to the imported skeleton's anatomical
# axes. This is an approximate retarget, not Unity's unavailable Avatar solver.
var skeleton: Skeleton3D
var rest := {}
var axes := {}
var curves: Dictionary
var previous := Vector3.ZERO
var clock := 0.0
var weight := 0.0
var hips := -1
var hips_rest := Vector3.ZERO
var heading := 0.0
var initialized := false
const POSE = preload("res://scripts/bank_cop_source_pose.gd")
static var clips: Dictionary = {}
var named_rest := {}
var named_axes := {}
var action_clip := ""
var action_time := 0.0
var action_hold := false
var action_blend := 0.0
var gun := ""
var dead := false
var weapon_meshes := {}
var knife: Node3D
var hand_rest := {}
var blend_from: Array[Transform3D] = []
var playback_speed := 1.0
var gender := 0
var cover_tier := 0
var wounded := ""
var locomotion_clip := "run_0"
var melee := ""
var machinegun := false
var source_prefab := ""
const FALL_TIME_LIMIT:=1.15
signal footstep(foot: String)

func configure_weapons(model: Node3D) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "RightHand"
	skeleton.add_child(attachment)
	knife = load("res://assets/horde/actors/knife/knife.gltf").instantiate()
	attachment.add_child(knife)
	knife.hide()
	for key in ["glock","revolver","rifle","shotgun","ax","machine_gun"]:
		var n := model.find_child(key,true,false) as MeshInstance3D
		if n != null:
			weapon_meshes[key] = n
			n.hide()
	if weapon_meshes.is_empty():
		# Rebind the source cop's weapon skins by bone NAME to the enemy rig.
		# Meshes/materials are shared resources; no extra character is rendered.
		var source: Node3D = load("res://assets/horde/actors/cop/cop_rig.gltf").instantiate()
		var source_skeleton: Skeleton3D = source.find_children("*","Skeleton3D",true,false)[0]
		var source_gun := source_skeleton.find_bone("gun")
		if source_gun >= 0 and skeleton.find_bone("gun") < 0:
			var new_bone := skeleton.add_bone("gun")
			var parent_name := source_skeleton.get_bone_name(source_skeleton.get_bone_parent(source_gun))
			skeleton.set_bone_parent(new_bone,skeleton.find_bone(parent_name))
			var local := source_skeleton.get_bone_rest(source_gun)
			skeleton.set_bone_rest(new_bone,local)
			skeleton.set_bone_pose_position(new_bone,local.origin)
			skeleton.set_bone_pose_rotation(new_bone,local.basis.get_rotation_quaternion())
		for key in ["glock","revolver","rifle","shotgun"]:
			var original := source.find_child(key,true,false) as MeshInstance3D
			if original == null or original.skin == null: continue
			var skin := Skin.new()
			for i in range(original.skin.get_bind_count()):
				var bone_name: StringName = original.skin.get_bind_name(i)
				if bone_name.is_empty(): bone_name = source_skeleton.get_bone_name(original.skin.get_bind_bone(i))
				skin.add_named_bind(bone_name,original.skin.get_bind_pose(i))
			var n := MeshInstance3D.new()
			n.mesh = original.mesh
			n.skin = skin
			skeleton.add_child(n)
			n.skeleton = NodePath("..")
			weapon_meshes[key] = n
			n.hide()
		source.free()

func update_weapons() -> void:
	var using_knife := action_clip == "knife_attack" and action_time<1.2541744 and not dead
	if knife != null: knife.visible = using_knife
	var held := "ax" if melee=="Ax" else "machine_gun" if machinegun else gun.to_lower()
	for key in weapon_meshes: weapon_meshes[key].visible = key == held and not dead and wounded!="躯干" and not using_knife and action_clip != "surrender"

func initialize(model: Node3D) -> void:
	if clips.is_empty(): clips = JSON.parse_string(FileAccess.get_file_as_string("res://assets/horde/combat_motion.json"))
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty(): return
	skeleton = found[0]
	curves = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/original_cop/run_source_curves.json"))
	for i in range(skeleton.get_bone_count()):
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_rest(i).basis.get_rotation_quaternion())
	for side in ["Left", "Right"]:
		var b := skeleton.find_bone(side + "Arm")
		if b >= 0:
			var axis := (skeleton.get_bone_global_rest(b).basis.inverse() * Vector3.BACK).normalized()
			skeleton.set_bone_pose_rotation(b, skeleton.get_bone_pose_rotation(b) * Quaternion(axis, deg_to_rad(70 if side == "Left" else -70)))
	for name in ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "Spine", "Spine1"]:
		var b := skeleton.find_bone(name)
		if b < 0: continue
		rest[b] = skeleton.get_bone_pose_rotation(b)
		var inverse := skeleton.get_bone_global_pose(b).basis.inverse()
		axes[b] = [(inverse * Vector3.RIGHT).normalized(), (inverse * Vector3.BACK).normalized(), (inverse * Vector3.UP).normalized()]
		named_rest[name] = rest[b]
		named_axes[name] = axes[b]
	hips = skeleton.find_bone("Hips")
	if hips >= 0: hips_rest = skeleton.get_bone_pose_position(hips)
	for side in ["Left","Right"]:
		var wrist := skeleton.find_bone(side+"Hand")
		hand_rest[side] = skeleton.get_bone_global_pose(wrist).basis.orthonormalized().get_rotation_quaternion()

func start_clip(clip: String, hold := false) -> void:
	if not clips.has(clip): return
	action_clip = clip
	action_time = 0.0
	action_hold = hold
	action_blend = 0.0
	blend_from.clear()
	for i in range(skeleton.get_bone_count()): blend_from.append(skeleton.get_bone_pose(i))
	update_weapons()

func release_action() -> void:
	# Keep the end pose as the blend source, not a one-frame reset to idle.
	action_clip = ""
	action_hold = false

func is_prone() -> bool:
	return skeleton!=null and hips>=0 and wounded=="躯干" and skeleton.get_bone_pose_position(hips).y<hips_rest.y-.4

func start_fall(speed:=1.0) -> float:
	wounded="躯干"
	playback_speed=maxf(speed,duration("idle_body_damage")/FALL_TIME_LIMIT)
	start_clip("idle_body_damage")
	return duration("idle_body_damage")/playback_speed

func start_death(clip: String="idle_body_damage",speed:=1.0) -> float:
	# A prone bleeding victim is already on the floor. Never replay a fall
	# whose opening pose is standing; the source dead_on_back is its endpoint.
	if is_prone(): clip="dead_on_back"
	dead=true
	playback_speed=speed if clip=="dead_on_back" else maxf(speed,duration(clip)/FALL_TIME_LIMIT)
	start_clip(clip,true)
	return duration(clip)/playback_speed

func hand_rotation(clip: String,side: String,time: float) -> Quaternion:
	var q := Quaternion(-POSE.sample(clips,clip,side+"HandQ.x",time),-POSE.sample(clips,clip,side+"HandQ.y",time),POSE.sample(clips,clip,side+"HandQ.z",time),POSE.sample(clips,clip,side+"HandQ.w",time)).normalized()
	return POSE.body_rotation(clips,clip,time)*q

func apply_clip(clip: String,time: float) -> void:
	POSE.apply(skeleton,named_rest,named_axes,hips_rest,clips,clip,time,1.0)
	# Retain source hand orientation, not only the IK endpoint. Without it,
	# the attached gun rotates with the elbow and points down during aiming.
	for side in ["Left","Right"]:
		var wrist := skeleton.find_bone(side+"Hand")
		var desired: Quaternion = hand_rotation(clip,side,time)*hand_rotation("idle_1",side,0).inverse()*hand_rest[side]
		var parent := skeleton.get_bone_parent(wrist)
		var parent_q := skeleton.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(wrist,parent_q.inverse()*desired)

func face(at: Vector3) -> void:
	var direction: Vector3 = at-get_parent().position
	if direction.length_squared()>0.001: heading = atan2(-direction.x,-direction.z)

func aim_at(at: Vector3, clip: String) -> void:
	face(at)
	# Cover clips aim over a shoulder in their authored local frame. Align that
	# frame with the solved target, rather than rotating every clip as a -Z shot.
	var time := event_time(clip)
	var hands := (POSE.goal(clips,clip,"RightHandT",time)+POSE.goal(clips,clip,"LeftHandT",time))*.5
	hands.y = 0
	if hands.length_squared()>.01: heading -= atan2(-hands.x,-hands.z)

func duration(clip: String) -> float:
	return float(clips.get(clip,{}).get("duration",0.2))

func event_time(clip: String) -> float:
	for event in clips[clip].events:
		if event.name == "OnAction": return float(event.time)
	return duration(clip)*0.5

func capture_pose() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for i in range(skeleton.get_bone_count()): poses.append(skeleton.get_bone_pose(i))
	return poses

func blend_pose(poses: Array[Transform3D], amount: float) -> void:
	for i in range(poses.size()):
		var pose := skeleton.get_bone_pose(i)
		skeleton.set_bone_pose_position(i,poses[i].origin.lerp(pose.origin,amount))
		skeleton.set_bone_pose_rotation(i,poses[i].basis.get_rotation_quaternion().slerp(pose.basis.get_rotation_quaternion(),amount))

func idle_clip() -> String:
	if wounded == "躯干": return "body_damage"
	if wounded == "腿": return "idle_damage_leg"
	if wounded == "手臂":
		if cover_tier > 0: return "rifle_damage_hand_hide_loop" if gun in ["Rifle","Shotgun"] else "hide_damage_hand"
		return "damage_hand_rifle_loop" if gun in ["Rifle","Shotgun"] else "idle_damage_hand"
	if melee=="Ax": return "idle_ax_worried_3parts"
	if cover_tier > 0: return "rifle_hide" if gun in ["Rifle","Shotgun"] else "hide_1"
	return "rifle_idle_fast" if gun in ["Rifle","Shotgun"] else "idle_1"

func value(attribute: String, centered := true) -> float:
	var samples: Array = curves.curves.get(attribute, [])
	if samples.is_empty(): return 0.0
	var frame := fposmod(clock, float(curves.duration)) * float(curves.fps)
	var i := mini(int(frame), samples.size()-1)
	return lerpf(float(samples[i]), float(samples[mini(i+1, samples.size()-1)]), frame-floorf(frame)) - (float(curves.center.get(attribute, 0)) if centered else 0.0)

func _process(delta: float) -> void:
	if skeleton == null: return
	var actor := get_parent() as Node3D
	# Hidden units have no presented action or audible footstep. Avoid solving
	# every bone off-screen; reset travel history before they become visible.
	if not actor.is_visible_in_tree():
		previous = actor.position
		initialized = false
		weight = 0.0
		return
	if not initialized:
		previous = actor.position
		initialized = true
	var travel := actor.position - previous
	previous = actor.position
	travel.y = 0
	var distance := travel.length()
	# Teleports and hidden enemy fast-forward must not advance the gait.
	var walking := distance > 0.0001 and distance < 2.1
	locomotion_clip = "rifle_run" if gun in ["Rifle","Shotgun"] else "woman_run" if gender == 1 else "run_0"
	if melee=="Ax": locomotion_clip="ax_run"
	elif source_prefab=="HeavyGuy": locomotion_clip="rifle_run_heavy_guy"
	if wounded == "手臂": locomotion_clip = "run_damage_hand"
	if walking:
		heading = atan2(-travel.x, -travel.z)
		var old_clock := clock
		clock += distance / float(clips[locomotion_clip].stride) * duration(locomotion_clip)
		for event in clips[locomotion_clip].events:
			if action_clip.is_empty() and event.name in ["OnLeftStep","OnRightStep"] and floori((old_clock-float(event.time))/duration(locomotion_clip)) != floori((clock-float(event.time))/duration(locomotion_clip)):
				footstep.emit("left" if event.name == "OnLeftStep" else "right")
	actor.rotation.y = lerp_angle(actor.rotation.y, heading, 1.0-exp(-delta*22.0))
	if not action_clip.is_empty():
		action_time = minf(action_time+delta*playback_speed,duration(action_clip))
		action_blend = minf(1,action_blend+delta*12)
		apply_clip(action_clip,action_time)
		if action_blend<1: blend_pose(blend_from,action_blend)
		update_weapons()
		if action_time >= duration(action_clip) and not action_hold:
			action_clip = ""
		return
	var before := capture_pose()
	weight = move_toward(weight, 1.0 if walking else 0.0, delta*8.0)
	var idle := idle_clip()
	apply_clip(idle,duration(idle) if wounded=="腿" else fmod(Time.get_ticks_msec()/1000.0,duration(idle)))
	if weight > .001:
		var standing := capture_pose()
		apply_clip(locomotion_clip,fposmod(clock,duration(locomotion_clip)))
		blend_pose(standing,weight)
	# Blend OUT of a finished action too; previously the very next frame
	# reset wrists/hips to an unrelated rest pose, producing a visible snap.
	blend_pose(before,1.0-exp(-delta*(30.0 if walking else 14.0)))
	update_weapons()
