extends Node3D
class_name BankWorld3D

const CELL_WORLD := 1.4
const GRID_W := 60
const GRID_H := 40
const DEFAULT_CAMERA_SIZE := 22.4
const WALK_SPEED := 2.288 # Approximate pace from Cop.controller's walk blend-tree Speed threshold.
const RUN_SPEED := 6.0 # MaleCopWithAllWeapons.prefab RunSpeed; controller run threshold 6.501593.
const RUN_ACCEL_TIME := 0.10
const RUN_DECEL_TIME := 0.14
const WALK_SOURCE_PATH := "res://assets/characters/original_cop/walk_source_curves.json"
const ENEMY_ANIMATOR = preload("res://scripts/bank_enemy_animator.gd")
const NAV = preload("res://scripts/bank_navigation.gd")
const SOURCE_POSE = preload("res://scripts/bank_cop_source_pose.gd")
const BANK_SCENE: PackedScene = preload("res://assets/bank/original_scene/bank_original.gltf")
const COP_RIG: PackedScene = preload("res://assets/horde/actors/cop/cop_rig.gltf")
const WEAPON_MOTION=preload("res://scripts/horde_actor_motion.gd")
const ENEMY_MALE_RIG: PackedScene = preload("res://assets/characters/original_enemy_male/enemy_male_rig.gltf")
const HOSTAGE_PROSTITUTE_RIG: PackedScene = preload("res://assets/characters/original_hostage_prostitute/hostage_prostitute_v1_rig.gltf")
const DOOR_PREFABS := [
	preload("res://assets/bank/openings/ColdOpenDoor1/coldopendoor1_original.gltf"),
	preload("res://assets/bank/openings/ColdOpenDoor2/coldopendoor2_original.gltf"),
	preload("res://assets/bank/openings/ArmoredDoor1/armoreddoor1_original.gltf")
]
const WINDOW_PREFAB: PackedScene = preload("res://assets/bank/openings/Window1/window1_original.gltf")
const PERSON_OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;
uniform vec4 outline_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float outline_width = 0.045;
void vertex() {
	VERTEX += NORMAL * outline_width;
}
void fragment() {
	ALBEDO = outline_color.rgb;
}
"""
const BANK_GROUND := [
	preload("res://assets/bank/GroundTexture_Bank00_0.png"),
	preload("res://assets/bank/GroundTexture_Bank01_0.png"),
	preload("res://assets/bank/GroundTexture_Bank10_0.png"),
	preload("res://assets/bank/GroundTexture_Bank11_0.png")
]

var camera: Camera3D
var cop_nodes: Array[Node3D] = []
var cop_tiles: Array[Vector2i] = []
var cop_motion_tweens: Dictionary = {}
var planned_routes: Dictionary = {}
var cop_gesture_tweens: Dictionary = {}
var cop_pose_axes: Array[Dictionary] = []
var cop_skeletons: Array[Skeleton3D] = []
var cop_leg_rest: Array[Dictionary] = []
var cop_hip_rest: Array[Vector3] = []
var cop_walk_time: Array[float] = []
var cop_motion_duration: Array[float] = []
var cop_turn_delay: Array[float] = []
var walk_source: Dictionary = {}
var run_source: Dictionary = {}
var interaction_source: Dictionary = {}
var cop_active_clips: Dictionary = {}
var vault_event_times: Dictionary = {}
var vault_start_heading: Dictionary = {}
var cop_motion_paths: Dictionary = {}
var cop_step_players: Array[AudioStreamPlayer] = []
var cop_step_index: Array[int] = []
var indoor_steps: Array[AudioStream] = []
var outdoor_steps: Array[AudioStream] = []
var cop_outlines: Array[ShaderMaterial] = []
var guard_nodes: Array[Node3D] = []
var guard_animators: Array = []
var guard_outlines: Array[ShaderMaterial] = []
var guard_tiles: Dictionary = {}
var guard_move_tweens: Dictionary = {}
var enemy_source: Dictionary = {}
var hostage_nodes: Array[Node3D] = []
var door_nodes: Dictionary = {}
var source_door_nodes: Dictionary = {}
var source_window_nodes: Dictionary = {}
var source_openings_ready := false
var objective_ring: MeshInstance3D
var selection_ring: MeshInstance3D
var movement_outline: MeshInstance3D
var movement_fills: Array[MeshInstance3D] = []
var movement_bands: Dictionary = {}
var person_outline_shader: Shader
var destination_ghost: Node3D
var destination_disk: MeshInstance3D
var destination_actor := -1
var destination_tile := Vector2i(-1, -1)
var cover_edges: Array = []
var cover_openings: Dictionary = {}
var posture_time: Array[float] = [0.0, 0.0, 0.0]
var low_cover: Array[bool] = [false, false, false]
var preview_time := 0.0
var cop_weapon_rigs: Array=[]
var scout_mesh: MeshInstance3D

func _process(delta: float) -> void:
	if interaction_source.is_empty(): return
	preview_time += delta
	for i in range(cop_skeletons.size()):
		if cop_motion_tweens.has(i) or cop_gesture_tweens.has(i): continue
		posture_time[i] += delta
		var covered := i < cop_tiles.size() and has_low_cover(cop_tiles[i])
		if covered != low_cover[i]:
			low_cover[i] = covered
			posture_time[i] = 0.0
		var transition := "idle_to_hide" if covered else "hide_to_idle"
		var duration := float(interaction_source[transition]["duration"])
		var clip := transition if posture_time[i] < duration else ("hide_1" if covered else "idle_1")
		var time := posture_time[i] if posture_time[i] < duration else posture_time[i] - duration
		_set_cop_source_pose(i, clip, time, 1.0)
	if destination_ghost != null and destination_ghost.visible and destination_actor >= 0:
		var skeleton := destination_ghost.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var clip := "hide_1" if has_low_cover(destination_tile) else "idle_1"
		SOURCE_POSE.apply(skeleton, cop_leg_rest[destination_actor], cop_pose_axes[destination_actor], cop_hip_rest[destination_actor], interaction_source, clip, preview_time, 1.0)

func has_low_cover(tile: Vector2i) -> bool:
	# EdgeTypesExtensions.GetCover: these five edge types provide half cover.
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if NAV.edge_type(NAV.edge_index(tile, tile + offset), cover_edges, cover_openings) in [2, 3, 9, 10, 14]: return true
	return false

func show_destination_preview(tile: Vector2i, actor: int, route: Array) -> void:
	if destination_ghost == null:
		destination_ghost = COP_RIG.instantiate() as Node3D
		destination_ghost.name = "DestinationPreviewNotAnActor"
		add_child(destination_ghost)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.22, 0.68, 1.0, 0.68)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		for node in destination_ghost.find_children("*", "MeshInstance3D", true, false):
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		destination_disk = _marker("DestinationPreviewDisk", Color("#b6e8ff"), 0.44)
	if tile.x < 0 or actor < 0:
		destination_ghost.hide()
		destination_disk.hide()
		return
	destination_ghost.show()
	destination_disk.show()
	destination_actor = actor
	destination_tile = tile
	destination_ghost.position = _grid(tile)
	destination_disk.position = _grid(tile, 0.045)
	var skeleton := destination_ghost.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var source := cop_skeletons[actor]
	for bone in range(source.get_bone_count()):
		skeleton.set_bone_pose_position(bone, source.get_bone_pose_position(bone))
		skeleton.set_bone_pose_rotation(bone, source.get_bone_pose_rotation(bone))
	if route.size() >= 2:
		var direction := _grid(tile) - _grid(route[route.size() - 2])
		destination_ghost.rotation.y = atan2(-direction.x, -direction.z)
	else:
		destination_ghost.rotation.y = cop_nodes[actor].rotation.y

func hide_destination_preview() -> void:
	if destination_ghost != null:
		destination_ghost.hide()
		destination_disk.hide()

func _ready() -> void:
	_build_lighting()
	var original_scene := BANK_SCENE.instantiate() as Node3D
	original_scene.name = "OriginalBankStaticScene"
	add_child(original_scene)
	_hide_roof_for_tactical_view(original_scene)
	_restore_static_vertex_colors(original_scene)
	walk_source = JSON.parse_string(FileAccess.get_file_as_string(WALK_SOURCE_PATH)) as Dictionary
	assert(walk_source.has("curves") and walk_source.has("events"), "Source walk curves are missing")
	run_source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/original_cop/run_source_curves.json")) as Dictionary
	assert(run_source.get("guid") == "66fbe64e1f22b37449b81643b11066b4", "Wrong cop run source")
	interaction_source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/original_cop/interaction_source_curves.json")) as Dictionary
	enemy_source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/original_enemy_male/enemy_source_curves.json")) as Dictionary
	assert(enemy_source.has("enemy_idle") and enemy_source.has("surrender"), "Enemy source clips are missing")
	_load_footsteps()
	_build_people()
	_build_markers()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Bank.unity: orthographic size 14, InitialCameraZoomMultiplier 0.8.
	# Unity stores half-height; Godot Camera3D.size uses full viewport height.
	camera.size = DEFAULT_CAMERA_SIZE
	camera.current = true
	add_child(camera)
	set_view(Vector2i(8, 11))

func _hide_roof_for_tactical_view(root: Node) -> void:
	if root.name.begins_with("CombineMeshRoof1"):
		root.visible = false
		return
	for child in root.get_children():
		_hide_roof_for_tactical_view(child)

func _restore_static_vertex_colors(root: Node) -> void:
	if root is MeshInstance3D:
		var instance := root as MeshInstance3D
		for surface in range(instance.mesh.get_surface_count()):
			if instance.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR:
				var source := instance.get_active_material(surface) as StandardMaterial3D
				if source != null:
					var material := source.duplicate() as StandardMaterial3D
					material.vertex_color_use_as_albedo = true
					instance.set_surface_override_material(surface, material)
	for child in root.get_children():
		_restore_static_vertex_colors(child)

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("#d9bda8")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#7c7373")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#aa9a9b")
	settings.ambient_light_energy = 0.55
	environment.environment = settings
	add_child(environment)

func _build_ground() -> void:
	var base := _box("GroundBase", Vector3(GRID_W * CELL_WORLD / 2.0, -0.13, GRID_H * CELL_WORLD / 2.0), Vector3(GRID_W * CELL_WORLD, 0.2, GRID_H * CELL_WORLD), Color("#777771"))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var half_width := GRID_W * CELL_WORLD / 2.0
	var half_depth := GRID_H * CELL_WORLD / 2.0
	for gx in range(2):
		for gy in range(2):
			var ground := MeshInstance3D.new()
			ground.name = "OriginalBankGround_%d%d" % [gx, gy]
			var plane := PlaneMesh.new()
			plane.size = Vector2(half_width, half_depth)
			ground.mesh = plane
			ground.position = Vector3((gx + 0.5) * half_width, -0.02, (gy + 0.5) * half_depth)
			ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var material := StandardMaterial3D.new()
			material.albedo_texture = BANK_GROUND[gx * 2 + gy]
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ground.set_surface_override_material(0, material)
			add_child(ground)

func _build_building() -> void:
	var bank_center := Vector3(31.5 * CELL_WORLD, 0.05, 20.5 * CELL_WORLD)
	_box("BankFloor", bank_center, Vector3(23 * CELL_WORLD, 0.12, 17 * CELL_WORLD), Color("#8d826d"))
	for x in range(20, 44):
		_wall(Vector2i(x, 12))
		_wall(Vector2i(x, 29))
	for z in range(13, 29):
		if z == 14 or z == 24:
			var door := _box("BankDoor_%d" % z, _grid(Vector2i(20, z), 0.95), Vector3(0.24, 1.9, CELL_WORLD * 0.83), Color("#9b724c"))
			door_nodes[Vector2i(20, z)] = door
		else:
			_wall(Vector2i(20, z))
		_wall(Vector2i(43, z))

	for pillar in [Vector2i(20, 12), Vector2i(20, 29), Vector2i(43, 12), Vector2i(43, 29)]:
		_box("StonePillar", _grid(pillar, 1.45), Vector3(0.9, 2.9, 0.9), Color("#d2c4a8"))

	for x in range(23, 41, 4):
		_box("BankWindow", _grid(Vector2i(x, 12), 1.12), Vector3(CELL_WORLD * 2.4, 0.95, 0.16), Color("#7cacae"))
	for z in range(16, 28, 4):
		_box("SideWindow", _grid(Vector2i(43, z), 1.12), Vector3(0.16, 0.95, CELL_WORLD * 2.1), Color("#7cacae"))

	# The roof is removed like the original tactical view, keeping the interior visible.
	for cover in [Vector2i(22, 24), Vector2i(23, 24), Vector2i(25, 18), Vector2i(29, 22), Vector2i(34, 26), Vector2i(36, 17), Vector2i(38, 23)]:
		_box("Cover_%d_%d" % [cover.x, cover.y], _grid(cover, 0.42), Vector3(1.2, 0.82, 1.1), Color("#a17f57"))
	for desk in [Vector2i(31, 19), Vector2i(34, 19), Vector2i(37, 19)]:
		_box("ServiceCounter", _grid(desk, 0.62), Vector3(2.0, 1.2, 0.72), Color("#5a443a"))
		_box("CounterTop", _grid(desk, 1.26), Vector3(2.1, 0.1, 0.85), Color("#b49770"))
	for bench in [Vector2i(25, 25), Vector2i(27, 25), Vector2i(25, 16), Vector2i(27, 16)]:
		_box("WaitingBench", _grid(bench, 0.24), Vector3(1.2, 0.42, 0.65), Color("#58493d"))

	var sign := Label3D.new()
	sign.text = "BANK"
	sign.font_size = 112
	sign.pixel_size = 0.008
	sign.modulate = Color("#e6d5ae")
	sign.position = _grid(Vector2i(20, 20), 2.7)
	sign.rotation_degrees.y = -90
	add_child(sign)

func _wall(tile: Vector2i) -> void:
	_box("BankWall", _grid(tile, 0.78), Vector3(CELL_WORLD * 0.95, 1.55, CELL_WORLD * 0.95), Color("#c4b6a0"))

func _build_street() -> void:
	for z in [14, 21, 28]:
		for x in range(7, 18, 2):
			_box("RoadMark", _grid(Vector2i(x, z), 0.025), Vector3(0.9, 0.02, 0.11), Color("#d6d3c8"))
	for z in [15, 31]:
		for x in [8, 16, 23, 45]:
			_tree(Vector2i(x, z))
	_car(Vector2i(9, 18), Color("#4d6573"))
	_car(Vector2i(11, 29), Color("#766857"))
	for x in [18, 44]:
		for z in [13, 28]:
			_box("StreetLamp", _grid(Vector2i(x, z), 1.5), Vector3(0.11, 3.0, 0.11), Color("#303c40"))
			_box("LampHead", _grid(Vector2i(x, z), 3.05), Vector3(0.5, 0.13, 0.5), Color("#e2c790"))

func _tree(tile: Vector2i) -> void:
	_box("TreeTrunk", _grid(tile, 0.8), Vector3(0.25, 1.6, 0.25), Color("#574735"))
	var crown := MeshInstance3D.new()
	crown.name = "TreeCrown"
	var sphere := SphereMesh.new()
	sphere.radius = 1.06
	sphere.height = 2.1
	crown.mesh = sphere
	crown.position = _grid(tile, 2.1)
	crown.set_surface_override_material(0, _material(Color("#67735f")))
	add_child(crown)

func _car(tile: Vector2i, color: Color) -> void:
	_box("ParkedCar", _grid(tile, 0.34), Vector3(2.45, 0.68, 1.28), color)
	_box("CarCabin", _grid(tile, 0.75), Vector3(1.28, 0.32, 0.97), Color("#a6b8b6"))
	for dx in [-0.8, 0.8]:
		for dz in [-0.58, 0.58]:
			_box("Wheel", _grid(tile, 0.17) + Vector3(dx, 0, dz), Vector3(0.34, 0.34, 0.2), Color("#222629"))

func _build_people() -> void:
	for i in range(3):
		cop_nodes.append(_original_cop("Cop_%d" % (i + 1)))
		var skeleton := cop_nodes[i].find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		cop_skeletons.append(skeleton)
		# Preserve imported bind rotations; local X is the long axis of several
		# bones, not a knee/hip hinge. Map anatomical axes into each posed bone.
		for bone in range(skeleton.get_bone_count()):
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
		for side in ["Left", "Right"]:
			var arm := skeleton.find_bone(side + "Arm")
			var axis := (skeleton.get_bone_global_rest(arm).basis.inverse() * Vector3.BACK).normalized()
			var angle := deg_to_rad(70.0 if side == "Left" else -70.0)
			skeleton.set_bone_pose_rotation(arm, skeleton.get_bone_pose_rotation(arm) * Quaternion(axis, angle))
		var rest := {}
		var axes := {}
		for bone_name in ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "Spine", "Spine1"]:
			var bone := skeleton.find_bone(bone_name)
			if bone >= 0:
				rest[bone_name] = skeleton.get_bone_pose_rotation(bone)
				var inverse := skeleton.get_bone_global_pose(bone).basis.inverse()
				axes[bone_name] = [(inverse * Vector3.RIGHT).normalized(), (inverse * Vector3.BACK).normalized(), (inverse * Vector3.UP).normalized()]
		cop_leg_rest.append(rest)
		cop_pose_axes.append(axes)
		cop_hip_rest.append(skeleton.get_bone_pose_position(skeleton.find_bone("Hips")))
		cop_walk_time.append(0.0)
		cop_motion_duration.append(0.0)
		cop_turn_delay.append(0.0)
		cop_step_index.append(0)
		var step_player := AudioStreamPlayer.new()
		step_player.volume_db = -11.0
		add_child(step_player)
		cop_step_players.append(step_player)
		guard_nodes.append(_original_enemy("Guard_%d" % (i + 1)))

func _load_footsteps() -> void:
	var base := "res://assets/bank/audio/footsteps/"
	for name in ["Step L1.ogg", "Step R1.ogg", "Step L2.ogg", "Step R2.ogg"]:
		indoor_steps.append(AudioStreamOggVorbis.load_from_file(base + name))
	for name in ["Snow L1.ogg", "Snow R1.ogg", "Snow L2.ogg", "Snow R2.ogg"]:
		outdoor_steps.append(AudioStreamOggVorbis.load_from_file(base + name))

func _play_cop_step(index: int, foot: String) -> void:
	# CharacterFootStep.cs selects room footsteps indoors and the Snow bank outdoors.
	var tile := Vector2i(floori(cop_nodes[index].position.x / CELL_WORLD), floori(-cop_nodes[index].position.z / CELL_WORLD))
	var sounds := indoor_steps if tile.x >= 20 and tile.x <= 44 and tile.y >= 12 and tile.y <= 29 else outdoor_steps
	var variation := floori(float(cop_step_index[index]) / 2.0) % 2
	var sound: AudioStream = sounds[int(variation) * 2 + (0 if foot == "left" else 1)]
	cop_step_index[index] += 1
	if sound != null:
		cop_step_players[index].stream = sound
		cop_step_players[index].play()

func reset_cop_motion() -> void:
	for rig in cop_weapon_rigs: rig.release_action();rig.set_process(false)
	if scout_mesh!=null: scout_mesh.hide()
	for gesture in cop_gesture_tweens.values():
		(gesture as Tween).kill()
	cop_gesture_tweens.clear()
	cop_active_clips.clear()
	vault_event_times.clear()
	vault_start_heading.clear()
	planned_routes.clear()
	for motion in cop_motion_tweens.values():
		if motion is Tween:
			motion.kill()
	cop_motion_tweens.clear()
	cop_motion_paths.clear()
	cop_tiles.clear()
	for i in range(cop_skeletons.size()):
		cop_walk_time[i] = 0.0
		cop_motion_duration[i] = 0.0
		cop_turn_delay[i] = 0.0
		cop_step_index[i] = 0
		posture_time[i] = 10.0
		low_cover[i] = false
		_set_cop_gait(i, 0.0, 0.0)
		cop_step_players[i].stop()

func _play_walk_events(index: int, previous_time: float, current_time: float) -> void:
	var duration := float(run_source["duration"])
	for cycle in range(floori(previous_time / duration), floori(current_time / duration) + 1):
		for event in run_source["events"]:
			var at := float(cycle) * duration + float(event["time"])
			if previous_time < at and at <= current_time:
				_play_cop_step(index, str(event["foot"]))

func _walk_value(name: String, time: float) -> float:
	var duration := float(run_source["duration"])
	var curve: Array = run_source["curves"][name]
	var frame := fposmod(time, duration) / duration * float(curve.size() - 1)
	var first := floori(frame)
	var second := mini(first + 1, curve.size() - 1)
	return lerpf(float(curve[first]), float(curve[second]), frame - float(first))

func _walk_offset(name: String, time: float) -> float:
	return _walk_value(name, time) - float(run_source["center"][name])

func _set_cop_gait(index: int, time: float, weight: float) -> void:
	var skeleton := cop_skeletons[index]
	var rest: Dictionary = cop_leg_rest[index]
	var hips := skeleton.find_bone("Hips")
	skeleton.set_bone_pose_rotation(hips, skeleton.get_bone_rest(hips).basis.get_rotation_quaternion())
	var bob := _walk_offset("RootT.y", time) * 0.65 * weight
	skeleton.set_bone_pose_position(hips, cop_hip_rest[index] + Vector3(0, bob, 0))
	for bone_name in rest:
		var amount := 0.0
		var spread := 0.0
		var twist := 0.0
		match bone_name:
			"LeftUpLeg":
				amount = _walk_offset("Left Upper Leg Front-Back", time) * 0.78
				spread = _walk_offset("Left Upper Leg In-Out", time) * 0.25
			"RightUpLeg":
				amount = _walk_offset("Right Upper Leg Front-Back", time) * 0.78
				spread = -_walk_offset("Right Upper Leg In-Out", time) * 0.25
			"LeftLeg": amount = -maxf(0.0, 0.9 - _walk_value("Left Lower Leg Stretch", time)) * 0.95
			"RightLeg": amount = -maxf(0.0, 0.9 - _walk_value("Right Lower Leg Stretch", time)) * 0.95
			"LeftFoot": amount = _walk_offset("Left Foot Up-Down", time) * 0.6
			"RightFoot": amount = _walk_offset("Right Foot Up-Down", time) * 0.6
			"LeftArm": amount = _walk_offset("Left Arm Front-Back", time) * 1.1
			"RightArm": amount = _walk_offset("Right Arm Front-Back", time) * 1.1
			"LeftForeArm": amount = maxf(0.0, 1.0 - _walk_value("Left Forearm Stretch", time)) * 1.8
			"RightForeArm": amount = maxf(0.0, 1.0 - _walk_value("Right Forearm Stretch", time)) * 1.8
			"Spine":
				amount = -0.12 + _walk_offset("Spine Front-Back", time) * 0.45
				spread = _walk_offset("Spine Left-Right", time) * 0.35
				twist = _walk_offset("Spine Twist Left-Right", time) * 0.40
			"Spine1":
				amount = _walk_offset("Chest Front-Back", time) * 0.45
				spread = _walk_offset("Chest Left-Right", time) * 0.35
				twist = _walk_offset("Chest Twist Left-Right", time) * 0.35
		if bone_name == "LeftArm":
			spread = _walk_offset("Left Arm Down-Up", time) * 0.55
		elif bone_name == "RightArm":
			spread = -_walk_offset("Right Arm Down-Up", time) * 0.55
		var bone := skeleton.find_bone(bone_name)
		var axes: Array = cop_pose_axes[index][bone_name]
		skeleton.set_bone_pose_rotation(bone, (rest[bone_name] as Quaternion) * Quaternion(axes[0], amount * weight) * Quaternion(axes[1], spread * weight) * Quaternion(axes[2], twist * weight))
	# Ground contact correction for the approximate Humanoid retarget.
	if weight > 0.0:
		var left := skeleton.find_bone("LeftFoot")
		var right := skeleton.find_bone("RightFoot")
		var floor_height := minf(skeleton.get_bone_global_rest(left).origin.y, skeleton.get_bone_global_rest(right).origin.y)
		var foot_height := minf(skeleton.get_bone_global_pose(left).origin.y, skeleton.get_bone_global_pose(right).origin.y)
		var correction := clampf(floor_height - foot_height, -0.2, 0.2) * weight
		skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + Vector3.UP * correction)

func play_cop_gesture(index: int, tile: Vector2i, action: int) -> Dictionary:
	# Return event timing to the action owner: effects may not precede contact.
	# Actions without a converted clip still use the explicit legacy fallback.
	var node := cop_nodes[index]
	var direction := _grid(tile) - node.position
	var tween := create_tween()
	cop_gesture_tweens[index] = tween
	var turn_time := 0.0
	if direction.length_squared() > 0.01:
		var heading := node.rotation.y + wrapf(atan2(-direction.x, -direction.z) - node.rotation.y, -PI, PI)
		turn_time = minf(0.18, absf(heading - node.rotation.y) / 12.0)
		if turn_time > 0.001: tween.tween_property(node, "rotation:y", heading, turn_time).set_trans(Tween.TRANS_SINE)
	if action in [10,11,35]:
		var motion=cop_weapon_rigs[index]
		var phases: Array=["gun_shooting_standing_start","gun_shooting_standing_shoot","gun_shooting_standing_end"] if action==10 else ["idle_reload" if action==11 else "interact"]
		var total:=turn_time
		var impact:=turn_time
		for phase: String in phases:
			if phase=="gun_shooting_standing_shoot" or action!=10: impact=total+float(motion.event_time(phase))
			tween.tween_callback(func(): motion.heading=node.rotation.y;motion.start_clip(phase,true);motion.set_process(true))
			tween.tween_interval(motion.duration(phase))
			total+=float(motion.duration(phase))
		# Keep this controller as the sole skeleton owner during the gesture.
		tween.tween_callback(func():
			motion.release_action();motion.set_process(false)
			cop_gesture_tweens.erase(index);cop_active_clips.erase(index))
		return {"impact":impact,"duration":total,"clip":phases[0]}
	var clip: String = {1: "baton_attack", 5: "arresting", 38: "door_window_open_shortright"}.get(action, "")
	var timing := {"impact": 0.5, "duration": 1.0, "clip": clip}
	if not clip.is_empty():
		var duration := float(interaction_source[clip]["duration"])
		for event in interaction_source[clip]["events"]:
			if event["name"] == "OnAction": timing["impact"] = turn_time + float(event["time"])
		timing["duration"] = turn_time + duration + 0.16
		cop_active_clips[index] = clip
		tween.tween_method(_advance_source_gesture.bind(index, clip), 0.0, duration, duration)
		tween.tween_method(_blend_out_source_gesture.bind(index, clip, duration), 1.0, 0.0, 0.16)
	else:
		tween.tween_method(_gesture_pose.bind(index, action), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_SINE)
		tween.tween_method(_gesture_pose.bind(index, action), 1.0, 0.0, 0.42).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		cop_gesture_tweens.erase(index)
		cop_active_clips.erase(index)
		_set_cop_gait(index, 0.0, 0.0))
	return timing

func _advance_source_gesture(time: float, index: int, clip: String) -> void:
	_set_cop_source_pose(index, clip, time, smoothstep(0.0, 0.12, time))

func _blend_out_source_gesture(weight: float, index: int, clip: String, time: float) -> void:
	_set_cop_source_pose(index, clip, time, weight)

func _set_cop_source_pose(index: int, clip: String, time: float, weight: float) -> void:
	SOURCE_POSE.apply(cop_skeletons[index], cop_leg_rest[index], cop_pose_axes[index], cop_hip_rest[index], interaction_source, clip, time, weight)

func _gesture_pose(weight: float, index: int, action: int) -> void:
	_set_cop_gait(index, 0.0, 0.0)
	var skeleton := cop_skeletons[index]
	for name in ["RightArm", "LeftArm", "Spine"]:
		var amplitude := -0.85 if name == "RightArm" else (-0.5 if name == "LeftArm" else 0.0)
		if action in [5, 55] and name == "Spine": amplitude = 0.25
		if action == 1 and name == "RightArm": amplitude = -1.25
		var axis: Vector3 = cop_pose_axes[index][name][0]
		skeleton.set_bone_pose_rotation(skeleton.find_bone(name), cop_leg_rest[index][name] * Quaternion(axis, amplitude * weight))

func _animate_cop_to(index: int, from_tile: Vector2i, to_tile: Vector2i, cells: Dictionary, grid_edges: Array, opened_edges: Dictionary) -> void:
	if cop_motion_tweens.has(index):
		(cop_motion_tweens[index] as Tween).kill()
		cop_motion_tweens.erase(index)
	var route_result := NAV.search(from_tile, 150.0, cells, grid_edges, opened_edges, {})
	var route: Array[Vector2i] = NAV.path(from_tile, to_tile, route_result["parents"])
	if planned_routes.has(index):
		route = planned_routes[index]
		planned_routes.erase(index)
	if route.is_empty():
		route = [to_tile]
	var previous := from_tile
	for tile in route:
		var edge := NAV.edge_index(previous, tile)
		if NAV.edge_type(edge, grid_edges, opened_edges) == 3:
			_animate_window_route(index, from_tile, route, grid_edges, opened_edges)
			return
		previous = tile
	var tween := create_tween()
	cop_motion_tweens[index] = tween
	cop_walk_time[index] = 0.0
	cop_turn_delay[index] = 0.0
	var points: Array[Vector3] = [_grid(from_tile)]
	var distances: Array[float] = [0.0]
	for tile in route:
		var next := _grid(tile)
		var segment := next.distance_to(points.back())
		if segment <= 0.001: continue
		distances.append(distances.back() + segment)
		points.append(next)
	var length: float = distances.back()
	var duration := length / RUN_SPEED + (RUN_ACCEL_TIME + RUN_DECEL_TIME) * 0.5
	var direction: Vector3 = points[1] - points[0]
	var heading := cop_nodes[index].rotation.y
	var desired := atan2(-direction.x, -direction.z)
	var turn := wrapf(desired - heading, -PI, PI)
	if absf(turn) > 0.1:
		cop_turn_delay[index] = minf(0.18, absf(turn) / 12.0)
		tween.tween_property(cop_nodes[index], "rotation:y", heading + turn, cop_turn_delay[index]).set_trans(Tween.TRANS_SINE)
	cop_motion_duration[index] = duration + cop_turn_delay[index]
	cop_motion_paths[index] = {"points": points, "distances": distances, "length": length, "duration": duration, "elapsed": 0.0, "phase": 0.0}
	# One distance clock for the entire verified polyline: accelerate once,
	# run through cell boundaries, decelerate once. Never ease every tile.
	tween.tween_method(_advance_cop_motion.bind(index), 0.0, duration, duration)
	tween.tween_callback(_finish_cop_motion.bind(index))

func _motion_distance(elapsed: float, duration: float, length: float) -> float:
	if elapsed < RUN_ACCEL_TIME:
		return RUN_SPEED * elapsed * elapsed / (2.0 * RUN_ACCEL_TIME)
	if elapsed > duration - RUN_DECEL_TIME:
		var remaining := maxf(0.0, duration - elapsed)
		return length - RUN_SPEED * remaining * remaining / (2.0 * RUN_DECEL_TIME)
	return RUN_SPEED * (elapsed - RUN_ACCEL_TIME * 0.5)

func _advance_cop_motion(elapsed: float, index: int) -> void:
	if not cop_motion_paths.has(index): return
	var data: Dictionary = cop_motion_paths[index]
	var distance := clampf(_motion_distance(elapsed, data["duration"], data["length"]), 0.0, data["length"])
	var points: Array = data["points"]
	var distances: Array = data["distances"]
	var segment := 1
	while segment < points.size() - 1 and distance > float(distances[segment]): segment += 1
	var direction: Vector3 = points[segment] - points[segment - 1]
	var fraction := (distance - float(distances[segment - 1])) / direction.length()
	cop_nodes[index].position = (points[segment - 1] as Vector3).lerp(points[segment], fraction)
	var desired := atan2(-direction.x, -direction.z)
	var difference := wrapf(desired - cop_nodes[index].rotation.y, -PI, PI)
	var delta := maxf(0.0, elapsed - float(data["elapsed"]))
	cop_nodes[index].rotation.y += clampf(difference, -16.0 * delta, 16.0 * delta)
	# Feet, body and footstep events follow travelled distance, not an unrelated
	# wall-clock animation. Startup/slowdown therefore do not cause fast shuffling.
	var phase := distance / RUN_SPEED
	_play_walk_events(index, data["phase"], phase)
	var blend := minf(1.0, minf(elapsed / RUN_ACCEL_TIME, (float(data["duration"]) - elapsed) / RUN_DECEL_TIME))
	_set_cop_gait(index, phase, maxf(0.0, blend))
	data["phase"] = phase
	data["elapsed"] = elapsed
	cop_walk_time[index] = elapsed + cop_turn_delay[index]

func _finish_cop_motion(index: int) -> void:
	cop_motion_tweens.erase(index)
	cop_motion_paths.erase(index)
	cop_active_clips.erase(index)
	vault_event_times.erase(index)
	vault_start_heading.erase(index)
	# Arrival starts the correct source idle/cover transition on the next frame.
	low_cover[index] = has_low_cover(cop_tiles[index]) if index < cop_tiles.size() else false
	posture_time[index] = 0.0 if low_cover[index] else 10.0
	_set_cop_gait(index, 0.0, 0.0)

func _animate_window_route(index: int, start: Vector2i, route: Array[Vector2i], edges: Array, opened_edges: Dictionary) -> void:
	# Split only at window edges. Continuous runs retain a single distance clock;
	# the sill crossing uses source root travel, limb curves and landing events.
	var tween := create_tween()
	cop_motion_tweens[index] = tween
	cop_motion_duration[index] = 0.0
	cop_walk_time[index] = 0.0
	cop_turn_delay[index] = 0.0
	var run: Array[Vector3] = [_grid(start)]
	var previous := start
	for tile in route:
		var edge := NAV.edge_index(previous, tile)
		if NAV.edge_type(edge, edges, opened_edges) == 3:
			_queue_run_span(tween, index, run)
			var from := _grid(previous)
			var to := _grid(tile)
			var duration := float(interaction_source["climbing_low"]["duration"])
			tween.tween_callback(_begin_vault.bind(index, from, to))
			tween.tween_method(_advance_vault.bind(index, from, to), 0.0, duration, duration)
			cop_motion_duration[index] += duration
			run = [to]
		else:
			run.append(_grid(tile))
		previous = tile
	_queue_run_span(tween, index, run)
	tween.tween_callback(_finish_cop_motion.bind(index))

func _queue_run_span(tween: Tween, index: int, points: Array[Vector3]) -> void:
	if points.size() < 2: return
	var distances: Array[float] = [0.0]
	for i in range(1, points.size()): distances.append(distances.back() + points[i].distance_to(points[i - 1]))
	var length: float = distances.back()
	var duration := length / RUN_SPEED + (RUN_ACCEL_TIME + RUN_DECEL_TIME) * 0.5
	var data := {"points": points.duplicate(), "distances": distances, "length": length, "duration": duration, "elapsed": 0.0, "phase": 0.0}
	tween.tween_callback(func():
		cop_motion_paths[index] = data
		cop_active_clips[index] = "run")
	tween.tween_method(_advance_cop_motion.bind(index), 0.0, duration, duration)
	cop_motion_duration[index] += duration

func _begin_vault(index: int, from: Vector3, to: Vector3) -> void:
	cop_active_clips[index] = "climbing_low"
	vault_event_times[index] = 0.0
	cop_motion_paths.erase(index)
	vault_start_heading[index] = cop_nodes[index].rotation.y

func _advance_vault(time: float, index: int, from: Vector3, to: Vector3) -> void:
	var clip := "climbing_low"
	var duration := float(interaction_source[clip]["duration"])
	var direction := to - from
	cop_nodes[index].rotation.y = lerp_angle(float(vault_start_heading.get(index, cop_nodes[index].rotation.y)), atan2(-direction.x, -direction.z), smoothstep(0.0, 0.16, time))
	var start_z := SOURCE_POSE.sample(interaction_source, clip, "RootT.z", 0.0)
	var end_z := SOURCE_POSE.sample(interaction_source, clip, "RootT.z", duration)
	var z := SOURCE_POSE.sample(interaction_source, clip, "RootT.z", time)
	var progress := clampf((z - start_z) / (end_z - start_z), 0.0, 1.0)
	cop_nodes[index].position = from.lerp(to, progress)
	var blend := minf(smoothstep(0.0, 0.10, time), smoothstep(0.0, 0.12, duration - time))
	_set_cop_source_pose(index, clip, time, blend)
	for event in interaction_source[clip]["events"]:
		if float(vault_event_times.get(index, 0.0)) < float(event["time"]) and time >= float(event["time"]):
			if event["name"] == "OnRightStep": _play_cop_step(index, "right")
			elif event["name"] == "OnLeftStep": _play_cop_step(index, "left")
	vault_event_times[index] = time

func _ensure_source_people(guard_count: int, hostage_count: int) -> void:
	while guard_nodes.size() < guard_count:
		guard_nodes.append(_original_enemy("Guard_%d" % (guard_nodes.size() + 1)))
	while hostage_nodes.size() < hostage_count:
		hostage_nodes.append(_original_hostage("Hostage_%d" % (hostage_nodes.size() + 1)))

func _ensure_source_openings(doors: Array, windows: Array, cells: Dictionary) -> void:
	if source_openings_ready:
		return
	for data in doors:
		if int(data["IsGenerated"]) == 0:
			continue
		var edge := int(data["EdgeIndex"])
		if source_door_nodes.has(edge):
			continue
		var model: Node3D = DOOR_PREFABS[int(data["MeshIndex"])].instantiate()
		model.name = "OriginalDoorEdge_%d" % edge
		_place_opening(model, edge, cells)
		_restore_static_vertex_colors(model)
		source_door_nodes[edge] = model
	for data in windows:
		if int(data["IsGenerated"]) == 0:
			continue
		var edge := int(data["EdgeIndex"])
		if source_window_nodes.has(edge):
			continue
		var model := WINDOW_PREFAB.instantiate() as Node3D
		model.name = "OriginalWindowEdge_%d" % edge
		_place_opening(model, edge, cells)
		_restore_static_vertex_colors(model)
		var broken := model.find_child("Broken", true, false) as Node3D
		if broken != null:
			broken.visible = false
		source_window_nodes[edge] = model
	source_openings_ready = true

func _place_opening(model: Node3D, edge: int, cells: Dictionary) -> void:
	var y := edge / (GRID_W * 2)
	var x := (edge % (GRID_W * 2)) / 2
	var west := edge % 2 == 1
	var a := Vector2i(x, y)
	var b := a + (Vector2i.LEFT if west else Vector2i.UP)
	var raised := (cells.has(a) and int(cells[a]["Height"]) == 2) or (cells.has(b) and int(cells[b]["Height"]) == 2)
	model.position = Vector3((float(x) + (0.0 if west else 0.5)) * CELL_WORLD,
		0.7 if raised else 0.0, -(float(y) + (0.5 if west else 0.0)) * CELL_WORLD)
	model.rotation_degrees.y = -90.0 if west else 0.0
	add_child(model)

func _opening_touched(edge: int, opened: Dictionary) -> bool:
	var y := edge / (GRID_W * 2)
	var x := (edge % (GRID_W * 2)) / 2
	var a := Vector2i(x, y)
	var b := a + (Vector2i.LEFT if edge % 2 == 1 else Vector2i.UP)
	return opened.has(a) or opened.has(b)

func _original_cop(person_name: String) -> Node3D:
	var person := Node3D.new()
	person.name = person_name
	add_child(person)
	var model := COP_RIG.instantiate() as Node3D
	person.add_child(model)
	_configure_original_cop(model)
	var motion=WEAPON_MOTION.new()
	motion.name="WeaponMotion"
	person.add_child(motion)
	motion.initialize(model);motion.configure_weapons(model)
	motion.gun="Glock";motion.update_weapons();motion.set_process(false)
	cop_weapon_rigs.append(motion)
	cop_outlines.append(_attach_person_outline(model, Color("#47a8d5")))
	return person

func show_room_scout(ids: Array,room: int) -> void:
	if scout_mesh==null:
		scout_mesh=MeshInstance3D.new();scout_mesh.name="ScoutRoomHighlight"
		scout_mesh.mesh=ImmediateMesh.new()
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color(.35,.72,.88,.22)
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		scout_mesh.material_override=material
		scout_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(scout_mesh)
	var mesh:=scout_mesh.mesh as ImmediateMesh
	mesh.clear_surfaces();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(GRID_W):
		for y in range(GRID_H):
			if int(ids[x*GRID_H+y])!=room: continue
			var at:=_grid(Vector2i(x,y),.15)
			for corner in [Vector3(-.7,0,-.7),Vector3(.7,0,-.7),Vector3(.7,0,.7),Vector3(-.7,0,-.7),Vector3(.7,0,.7),Vector3(-.7,0,.7)]: mesh.surface_add_vertex(at+corner)
	mesh.surface_end();scout_mesh.show()

func _original_enemy(person_name: String) -> Node3D:
	var person := Node3D.new()
	person.name = person_name
	add_child(person)
	var model := ENEMY_MALE_RIG.instantiate() as Node3D
	person.add_child(model)
	# The exported prefab retains its authoring-scene placement (11.62, 0, -4.969).
	# Grid placement owns this offset at runtime; keeping both displaced every enemy.
	var prefab_root := model.find_child("EnemyMale", true, false) as Node3D
	if prefab_root != null:
		prefab_root.position = Vector3.ZERO
	_configure_original_cop(model)
	guard_outlines.append(_attach_person_outline(model, Color("#d75b4a")))
	var animator := ENEMY_ANIMATOR.new()
	person.add_child(animator)
	animator.configure(model, enemy_source, float(guard_animators.size()) * 0.71)
	guard_animators.append(animator)
	return person

func reset_guard_visuals() -> void:
	for motion in guard_move_tweens.values():
		(motion as Tween).kill()
	guard_move_tweens.clear()
	guard_tiles.clear()
	for i in range(guard_animators.size()):
		guard_animators[i].reset()
		guard_nodes[i].rotation = Vector3.ZERO

func _finish_guard_move(index: int) -> void:
	guard_move_tweens.erase(index)
	guard_animators[index].moving = false
	if guard_animators[index].state == "逃离":
		guard_nodes[index].hide()

func _sync_guard_visual(index: int, guard: Dictionary, cells: Dictionary, grid_edges: Array, opened_edges: Dictionary) -> void:
	var target: Vector2i = guard["pos"]
	var node := guard_nodes[index]
	var animator = guard_animators[index]
	if guard["state"] in ["举手", "昏迷", "倒地", "已逮捕"] and guard_move_tweens.has(index):
		(guard_move_tweens[index] as Tween).kill()
		guard_move_tweens.erase(index)
		animator.moving = false
		node.position = _grid(target)
	if not guard_tiles.has(index):
		node.position = _grid(target)
	elif guard_tiles[index] != target:
		if guard_move_tweens.has(index):
			(guard_move_tweens[index] as Tween).kill()
			guard_move_tweens.erase(index)
		var start: Vector2i = guard_tiles[index]
		var search_result := NAV.search(start, 150.0, cells, grid_edges, opened_edges, {})
		var route: Array[Vector2i] = NAV.path(start, target, search_result["parents"])
		if route.is_empty():
			# No verified route: preserve the scripted logical placement, don't invent a wall-crossing animation.
			node.position = _grid(target)
			animator.moving = false
		else:
			var motion := create_tween()
			guard_move_tweens[index] = motion
			animator.moving = true
			node.show()
			var heading := node.rotation.y
			for tile in route:
				var direction := _grid(tile) - _grid(start)
				var duration := direction.length() / 2.0 # EnemyMale.prefab WalkSpeed.
				heading += wrapf(atan2(-direction.x, -direction.z) - heading, -PI, PI)
				motion.tween_property(node, "position", _grid(tile), duration)
				motion.parallel().tween_property(node, "rotation:y", heading, minf(duration, 0.22))
				start = tile
			motion.tween_callback(_finish_guard_move.bind(index))
	guard_tiles[index] = target
	animator.set_state(str(guard["state"]))
	var color := Color("#d75b4a")
	if guard["state"] in ["举手", "昏迷"]:
		color = Color("#d7b854")
	elif guard["state"] in ["倒地", "已逮捕"]:
		color = Color("#8b9298")
	guard_outlines[index].set_shader_parameter("outline_color", color)

func _original_hostage(person_name: String) -> Node3D:
	var person := Node3D.new()
	person.name = person_name
	add_child(person)
	var model := HOSTAGE_PROSTITUTE_RIG.instantiate() as Node3D
	person.add_child(model)
	_configure_original_cop(model)
	_attach_person_outline(model, Color("#d9c05c"))
	return person

func _attach_person_outline(model: Node, color: Color) -> ShaderMaterial:
	if person_outline_shader == null:
		person_outline_shader = Shader.new()
		person_outline_shader.code = PERSON_OUTLINE_SHADER
	var outline := ShaderMaterial.new()
	outline.shader = person_outline_shader
	outline.set_shader_parameter("outline_color", color)
	_apply_person_outline(model, outline)
	return outline

func _apply_person_outline(node: Node, outline: ShaderMaterial) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		for surface in range(mesh_node.mesh.get_surface_count()):
			var material := mesh_node.get_active_material(surface)
			if material != null:
				material.next_pass = outline
	for child in node.get_children():
		_apply_person_outline(child, outline)

func _configure_original_cop(node: Node) -> void:
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		for bone in range(skeleton.get_bone_count()):
			if skeleton.get_bone_name(bone) == "LeftArm":
				skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3.FORWARD, deg_to_rad(-70)))
			elif skeleton.get_bone_name(bone) == "RightArm":
				skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3.FORWARD, deg_to_rad(70)))
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		for surface in range(mesh_node.mesh.get_surface_count()):
			var source_material := mesh_node.get_active_material(surface) as StandardMaterial3D
			if source_material:
				var material := source_material.duplicate() as StandardMaterial3D
				material.vertex_color_use_as_albedo = true
				mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_configure_original_cop(child)

func _person(person_name: String, uniform_color: Color, skin_color: Color) -> Node3D:
	var person := Node3D.new()
	person.name = person_name
	add_child(person)
	_box("Body", Vector3(0, 0.87, 0), Vector3(0.55, 0.8, 0.35), uniform_color, person)
	_box("Belt", Vector3(0, 0.47, 0), Vector3(0.58, 0.12, 0.36), Color("#272b2c"), person)
	_box("Head", Vector3(0, 1.47, 0), Vector3(0.34, 0.34, 0.32), skin_color, person)
	_box("Cap", Vector3(0, 1.68, 0), Vector3(0.46, 0.16, 0.39), uniform_color.darkened(0.2), person)
	for x in [-0.18, 0.18]:
		_box("Leg", Vector3(x, 0.2, 0), Vector3(0.17, 0.43, 0.2), Color("#323b40"), person)
	for x in [-0.37, 0.37]:
		_box("Arm", Vector3(x, 0.87, 0), Vector3(0.16, 0.67, 0.19), uniform_color, person)
	return person

func _build_markers() -> void:
	selection_ring = _marker("Selection", Color("#ffdb80"), 0.68)
	objective_ring = MeshInstance3D.new()
	objective_ring.name = "ObjectiveTileOutline"
	var target_square := ImmediateMesh.new()
	target_square.surface_begin(Mesh.PRIMITIVE_LINES)
	var half := CELL_WORLD * 0.49
	var corners := [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]
	for i in range(4):
		target_square.surface_add_vertex(corners[i])
		target_square.surface_add_vertex(corners[(i + 1) % 4])
	target_square.surface_end()
	objective_ring.mesh = target_square
	var target_material := StandardMaterial3D.new()
	target_material.albedo_color = Color("#ffe394")
	target_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	objective_ring.material_override = target_material
	add_child(objective_ring)
	movement_outline = MeshInstance3D.new()
	movement_outline.name = "ReachableAreaOutline"
	movement_outline.mesh = ImmediateMesh.new()
	var outline_material := StandardMaterial3D.new()
	outline_material.albedo_color = Color(1, 1, 1, 0.9)
	outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	movement_outline.material_override = outline_material
	add_child(movement_outline)
	# Two disjoint cost bands, not two overlapping disks. The actual Dijkstra
	# costs include diagonal travel, detours and window/cover surcharges.
	for color in [Color(0.43, 0.47, 0.53, 0.26), Color(0.79, 0.64, 0.65, 0.33)]:
		var fill := MeshInstance3D.new()
		fill.name = "MovementCostBand%d" % (movement_fills.size() + 1)
		fill.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		fill.material_override = material
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fill)
		movement_fills.append(fill)

func _marker(marker_name: String, color: Color, radius: float) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	var disk := CylinderMesh.new()
	disk.top_radius = radius
	disk.bottom_radius = radius
	disk.height = 0.035
	marker.mesh = disk
	var material := _material(color)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.set_surface_override_material(0, material)
	add_child(marker)
	return marker

func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.87
	return result

func _box(mesh_name: String, world_position: Vector3, box_size: Vector3, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	var box := BoxMesh.new()
	box.size = box_size
	instance.mesh = box
	instance.position = world_position
	instance.set_surface_override_material(0, _material(color))
	parent.add_child(instance)
	return instance

func _grid(tile: Vector2i, height: float = 0.0) -> Vector3:
	return Vector3(tile.x * CELL_WORLD + CELL_WORLD * 0.5, height, -(tile.y * CELL_WORLD + CELL_WORLD * 0.5))

func set_view(origin: Vector2i) -> void:
	if camera == null:
		return
	var focus := _grid(origin + Vector2i(14, 9))
	# Match the bank's street-facing view in the original playthrough. Unity's
	# camera yaw must be mirrored when its scene is converted to Godot's axes.
	camera.position = focus + Vector3(-20.0, 28.3, 20.0)
	camera.look_at(focus, Vector3.UP)

func set_zoomed_out(zoomed_out: bool) -> void:
	if camera != null:
		camera.size = DEFAULT_CAMERA_SIZE * (2.0 if zoomed_out else 1.0)

func pick_tile(pixel: Vector2) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	var ray_origin := camera.project_ray_origin(pixel)
	var ray_direction := camera.project_ray_normal(pixel)
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(ray_origin, ray_direction)
	if hit == null:
		return Vector2i(-1, -1)
	return Vector2i(floori(hit.x / CELL_WORLD), floori(-hit.z / CELL_WORLD))

func sync(cops: Array[Dictionary], guards: Array[Dictionary], doors_open: Dictionary, selected_cop: int, lesson: int, camera_origin: Vector2i) -> void:
	set_view(camera_origin)
	for i in range(mini(3, cops.size())):
		cop_nodes[i].position = _grid(cops[i]["pos"])
		cop_nodes[i].visible = cops[i]["hp"] > 0
		cop_outlines[i].set_shader_parameter("outline_color", Color("#f3d757") if i == selected_cop else Color("#47a8d5"))
	for i in range(mini(3, guards.size())):
		guard_nodes[i].position = _grid(guards[i]["pos"])
		guard_nodes[i].visible = guards[i]["state"] != "已逮捕" and guards[i]["state"] != "逃离"
	for tile in door_nodes:
		door_nodes[tile].visible = not doors_open.has(tile)
	selection_ring.visible = false
	var target := Vector2i(-1, -1)
	if lesson == 0:
		target = Vector2i(17, 24)
	elif lesson == 1:
		target = Vector2i(20, 24)
	elif lesson == 2:
		target = Vector2i(22, 25)
	else:
		for guard in guards:
			if guard["state"] != "已逮捕":
				target = guard["pos"]
				break
	objective_ring.visible = target.x >= 0
	if objective_ring.visible:
		objective_ring.position = _grid(target, 0.045)

func sync_source(cops: Array[Dictionary], guards: Array[Dictionary], hostages: Array[Dictionary], opened: Dictionary, opened_edges: Dictionary, cells: Dictionary, grid_edges: Array, selected_cop: int, target: Vector2i, camera_origin: Vector2i, doors: Array, windows: Array) -> void:
	cover_edges = grid_edges
	cover_openings = opened_edges
	_ensure_source_people(guards.size(), hostages.size())
	_ensure_source_openings(doors, windows, cells)
	set_view(camera_origin)
	for i in range(mini(cop_nodes.size(), cops.size())):
		var next_tile: Vector2i = cops[i]["pos"]
		if i >= cop_tiles.size():
			cop_tiles.append(next_tile)
			cop_nodes[i].position = _grid(next_tile)
		elif cop_tiles[i] != next_tile:
			_animate_cop_to(i, cop_tiles[i], next_tile, cells, grid_edges, opened_edges)
			cop_tiles[i] = next_tile
		elif not cop_motion_tweens.has(i):
			cop_nodes[i].position = _grid(next_tile)
		cop_nodes[i].visible = int(cops[i]["hp"]) > 0
		cop_outlines[i].set_shader_parameter("outline_color", Color("#f3d757") if i == selected_cop else Color("#47a8d5"))
	for i in range(guards.size()):
		_sync_guard_visual(i, guards[i], cells, grid_edges, opened_edges)
	for i in range(hostages.size()):
		hostage_nodes[i].position = _grid(hostages[i]["pos"])
		hostage_nodes[i].visible = hostages[i]["state"] != "已获救"
	for tile in door_nodes:
		door_nodes[tile].visible = not opened.has(tile)
	for edge in source_door_nodes:
		source_door_nodes[edge].visible = not opened_edges.has(edge)
	for edge in source_window_nodes:
		source_window_nodes[edge].visible = not opened_edges.has(edge)
	selection_ring.visible = false
	objective_ring.visible = target.x >= 0
	if objective_ring.visible:
		objective_ring.position = _grid(target, 0.045)
	_update_movement_outline(cops, guards, opened_edges, cells, grid_edges, selected_cop, target.x >= 0)

func _update_movement_outline(cops: Array[Dictionary], guards: Array[Dictionary], opened_edges: Dictionary, cells: Dictionary, grid_edges: Array, selected_cop: int, visible: bool, occupied: Dictionary = {}) -> void:
	var lines := movement_outline.mesh as ImmediateMesh
	lines.clear_surfaces()
	movement_bands.clear()
	for fill in movement_fills: (fill.mesh as ImmediateMesh).clear_surfaces()
	if not visible or int(cops[selected_cop]["ap"]) <= 0:
		return
	var start: Vector2i = cops[selected_cop]["pos"]
	var blocked: Dictionary = occupied.duplicate()
	for guard in guards:
		if guard["state"] != "已逮捕" and guard["state"] != "逃离":
			blocked[guard["pos"]] = true
	var range_world := float(int(cops[selected_cop]["ap"]) * int(cops[selected_cop]["max_move"])) * CELL_WORLD
	var search_result := NAV.search(start, range_world, cells, grid_edges, opened_edges, blocked)
	var reached: Dictionary = search_result["costs"]
	for tile in reached:
		movement_bands[tile] = NAV.movement_ap_cost(float(reached[tile]), int(cops[selected_cop]["max_move"]))
	for band in [1, 2]:
		var fill := movement_fills[band - 1].mesh as ImmediateMesh
		var begun := false
		for tile in reached:
			if int(movement_bands[tile]) != band: continue
			if not begun:
				fill.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				begun = true
			var center := _grid(tile, 0.075)
			var h := CELL_WORLD * 0.5
			var a := center + Vector3(-h, 0, -h)
			var b := center + Vector3(h, 0, -h)
			var c := center + Vector3(h, 0, h)
			var d := center + Vector3(-h, 0, h)
			for vertex in [a, b, c, a, c, d]: fill.surface_add_vertex(vertex)
		if begun: fill.surface_end()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for tile in reached:
		var center := _grid(tile, 0.10)
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			# Draw exterior once; draw the shared 1/2 AP border only from band 1.
			if reached.has(tile + direction) and not (int(movement_bands[tile]) == 1 and int(movement_bands[tile + direction]) == 2):
				continue
			var a := Vector3.ZERO
			var b := Vector3.ZERO
			if direction == Vector2i.LEFT:
				a = center + Vector3(-CELL_WORLD * 0.5, 0, -CELL_WORLD * 0.5)
				b = center + Vector3(-CELL_WORLD * 0.5, 0, CELL_WORLD * 0.5)
			elif direction == Vector2i.RIGHT:
				a = center + Vector3(CELL_WORLD * 0.5, 0, -CELL_WORLD * 0.5)
				b = center + Vector3(CELL_WORLD * 0.5, 0, CELL_WORLD * 0.5)
			elif direction == Vector2i.UP:
				a = center + Vector3(-CELL_WORLD * 0.5, 0, CELL_WORLD * 0.5)
				b = center + Vector3(CELL_WORLD * 0.5, 0, CELL_WORLD * 0.5)
			else:
				a = center + Vector3(-CELL_WORLD * 0.5, 0, -CELL_WORLD * 0.5)
				b = center + Vector3(CELL_WORLD * 0.5, 0, -CELL_WORLD * 0.5)
			lines.surface_add_vertex(a)
			lines.surface_add_vertex(b)
	lines.surface_end()
