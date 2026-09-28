extends Control

var content: VBoxContainer
var status: Label
var loading := ""
var buttons: Array[Button] = []
var artwork: Array = []
var pointer := Vector2.ZERO
var pointer_target := Vector2.ZERO
var overlay: ColorRect
var changing := false
var can_resume := false
var options_panel: PanelContainer
const SETTINGS = preload("res://scripts/horde_settings.gd")
var settings_path := SETTINGS.PATH
var settings: Dictionary

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("#181c1c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	settings = SETTINGS.read_settings(settings_path)
	var layers: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/menu/layers.json"))
	for layer: Dictionary in layers:
		var art := TextureRect.new()
		art.texture = load(layer.file)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		artwork.append({"node":art,"data":layer})
	# A soft local scrim keeps the original layered illustration visible.
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("#111613f2"),Color("#111613dc"),Color("#11161300")])
	gradient.offsets = PackedFloat32Array([0,.32,.72])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0,.5)
	texture.fill_to = Vector2(1,.5)
	var scrim := TextureRect.new()
	scrim.texture = texture
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var stripe := ColorRect.new()
	stripe.color = Color("#efd43d")
	stripe.position = Vector2(0, 0)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 8
	add_child(stripe)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	add_child(content)
	text("REBEL COPS", 44, Color("#f1d542"))
	text("选择行动", 24, Color("#f1ead6"))
	text("Godot 个人学习项目 · 玩法移植开发中", 15, Color("#a5afa8"))
	var saved := preload("res://scripts/horde_save.gd").read_save()
	var resume := Button.new()
	resume.text = "继续义军呐喊" if saved.ok else "暂无可继续战局"
	resume.custom_minimum_size.y = 48
	resume.disabled = not saved.ok
	can_resume = saved.ok
	resume.tooltip_text = "读取上一份有效备份" if saved.get("backup",false) else saved.get("error","")
	resume.pressed.connect(func(): get_tree().set_meta("horde_resume",true); start("res://scenes/horde_mode.tscn"))
	content.add_child(resume)
	buttons.append(resume)
	add_mode("义军呐喊  /  REBEL YELL", "四人持刀开局 · 搜集补给 · 抵抗持续增援\n利用掩体、警戒和声响，与队员互相支援。", "res://scenes/horde_mode.tscn")
	add_mode("银行教学关", "保留现有银行关，包含自由行动与教程指引。", "res://scenes/bank_tutorial.tscn")
	var options := Button.new()
	options.text = "选项 / 音量与战斗显示"
	options.custom_minimum_size.y = 38
	options.pressed.connect(show_options)
	content.add_child(options)
	status = text("回合边界自动保存 · 战场中按 F5 手动保存", 14, Color("#a5afa8"))
	overlay = ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	create_tween().tween_property(overlay,"modulate:a",0.0,.3)
	resized.connect(layout)
	content.minimum_size_changed.connect(func(): layout.call_deferred())
	layout()

func text(value: String, font_size: int, color: Color) -> Label:
	var n := Label.new()
	n.text = value
	n.add_theme_font_size_override("font_size", font_size)
	n.add_theme_color_override("font_color", color)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(n)
	return n

func add_mode(title: String, description: String, scene: String) -> void:
	var b := Button.new()
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 54
	b.add_theme_font_size_override("font_size", 22)
	for variant in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#303c3c") if variant == "normal" else Color("#596145")
		style.border_color = Color("#d0b849")
		style.set_border_width_all(1)
		style.content_margin_left = 23
		b.add_theme_stylebox_override(variant, style)
	b.pressed.connect(start.bind(scene))
	content.add_child(b)
	buttons.append(b)
	text(description, 16, Color("#d1d4c9"))

func layout() -> void:
	var ui_scale := minf(size.x/1280.0,size.y/720.0)
	content.scale = Vector2.ONE*ui_scale
	content.custom_minimum_size.x = 470
	content.size.x = content.custom_minimum_size.x
	content.reset_size()
	content.position = Vector2(52*ui_scale,maxf(22*ui_scale,(size.y-content.size.y*ui_scale)*.5))
	layout_art()
	if is_instance_valid(options_panel):
		options_panel.scale = Vector2.ONE*ui_scale
		options_panel.position = (size-options_panel.size*ui_scale)*.5

