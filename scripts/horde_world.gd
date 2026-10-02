extends Node3D

const SCENE = preload("res://assets/horde/original_scene/hordemode_original.gltf")
const COP = preload("res://assets/horde/actors/cop/cop_rig.gltf")
const FEMALE_COP = preload("res://assets/horde/actors/cop_female/cop_female_rig.gltf")
const ENEMY = preload("res://assets/characters/original_enemy_male/enemy_male_rig.gltf")
const UI = preload("res://scripts/horde_ui_theme.gd")
const OPENINGS = [preload("res://assets/bank/openings/ColdOpenDoor1/coldopendoor1_original.gltf"), preload("res://assets/bank/openings/ColdOpenDoor2/coldopendoor2_original.gltf"), preload("res://assets/bank/openings/ArmoredDoor1/armoreddoor1_original.gltf")]
const WINDOW = preload("res://assets/bank/openings/Window1/window1_original.gltf")
const CASE_TEXTURES = {"Weapon": "res://assets/horde/loot/Gun.png", "Ammo": "res://assets/horde/loot/Ammo.png", "Equipment": "res://assets/horde/loot/Other.png", "RebelPoint": "res://assets/horde/loot/RebelPoints.png"}
const GRENADE_FLIGHT_TIME := 0.62
var state
var camera: Camera3D
var focus := Vector3.ZERO
var actors: Dictionary = {}
var actor_labels: Dictionary = {}
var rings: Dictionary = {}
var cases: Dictionary = {}
var source_cases: Dictionary = {}
var opening_nodes: Dictionary = {}
var band_meshes: Array = []
var boundary: MeshInstance3D
var preview: MeshInstance3D
var static_scene: Node3D
var moving: Dictionary = {}
var selected := 0
var reached: Dictionary = {}
var zoom_alternate := false
var zoom_return_size := 28.0
var cover_current: Node3D
var cover_preview: Node3D
var enemy_playback: Node3D
var enemy_visible_tile := Vector2i(-1, -1)
var enemy_playback_unit: Dictionary = {}
var sunlight: DirectionalLight3D
var atmosphere: Environment
var weather_index := 0
var weather_tween: Tween
var room_ids: Array = []
var follow_actions := true
var effects_gain := 1.0
var intel_markers: Dictionary = {}
var preview_hint_cache: Dictionary = {}
var preview_tile := Vector2i(-1,-1)
var preview_cost := 0
var awareness_clock:=0.0
var enemy_vision: MeshInstance3D
var enemy_vision_key:=""
var vision_pointer:=Vector2(-1000,-1000)
const WEATHER_NAMES = ["晴朗", "阴天", "黄昏", "明亮夜色", "细雨"]

func map_scene() -> Node3D:
	return SCENE.instantiate()

func initialize(game_state) -> void:
	state = game_state
	get_window().mouse_exited.connect(clear_vision_pointer)
	room_ids = state.data.get("room_ids",JSON.parse_string(FileAccess.get_file_as_string("res://assets/horde/room_ids.json")))
	static_scene = map_scene()
	add_child(static_scene)
	prepare_scene(static_scene)
	for record in state.data.loot_spawns:
		var n := static_scene.find_child(str(record.node), true, false) as Node3D
		if n != null: source_cases[Vector2i(int(record.x), int(record.y))] = n
	var sun := DirectionalLight3D.new()
	sunlight = sun
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("#ded3c5")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	atmosphere = settings
	settings.fog_enabled = false
	settings.volumetric_fog_enabled = false
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#656763")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#b3b4b0")
	settings.ambient_light_energy = 0.7
	env.environment = settings
	add_child(env)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28
	camera.far = 400
	add_child(camera)
	camera.current = true
	for color in [Color(0.43, 0.54, 0.64, 0.22), Color(0.82, 0.60, 0.66, 0.24), Color(0.79, 0.70, 0.34, 0.24)]: band_meshes.append(immediate(color))
	boundary = immediate(Color("#efeee5"))
	preview = immediate(Color("#99dbff"))
	cover_current = Node3D.new()
	cover_current.name = "StandingCover"
	add_child(cover_current)
	cover_preview = Node3D.new()
	cover_preview.name = "DestinationCover"
	add_child(cover_preview)
	create_openings()
	sync(0)
	center_on(state.cops[0].pos)

func prepare_scene(root: Node) -> void:
	if root is Node3D and (str(root.name).begins_with("CombineMeshRoof") or str(root.name).begins_with("HordeLoot")):
		root.hide()
	if root is MeshInstance3D and root.mesh != null:
		for i in range(root.mesh.get_surface_count()):
			var source := root.get_active_material(i) as StandardMaterial3D
			if source:
				var mat := source.duplicate() as StandardMaterial3D
				mat.vertex_color_use_as_albedo = true
				root.set_surface_override_material(i, mat)
	for child in root.get_children(): prepare_scene(child)

