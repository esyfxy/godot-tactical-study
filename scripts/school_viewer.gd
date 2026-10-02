extends Control

const MAP = preload("res://scripts/school_map.gd")
const RIG = preload("res://assets/horde/actors/cop/cop_rig.gltf")
const MOTION = preload("res://scripts/horde_actor_motion.gd")
var campus
var camera: Camera3D
var focus := Vector3(53,0,-54)
var world: Node3D
var surface: SubViewportContainer
var viewport: SubViewport
var actor: Node3D
var movement: Tween
var busy := false
var drag := false
var drag_start := Vector2.ZERO
var drag_last := Vector2.ZERO
var dragged := false
var route_mesh: MeshInstance3D
var marker: MeshInstance3D
var caption: Label
var message: Label
var roof_button: Button
var rain_button: Button
var weather
var hover_tile := Vector2i(-1,-1)
var overview := true
var sun: DirectionalLight3D
var hud: Control
var tools_row: HBoxContainer
var locations: HBoxContainer
var audio: AudioStreamPlayer
var weather_tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface=SubViewportContainer.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.stretch=true
	add_child(surface)
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_2X
	surface.add_child(viewport)
	world=Node3D.new()
	viewport.add_child(world)
	campus=MAP.new()
	campus.name="PingnanCampus"
	world.add_child(campus)
	sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-52,-32,0)
	sun.light_color=Color("#fff0d4")
	sun.light_energy=.72
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=220
	world.add_child(sun)
	var env:=WorldEnvironment.new()
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("#bcc7bd")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("#bfcbd4")
	environment.ambient_light_energy=.44
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	env.environment=environment
	world.add_child(env)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=118
	camera.far=400
	world.add_child(camera)
	camera.current=true
	_update_camera()
	_create_actor()
	route_mesh=MeshInstance3D.new()
	route_mesh.mesh=ImmediateMesh.new()
	var route_mat:=StandardMaterial3D.new()
	route_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	route_mat.albedo_color=Color("#82c6c0")
	route_mat.no_depth_test=true
	route_mesh.material_override=route_mat
	world.add_child(route_mesh)
	marker=MeshInstance3D.new()
	var circle:=TorusMesh.new()
	circle.inner_radius=.41
	circle.outer_radius=.48
	circle.rings=24
	circle.ring_segments=5
	marker.mesh=circle
	marker.material_override=route_mat
	marker.hide()
	world.add_child(marker)
	weather=preload("res://scripts/school_rain.gd").new()
	weather.viewer=self
	add_child(weather)
	_build_hud()
	surface.gui_input.connect(_map_input)
	surface.mouse_exited.connect(func():
		if not drag: _clear_preview())
	resized.connect(_layout)
	get_window().focus_exited.connect(func(): drag=false)
	_layout()

func _exit_tree() -> void:
	if movement != null and movement.is_valid(): movement.kill()
	if audio != null:
		audio.stop()
		audio.stream=null

func _create_actor() -> void:
	actor=Node3D.new()
	actor.name="CampusVisitor"
	world.add_child(actor)
	actor.position=campus.world_at(Vector2i(48,9))
	var model: Node3D=RIG.instantiate()
	actor.add_child(model)
	var motion:=MOTION.new()
	actor.add_child(motion)
	motion.initialize(model)
	motion.configure_weapons(model)
	audio=AudioStreamPlayer.new()
	audio.volume_db=-25
	add_child(audio)
	motion.footstep.connect(func(foot: String):
		audio.stream=load("res://assets/bank/audio/footsteps/Step "+("L" if foot=="left" else "R")+"1.ogg")
		audio.play())
	var circle:=MeshInstance3D.new()
	var torus:=TorusMesh.new()
	torus.inner_radius=.38
	torus.outer_radius=.43
	torus.rings=24
	torus.ring_segments=5
	circle.mesh=torus
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=Color("#efd36e")
	circle.material_override=mat
	circle.position.y=.06
	actor.add_child(circle)

