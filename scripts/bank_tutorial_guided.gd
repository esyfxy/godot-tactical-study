extends Control

# Source-guided Bank tutorial. The 49 prompts, targets, actor indices and grid
# come from the exported Unity Bank scene; action simulation is still partial.
const GRID_W := 60
const GRID_H := 40
const NAV = preload("res://scripts/bank_navigation.gd")
# EmployeeDatabase.asset: COP0001/2/3 Speed = 1/0/1; Cop.MaxMoveDistance = 5 + Speed.
const COP_MAX_MOVE := [6, 5, 6]
const ACTION_NAMES := {
	-1: "移动", 1: "警棍", 3: "泰瑟枪", 5: "逮捕", 10: "射击",
	11: "装填",14: "喝止", 33: "互动", 35: "急救包", 38: "打开", 55: "解救",60:"侦察房间"
}
# Bank.unity tutorial interaction targets map to DoorData/WindowData EdgeIndex.
const OPENING_EDGES_BY_STEP := {6: 2921, 8: 1721, 23: 2455, 25: 1735,
	34: 2343, 35: 1863, 38: 2943}
const ACTION_SOUNDS := {
	-1: preload("res://assets/bank/audio/assetbundles_sounds_tactics_TacticsChooseDestination.wav"),
	1: preload("res://assets/bank/audio/assetbundles_sounds_tactics_TacticsBaton.wav"),
	3: preload("res://assets/bank/audio/assetbundles_sounds_tactics_TacticsTaser.wav"),
	5: preload("res://assets/bank/audio/assetbundles_sounds_tactics_TacticsHandcuffs.wav"),
	10: preload("res://assets/bank/audio/assetbundles_sounds_tactics_gunshots_TacticsGunshot.wav")
}
const WINDOW_SOUND: AudioStream = preload("res://assets/bank/audio/assetbundles_sounds_tactics_TacticsOpenWindow.wav")
const ALARM_SOUND: AudioStream = preload("res://assets/bank/audio/assetbundles_sounds_tactics_TacticsAlarmed.wav")
const VICTORY_SOUND: AudioStream = preload("res://assets/bank/audio/assetbundles_sounds_tactics_TacticsVictory.ogg")
const PORTRAITS = preload("res://scripts/cop_portraits.gd")
const TACTICS_UI_ATLAS: Texture2D = preload("res://assets/bank/ui/tactics_ui_original.png")
const TACTICS_ACTION_ATLAS: Texture2D = preload("res://assets/bank/ui/tactics_actions_original.png")
const CARD_NAMES := ["什韦茨", "利维", "阿勒代斯", "布恩"]
# Four distinct male portraits from the user's ten-person sheet. Character
# names/gameplay remain unchanged; the other six are used by Horde recruits.
const CARD_PORTRAITS := [1, 3, 4, 8]

var source_data: Dictionary = {}
var cells: Dictionary = {}
var grid_edges: Array = []
var steps: Array = []
var locale: Dictionary = {}
var cops: Array[Dictionary] = []
var guards: Array[Dictionary] = []
var hostages: Array[Dictionary] = []
var opened: Dictionary = {}
var opened_edges: Dictionary = {}
var selected_cop := 0
var step_index := 0
var turn_number := 1
var finished := false
var shootout_occurred := false
var camera_origin := Vector2i(8, 11)
var zoomed_out := false
var notice := ""

var world_container: SubViewportContainer
var world_viewport: SubViewport
var bank_world: BankWorld3D
var sidebar: PanelContainer
var objective_panel: PanelContainer
var objective_label: Label
var title_overlay: ColorRect
var top_hud: ColorRect
var bottom_hud: ColorRect
var turn_button: Button
var restart_button: Button
var cop_cards: Array[Button] = []
var card_portraits: Array[TextureRect] = []
var card_labels: Array[Label] = []
var title_label: Label
var status_label: Label
var lesson_label: Label
var cop_label: Label
var notice_label: Label
var action_button: Button
var ammo_label: Label
var bottom_decorations: Array[TextureRect] = []
var lesson_player: AudioStreamPlayer
var action_player: AudioStreamPlayer

func _ready() -> void:
	_load_source()
	_build_ui()
	_reset_mission()
	resized.connect(_layout_ui)
	_layout_ui()

