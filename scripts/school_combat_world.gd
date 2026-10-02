extends "res://scripts/horde_world.gd"

var campus
var hostage_nodes: Dictionary={}
var occlusion
var hover_tile:=Vector2i(-1,-1)
var preview_route: Array=[]
var active_route: Array=[]
var interaction_target: Dictionary={}
const HOSTAGE_MALE=preload("res://assets/characters/original_hostage_male/hostage_male_rig.gltf")
const HOSTAGE_FEMALE=preload("res://assets/characters/original_hostage_prostitute/hostage_prostitute_v1_rig.gltf")

func map_scene() -> Node3D:
	campus.scale=Vector3(1.4,1,1.4)
	campus.set_roofs(false)
	return campus

func initialize(game_state) -> void:
	super.initialize(game_state)
	camera.size=38
	camera.far=500
	sunlight.directional_shadow_max_distance=180
	atmosphere.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	atmosphere.background_color=Color("#bcc7bd")
	center_on(Vector2i(49,13))
	occlusion=preload("res://scripts/school_occlusion.gd").new()
	add_child(occlusion)
	occlusion.initialize(campus,camera)

func grid(tile: Vector2i,offset: float=0.0) -> Vector3:
	var at: Vector3=super.grid(tile,offset)
	if campus!=null: at.y+=.29 if campus.indoor(Vector3(tile.x+.5,0,-tile.y-.5)) else .12
	return at

func pick_tile(pixel: Vector2) -> Vector2i:
	# Two floor elevations; choose the plane consistent with the room grid.
	for elevation in [.29,.12]:
		var at: Variant=Plane(Vector3.UP,elevation).intersects_ray(camera.project_ray_origin(pixel),camera.project_ray_normal(pixel))
		if at==null: continue
		var tile:=Vector2i(floori(at.x/1.4),floori(-at.z/1.4))
		if not state.nav.inside(tile): continue
		var indoor: bool=int(room_ids[tile.y*state.nav.width+tile.x])!=0
		if indoor==(elevation>.2): return tile
	return Vector2i(-1,-1)

func sync(index: int) -> void:
	super.sync(index)
	for h: Dictionary in state.hostages:
		if not hostage_nodes.has(h.id): _hostage(h)
		var node: Node3D=hostage_nodes[h.id]
		node.position=grid(h.pos)
		node.visible=state.hostage_visible(h)
		var label:=node.get_node("Name") as Label3D
		label.text=h.name+(" · 已解救" if h.rescued else " · 待解救")
		label.modulate=Color("#89e7ba") if h.rescued else Color("#f6e1a5")
		(node.get_node("Ring").material_override as StandardMaterial3D).albedo_color=label.modulate
		var motion=node.get_node("Motion")
		if h.rescued and motion.action_hold: motion.release_action()
	interaction_target={}

func clear_preview() -> void:
	super.clear_preview()
	hover_tile=Vector2i(-1,-1)
	preview_route=[]

func draw_preview(tile: Vector2i) -> int:
	var cost:=super.draw_preview(tile)
	if state.nav.inside(tile) and state.nav.passable(tile) and state.tile_visible(tile): hover_tile=tile
	if cost>0:
		hover_tile=tile
		preview_route=state.nav.path(state.cops[selected].pos,tile,reached.parents)
	return cost

func move_unit(unit: Dictionary,route: Array,quick:=false) -> void:
	active_route=route.duplicate()
	await super.move_unit(unit,route,quick)
	active_route=[]

func reveal_interaction(unit: Dictionary) -> void:
	interaction_target=unit

func _hostage(h: Dictionary) -> void:
	var node:=Node3D.new()
	node.name="Hostage_%d"%h.id
	add_child(node)
	var model: Node3D=(HOSTAGE_FEMALE if h.gender==1 else HOSTAGE_MALE).instantiate()
	node.add_child(model)
	# Source prefab roots carry Unity scene offsets, not local placement.
	for child in model.get_children():
		if child is Node3D: child.position=Vector3.ZERO
	prepare_scene(model)
	var motion:=preload("res://scripts/horde_actor_motion.gd").new()
	motion.name="Motion"
	node.add_child(motion)
	motion.initialize(model)
	motion.gender=h.gender
	motion.start_clip("surrender",true)
	var marker:=ring(Color("#f6e1a5"))
	marker.name="Ring"
	node.add_child(marker)
	var caption:=Label3D.new()
	caption.name="Name"
	caption.position.y=2.2
	caption.font_size=28
	caption.pixel_size=.009
	caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	caption.outline_size=8
	node.add_child(caption)
	hostage_nodes[h.id]=node