func layout_art() -> void:
	var factor := maxf(size.x/1920.0,size.y/1080.0)*1.06
	var origin := (size-Vector2(1920,1080)*factor)*.5
	for layer: Dictionary in artwork:
		var rect: Array = layer.data.rect
		layer.node.position = origin+Vector2(rect[0],rect[1])*factor+pointer*float(layer.data.parallax)*76*factor
		layer.node.size = Vector2(rect[2],rect[3])*factor

func show_options() -> void:
	if is_instance_valid(options_panel) or not loading.is_empty(): return
	options_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151915fa")
	style.border_color = Color("#efd43d")
	style.set_border_width_all(1)
	style.set_content_margin_all(24)
	options_panel.add_theme_stylebox_override("panel",style)
	options_panel.custom_minimum_size.x = 540
	add_child(options_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	options_panel.add_child(column)
	var heading := Label.new()
	heading.text = "选项 · 设置自动保存"
	heading.add_theme_font_size_override("font_size",26)
	column.add_child(heading)
	for entry in [["music","背景音乐"],["voice","警员语音"],["effects","音效"],["ui_scale","战场界面缩放"]]:
		var name_label := Label.new()
		column.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = .85 if entry[0]=="ui_scale" else 0
		slider.max_value = 1
		slider.step = .01
		slider.value = float(settings[entry[0]])
		slider.custom_minimum_size = Vector2(480,24)
		column.add_child(slider)
		var update := func(value: float): name_label.text="%s  %d%%" % [entry[1],roundi(value*100)]
		update.call(slider.value)
		slider.value_changed.connect(func(value: float): update.call(value); setting(entry[0],value))
	var follow := CheckButton.new()
	follow.text = "镜头跟随可见敌人行动"
	follow.button_pressed = bool(settings.follow)
	follow.toggled.connect(func(value: bool): setting("follow",value))
	column.add_child(follow)
	var speed := CheckButton.new()
	speed.text = "敌方动作快速播放"
	speed.button_pressed = float(settings.enemy_speed)>1
	speed.toggled.connect(func(value: bool): setting("enemy_speed",2.0 if value else 1.0))
	column.add_child(speed)
	var back := Button.new()
	back.text = "返回 [Esc]"
	back.custom_minimum_size.y = 40
	back.pressed.connect(close_options)
	column.add_child(back)
	content.hide()
	layout.call_deferred()

func setting(key: String,value: Variant) -> void:
	settings[key]=value
	var error: Error = SETTINGS.write_settings(settings,settings_path)
	if error!=OK: status.text="设置无法保存："+error_string(error)

func close_options() -> void:
	if is_instance_valid(options_panel): options_panel.queue_free()
	options_panel=null
	content.show()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and is_instance_valid(options_panel):
		close_options()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_target = (event.position/size*2-Vector2.ONE).clamp(-Vector2.ONE,Vector2.ONE)

func start(scene: String) -> void:
	if not loading.is_empty(): return
	loading = scene
	for b in buttons: b.disabled = true
	status.text = "正在载入地图… 首次载入可能需要片刻。"
	var error := ResourceLoader.load_threaded_request(scene)
	if error != OK:
		loading = ""
		status.text = "地图载入失败：%s" % error_string(error)
		for b in buttons: b.disabled = false
		buttons[0].disabled = not can_resume

func _process(delta: float) -> void:
	pointer = pointer.lerp(pointer_target,1-exp(-delta*10))
	layout_art()
	if changing: return
	if loading.is_empty(): return
	var progress: Array = []
	var state := ResourceLoader.load_threaded_get_status(loading, progress)
	if state == ResourceLoader.THREAD_LOAD_LOADED:
		var scene: PackedScene = ResourceLoader.load_threaded_get(loading)
		changing = true
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		var fade := create_tween()
		fade.tween_property(overlay,"modulate:a",1.0,.18)
		await fade.finished
		get_tree().change_scene_to_packed(scene)
		loading = ""
	elif state == ResourceLoader.THREAD_LOAD_FAILED:
		status.text = "载入失败，请检查导入日志。银行关文件仍保留。"
		loading = ""
		for b in buttons: b.disabled = false
		buttons[0].disabled = not can_resume
	elif not progress.is_empty(): status.text = "正在载入地图… %d%%" % int(float(progress[0]) * 100)
