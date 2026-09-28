extends Control

# UI presentation only: the tactical controller remains the authority for
# action range, AP, target state and execution. Coordinates come from the
# exported Sprite.m_Rect (Unity bottom-left converted to Godot top-left).
signal action_requested(id: int)
signal dismissed
const ATLAS = preload("res://assets/bank/ui/tactics_actions_original.png")
const ICONS := {1: Rect2(528, 208, 256, 256), 3: Rect2(2112, 1528, 256, 256),
	5: Rect2(1848, 1000, 256, 256), 10: Rect2(0, 1000, 256, 256),
	14: Rect2(792, 208, 256, 256)} # AimedShot / MisterFreeze, not surrender flag.
const DETAILS := {14: "命令罪犯举手投降。需要进入喝止范围，且视线没有被墙挡住。",
	1: "近身使用警棍击昏目标，再使用手铐逮捕。",
	3: "使用泰瑟枪制服近距离目标。目标昏迷后可以逮捕。",
	10: "使用手枪攻击目标。当前仍为简化射击判定，部位瞄准尚未接入。",
	5: "给已举手或昏迷的罪犯戴上手铐。先靠近目标再执行。",
	55: "靠近人质并解除束缚。"}
var buttons: Dictionary = {}
var info: Label
var heading: Label
var center := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 20
	hide()

func _circle(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(36)
	return style

func present(entries: Array, at: Vector2, viewport_size: Vector2, title: String, preferred: int) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	position = Vector2.ZERO
	size = viewport_size
	center = Vector2(clampf(at.x, 160, maxf(160, size.x - 160)), clampf(at.y, 255, maxf(255, size.y - 292)))
	heading = Label.new()
	heading.text = title + "\n选择动作"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_shadow_color", Color.BLACK)
	heading.add_theme_constant_override("shadow_offset_x", 2)
	heading.add_theme_constant_override("shadow_offset_y", 2)
	heading.position = center - Vector2(95, 37)
	heading.size = Vector2(190, 50)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(heading)
	var panel := ColorRect.new()
	panel.color = Color(0.04, 0.035, 0.03, 0.96)
	panel.position = Vector2(0, size.y - 132)
	panel.size = Vector2(size.x, 132)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var rule := ColorRect.new()
	rule.color = Color("#ffe123")
	rule.size = Vector2(size.x, 2)
	panel.add_child(rule)
	info = Label.new()
	info.position = Vector2(32, 14)
	info.size = Vector2(size.x - 64, 108)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 18)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(info)
	var initial: Dictionary = entries[0]
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var id: int = entry["id"]
		var button := Button.new()
		button.name = "Action_%d" % id
		button.size = Vector2(66, 66)
		var angle := -PI * 0.5 + TAU * float(index) / float(entries.size())
		button.position = center + Vector2(cos(angle), sin(angle)) * 117.0 - button.size * 0.5
		button.focus_mode = Control.FOCUS_NONE
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		button.disabled = not str(entry["reason"]).is_empty()
		button.tooltip_text = "%s · %s" % [entry["label"], entry["reason"] if button.disabled else "%d AP" % entry["cost"]]
		button.add_theme_stylebox_override("normal", _circle(Color("#e3dcc7"), Color("#fff4d1")))
		button.add_theme_stylebox_override("hover", _circle(Color("#ffe123"), Color.WHITE))
		button.add_theme_stylebox_override("pressed", _circle(Color("#e2b91a"), Color.WHITE))
		button.add_theme_stylebox_override("disabled", _circle(Color(0.55, 0.53, 0.49, 0.86), Color("#847f72")))
		add_child(button)
		if ICONS.has(id):
			var icon := TextureRect.new()
			var crop := AtlasTexture.new()
			crop.atlas = ATLAS
			crop.region = ICONS[id]
			icon.texture = crop
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.position = Vector2(12, 12)
			icon.size = Vector2(42, 42)
			icon.modulate = Color("#625f53") if button.disabled else Color("#27251d")
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(icon)
		else:
			button.text = str(entry["label"])
			button.add_theme_color_override("font_color", Color("#27251d"))
		button.mouse_entered.connect(_describe.bind(entry))
		button.pressed.connect(func(): action_requested.emit(id))
		buttons[id] = button
		if id == preferred:
			initial = entry
			if not button.disabled:
				button.add_theme_stylebox_override("normal", _circle(Color("#ffe123"), Color.WHITE))
	var cancel := Button.new()
	cancel.text = "取消 [Esc]"
	cancel.position = center + Vector2(-55, 22)
	cancel.size = Vector2(110, 34)
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func(): dismissed.emit())
	add_child(cancel)
	_describe(initial)
	show()
	move_to_front()
	queue_redraw()

func _describe(entry: Dictionary) -> void:
	var reason := str(entry["reason"])
	info.text = "%s   ·   %s\n%s\n%s" % [entry["label"], "不可用：" + reason if not reason.is_empty() else "%d AP" % entry["cost"], DETAILS.get(entry["id"], ""), "点击图标执行 · 右键 / Esc 取消"]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		accept_event()
		dismissed.emit() # Consume the dismissal click; never move on the same event.

func _draw() -> void:
	if visible:
		draw_arc(center, 117, 0, TAU, 80, Color(1, 0.94, 0.68, 0.45), 1.5, true)