func _load_source() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/bank/tutorial_data.json"))
	assert(parsed is Dictionary, "Bank tutorial source data is missing")
	source_data = parsed
	steps = source_data["actions"]
	locale = source_data["zh_cn_text"]
	for cell in source_data["grid_cells"]:
		cells[Vector2i(int(cell["PositionX"]), int(cell["PositionY"]))] = cell
	grid_edges = source_data["grid_edges"]
	assert(steps.size() == 49 and cells.size() == GRID_W * GRID_H and grid_edges.size() == GRID_W * GRID_H * 2, "Bank source data is incomplete")

func _reset_mission() -> void:
	cops.clear()
	for source_cop in source_data["start_cops"]:
		var slot := int(source_cop["SlotIndex"])
		cops.append({"name": "警员 %d" % (int(source_cop["SlotIndex"]) + 1),
			"pos": Vector2i(int(source_cop["X"]), int(source_cop["Y"])), "ap": 2, "hp": 3, "ammo": 9,
			"max_move": COP_MAX_MOVE[slot]})
	guards.clear()
	hostages.clear()
	for cell in source_data["grid_cells"]:
		var tile := Vector2i(int(cell["PositionX"]), int(cell["PositionY"]))
		if int(cell["Content"]) == 2:
			guards.append({"pos": tile, "state": "巡逻"})
	for source_hostage in source_data["start_hostages"]:
		hostages.append({"pos": Vector2i(int(source_hostage["X"]), int(source_hostage["Y"])),
			"state": "等待救援", "prefab": str(source_hostage["PrefabName"]),
			"animation": str(source_hostage["Animation"])})
	opened.clear()
	opened_edges.clear()
	selected_cop = 0
	step_index = 0
	turn_number = 1
	finished = false
	shootout_occurred = false
	zoomed_out = false
	bank_world.reset_cop_motion()
	bank_world.reset_guard_visuals()
	bank_world.set_zoomed_out(false)
	notice = "已载入原版银行关 49 条教学动作与 60×40 格子。点击高亮目标。"
	sidebar.visible = false
	title_overlay.visible = true
	_focus_step()
	_update_ui()

