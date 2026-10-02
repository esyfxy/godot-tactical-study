extends Control

signal focused(tile: Vector2i)
var state
var map_texture: ImageTexture
var selected := 0

func initialize(game_state) -> void:
	state = game_state
	var img := Image.create(state.nav.width, state.nav.height, false, Image.FORMAT_RGB8)
	img.fill(Color("#1e2426"))
	for p in state.nav.cells:
		if state.nav.passable(p): img.set_pixel(p.x, p.y, Color("#66645b"))
	map_texture = ImageTexture.create_from_image(img)
	tooltip_text = "点击指挥地图移动镜头。蓝点：警员；红点：可见敌人；橙点：补给。"
	queue_redraw()

func to_pixel(tile: Vector2i) -> Vector2:
	return Vector2(tile) / Vector2(state.nav.width, state.nav.height) * size

func _draw() -> void:
	if state == null: return
	draw_texture_rect(map_texture, Rect2(Vector2.ZERO, size), false)
	for p in state.loot: draw_circle(to_pixel(p), 2, Color("#ef9a64"))
	for e in state.active_enemies():
		if state.visible_enemy(e): draw_circle(to_pixel(e.pos), 3, Color("#fa6154"))
	for i in range(state.cops.size()):
		var c: Dictionary = state.cops[i]
		if c.dead: continue
		draw_circle(to_pixel(c.pos), 4 if i == selected else 3, Color("#ffe33c") if i == selected else Color("#87d9fa"))
	if state.has_method("hostage_visible"):
		for h: Dictionary in state.hostages:
			if state.discovered_hostages.has(h.id): draw_circle(to_pixel(h.pos),3,Color("#89e7ba") if h.rescued else Color("#f6e1a5"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#bca853"), false, 1)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		focused.emit(Vector2i(event.position / size * Vector2(state.nav.width, state.nav.height)))
		accept_event()