func grid(tile: Vector2i, offset := 0.0) -> Vector3:
	var h := int(state.nav.cells.get(tile, {}).get("Height", 0))
	return Vector3((tile.x + 0.5) * 1.4, (0.7 if h == 2 else 0.35 if h == 1 else 0.0) + offset, -(tile.y + 0.5) * 1.4)

func center_on(tile: Vector2i) -> void:
	focus = grid(tile)
	update_camera()

func update_camera() -> void:
	focus.x = clampf(focus.x, 0, state.nav.width * 1.4)
	focus.z = clampf(focus.z, -state.nav.height * 1.4, 0)
	camera.position = focus + Vector3(-25, 35.4, 25)
	camera.look_at(focus, Vector3.UP)

func pan(delta: Vector2) -> void:
	var right := camera.global_basis.x
	var forward := Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
	focus += right * delta.x + forward * delta.y
	update_camera()

func zoom(factor: float) -> void:
	camera.size = clampf(camera.size * factor, 15, 90)
	zoom_alternate = false

func toggle_zoom() -> void:
	if zoom_alternate:
		camera.size = zoom_return_size
	else:
		zoom_return_size = camera.size
		camera.size = minf(90, camera.size * 2)
		if is_equal_approx(camera.size, zoom_return_size): camera.size = maxf(15, camera.size * 0.5)
	zoom_alternate = not zoom_alternate

func drag_view(from_pixel: Vector2, to_pixel: Vector2) -> void:
	# Grab the ground under the cursor. Projecting onto the focus-height plane
	# keeps dragging screen-aligned and equally responsive at every zoom level.
	var plane := Plane(Vector3.UP, focus.y)
	var before: Variant = plane.intersects_ray(camera.project_ray_origin(from_pixel), camera.project_ray_normal(from_pixel))
	var after: Variant = plane.intersects_ray(camera.project_ray_origin(to_pixel), camera.project_ray_normal(to_pixel))
	if before == null or after == null: return
	focus += before - after
	update_camera()