func _build_ui() -> void:
	world_container = SubViewportContainer.new()
	world_container.stretch = false
	world_container.mouse_filter = Control.MOUSE_FILTER_STOP
	world_container.gui_input.connect(_on_world_input)
	add_child(world_container)
	world_viewport = SubViewport.new()
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.size = Vector2i(900, 600)
	world_container.add_child(world_viewport)
	bank_world = BankWorld3D.new()
	world_viewport.add_child(bank_world)

	top_hud = ColorRect.new()
	top_hud.color = Color(0.06, 0.05, 0.055, 0.88)
	top_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_hud)
	var top_line := ColorRect.new()
	top_line.name = "GoldLine"
	top_line.color = Color("#d5b94e")
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_hud.add_child(top_line)
	title_label = Label.new()
	title_label.text = "REBEL COPS  /  银行教学关"
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", Color("#e9d58e"))
	top_hud.add_child(title_label)
	restart_button = Button.new()
	restart_button.text = ""
	restart_button.tooltip_text = "重置教学关；F1 显示或隐藏教学提示"
	restart_button.add_theme_font_size_override("font_size", 31)
	restart_button.add_theme_color_override("font_color", Color("#211e17"))
	restart_button.add_theme_stylebox_override("normal", _hud_style(Color("#f1cd3b")))
	restart_button.add_theme_stylebox_override("hover", _hud_style(Color("#ffe276")))
	restart_button.pressed.connect(_reset_mission)
	top_hud.add_child(restart_button)
	var options_icon := TextureRect.new()
	var options_crop := AtlasTexture.new()
	options_crop.atlas = TACTICS_UI_ATLAS
	options_crop.region = Rect2(2117, 1785, 81, 72)
	options_icon.texture = options_crop
	options_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	options_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	options_icon.modulate = Color("#17130d")
	options_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	options_icon.position = Vector2(10, 14)
	options_icon.size = Vector2(48, 48)
	restart_button.add_child(options_icon)
	for card_index in range(4):
		var card := Button.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.clip_contents = true
		top_hud.add_child(card)
		cop_cards.append(card)
		var portrait := TextureRect.new()
		portrait.texture = PORTRAITS.texture(CARD_PORTRAITS[card_index])
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(portrait)
		card_portraits.append(portrait)
		var name_bar := ColorRect.new()
		name_bar.color = Color(0.09, 0.075, 0.06, 0.92)
		name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_bar.position = Vector2(0, 86)
		name_bar.size = Vector2(104, 22)
		card.add_child(name_bar)
		var name_label := Label.new()
		name_label.text = CARD_NAMES[card_index]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_bar.add_child(name_label)
		card_labels.append(name_label)
	turn_button = Button.new()
	turn_button.text = "结束回合  [Enter]"
	turn_button.add_theme_font_size_override("font_size", 22)
	turn_button.add_theme_color_override("font_color", Color("#1c1b15"))
	turn_button.add_theme_stylebox_override("normal", _hud_style(Color("#f1cd3b")))
	turn_button.add_theme_stylebox_override("hover", _hud_style(Color("#ffe276")))
	turn_button.pressed.connect(_end_turn)
	top_hud.add_child(turn_button)

	bottom_hud = ColorRect.new()
	bottom_hud.color = Color(0.06, 0.05, 0.055, 0.92)
	bottom_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_hud)
	var bottom_line := ColorRect.new()
	bottom_line.name = "GoldLine"
	bottom_line.color = Color("#d5b94e")
	bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_hud.add_child(bottom_line)
	ammo_label = Label.new()
	ammo_label.add_theme_font_size_override("font_size", 26)
	ammo_label.add_theme_color_override("font_color", Color.WHITE)
	bottom_hud.add_child(ammo_label)
	bottom_decorations.append(_atlas_icon(TACTICS_ACTION_ATLAS, Rect2(1320, 1528, 256, 256), Color.WHITE)) # Glock
	bottom_decorations.append(_atlas_icon(TACTICS_ACTION_ATLAS, Rect2(1848, 1528, 256, 256), Color("#70631e"))) # Tools
	bottom_decorations.append(_atlas_icon(TACTICS_UI_ATLAS, Rect2(2206, 1771, 66, 86), Color("#d4b83d"))) # Briefing
	bottom_decorations.append(_atlas_icon(TACTICS_UI_ATLAS, Rect2(1899, 892, 124, 140), Color("#74651e"))) # Death
	bottom_decorations.append(_atlas_icon(TACTICS_ACTION_ATLAS, Rect2(264, 1000, 256, 256), Color("#70631e"))) # Perks
	action_button = Button.new()
	action_button.add_theme_font_size_override("font_size", 18)
	action_button.add_theme_color_override("font_color", Color("#e9d58e"))
	action_button.add_theme_stylebox_override("normal", _hud_style(Color("#171513")))
	action_button.add_theme_stylebox_override("hover", _hud_style(Color("#363025")))
	action_button.pressed.connect(_action_button_pressed)
	bottom_hud.add_child(action_button)

	sidebar = PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.07, 0.075, 0.84)
	panel_style.border_color = Color("#a28b4a")
	panel_style.set_border_width_all(1)
	sidebar.add_theme_stylebox_override("panel", panel_style)
	add_child(sidebar)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	sidebar.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "教学目标"
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color("#e4bd75"))
	column.add_child(heading)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("#d1c7ab"))
	column.add_child(status_label)
	column.add_child(HSeparator.new())
	lesson_label = Label.new()
	lesson_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lesson_label.custom_minimum_size.y = 145
	lesson_label.add_theme_font_size_override("font_size", 16)
	lesson_label.add_theme_color_override("font_color", Color("#ecdfc7"))
	column.add_child(lesson_label)
	cop_label = Label.new()
	cop_label.add_theme_color_override("font_color", Color("#e9d58e"))
	column.add_child(cop_label)
	notice_label = Label.new()
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size.y = 55
	notice_label.add_theme_color_override("font_color", Color("#a7d7df"))
	column.add_child(notice_label)
	var controls := Label.new()
	controls.text = "WASD / 方向键平移；鼠标中键切换总览。\n自由操作版：1–3 选人，右键取消菜单。战斗、开锁和敌方 AI 尚未完整还原。"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_font_size_override("font_size", 13)
	controls.add_theme_color_override("font_color", Color("#90a3ac"))
	column.add_child(controls)
	objective_panel = PanelContainer.new()
	objective_panel.add_theme_stylebox_override("panel", _hud_style(Color(0.06, 0.055, 0.055, 0.91)))
	add_child(objective_panel)
	var objective_margin := MarginContainer.new()
	objective_margin.add_theme_constant_override("margin_left", 14)
	objective_margin.add_theme_constant_override("margin_right", 14)
	objective_margin.add_theme_constant_override("margin_top", 10)
	objective_margin.add_theme_constant_override("margin_bottom", 10)
	objective_panel.add_child(objective_margin)
	objective_label = Label.new()
	objective_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	objective_label.custom_minimum_size = Vector2(360, 84)
	objective_label.add_theme_font_size_override("font_size", 16)
	objective_label.add_theme_color_override("font_color", Color("#f2e3bd"))
	objective_margin.add_child(objective_label)
	title_overlay = ColorRect.new()
	title_overlay.color = Color(0.035, 0.032, 0.035, 0.89)
	title_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(title_overlay)
	var logo := TextureRect.new()
	logo.name = "OriginalLogo"
	var logo_image := Image.new()
	var logo_bytes := FileAccess.get_file_as_bytes("res://assets/bank/ui/rebel_cops_logo_original.png")
	assert(logo_image.load_png_from_buffer(logo_bytes) == OK)
	logo.texture = ImageTexture.create_from_image(logo_image)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_overlay.add_child(logo)
	var intro := Label.new()
	intro.name = "Intro"
	intro.text = "银行教学关  ·  学习复刻版\n跟随左侧目标，点击地图上的金色格子；行动力耗尽时按 Enter 结束回合。\nF1 查看原版教学文字，WASD 平移镜头，中键切换总览。"
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 19)
	intro.add_theme_color_override("font_color", Color("#f3e7cd"))
	title_overlay.add_child(intro)
	var start_button := Button.new()
	start_button.name = "StartButton"
	start_button.text = "开始教学  [Enter]"
	start_button.add_theme_font_size_override("font_size", 23)
	start_button.add_theme_color_override("font_color", Color("#1c1b15"))
	start_button.add_theme_stylebox_override("normal", _hud_style(Color("#f1cd3b")))
	start_button.add_theme_stylebox_override("hover", _hud_style(Color("#ffe276")))
	start_button.pressed.connect(_start_tutorial)
	title_overlay.add_child(start_button)
	lesson_player = AudioStreamPlayer.new()
	lesson_player.stream = preload("res://assets/samples/tutorial_slide.wav")
	add_child(lesson_player)
	action_player = AudioStreamPlayer.new()
	add_child(action_player)