func pick_unit(pixel: Vector2) -> Dictionary:
	var picked: Dictionary=super.pick_unit(pixel)
	var nearest:=INF
	if not picked.is_empty(): nearest=unit_hit_score(pixel,actors[picked.id],picked.wound=="躯干")
	for h: Dictionary in state.hostages:
		if not hostage_nodes.has(h.id) or not hostage_nodes[h.id].visible: continue
		var distance:=unit_hit_score(pixel,hostage_nodes[h.id])
		if distance<nearest: picked=h;nearest=distance
	return picked

func _set_cop_position(at: Vector3,u: Dictionary,n: Node3D) -> void:
	super._set_cop_position(at,u,n)
	for h: Dictionary in state.hostages:
		if hostage_nodes.has(h.id): hostage_nodes[h.id].visible=state.hostage_visible(h)

func _process(delta: float) -> void:
	super._process(delta)
	if camera==null: return
	var pixel:=camera.size/maxf(1,get_viewport().get_visible_rect().size.y)
	for node: Node3D in hostage_nodes.values():
		(node.get_node("Name") as Label3D).pixel_size=pixel*.5
	for case_node: Node3D in cases.values():
		var icon:=case_node.get_node("LootIcon") as Sprite3D
		if icon.texture!=null: icon.pixel_size=pixel*30/maxf(icon.texture.get_width(),icon.texture.get_height())
	if occlusion!=null:
		var points: Array[Vector3]=[]
		var cop: Dictionary=state.cops[selected]
		var actor: Node3D=actors.get(cop.id)
		if actor!=null and actor.visible:
			points.append(actor.position+Vector3.UP*.18)
			points.append(actor.position+Vector3.UP*1.1)
		# Visible enemy playback gets the same treatment; never reveal hidden AI.
		for id in moving:
			if id==cop.id or not actors.has(id) or not actors[id].visible: continue
			points.append(actors[id].position+Vector3.UP*.18)
			points.append(actors[id].position+Vector3.UP*1.1)
			break
		if hover_tile.x>=0: points.append(grid(hover_tile,.12))
		elif not interaction_target.is_empty() and state.tile_visible(interaction_target.pos): points.append(grid(interaction_target.pos,.7))
		var route:=preview_route
		if not active_route.is_empty() and actor!=null:
			var nearest:=0
			for i in range(active_route.size()):
				if actor.position.distance_squared_to(grid(active_route[i]))<actor.position.distance_squared_to(grid(active_route[nearest])): nearest=i
			route=active_route.slice(nearest)
		if not route.is_empty():
			var count:=mini(8-points.size(),route.size())
			for i in range(count):
				var index:=roundi(float(i)*(route.size()-1)/maxi(1,count-1))
				points.append(grid(route[index],.12))
		occlusion.set_targets(points)

func set_weather(index: int,animate: bool=true) -> void:
	super.set_weather(index,animate)
	# Campus cream surfaces need less fill than the original dark horde map.
	if weather_tween!=null and weather_tween.is_valid(): weather_tween.kill()
	sunlight.light_energy=.52 if index==4 else .72 if index==0 else .55
	atmosphere.ambient_light_energy=.44

func toggle_zoom() -> void:
	if zoom_alternate: camera.size=zoom_return_size; center_on(state.cops[selected].pos)
	else:
		zoom_return_size=camera.size
		camera.size=165
		focus=Vector3(53*1.4,0,-54*1.4)
		update_camera()
	zoom_alternate=not zoom_alternate

func zoom(factor: float) -> void:
	camera.size=clampf(camera.size*factor,15,175)
	zoom_alternate=false
