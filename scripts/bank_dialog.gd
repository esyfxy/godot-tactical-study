extends Control

# Modal UI only. Inventory, AP, passwords and mission state belong to the game.
signal dismissed
signal confirmed(value: String)
var panel: PanelContainer
var column: VBoxContainer
var title: Label
var body: RichTextLabel
var entry: LineEdit
var confirm: Button
var cancel: Button
var choices: VBoxContainer
var mode := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.025, 0.025, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#24211b")
	style.border_color = Color("#ffe12d")
	style.set_border_width_all(2)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffe12d"))
	column.add_child(title)
	body = RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = true
	body.custom_minimum_size.y = 120
	body.add_theme_font_size_override("normal_font_size", 18)
	column.add_child(body)
	entry = LineEdit.new()
	entry.max_length = 4
	entry.placeholder_text = "输入四位密码"
	entry.custom_minimum_size.y = 42
	entry.add_theme_font_size_override("font_size", 24)
	entry.text_changed.connect(func(value: String): confirm.disabled = value.length() != 4 or not value.is_valid_int())
	entry.text_submitted.connect(func(_value: String): _confirm())
	column.add_child(entry)
	choices = VBoxContainer.new()
	column.add_child(choices)
	confirm = Button.new()
	confirm.custom_minimum_size.y = 42
	confirm.pressed.connect(_confirm)
	column.add_child(confirm)
	cancel = Button.new()
	cancel.text = "返回游戏  [Esc]"
	cancel.custom_minimum_size.y = 38
	cancel.pressed.connect(close)
	column.add_child(cancel)
	resized.connect(_layout)
	hide()

func present(kind: String, heading: String, content: String, accept_text: String = "继续") -> void:
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	mode = kind
	title.text = heading
	body.text = content
	entry.visible = kind == "password"
	entry.text = ""
	confirm.text = accept_text
	confirm.disabled = entry.visible
	cancel.visible = kind in ["password", "pause", "restart"]
	show()
	move_to_front()
	_layout()
	if entry.visible: entry.grab_focus()
	else: confirm.grab_focus()

func add_choice(label: String, token: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 32
	button.pressed.connect(func(): confirmed.emit(token))
	choices.add_child(button)
	_layout.call_deferred()

func _layout() -> void:
	if panel == null: return
	panel.custom_minimum_size.x = minf(650, maxf(300, size.x - 48))
	panel.size = Vector2(panel.custom_minimum_size.x, 0)
	body.fit_content = false
	body.custom_minimum_size = Vector2(0, minf(240, maxf(120, size.y * 0.3)))
	panel.reset_size()
	panel.position = (size - panel.size) * 0.5
	# Containers finish their minimum-size layout after the text changes.
	_center.call_deferred()

func _center() -> void:
	if panel != null: panel.position = (size - panel.size) * 0.5

func _confirm() -> void:
	if confirm.disabled: return
	confirmed.emit(entry.text if entry.visible else mode)

func close() -> void:
	hide()
	dismissed.emit()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_confirm()
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton: accept_event()
