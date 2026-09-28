extends Control

signal camera_drag_requested(at: Vector2)

const UI = preload("res://scripts/horde_ui_theme.gd")
const MOTION = preload("res://scripts/horde_ui_motion.gd")
var buttons: Dictionary = {}
var info: Label
var title: Label
var footer: Label
var large_icon: TextureRect
var center := Vector2.ZERO
var entries: Array = []
var anchor_pixel := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 20
	hide()

func circle(color: Color) -> StyleBoxFlat:
	var s := UI.flat(color)
	s.set_corner_radius_all(48)
	return s

func present(options: Array, at: Vector2, view_size: Vector2) -> void:
	entries = options
	anchor_pixel = at
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	var factor := minf(view_size.x/1920.0, view_size.y/1080.0)
	scale = Vector2.ONE * factor
	size = view_size / factor
	var radius := 228.0 if entries.size() > 6 else 195.0
	center = Vector2(clampf(at.x/factor, radius+62, size.x-radius-62), clampf(at.y/factor-35, radius+180, size.y-240-radius-52))
	var panel := ColorRect.new()
	panel.position = Vector2(0, size.y-230)
	panel.size = Vector2(size.x, 230)
	panel.color = Color("#090909f5")
	add_child(panel)
	var line := ColorRect.new()
	line.color = UI.GOLD
	line.size = Vector2(size.x, 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
	var badge := Panel.new()
	badge.position = Vector2(293, 38)
	badge.size = Vector2(106, 106)
	badge.add_theme_stylebox_override("panel", circle(Color.WHITE))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(badge)
	large_icon = UI.icon(badge, "Trade", Rect2(18, 18, 70, 70), UI.INK)
	title = UI.text(panel, "", Rect2(434, 28, size.x-485, 45), 34)
	info = UI.text(panel, "", Rect2(434, 83, size.x-515, 70), 25)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer = UI.text(panel, "", Rect2(434, 168, size.x-485, 42), 22)
	UI.text(panel, "右键 / Esc 取消", Rect2(size.x-300, 182, 270, 32), 19, Color("#aaaaa1"), true)
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var angle := -PI/2 - 0.16 + TAU*i/maxi(1, entries.size())
		var b := Button.new()
		b.position = center + Vector2(cos(angle), sin(angle))*radius - Vector2(46, 46)
		b.size = Vector2(92, 92)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not str(entry.get("reason", "")).is_empty()
		b.add_theme_stylebox_override("normal", circle(Color("#f8f8f7")))
		b.add_theme_stylebox_override("hover", circle(UI.GOLD))
		b.add_theme_stylebox_override("pressed", circle(Color("#e1bd19")))
		b.add_theme_stylebox_override("disabled", circle(Color("#898985dc")))
		b.tooltip_text = str(entry.label) + ("：" + str(entry.reason) if b.disabled else "")
		add_child(b)
		MOTION.bind_button(b)
		var glyph := UI.icon(b, entry.get("icon", "Interact"), Rect2(17, 17, 58, 58), Color("#565652") if b.disabled else UI.INK)
		glyph.pivot_offset=glyph.size*.5
		if entry.has("chance") and not b.disabled:
			var chance := preload("res://scripts/horde_chance_pointer.gd").new()
			chance.position=Vector2(4,4)
			chance.size=Vector2(84,84)
			chance.radius=39
			chance.disk=false
			b.add_child(chance)
			chance.restart(float(entry.chance),0.33)
		b.mouse_entered.connect(func():
			if not b.disabled: MOTION.animate(glyph,"scale",^"scale",Vector2.ONE*1.07,0.13))
		b.mouse_exited.connect(func(): MOTION.animate(glyph,"scale",^"scale",Vector2.ONE,0.13))
		b.mouse_entered.connect(describe.bind(entry))
		b.pressed.connect(func():
			hide()
			if entry.has("run"): entry.run.call())
		buttons[entry.id] = b
	if not entries.is_empty(): describe(entries[0])
	show()
	move_to_front()
	preload("res://scripts/horde_ui_motion.gd").reveal(self)

func describe(entry: Dictionary) -> void:
	title.text = str(entry.label)
	info.text = str(entry.get("description", ""))
	var reason := str(entry.get("reason", ""))
	if not reason.is_empty(): info.text += "\n不可用：" + reason
	var cost := int(entry.get("cost", 0))
	footer.text = ("大声" if entry.get("loud", false) else "静默") + "    ·    " + ("不消耗行动点" if cost == 0 else "%d 行动点" % cost)
	footer.add_theme_color_override("font_color", Color("#e9604f") if entry.get("loud", false) else Color.WHITE)
	large_icon.texture = UI.texture(entry.get("icon", "Interact"))
	MOTION.reveal(large_icon)
	MOTION.reveal(title)
	MOTION.reveal(info)

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		hide()
		camera_drag_requested.emit(event.position)
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT: hide()