func pick_tile(pixel: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	for height in [0.7, 0.35, 0.0]:
		var hit: Variant = Plane(Vector3.UP, height).intersects_ray(origin, direction)
		if hit == null: continue
		var tile := Vector2i(floori(hit.x / 1.4), floori(-hit.z / 1.4))
		if state.nav.inside(tile) and absf(grid(tile).y - height) < 0.02: return tile
	return Vector2i(-1, -1)

func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1: mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func immediate(color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = ImmediateMesh.new()
	n.material_override = material(color)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	return n

func ring(color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.32
	mesh.outer_radius = 0.38
	mesh.rings = 16
	mesh.ring_segments = 6
	n.mesh = mesh
	n.material_override = material(color)
	n.position.y = 0.08
	return n

func actor(u: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Unit_%d" % u.id
	add_child(node)
	var scene: PackedScene = (FEMALE_COP if int(u.get("gender", 0)) == 1 else COP) if u.side == "cop" else ENEMY
	var archetype: String = u.get("source_prefab","")
	if u.side=="enemy" and archetype in ["HeavyGuy","Jigurda","FinalMissionEnemy"]:
		scene = load("res://assets/horde/actors/%s/%s.gltf" % [archetype,archetype])
	var model: Node3D = scene.instantiate()
	node.add_child(model)
	if not archetype.is_empty():
		var source_root := model.find_child(archetype,true,false) as Node3D
		if source_root: source_root.position = Vector3.ZERO
	var enemy_root := model.find_child("EnemyMale", true, false) as Node3D
	if enemy_root: enemy_root.position = Vector3.ZERO
	var female_root := model.find_child("FemaleCopWithAllWeapons", true, false) as Node3D
	if female_root: female_root.position = Vector3.ZERO
	prepare_scene(model)
	var motion := preload("res://scripts/horde_actor_motion.gd").new()
	motion.name = "Motion"
	node.add_child(motion)
	motion.initialize(model)
	motion.configure_weapons(model)
	var step_sound := AudioStreamPlayer.new()
	step_sound.volume_db = -22
	node.add_child(step_sound)
	motion.footstep.connect(func(foot: String):
		if not node.visible: return
		step_sound.volume_db = -22+linear_to_db(maxf(.0001,effects_gain))
		var x := clampi(floori(node.position.x/1.4),0,state.nav.width-1)
		var y := clampi(floori(-node.position.z/1.4),0,state.nav.height-1)
		var indoor: bool = int(room_ids[y*state.nav.width+x]) != 0
		var file := ("Step " if indoor else "Snow ")+("L" if foot == "left" else "R")+"1.ogg"
		step_sound.stream = load("res://assets/bank/audio/footsteps/"+file)
		step_sound.play())
	var marker := ring(Color("#81d8fc") if u.side == "cop" else Color("#f3534d"))
	node.add_child(marker)
	rings[u.id] = marker
	var label := Label3D.new()
	label.position.y = 2.1
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.012
	label.no_depth_test = true
	label.outline_size = 8
	node.add_child(label)
	actor_labels[u.id] = label
	actors[u.id] = node
	return node

func create_openings() -> void:
	for d in state.data.doors + state.data.windows:
		if int(d.IsGenerated) == 0: continue
		var index := int(d.EdgeIndex)
		var pair: Array = state.nav.edge_pair(index)
		var is_window: bool = d in state.data.windows
		var scene: PackedScene = WINDOW if is_window else OPENINGS[mini(int(d.MeshIndex), 2)]
		var n: Node3D = scene.instantiate()
		add_child(n)
		n.position = (grid(pair[0]) + grid(pair[1])) * 0.5
		n.rotation_degrees.y = -90 if index % 2 else 0
		var broken := n.find_child("Broken", true, false) as Node3D
		if broken: broken.hide()
		prepare_scene(n)
		opening_nodes[index] = n

func sync(index: int) -> void:
	selected = index
	clear_preview()
	preview_hint_cache.clear()
	var active_ids: Dictionary = {}
	for u in state.cops + state.enemies: active_ids[u.id] = true
	for id in actors.keys():
		if not active_ids.has(id):
			actors[id].queue_free()
			actors.erase(id)
			actor_labels.erase(id)
			rings.erase(id)
	for u in state.cops + state.enemies:
		var n: Node3D = actors.get(u.id)
		if n == null: n = actor(u)
		if not moving.has(u.id): n.position = grid(u.pos)
		n.visible = not u.captured and (u.side == "cop" or state.enemy_visible_at(u,u.pos))
		if u.side=="enemy" and n.visible: state.remember_enemy(u,u.pos)
		var motion = n.get_node("Motion")
		if u.side=="enemy" and not moving.has(u.id) and motion.action_clip.is_empty():
			var facing: Vector2i=u.get("facing",Vector2i.DOWN)
			motion.heading=atan2(-float(facing.x),float(facing.y))
		motion.gun = str(u.gun)
		motion.gender = int(u.get("gender",0))
		motion.melee = str(u.get("melee",""))
		motion.machinegun = bool(u.get("machinegun",false))
		motion.source_prefab = str(u.get("source_prefab",""))
		motion.wounded = state.effective_wound(u)
		motion.cover_tier = 0
		if state.cover_enabled(u):
			for cover in state.nav.covers_at(u.pos): motion.cover_tier = maxi(motion.cover_tier,int(cover.tier))
		motion.update_weapons()
		if u.dead and not motion.dead:
			var death_clip: String = "dead_on_back" if u.wound=="躯干" else u.get("death_animation","idle_body_damage")
			motion.start_death(death_clip)
			motion.action_time = motion.duration(motion.action_clip)
			motion.action_blend=1.0
			motion.apply_clip(motion.action_clip,motion.action_time)
		rings[u.id].visible = not u.dead
		actor_labels[u.id].visible = not u.dead
		var is_selected: bool = u.side == "cop" and int(u.id) == int(state.cops[selected].id)
		(rings[u.id].material_override as StandardMaterial3D).albedo_color = Color("#ffe033") if is_selected else Color("#81d8fc") if u.side == "cop" else Color("#f3534d")
		var status := ""
		if u.wound=="躯干": status = " 倒地 · 失血 %d" % u.bleed if int(u.bleed)>0 else " 倒地 · 已止血"
		elif int(u.bleed) > 0: status = " 失血 %d" % u.bleed
		elif int(u.stun) > 0: status = " 眩晕"
		elif u.surrender: status = " 投降"
		actor_labels[u.id].text = str(u.name) + status
		actor_labels[u.id].modulate = Color("#ffe033") if is_selected else Color.WHITE
	refresh_intel_markers()
	refresh_awareness_labels()
	sync_loot_and_ranges()

func refresh_awareness_labels() -> void:
	var snapshot: Dictionary=state.awareness_snapshot()
	for u: Dictionary in state.cops+state.enemies:
		if not actor_labels.has(u.id) or u.dead or not state.conscious(u) or u.surrender: continue
		var label: Label3D=actor_labels[u.id]
		var kind: String=snapshot.cops.get(u.id,"unknown") if u.side=="cop" else snapshot.enemies.get(u.id,"inactive")
		var suffix: String={"combat":" ! 已发现","suspicious":" ? 怀疑","investigate":" ? 调查声响","track":" ! 追踪最后位置","search":" ? 搜索"}.get(kind,"")
		# Preserve injury text already assigned by sync; do not accumulate suffixes.
		var status: String=" 手臂受伤" if u.wound=="手臂" else " 腿部受伤" if u.wound=="腿" else ""
		if int(u.bleed)>0: status+=" · 失血 %d"%u.bleed
		label.text=str(u.name)+status+suffix
		var selected_cop: bool=u.side=="cop" and int(u.id)==int(state.cops[selected].id)
		label.modulate=Color("#ff7865") if kind=="combat" else Color("#f4d345") if kind in ["suspicious","investigate","track","search"] or selected_cop else Color.WHITE

func _input(event: InputEvent) -> void:
	if event is InputEventMouse: vision_pointer=event.position

func clear_vision_pointer() -> void:
	vision_pointer=Vector2(-1000,-1000)

func update_enemy_vision() -> void:
	if enemy_vision==null:
		enemy_vision=MeshInstance3D.new();enemy_vision.name="VisibleEnemyVision"
		enemy_vision.mesh=ImmediateMesh.new()
		var material:=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo=true
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		enemy_vision.material_override=material;add_child(enemy_vision)
	var unit:=pick_unit(vision_pointer)
	if unit.is_empty() or unit.side!="enemy" or not state.conscious(unit) or unit.surrender or not moving.is_empty():
		enemy_vision.hide();enemy_vision_key="";return
	var key:="%s:%s:%s:%s:%s:%s"%[unit.id,unit.pos,unit.get("facing",Vector2i.DOWN),state.ENEMY_AI.alerted(state,unit),state.nav.revision,state.cover_enabled(unit)]
	if key==enemy_vision_key: enemy_vision.show();return
	enemy_vision_key=key
	var mesh: ImmediateMesh=enemy_vision.mesh
	mesh.clear_surfaces();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(unit.pos.y-11,unit.pos.y+12):
		for x in range(unit.pos.x-11,unit.pos.x+12):
			var tile:=Vector2i(x,y)
			if not state.nav.inside(tile): continue
			var area: int=state.ENEMY_AI.vision_area(state,unit,tile)
			if area==0: continue
			mesh.surface_set_color(Color(1,.35,.2,.16) if area==1 else Color(1,.8,.18,.12))
			var p:=grid(tile,.10)
			for v in [Vector3(-.7,0,-.7),Vector3(.7,0,-.7),Vector3(.7,0,.7),Vector3(-.7,0,-.7),Vector3(.7,0,.7),Vector3(-.7,0,.7)]: mesh.surface_add_vertex(p+v)
	mesh.surface_end();enemy_vision.show()

func sync_loot_and_ranges() -> void:
	for tile in cases.keys():
		if not state.loot.has(tile):
			if source_cases.has(tile): source_cases[tile].hide()
			cases[tile].queue_free()
			cases.erase(tile)
	for tile in state.loot:
		if cases.has(tile): continue
		var case_node := Node3D.new()
		add_child(case_node)
		case_node.position = grid(tile, 0.15)
		if source_cases.has(tile):
			source_cases[tile].show()
			case_node.global_position = source_cases[tile].global_position + Vector3.UP * 0.15
			var source_mesh := source_cases[tile] as MeshInstance3D
			if source_mesh != null:
				var mat := source_mesh.get_active_material(0) as StandardMaterial3D
				mat.albedo_texture = load(CASE_TEXTURES[state.loot[tile].category])
		var marker := ring(Color("#ff7465"))
		marker.scale = Vector3(1.5,1,1.5)
		marker.material_override.no_depth_test = true
		case_node.add_child(marker)
		var label := Label3D.new()
		label.text = ("地上 · " if state.loot[tile].get("dropped",false) else "补给 · ") + state.loot_name(state.loot[tile]) + "\n▼"
		label.position.y = 1.2
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 30
		label.pixel_size = 0.008
		label.modulate = Color("#ffe126")
		label.outline_size = 10
		label.no_depth_test = true
		label.name = "LootMarker"
		case_node.add_child(label)
		var icon := Sprite3D.new()
		icon.name = "LootIcon"
		var item: String = state.loot[tile].item
		var icon_key: String = {"BodyArmor":"Armor","BigMedkit":"MedkitBig","SmallMedkit":"MedkitSmall","Points":"RebelPoint"}.get(item,item)
		icon.texture = UI.texture(UI.ammo_icon(item) if state.loot[tile].category == "Ammo" else icon_key)
		icon.position.y = 1.2
		icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon.no_depth_test = true
		icon.modulate = Color("#ffe126")
		case_node.add_child(icon)
		cases[tile] = case_node
		if source_cases.has(tile): pulse_loot(source_cases[tile], case_node)
	for edge in opening_nodes: opening_nodes[edge].visible = state.nav.kind(edge) in [10, 11]
	reached = state.reachable(state.cops[selected])
	draw_ranges()

func pick_loot_marker(pixel: Vector2) -> Vector2i:
	var nearest := 30.0
	var result := Vector2i(-1,-1)
	for tile in cases:
		var label := cases[tile].get_node_or_null("LootMarker") as Label3D
		if label == null or (not label.visible and not cases[tile].get_node("LootIcon").visible): continue
		var distance := camera.unproject_position(label.global_position).distance_to(pixel)
		if distance < nearest:
			nearest = distance
			result = tile
	return result

func _process(_delta: float) -> void:
	if camera == null: return
	awareness_clock-=_delta
	if awareness_clock<=0:
		awareness_clock=.12
		refresh_awareness_labels()
		update_enemy_vision()
	# Keep supply text readable in screen pixels when zooming out.
	var pixel := camera.size / maxf(1,get_viewport().get_visible_rect().size.y) * 0.5
	for id in actor_labels: actor_labels[id].pixel_size = pixel
	var screen_size := get_viewport().get_visible_rect().size
	var pointer := get_viewport().get_mouse_position()
	var occupied_labels: Array[Rect2] = []
	for id in actor_labels:
		if actor_labels[id].is_visible_in_tree():
			var at := camera.unproject_position(actor_labels[id].global_position)
			occupied_labels.append(Rect2(at-Vector2(55,14),Vector2(110,28)))
	for tile in cases:
		var label := cases[tile].get_node_or_null("LootMarker") as Label3D
		if label == null: continue
		label.pixel_size = pixel
		var icon := cases[tile].get_node("LootIcon") as Sprite3D
		icon.pixel_size = pixel*.75
		var at := camera.unproject_position(label.global_position)
		var on_map := at.y>screen_size.y*.19 and at.y<screen_size.y-80 and at.x>20 and at.x<screen_size.x-20
		var hovered := pointer.distance_to(at)<35
		var nearby := Vector2(tile).distance_to(Vector2(state.cops[selected].pos))<=8 and camera.size<=35
		var rect := Rect2(at-Vector2(68,23),Vector2(136,46))
		var crowded := occupied_labels.any(func(other: Rect2): return other.intersects(rect))
		label.visible = on_map and (hovered or (nearby and not crowded))
		icon.visible = on_map and not label.visible
		if label.visible: occupied_labels.append(rect)

func pulse_loot(source: MeshInstance3D, lifetime: Node3D) -> void:
	# TacticsHordeLoot.Spawn calls a two-second blinking outline. Keep the
	# original mesh fixed in place; the pulse is a spawn cue, not a falling box.
	var outline := material(Color(0.675,0.17,0.17,0.0))
	outline.grow = true
	outline.grow_amount = 0.025
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	source.material_overlay = outline
	var tween := lifetime.create_tween()
	for i in range(3):
		tween.tween_property(outline,"albedo_color:a",0.95,0.24)
		tween.tween_property(outline,"albedo_color:a",0.0,0.4266667)
	tween.tween_callback(func():
		if is_instance_valid(source) and source.material_overlay == outline: source.material_overlay = null)

func draw_ranges() -> void:
	for n in band_meshes: n.mesh.clear_surfaces()
	boundary.mesh.clear_surfaces()
	clear_preview()
	clear_cover(cover_current)
	if state.phase != "player" or not moving.is_empty(): return
	var c: Dictionary = state.cops[selected]
	if not c.dead and not c.captured and int(c.stun) == 0 and c.wound not in ["腿", "躯干"]:
		draw_cover(c.pos, cover_current)
	var bands: Dictionary = {}
	for tile in reached.costs: bands[tile] = maxi(1, int(ceil((float(reached.costs[tile]) - 0.001) / (state.move_distance(c) * 1.4))))
	for band in range(1, 4):
		var mesh: ImmediateMesh = band_meshes[band - 1].mesh
		var started := false
		for tile in bands:
			if bands[tile] != band: continue
			if not started:
				mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				started = true
			var p := grid(tile, 0.09)
			for v in [Vector3(-.7,0,-.7), Vector3(.7,0,-.7), Vector3(.7,0,.7), Vector3(-.7,0,-.7), Vector3(.7,0,.7), Vector3(-.7,0,.7)]: mesh.surface_add_vertex(p + v)
		if started: mesh.surface_end()
	if bands.is_empty(): return
	var lines: ImmediateMesh = boundary.mesh
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for tile in bands:
		var p := grid(tile, 0.12)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if bands.has(tile + d) and int(bands[tile + d]) <= int(bands[tile]): continue
			var middle := p + Vector3(d.x, 0, -d.y) * 0.7
			var along := Vector3(abs(d.y), 0, abs(d.x)) * 0.7
			lines.surface_add_vertex(middle - along)
			lines.surface_add_vertex(middle + along)
	lines.surface_end()

func draw_preview(tile: Vector2i) -> int:
	if tile==preview_tile and state.phase=="player" and moving.is_empty(): return preview_cost
	var mesh: ImmediateMesh = preview.mesh
	clear_preview()
	if not reached.costs.has(tile) or state.phase != "player" or not moving.is_empty(): return 0
	var c: Dictionary = state.cops[selected]
	if tile == c.pos: return 0
	draw_cover(tile, cover_preview)
	var route: Array = [c.pos]
	route.append_array(state.nav.path(c.pos, tile, reached.parents))
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, route.size()):
		mesh.surface_add_vertex(grid(route[i - 1], 0.18))
		mesh.surface_add_vertex(grid(route[i], 0.18))
	var p := grid(tile, 0.18)
	var corners := [Vector3(-.65,0,-.65), Vector3(.65,0,-.65), Vector3(.65,0,.65), Vector3(-.65,0,.65)]
	for i in range(4):
		mesh.surface_add_vertex(p + corners[i])
		mesh.surface_add_vertex(p + corners[(i + 1) % 4])
	mesh.surface_end()
	preview_tile=tile
	preview_cost=maxi(1, int(ceil((float(reached.costs[tile]) - 0.001) / (state.move_distance(c) * 1.4))))
	return preview_cost

func movement_hint(tile: Vector2i) -> String:
	if preview_hint_cache.has(tile): return preview_hint_cache[tile]
	var c: Dictionary=state.cops[selected]
	var threats := 0
	for e: Dictionary in state.active_enemies():
		if e.gun=="" or int(e.stun)>0 or e.surrender or e.wound=="手臂" or not state.visible_enemy(e): continue
		if state.nav.targeting(e.pos,tile,state.current_shot_range(e),state.cover_enabled(e),state.cover_enabled(c)).clear: threats+=1
	var text := "未侦察，敌情未知" if not state.tile_visible(tile) else "队伍视野内"
	text += " · %d 条已知枪线" % threats if threats>0 else " · 无已知枪线"
	preview_hint_cache[tile]=text
	return text

func clear_cover(root: Node3D) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()

func clear_preview() -> void:
	preview_tile=Vector2i(-1,-1)
	preview_cost=0
	preview.mesh.clear_surfaces()
	clear_cover(cover_preview)

func draw_cover(tile: Vector2i, root: Node3D) -> void:
	clear_cover(root)
	for cover in state.nav.covers_at(tile):
		var icon := Sprite3D.new()
		icon.name = ("FullCover" if cover.tier == 2 else "HalfCover") + str(cover.edge)
		icon.texture = UI.texture("FullCover" if cover.tier == 2 else "HalfCover")
		icon.pixel_size = 1.0 / 450.0
		icon.shaded = false
		icon.double_sided = true
		icon.no_depth_test = true
		icon.render_priority = 5
		var direction: Vector2i = cover.direction
		icon.position = grid(tile, 1.05) + Vector3(direction.x, 0, -direction.y) * 0.66
		icon.rotation.y = PI / 2 if direction.x != 0 else 0.0
		icon.set_meta("tier", cover.tier)
		icon.set_meta("edge", cover.edge)
		root.add_child(icon)

func refresh_intel_markers() -> void:
	for id in state.last_seen.keys():
		var memory: Dictionary = state.last_seen[id]
		var visible_now: bool = actors.has(id) and actors[id].visible
		# A newly inspected empty cell invalidates the old report. Never move
		# its marker to the hidden actor's current logical position.
		if not visible_now and state.tile_visible(memory.pos):
			state.last_seen.erase(id)
			continue
		if not intel_markers.has(id):
			var marker := Label3D.new()
			marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			marker.font_size=24
			marker.pixel_size=.012
			marker.modulate=Color("#dbbf83")
			marker.outline_size=6
			add_child(marker)
			intel_markers[id]=marker
		var label: Label3D = intel_markers[id]
		label.position=grid(memory.pos,1.1)
		label.text="? %s\n最后目击 · %d 回合前" % [memory.name,maxi(0,state.turn-int(memory.turn))]
		label.visible=not visible_now
	for id in intel_markers.keys():
		if not state.last_seen.has(id):
			intel_markers[id].queue_free()
			intel_markers.erase(id)

func _set_enemy_position(position_in_world: Vector3) -> void:
	if enemy_playback == null: return
	# A tween runs after _process: update visibility in the same callback as
	# position so crossing a sight boundary never leaks a one-frame silhouette.
	enemy_playback.position = position_in_world
	var tile := Vector2i(floori(enemy_playback.position.x / 1.4), floori(-enemy_playback.position.z / 1.4))
	if tile != enemy_visible_tile:
		enemy_visible_tile = tile
		enemy_playback.visible = enemy_seen_at(tile)
		if enemy_playback.visible and not enemy_playback_unit.is_empty() and state.has_method("remember_enemy"):
			state.remember_enemy(enemy_playback_unit,tile)
	if enemy_playback.visible and follow_actions:
		focus = focus.lerp(enemy_playback.position, 1.0 - exp(-get_process_delta_time() * 12.0))
		update_camera()

func enemy_seen_at(tile: Vector2i) -> bool:
	if state.has_method("enemy_visible_at") and not enemy_playback_unit.is_empty():
		return state.enemy_visible_at(enemy_playback_unit,tile)
	return state.tile_visible(tile)

func play_enemy_move(u: Dictionary, route: Array, start: Vector2i, quick := false,after_step := Callable()) -> void:
	if route.is_empty(): return
	var n: Node3D = actors[u.id]
	enemy_playback_unit = u
	moving[u.id] = true
	draw_ranges()
	n.position = grid(start)
	n.visible = enemy_seen_at(start)
	var previous := start
	u.presented_tile=start
	var presented := false
	for tile: Vector2i in route:
		u.facing=tile-previous
		var next := grid(tile)
		# Inspect every segment, including routes whose endpoints are both hidden.
		var show_segment: bool = enemy_seen_at(previous) or enemy_seen_at(tile)
		if show_segment:
			if not presented and follow_actions:
				var known: Vector2i = previous if enemy_seen_at(previous) else tile
				var pan_tween := create_tween()
				pan_tween.tween_method(func(p: Vector3): focus = p; update_camera(), focus, grid(known), 0.12 if quick else 0.22).set_trans(Tween.TRANS_SINE)
				await pan_tween.finished
				presented = true
			enemy_visible_tile = Vector2i(-1, -1)
			enemy_playback = n
			var direction := next - n.position
			var tween := create_tween()
			tween.tween_method(_set_enemy_position, n.position, next, direction.length() / (12.0 if quick else 6.0))
			await tween.finished
			enemy_playback = null
		else:
			n.position = next
			n.hide()
			presented = false
		n.visible = enemy_seen_at(tile)
		previous = tile
		if after_step.is_valid():
			var interrupted: bool = await after_step.call(tile)
			if interrupted: break
	if n.visible: await get_tree().create_timer(0.06 if quick else 0.15).timeout
	moving.erase(u.id)
	u.erase("presented_tile")
	enemy_playback_unit = {}

func move_unit(u: Dictionary, route: Array, quick := false) -> void:
	if route.is_empty(): return
	var n: Node3D = actors[u.id]
	moving[u.id] = true
	draw_ranges()
	var tween := create_tween()
	var previous := n.position
	_set_cop_position(previous,u,n)
	for tile in route:
		var next := grid(tile)
		tween.tween_method(_set_cop_position.bind(u,n),previous,next,previous.distance_to(next) / (16.0 if quick else 8.0))
		previous = next
	await tween.finished
	state.viewing_positions.erase(u.id)
	moving.erase(u.id)

func _set_cop_position(at: Vector3,u: Dictionary,n: Node3D) -> void:
	n.position = at
	var tile := Vector2i(floori(at.x/1.4),floori(-at.z/1.4))
	if state.viewing_positions.get(u.id,Vector2i(-1,-1)) == tile: return
	state.player_movement_step(u,tile)
	# Movement commits its logical destination first; visibility follows the
	# rendered cop at each crossed tile, not that future destination.
	for enemy: Dictionary in state.enemies:
		if actors.has(enemy.id):
			actors[enemy.id].visible = not enemy.captured and state.enemy_visible_at(enemy,enemy.pos)
			if actors[enemy.id].visible: state.remember_enemy(enemy,enemy.pos)
	refresh_intel_markers()

func cycle_weather() -> void:
	set_weather((weather_index + 1) % WEATHER_NAMES.size())

func set_weather(index: int, animate := true) -> void:
	weather_index = clampi(index, 0, WEATHER_NAMES.size() - 1)
	if weather_tween != null and weather_tween.is_valid(): weather_tween.kill()
	var colors := [Color("ded3c5"), Color("c5d1df"), Color("f5c99a"), Color("afc3e6"), Color("becbd0")]
	var energy := [0.9, 0.55, 0.75, 0.42, 0.59]
	var ambient := 0.85 if weather_index == 3 else 0.76 if weather_index == 4 else 0.7
	if not animate:
		sunlight.light_color = colors[weather_index]
		sunlight.light_energy = energy[weather_index]
		atmosphere.ambient_light_energy = ambient
		return
	weather_tween = create_tween().set_parallel(true)
	weather_tween.tween_property(sunlight, "light_color", colors[weather_index], 1.2)
	weather_tween.tween_property(sunlight, "light_energy", energy[weather_index], 1.2)
	weather_tween.tween_property(atmosphere, "ambient_light_energy", ambient, 1.2)

func unit_hit_score(pixel: Vector2,node: Node3D,prone:=false) -> float:
	# Pick the projected body and foot ring, not a fixed circle at the chest.
	var foot:=node.global_position
	var head:=foot+Vector3.UP*1.95
	if prone and node.has_node("Motion"):
		var motion=node.get_node("Motion")
		head=motion.skeleton.global_transform*motion.skeleton.get_bone_global_pose(motion.hips).origin
	if camera.is_position_behind(foot): return INF
	var a:=camera.unproject_position(foot)
	var b:=camera.unproject_position(head)
	var segment:=b-a
	var fraction:=clampf((pixel-a).dot(segment)/maxf(.001,segment.length_squared()),0,1)
	var scale:=get_viewport().get_visible_rect().size.y/720.0
	var side:=camera.unproject_position(foot+camera.global_basis.x*.48)
	var radius:=maxf(10.0*scale,a.distance_to(side))+2.0*scale
	var distance:=pixel.distance_to(a+segment*fraction)
	return distance/radius if distance<=radius else INF

func pick_unit(pixel: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var nearest := INF
	for u in state.cops + state.enemies:
		if u.dead or u.captured: continue
		if not actors.has(u.id) or not actors[u.id].visible: continue
		var distance:=unit_hit_score(pixel,actors[u.id],u.wound=="躯干")
		if distance < nearest:
			nearest = distance
			best = u
	return best

func shot_flash(actor: Node3D) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1,.7,.3)
	light.light_energy = 2.0
	light.omni_range = 2.0
	light.position = Vector3(0,1.2,-.5)
	actor.add_child(light)
	var tween := light.create_tween()
	tween.tween_property(light,"light_energy",0.0,.08)
	tween.tween_callback(light.queue_free)

func grenade_flight(from: Vector2i, to: Vector2i) -> void:
	var grenade := MeshInstance3D.new()
	grenade.name = "GrenadeProjectile"
	var shape := CapsuleMesh.new()
	shape.radius = .13
	shape.height = .34
	grenade.mesh = shape
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#282d25")
	mat.metallic = .45
	grenade.material_override = mat
	add_child(grenade)
	var band := MeshInstance3D.new()
	var bead := SphereMesh.new()
	bead.radius = .085
	bead.height = .17
	band.mesh = bead
	band.position.y = .13
	var marker := StandardMaterial3D.new()
	marker.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.albedo_color = Color("#ffe45a")
	band.material_override = marker
	grenade.add_child(band)
	var start := grid(from,1.32)
	var finish := grid(to,.16)
	grenade.position = start
	var tween := create_tween()
	tween.tween_method(func(t: float):
		if is_instance_valid(grenade):
			grenade.position = start.lerp(finish,t)+Vector3.UP*(1.85*4.0*t*(1.0-t))
			grenade.rotation.z = t*TAU*2.0,
		0.0,1.0,GRENADE_FLIGHT_TIME).set_trans(Tween.TRANS_LINEAR)
	await tween.finished
	grenade.free()

func grenade_blast(tile: Vector2i) -> void:
	# Ground-level flash/ring preserves battlefield readability; no full-screen
	# white overlay or lingering smoke that would hide units and cover.
	var burst := Node3D.new()
	burst.name = "GrenadeBurst"
	burst.position = grid(tile,.11)
	add_child(burst)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.12
	torus.outer_radius = 3.48
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0,.94,.65,.75)
	ring.material_override = material
	ring.scale = Vector3(.06,.06,.06)
	burst.add_child(ring)
	var flash := OmniLight3D.new()
	flash.light_color = Color("#fff1ad")
	flash.light_energy = 4.0
	flash.omni_range = 5.0
	flash.position.y = .9
	burst.add_child(flash)
	var tween := burst.create_tween().set_parallel(true)
	tween.tween_property(ring,"scale",Vector3.ONE,.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material,"albedo_color",Color(1.0,.94,.65,0),.38)
	tween.tween_property(flash,"light_energy",0.0,.34)
	tween.chain().tween_callback(burst.queue_free)

func combat_text(actor: Node3D, value: String) -> void:
	var label := Label3D.new()
	label.text = value
	label.font_size = 28
	label.pixel_size = .02
	label.position.y = 2.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color("ffe126")
	actor.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label,"position:y",3.1,.7)
	tween.tween_property(label,"modulate:a",0,.2)
	tween.tween_callback(label.queue_free)

func pick_opening(pixel: Vector2) -> int:
	var nearest := 23.0
	var picked := -1
	for d in state.data.doors + state.data.windows:
		var edge := int(d.EdgeIndex)
		if state.nav.kind(edge) not in [3, 4, 10, 11]: continue
		var pair: Array = state.nav.edge_pair(edge)
		var point := (grid(pair[0]) + grid(pair[1])) * 0.5 + Vector3.UP * 0.65
		var distance := pixel.distance_to(camera.unproject_position(point))
		if distance < nearest:
			nearest = distance
			picked = edge
	return picked
