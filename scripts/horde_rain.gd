extends Control

# Camera-relative outdoor rain. The weather is presentation only: tactical
# sight lines, hit chance and pathfinding never depend on this control.
const RAIN_SOUND = preload("res://assets/horde/audio/ambient/Rain.ogg")
const DROP_COUNT := 260
var world: Node3D
var drops: Array = []
var ripples: Array = []
var rng := RandomNumberGenerator.new()
var ambience: AudioStreamPlayer
var outdoor_tiles: Dictionary = {}
var target := 0.0
var amount := 0.0
var effects_gain := 1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.seed = 20260930 # Visual RNG never advances combat RNG.
	_build_outdoor_tiles()
	ambience = AudioStreamPlayer.new()
	ambience.stream = RAIN_SOUND.duplicate()
	ambience.stream.loop = true
	add_child(ambience)
	set_process(false)

func _build_outdoor_tiles() -> void:
	# Room IDs omit some large shop interiors. Flood from map boundaries across
	# permanently open edges; doors/windows never turn an indoor floor into sky.
	var nav = world.state.nav
	if world.state.data.has("room_ids"):
		# Custom maps provide explicit rooms, including enclosed outdoor yards.
		for tile: Vector2i in nav.cells:
			if nav.passable(tile) and int(world.room_ids[tile.y*nav.width+tile.x])==0: outdoor_tiles[tile]=true
		return
	var frontier: Array[Vector2i] = []
	for x in range(nav.width):
		for y in [0, nav.height-1]:
			var tile := Vector2i(x,y)
			if nav.passable(tile) and int(world.room_ids[y*nav.width+x]) == 0 and not outdoor_tiles.has(tile):
				outdoor_tiles[tile] = true
				frontier.append(tile)
	for y in range(nav.height):
		for x in [0, nav.width-1]:
			var tile := Vector2i(x,y)
			if nav.passable(tile) and int(world.room_ids[y*nav.width+x]) == 0 and not outdoor_tiles.has(tile):
				outdoor_tiles[tile] = true
				frontier.append(tile)
	var head := 0
	while head < frontier.size():
		var tile := frontier[head]
		head += 1
		for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var next: Vector2i = tile + direction
			if not nav.inside(next) or not nav.passable(next) or outdoor_tiles.has(next): continue
			if int(world.room_ids[next.y*nav.width+next.x]) != 0: continue
			var edge: int = nav.edge(tile,next)
			if edge < 0 or int(nav.edges[edge]) not in [0,5,13]: continue
			outdoor_tiles[next] = true
			frontier.append(next)

func is_outdoor(tile: Vector2i) -> bool:
	return outdoor_tiles.has(tile)

func _exit_tree() -> void:
	if ambience != null:
		ambience.stop()
		ambience.stream = null

func set_raining(value: bool) -> void:
	target = 1.0 if value else 0.0
	if value and drops.is_empty():
		for i in range(DROP_COUNT): drops.append(_spawn())
	set_process(true)

func _spawn() -> Dictionary:
	if world == null or world.state == null: return {}
	var nav = world.state.nav
	var radius := maxf(23.0, world.camera.size * 1.1)
	for attempt in range(30):
		var x: float = world.focus.x + rng.randf_range(-radius, radius)
		var z: float = world.focus.z + rng.randf_range(-radius, radius)
		var tile := Vector2i(floori(x / 1.4), floori(-z / 1.4))
		if not nav.inside(tile): continue
		if not is_outdoor(tile): continue
		var ground: float = world.grid(tile).y
		return {"pos": Vector3(x, ground + rng.randf_range(1.0, 7.0), z), "ground": ground,
			"speed": rng.randf_range(10.0, 16.0), "length": rng.randf_range(0.5, 0.95)}
	return {}

func _process(delta: float) -> void:
	amount = move_toward(amount, target, delta * 0.85)
	if amount < 0.001 and target == 0.0:
		amount = 0.0
		ambience.stop()
		set_process(false)
		queue_redraw()
		return
	if not ambience.playing and target > 0.0: ambience.play()
	ambience.volume_db = linear_to_db(maxf(0.0001, amount * effects_gain * 0.11))
	var radius := maxf(23.0, world.camera.size * 1.1)
	for i in range(drops.size()):
		var drop: Dictionary = drops[i]
		if drop.is_empty():
			drops[i] = _spawn()
			continue
		var position: Vector3 = drop.pos
		if absf(position.x-world.focus.x) > radius or absf(position.z-world.focus.z) > radius:
			drops[i] = _spawn()
			continue
		position.y -= float(drop.speed) * minf(delta, 0.05)
		if position.y <= float(drop.ground):
			if ripples.size() < 26 and rng.randf() < 0.2:
				ripples.append({"pos": Vector3(position.x,float(drop.ground)+0.035,position.z), "age": 0.0})
			position.y = float(drop.ground) + rng.randf_range(4.0, 8.0)
		drop.pos = position
	for i in range(ripples.size()-1, -1, -1):
		ripples[i].age += delta
		if ripples[i].age >= 0.58: ripples.remove_at(i)
	queue_redraw()

func _draw() -> void:
	if amount <= 0.0 or world == null or world.camera == null: return
	var camera: Camera3D = world.camera
	var viewport_size := size
	for drop: Dictionary in drops:
		if drop.is_empty(): continue
		var position: Vector3 = drop.pos
		if camera.is_position_behind(position): continue
		var head := camera.unproject_position(position + Vector3.UP * float(drop.length))
		var tail := camera.unproject_position(position)
		if tail.x < -20 or tail.x > viewport_size.x+20 or tail.y < -20 or tail.y > viewport_size.y+20: continue
		# A screen overlay has no depth test. Cull rain whose projected pixel
		# lands on an indoor floor, even if its world-space drop is outdoors.
		var visible_tile: Vector2i = world.pick_tile(tail)
		if not is_outdoor(visible_tile): continue
		draw_line(head + Vector2(-2, 0), tail, Color(0.76, 0.87, 0.93, 0.34 * amount), 1.0, true)
	for ripple: Dictionary in ripples:
		var position: Vector3 = ripple.pos
		if camera.is_position_behind(position): continue
		var center := camera.unproject_position(position)
		if not Rect2(Vector2.ZERO, viewport_size).has_point(center): continue
		var visible_tile: Vector2i = world.pick_tile(center)
		if not is_outdoor(visible_tile): continue
		var age: float = ripple.age
		var edge := camera.unproject_position(position + Vector3(0.11 + age * 0.27, 0, 0))
		var radius := clampf(center.distance_to(edge), 1.2, 8.0)
		draw_arc(center, radius, 0, TAU, 16, Color(0.76, 0.88, 0.92, (1.0 - age / 0.58) * 0.34 * amount), 1.0, true)