func _label(parent: Node,value: String,font_size: int) -> Label:
	var label:=Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("#f4efdc"))
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node,value: String,callback: Callable) -> Button:
	var button:=Button.new()
	button.text=value
	button.focus_mode=Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size",14)
	button.custom_minimum_size=Vector2(100,36)
	for variant in ["normal","hover","pressed"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("#263d3df0") if variant=="normal" else Color("#42615deb")
		style.border_color=Color("#b9b487")
		style.set_border_width_all(1)
		style.set_content_margin_all(9)
		style.set_corner_radius_all(4)
		button.add_theme_stylebox_override(variant,style)
	button.pressed.connect(callback)
	parent.add_child(button)
	preload("res://scripts/horde_ui_motion.gd").bind_button(button)
	return button

func _build_hud() -> void:
	hud=Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var panel:=PanelContainer.new()
	panel.position=Vector2(18,16)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("#213836ed")
	style.set_content_margin_all(12)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel",style)
	hud.add_child(panel)
	var column:=VBoxContainer.new()
	panel.add_child(column)
	caption=_label(column,"平南县中学",24)
	_label(column,"原创校园 · 雨后清晨",13)
	tools_row=HBoxContainer.new()
	tools_row.add_theme_constant_override("separation",6)
	hud.add_child(tools_row)
	roof_button=_button(tools_row,"剖开屋顶 [R]",toggle_roofs)
	rain_button=_button(tools_row,"细雨 [T]",toggle_rain)
	_button(tools_row,"全景 [中键]",toggle_zoom)
	_button(tools_row,"返回 [Esc]",back)
	locations=HBoxContainer.new()
	locations.add_theme_constant_override("separation",6)
	hud.add_child(locations)
	for entry in [["校门",Vector3(48,0,-13)],["教学楼",Vector3(25,0,-69)],["图书馆",Vector3(56,0,-55)],["食堂",Vector3(89,0,-38)],["操场",Vector3(78,0,-88)]]:
		_button(locations,entry[0],locate.bind(entry[1]))
	message=_label(hud,"左键移动 · 滚轮缩放 · 右键拖动 · 空格定位人物",14)
	message.add_theme_color_override("font_shadow_color",Color("#152a28"))
	message.add_theme_constant_override("shadow_outline_size",3)
	message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER

func _layout() -> void:
	if viewport==null: return
	var scale_factor:=minf(1.0,size.x/1280.0)
	tools_row.scale=Vector2.ONE*scale_factor
	tools_row.reset_size()
	tools_row.position=Vector2(size.x-tools_row.size.x*scale_factor-18,18)
	locations.scale=Vector2.ONE*scale_factor
	locations.reset_size()
	locations.position=Vector2((size.x-locations.size.x*scale_factor)*.5,size.y-66)
	message.position=Vector2(12,size.y-27)
	message.size=Vector2(size.x-24,24)

func _update_camera() -> void:
	focus.x=clampf(focus.x,4,104)
	focus.z=clampf(focus.z,-105,-3)
	camera.position=focus+Vector3(-80,113,80)
	camera.look_at(focus)

func locate(at: Vector3) -> void:
	focus=at
	camera.size=40
	overview=false
	if campus.indoor(at) and campus.roofs_visible: toggle_roofs()
	_update_camera()

func toggle_zoom() -> void:
	overview=not overview
	camera.size=118 if overview else 42
	if overview: focus=Vector3(53,0,-54)
	else: focus=actor.position
	_update_camera()

func toggle_roofs() -> void:
	campus.set_roofs(not campus.roofs_visible)
	roof_button.text="剖开屋顶 [R]" if campus.roofs_visible else "恢复屋顶 [R]"

func toggle_rain() -> void:
	weather.set_raining(weather.target<.5)
	rain_button.text="雨后晴光 [T]" if weather.target>.5 else "细雨 [T]"
	if weather_tween!=null and weather_tween.is_valid(): weather_tween.kill()
	weather_tween=create_tween().set_parallel(true)
	weather_tween.tween_property(sun,"light_color",Color("#cbdde0") if weather.target>.5 else Color("#fff0d4"),1.0)
	weather_tween.tween_property(sun,"light_energy",.52 if weather.target>.5 else .72,1.0)

func ground_at(pixel: Vector2) -> Variant:
	return Plane(Vector3.UP,.12).intersects_ray(camera.project_ray_origin(pixel),camera.project_ray_normal(pixel))

func _clear_preview() -> void:
	if route_mesh!=null: (route_mesh.mesh as ImmediateMesh).clear_surfaces()
	if marker!=null: marker.hide()
	hover_tile=Vector2i(-1,-1)

func _preview(pixel: Vector2) -> void:
	if busy: return
	var at: Variant=ground_at(pixel)
	if at==null: return
	var tile: Vector2i=campus.tile_at(at)
	if tile==hover_tile: return
	hover_tile=tile
	var route: PackedVector3Array=campus.path(actor.position,at)
	var mesh:=route_mesh.mesh as ImmediateMesh
	mesh.clear_surfaces()
	marker.visible=not route.is_empty()
	if route.is_empty(): return
	marker.position=route[-1]+Vector3.UP*.05
	if route.size()<2: return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(route.size()-1):
		mesh.surface_add_vertex(route[i]+Vector3.UP*.08)
		mesh.surface_add_vertex(route[i+1]+Vector3.UP*.08)
	mesh.surface_end()

func move_to(at: Vector3) -> bool:
	if busy: return false
	var route: PackedVector3Array=campus.path(actor.position,at)
	if route.size()<2:
		message.text="这里没有可通行路线；可以从门口进入建筑。"
		return false
	busy=true
	if campus.indoor(route[-1]) and campus.roofs_visible: toggle_roofs()
	_clear_preview()
	marker.position=route[-1]+Vector3.UP*.05
	marker.show()
	message.text="正在前往目的地 · 可继续拖动和缩放视角"
	movement=create_tween()
	for i in range(1,route.size()):
		movement.tween_property(actor,"position",route[i],actor.position.distance_to(route[i]) / 6.0 if i==1 else route[i-1].distance_to(route[i])/6.0)
	movement.tween_callback(func():
		busy=false
		marker.hide()
		if campus.indoor(actor.position) and campus.roofs_visible: toggle_roofs()
		message.text="已到达 · 左键移动 · 右键拖动 · 空格定位人物")
	return true

func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:
			drag=event.pressed
			dragged=false
			drag_start=event.position
			drag_last=event.position
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:
			camera.size=clampf(camera.size*.90,22,135)
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			camera.size=clampf(camera.size*1.1,22,135)
		elif event.pressed and event.button_index==MOUSE_BUTTON_MIDDLE: toggle_zoom()
		elif event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var at: Variant=ground_at(event.position)
			if at!=null: move_to(at)
	elif event is InputEventMouseMotion:
		if drag:
			var before: Variant=ground_at(drag_last)
			var after: Variant=ground_at(event.position)
			if before!=null and after!=null:
				focus+=before-after
				_update_camera()
			drag_last=event.position
		else: _preview(event.position)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed: drag=false

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_ESCAPE: back()
		KEY_R: toggle_roofs()
		KEY_T: toggle_rain()
		KEY_SPACE:
			focus=actor.position
			_update_camera()
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if camera==null: return
	var move:=Vector2(Input.get_axis("ui_left","ui_right"),Input.get_axis("ui_up","ui_down"))
	move+=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	if move.length_squared()>.01:
		var right:=camera.global_basis.x
		var forward:=Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
		focus+=(right*move.x+forward*move.y)*delta*camera.size*.42
		_update_camera()

func back() -> void:
	get_tree().change_scene_to_file("res://scenes/mode_menu.tscn")