func _hud_style(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color("#ccb44d")
	style.set_border_width_all(1)
	return style

func _atlas_icon(atlas: Texture2D, region: Rect2, tint: Color) -> TextureRect:
	var crop := AtlasTexture.new()
	crop.atlas = atlas
	crop.region = region
	var icon := TextureRect.new()
	icon.texture = crop
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = tint
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_hud.add_child(icon)
	return icon

func _layout_ui() -> void:
	if sidebar == null:
		return
	world_container.position = Vector2.ZERO
	world_container.size = size
	world_viewport.size = Vector2i(maxi(640, roundi(size.x)), maxi(360, roundi(size.y)))
	top_hud.position = Vector2.ZERO
	top_hud.size = Vector2(size.x, 44)
	top_hud.get_node("GoldLine").position = Vector2(0, 42)
	top_hud.get_node("GoldLine").size = Vector2(size.x, 2)
	restart_button.position = Vector2(28, 0)
	restart_button.size = Vector2(68, 84)
	title_label.position = Vector2(115, 10)
	title_label.size = Vector2(260, 28)
	var card_width := 104.0
	var card_gap := 26.0
	var cards_left := size.x * 0.5 - 304.0
	for i in range(4):
		cop_cards[i].position = Vector2(cards_left + i * (card_width + card_gap), 0)
		cop_cards[i].size = Vector2(card_width, 108)
		card_portraits[i].position = Vector2.ZERO
		card_portraits[i].size = Vector2(card_width, 100)
		card_labels[i].position = Vector2(0, 1)
		card_labels[i].size = Vector2(card_width, 20)
	turn_button.position = Vector2(size.x - 292, 0)
	turn_button.size = Vector2(265, 74)
	bottom_hud.position = Vector2(0, size.y - 76)
	bottom_hud.size = Vector2(size.x, 76)
	bottom_hud.get_node("GoldLine").position = Vector2.ZERO
	bottom_hud.get_node("GoldLine").size = Vector2(size.x, 2)
	ammo_label.position = Vector2(27, 23)
	ammo_label.size = Vector2(35, 35)
	bottom_decorations[0].position = Vector2(67, 15)
	bottom_decorations[0].size = Vector2(50, 50)
	var positions := [Vector2(370, 14), Vector2(447, 10), Vector2(516, 16), Vector2(582, 16)]
	var sizes := [Vector2(47, 47), Vector2(46, 55), Vector2(46, 47), Vector2(47, 47)]
	for i in range(4):
		bottom_decorations[i + 1].position = positions[i]
		bottom_decorations[i + 1].size = sizes[i]
		bottom_decorations[i + 1].visible = size.x >= 1500
	action_button.position = Vector2(size.x * 0.5 - 185, 13)
	action_button.size = Vector2(370, 51)
	sidebar.position = Vector2(24, 112)
	sidebar.size = Vector2(380, minf(430, size.y - 210))
	objective_panel.position = Vector2(24, 112)
	objective_panel.size = Vector2(390, 122)
	objective_panel.visible = not sidebar.visible
	title_overlay.position = Vector2.ZERO
	title_overlay.size = size
	var logo := title_overlay.get_node("OriginalLogo") as TextureRect
	logo.position = Vector2(size.x * 0.5 - 235, size.y * 0.5 - 290)
	logo.size = Vector2(470, 340)
	var intro := title_overlay.get_node("Intro") as Label
	intro.position = Vector2(size.x * 0.5 - 390, size.y * 0.5 + 48)
	intro.size = Vector2(780, 110)
	var start_button := title_overlay.get_node("StartButton") as Button
	start_button.position = Vector2(size.x * 0.5 - 150, size.y * 0.5 + 171)
	start_button.size = Vector2(300, 64)
	_sync_world()

func _start_tutorial() -> void:
	title_overlay.hide()
	_focus_step()
	_update_ui()

func _current_step() -> Dictionary:
	return steps[step_index] if step_index < steps.size() else {}

func _step_tile() -> Vector2i:
	var step := _current_step()
	return Vector2i(int(step["X"]), int(step["Y"]))

func _step_name() -> String:
	var step := _current_step()
	return str(locale.get("TacticsTutorial%d" % int(step["TooltipId"]), "教学动作"))

func _focus_step() -> void:
	if finished:
		return
	var step := _current_step()
	if int(step["CopIndex"]) > 0:
		selected_cop = int(step["CopIndex"]) - 1
	var target := _step_tile()
	camera_origin = Vector2i(clampi(target.x - 14, 0, GRID_W - 1), clampi(target.y - 9, 0, GRID_H - 1))
	_sync_world()

func _on_world_input(event: InputEvent) -> void:
	if title_overlay.visible:
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_origin.y = maxi(0, camera_origin.y - 2)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_origin.y = mini(GRID_H - 1, camera_origin.y + 2)
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		zoomed_out = not zoomed_out
		bank_world.set_zoomed_out(zoomed_out)
		return
	elif event.button_index == MOUSE_BUTTON_LEFT:
		var viewport_pixel: Vector2 = (event as InputEventMouseButton).position * Vector2(world_viewport.size) / world_container.size
		_click_tile(bank_world.pick_tile(viewport_pixel))
		return
	_sync_world()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if title_overlay.visible:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_start_tutorial()
		return
	match event.keycode:
		KEY_F1:
			sidebar.visible = not sidebar.visible
			objective_panel.visible = not sidebar.visible
		KEY_ENTER, KEY_KP_ENTER:
			_end_turn()
		KEY_LEFT, KEY_A:
			camera_origin.x = maxi(0, camera_origin.x - 3)
		KEY_RIGHT, KEY_D:
			camera_origin.x = mini(GRID_W - 1, camera_origin.x + 3)
		KEY_UP, KEY_W:
			camera_origin.y = maxi(0, camera_origin.y - 3)
		KEY_DOWN, KEY_S:
			camera_origin.y = mini(GRID_H - 1, camera_origin.y + 3)
	_sync_world()

func _action_button_pressed() -> void:
	if not finished:
		if int(_current_step()["CopIndex"]) > 0 and int(cops[selected_cop]["ap"]) <= 0:
			_end_turn()
			return
		_show_notice("请点击地图上的金色目标格 (%d, %d) 执行“%s”。" % [_step_tile().x, _step_tile().y, _step_name()])
		_focus_step()

func _click_tile(tile: Vector2i) -> void:
	if finished or not _inside(tile):
		return
	if tile != _step_tile():
		_show_notice("原版教学当前指定目标是 (%d, %d)：%s。" % [_step_tile().x, _step_tile().y, _step_name()])
		return
	var step := _current_step()
	var action_id := int(step["AllowedAction"])
	if action_id == -1 and int(step["CopIndex"]) > 0:
		if not _move_guided(tile):
			return
	else:
		if not _execute_guided_action(tile, action_id):
			return
	_play_action_sound(action_id, int(step["TooltipId"]))
	var completed_name := _step_name()
	var completed_index := step_index
	var force_turn := int(step["ForceEndTurn"]) != 0
	step_index += 1
	if force_turn:
		_end_turn()
	if completed_index == 38:
		_play_scripted_shootout()
	if step_index >= steps.size():
		finished = true
		action_player.stream = VICTORY_SOUND
		action_player.play()
		_show_notice("49 条原版教学目标已走完。动作、演出与战斗规则仍未 1:1。")
	else:
		_focus_step()
		if completed_index == 38:
			_show_notice("敌方脚本交火：警员 1、3 受伤；一名罪犯逃离，一名移至 (37, 19)。下一步：%s。" % _step_name())
		else:
			_show_notice("已完成：%s。下一步：%s。" % [completed_name, _step_name()])
		lesson_player.play()
	_update_ui()

func _move_guided(tile: Vector2i) -> bool:
	var cop: Dictionary = cops[selected_cop]
	if cop["pos"] == tile:
		return true
	if int(cop["ap"]) <= 0:
		_show_notice("警员 %d 的行动力已用尽。点击顶部或底部黄色“结束回合”，也可按 Enter。" % (selected_cop + 1))
		return false
	var start: Vector2i = cop["pos"]
	var range_world := float(int(cop["ap"]) * int(cop["max_move"])) * 1.4
	var search_result := NAV.search(start, range_world, cells, grid_edges, opened_edges, _blocked_for_move())
	var destination := tile
	var distance := float(search_result["costs"].get(tile, -1.0))
	if distance < 0.0:
		# Tutorial prompts can point beyond one turn. Follow the original grid path
		# as far as available AP permits, keeping the same objective for next turn.
		var full_result := NAV.search(start, 150.0, cells, grid_edges, opened_edges, _blocked_for_move())
		var full_path: Array[Vector2i] = NAV.path(start, tile, full_result["parents"])
		if full_path.is_empty():
			_show_notice("路径被墙、未打开的门窗或人员阻挡。")
			return false
		destination = start
		for next_tile in full_path:
			if not search_result["costs"].has(next_tile):
				break
			if float(full_result["costs"][next_tile]) > range_world + 0.001:
				break
			destination = next_tile
		if destination == start:
			_show_notice("剩余行动力不足以走到下一个可停留格，请结束回合。")
			return false
		distance = float(search_result["costs"][destination])
	var cost := 1 if distance <= float(int(cop["max_move"])) * 1.4 + 0.001 else 2
	if int(cop["ap"]) < cost:
		_show_notice("行动力不足，请按 Enter 结束回合。")
		return false
	cop["pos"] = destination
	cop["ap"] = int(cop["ap"]) - cost
	# The original plays this on destination confirmation, then separate footstep samples.
	action_player.stream = ACTION_SOUNDS[-1]
	action_player.volume_db = -14.0
	action_player.play()
	if destination != tile:
		_show_notice("沿原版路径前进至 (%d, %d)；目标尚未到达，结束回合后继续。" % [destination.x, destination.y])
		return false
	return true

func _execute_guided_action(tile: Vector2i, action_id: int) -> bool:
	if int(_current_step()["CopIndex"]) == 0:
		return true # Original sniper-room reveal still needs its own camera/action system.
	var cop: Dictionary = cops[selected_cop]
	if int(cop["ap"]) <= 0:
		_show_notice("行动力不足，请按 Enter 结束回合。")
		return false
	if action_id == 10 and int(cop["ammo"]) <= 0:
		_show_notice("弹药已用尽；装填动作尚未完成。")
		return false
	if action_id == 38:
		opened[tile] = true
		if OPENING_EDGES_BY_STEP.has(step_index):
			opened_edges[OPENING_EDGES_BY_STEP[step_index]] = true
	elif action_id == 1 or action_id == 3 or action_id == 14 or action_id == 5 or action_id == 10:
		var guard := _guard_at(tile)
		if guard < 0 and action_id == 10:
			for i in range(guards.size()):
				if guards[i]["state"] == "巡逻" and absi(guards[i]["pos"].x - tile.x) + absi(guards[i]["pos"].y - tile.y) <= 1:
					guard = i
					break
		if guard < 0:
			_show_notice("目标位置没有可交互的罪犯。")
			return false
		if action_id == 5 and guards[guard]["state"] != "昏迷" and guards[guard]["state"] != "举手":
			_show_notice("先制服或击晕罪犯。")
			return false
		if action_id == 5:
			guards[guard]["state"] = "已逮捕"
		elif action_id == 10:
			guards[guard]["state"] = "倒地"
			cop["ammo"] = int(cop["ammo"]) - 1
		elif action_id == 14:
			guards[guard]["state"] = "举手"
		else:
			guards[guard]["state"] = "昏迷"
	elif action_id == 55:
		for hostage in hostages:
			if hostage["pos"] == tile:
				hostage["state"] = "已获救"
	elif action_id == 35:
		cops[0]["hp"] = 3
	cop["ap"] = int(cop["ap"]) - 1
	return true

func _guard_at(tile: Vector2i) -> int:
	for i in range(guards.size()):
		if guards[i]["pos"] == tile and guards[i]["state"] != "已逮捕" and guards[i]["state"] != "逃离":
			return i
	return -1

func _play_scripted_shootout() -> void:
	# BankMission.cs: PlayEnemyShootOut(), triggered at tutorial index 38.
	shootout_occurred = true
	for guard in guards:
		if guard["pos"] == Vector2i(33, 24):
			guard["pos"] = Vector2i(44, 24)
			guard["state"] = "逃离"
		elif guard["pos"] == Vector2i(38, 19):
			guard["pos"] = Vector2i(37, 19)
	cops[0]["hp"] = maxi(1, int(cops[0]["hp"]) - 1)
	cops[2]["hp"] = maxi(1, int(cops[2]["hp"]) - 1)
	turn_number += 1
	for cop in cops:
		cop["ap"] = 2
	action_player.stream = ALARM_SOUND
	action_player.play()

func _play_action_sound(action_id: int, tooltip_id: int) -> void:
	if action_id == -1:
		return # Movement confirmation already plays when the route starts.
	var stream: AudioStream = ACTION_SOUNDS.get(action_id) as AudioStream
	if action_id == 38 and tooltip_id in [9, 33, 34]:
		stream = WINDOW_SOUND
	if stream != null:
		action_player.stream = stream
		action_player.volume_db = 0.0
		action_player.play()

func _blocked_for_move() -> Dictionary:
	var blocked: Dictionary = {}
	for guard in guards:
		if guard["state"] != "已逮捕" and guard["state"] != "逃离":
			blocked[guard["pos"]] = true
	return blocked

func _inside(tile: Vector2i) -> bool:
	return NAV.inside(tile)

func _edge_index_between(a: Vector2i, b: Vector2i) -> int:
	return NAV.edge_index(a, b)

func _edge_passable(a: Vector2i, b: Vector2i) -> bool:
	return NAV.can_cross(a, b, cells, grid_edges, opened_edges)

func _end_turn() -> void:
	if finished:
		return
	turn_number += 1
	for cop in cops:
		cop["ap"] = 2 if int(cop["hp"]) > 0 else 0
	_show_notice("第 %d 回合。行动力已恢复；原版敌方回合逻辑尚未接入。" % turn_number)
	_update_ui()

func _show_notice(message: String) -> void:
	notice = message
	_update_ui()

func _update_ui() -> void:
	if status_label == null:
		return
	var arrested := 0
	for guard in guards:
		if guard["state"] == "已逮捕":
			arrested += 1
	status_label.text = "回合 %d   ·   原版教学 %d/49\n罪犯 %d/%d 已逮捕" % [turn_number, mini(step_index + 1, steps.size()), arrested, guards.size()]
	if finished:
		lesson_label.text = "已走完 49 个教学目标。\n\n当前仍是源数据引导原型，不是原版完整复刻。"
		objective_label.text = "银行教学关  ·  已完成 49 / 49\n当前是学习复刻版，尚未达到原版 1:1。"
		action_button.disabled = true
	else:
		var step := _current_step()
		var key := "TacticsTutorial%d" % int(step["TooltipId"])
		var description := str(locale.get(key + "Description", ""))
		lesson_label.text = "%02d / 49  %s\n\n%s\n\n目标格 (%d, %d)" % [step_index + 1, _step_name(), description, int(step["X"]), int(step["Y"])]
		var actor := "狙击手" if int(step["CopIndex"]) == 0 else "警员 %d" % int(step["CopIndex"])
		var verb := str(ACTION_NAMES.get(int(step["AllowedAction"]), "执行"))
		var instruction := "点击金色目标格，执行“%s”。" % verb
		if int(step["AllowedAction"]) == -1:
			instruction = "点击金色格，%s沿白色路径前进。" % actor
		if int(step["CopIndex"]) > 0 and int(cops[selected_cop]["ap"]) == 0:
			instruction = "行动力用尽：点下方黄色按钮换回合。"
		objective_label.text = "教学 %02d/49 · %s：%s\n%s\nF1 详细说明 · 回合 %d" % [step_index + 1, actor, _step_name(), instruction, turn_number]
		if int(step["CopIndex"]) > 0 and int(cops[selected_cop]["ap"]) == 0:
			action_button.text = "行动力已用尽 → 点这里结束回合  [Enter]"
			action_button.add_theme_stylebox_override("normal", _hud_style(Color("#f1cd3b")))
			action_button.add_theme_stylebox_override("hover", _hud_style(Color("#ffe276")))
			action_button.add_theme_color_override("font_color", Color("#1c1b15"))
		else:
			action_button.text = "%s：点击地图高亮目标" % ACTION_NAMES.get(int(step["AllowedAction"]), "执行")
			action_button.add_theme_stylebox_override("normal", _hud_style(Color("#171513")))
			action_button.add_theme_stylebox_override("hover", _hud_style(Color("#363025")))
			action_button.add_theme_color_override("font_color", Color("#e9d58e"))
		action_button.disabled = false
	var cop: Dictionary = cops[selected_cop]
	cop_label.text = "%s   HP %d/3   AP %d/2" % [cop["name"], cop["hp"], cop["ap"]]
	ammo_label.text = str(cop["ammo"])
	var active_card := 0 if not finished and int(_current_step()["CopIndex"]) == 0 else selected_cop + 1
	for i in range(cop_cards.size()):
		var card := cop_cards[i]
		var active := i == active_card
		card_portraits[i].modulate = Color.WHITE if active else Color(0.68, 0.63, 0.55, 0.74)
		card_labels[i].add_theme_color_override("font_color", Color.WHITE if active else Color("#c8bd9c"))
		card.add_theme_stylebox_override("normal", _hud_style(Color("#f1cd3b") if active else Color(0.13, 0.11, 0.10, 0.82)))
	notice_label.text = notice
	_sync_world()

func _sync_world() -> void:
	if bank_world != null and bank_world.is_node_ready() and not cops.is_empty():
		var target := Vector2i(-1, -1) if finished else _step_tile()
		bank_world.sync_source(cops, guards, hostages, opened, opened_edges, cells, grid_edges, selected_cop, target, camera_origin,
			source_data["doors"], source_data["windows"])
