extends Control

# A lightweight, playable interpretation of the Bank mission. Grid coordinates,
# the three-cop limit, and the late guard positions come from the exported game data.
const GRID_W := 50
const GRID_H := 34
const CELL := 34
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const DOORS := [Vector2i(20, 14), Vector2i(20, 24)]
const COVER := [Vector2i(22, 24), Vector2i(23, 24), Vector2i(25, 18), Vector2i(29, 22), Vector2i(34, 26), Vector2i(36, 17), Vector2i(38, 23)]
const LESSONS := [
	"选中警员，点击银行入口附近的格子移动。每名警员每回合有 2 点行动力。",
	"靠近银行左侧的门，点“开门”，再点击门。",
	"进入银行，停在金色掩体旁。掩体能保护警员。",
	"靠近守卫，点“喝止”，再点击守卫。",
	"走到举手守卫旁，点“逮捕”，再点击守卫。",
	"继续控制小队，逮捕剩余两名守卫。"
]

var cops: Array[Dictionary] = []
var guards: Array[Dictionary] = []
var doors_open: Dictionary = {}
var selected_cop := 0
var mode := "移动"
var turn_number := 1
var lesson := 0
var alarm := false
var finished := false
var failed := false
var camera_origin := Vector2i(8, 11)
var notice := ""
var click_sound: AudioStream = preload("res://assets/samples/audio.ogg")
var lesson_sound: AudioStream = preload("res://assets/samples/tutorial_slide.wav")

var board_rect := Rect2()
var world_container: SubViewportContainer
var world_viewport: SubViewport
var bank_world: BankWorld3D
var top_bar: ColorRect
var sidebar: PanelContainer
var lesson_label: Label
var status_label: Label
var cop_label: Label
var notice_label: Label
var title_label: Label
var action_buttons: Dictionary = {}
var sound_player: AudioStreamPlayer
var lesson_player: AudioStreamPlayer

func _ready() -> void:
	_build_ui()
	_reset_mission()
	resized.connect(_layout_ui)
	_layout_ui()

func _reset_mission() -> void:
	cops = [
		{"name": "警员 1", "pos": Vector2i(11, 24), "ap": 2, "hp": 3},
		{"name": "警员 2", "pos": Vector2i(13, 20), "ap": 2, "hp": 3},
		{"name": "警员 3", "pos": Vector2i(15, 16), "ap": 2, "hp": 3}
	]
	guards = [
		{"name": "守卫 A", "pos": Vector2i(33, 24), "state": "巡逻"},
		{"name": "守卫 B", "pos": Vector2i(38, 19), "state": "巡逻"},
		{"name": "守卫 C", "pos": Vector2i(36, 16), "state": "巡逻"}
	]
	doors_open = {}
	selected_cop = 0
	mode = "移动"
	turn_number = 1
	lesson = 0
	alarm = false
	finished = false
	failed = false
	camera_origin = Vector2i(8, 11)
	notice = "银行劫案 · 点击警员或按 1/2/3 选择小队成员。"
	_update_ui()
	queue_redraw()

func _build_ui() -> void:
	world_container = SubViewportContainer.new()
	world_container.stretch = true
	world_container.mouse_filter = Control.MOUSE_FILTER_STOP
	world_container.gui_input.connect(_on_world_input)
	add_child(world_container)
	world_viewport = SubViewport.new()
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.size = Vector2i(900, 600)
	world_container.add_child(world_viewport)
	bank_world = BankWorld3D.new()
	world_viewport.add_child(bank_world)

	top_bar = ColorRect.new()
	top_bar.color = Color("#14202a")
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)

	title_label = Label.new()
	title_label.text = "REBEL COPS   /   银行教学关（开发中）"
	title_label.add_theme_font_size_override("font_size", 25)
	title_label.add_theme_color_override("font_color", Color("#f1e2c1"))
	top_bar.add_child(title_label)

	sidebar = PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#17232d")
	panel_style.border_color = Color("#42515b")
	panel_style.set_border_width_all(1)
	sidebar.add_theme_stylebox_override("panel", panel_style)
	add_child(sidebar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	sidebar.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var mission_title := Label.new()
	mission_title.text = "任务 / 银行劫案"
	mission_title.add_theme_font_size_override("font_size", 21)
	mission_title.add_theme_color_override("font_color", Color("#e4bd75"))
	column.add_child(mission_title)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	column.add_child(status_label)

	var divider := HSeparator.new()
	column.add_child(divider)

	lesson_label = Label.new()
	lesson_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lesson_label.custom_minimum_size.y = 100
	lesson_label.add_theme_font_size_override("font_size", 17)
	lesson_label.add_theme_color_override("font_color", Color("#ecdfc7"))
	column.add_child(lesson_label)

	cop_label = Label.new()
	cop_label.add_theme_font_size_override("font_size", 17)
	column.add_child(cop_label)

	var modes := GridContainer.new()
	modes.columns = 2
	modes.add_theme_constant_override("h_separation", 8)
	modes.add_theme_constant_override("v_separation", 8)
	column.add_child(modes)
	for action_name in ["移动", "开门", "喝止", "逮捕"]:
		var button := Button.new()
		button.text = action_name
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(125, 42)
		button.pressed.connect(_set_mode.bind(action_name))
		modes.add_child(button)
		action_buttons[action_name] = button

	var turn_button := Button.new()
	turn_button.text = "结束回合  [Enter]"
	turn_button.custom_minimum_size.y = 43
	turn_button.pressed.connect(_end_turn)
	column.add_child(turn_button)

	var restart_button := Button.new()
	restart_button.text = "重新开始"
	restart_button.pressed.connect(_reset_mission)
	column.add_child(restart_button)

	var catalog_button := Button.new()
	catalog_button.text = "查看素材目录"
	catalog_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn"))
	column.add_child(catalog_button)

	notice_label = Label.new()
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size.y = 64
	notice_label.add_theme_color_override("font_color", Color("#a7d7df"))
	column.add_child(notice_label)

	var controls := Label.new()
	controls.text = "操作：左键选人/格子；1-3 切换警员\nM 移动  O 开门  F 喝止  R 逮捕\n方向键平移视野；鼠标滚轮上下浏览"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_font_size_override("font_size", 13)
	controls.add_theme_color_override("font_color", Color("#90a3ac"))
	column.add_child(controls)

	sound_player = AudioStreamPlayer.new()
	sound_player.stream = click_sound
	add_child(sound_player)
	lesson_player = AudioStreamPlayer.new()
	lesson_player.stream = lesson_sound
	add_child(lesson_player)

func _layout_ui() -> void:
	if top_bar == null:
		return
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(size.x, 59)
	title_label.position = Vector2(20, 12)
	title_label.size = Vector2(size.x - 40, 42)
	sidebar.position = Vector2(size.x - 318, 72)
	sidebar.size = Vector2(303, size.y - 88)
	board_rect = Rect2(16, 72, maxf(200.0, size.x - 350.0), maxf(200.0, size.y - 88.0))
	world_container.position = board_rect.position
	world_container.size = board_rect.size
	_sync_world()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0e171e"))
	if bank_world != null:
		return
	draw_rect(board_rect, Color("#293033"))
	var cols := ceili(board_rect.size.x / CELL)
	var rows := ceili(board_rect.size.y / CELL)
	for sy in range(rows):
		for sx in range(cols):
			var tile := camera_origin + Vector2i(sx, sy)
			if not _inside(tile):
				continue
			var rect := Rect2(board_rect.position + Vector2(sx * CELL, sy * CELL), Vector2(CELL - 1, CELL - 1))
			if rect.position.x >= board_rect.end.x or rect.position.y >= board_rect.end.y:
				continue
			var color := Color("#626460") if tile.x < 18 else Color("#a29b86")
			if tile.x >= 21 and tile.x <= 42 and tile.y >= 13 and tile.y <= 28:
				color = Color("#796d5d") if (tile.x + tile.y) % 2 == 0 else Color("#817463")
			if tile.x < 18 and tile.x % 8 == 0 and tile.y % 6 == 0:
				color = Color("#74736b")
			draw_rect(rect, color)
			if tile.x < 17 and tile.y % 8 == 0:
				draw_rect(Rect2(rect.position + Vector2(4, 15), Vector2(CELL - 9, 3)), Color("#a7a8a1"))
			if tile.x == 18 and tile.y >= 11 and tile.y <= 29:
				draw_rect(Rect2(rect.position + Vector2(11, 0), Vector2(4, CELL - 1)), Color("#d2cab2"))
			if _is_wall(tile):
				draw_rect(rect, Color("#32383b"))
				draw_rect(Rect2(rect.position, Vector2(CELL - 1, 5)), Color("#536067"))
			if tile in DOORS:
				draw_rect(rect.grow(-4), Color("#57918a") if doors_open.has(tile) else Color("#ba8955"))
			if tile in COVER:
				draw_rect(rect.grow(-5), Color("#a57f54"))
				draw_rect(Rect2(rect.position + Vector2(8, 6), Vector2(CELL - 16, 4)), Color("#d1aa72"))
			if tile == Vector2i(11, 24) or tile == Vector2i(13, 20) or tile == Vector2i(15, 16):
				draw_rect(Rect2(rect.position + Vector2(3, CELL - 6), Vector2(CELL - 6, 3)), Color("#76a4bb"))
	_draw_units()
	_draw_highlight()
	draw_rect(board_rect, Color("#87959c"), false, 2.0)

func _draw_units() -> void:
	var font := ThemeDB.fallback_font
	for i in range(guards.size()):
		var guard: Dictionary = guards[i]
		if guard["state"] == "已逮捕":
			continue
		var point := _screen_pos(guard["pos"])
		if not board_rect.has_point(point):
			continue
		var guard_color := Color("#e6c67b") if guard["state"] == "举手" else Color("#af5147")
		draw_circle(point, 13, guard_color)
		draw_circle(point, 13, Color("#352724"), false, 2.0)
		draw_string(font, point + Vector2(-6, 5), "G%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	for i in range(cops.size()):
		var cop: Dictionary = cops[i]
		var point := _screen_pos(cop["pos"])
		if not board_rect.has_point(point):
			continue
		if i == selected_cop:
			draw_circle(point, 18, Color("#f0d385"))
		draw_circle(point, 13, Color("#5596ab") if cop["hp"] > 0 else Color("#5a6669"))
		draw_string(font, point + Vector2(-6, 5), "C%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		for pip in range(int(cop["ap"])):
			draw_circle(point + Vector2(-5 + pip * 10, 19), 3, Color("#b4e4e6"))

func _draw_highlight() -> void:
	var target := Vector2i(-1, -1)
	if lesson == 0:
		target = Vector2i(17, 24)
	elif lesson == 1:
		target = Vector2i(20, 24)
	elif lesson == 2:
		target = Vector2i(22, 25)
	elif lesson >= 3 and lesson <= 5:
		for guard in guards:
			if guard["state"] != "已逮捕":
				target = guard["pos"]
				break
	if target.x < 0:
		return
	var point := _screen_pos(target)
	if board_rect.has_point(point):
		draw_arc(point, 21, 0, TAU, 32, Color("#f7d688"), 2.5)

func _screen_pos(tile: Vector2i) -> Vector2:
	return board_rect.position + Vector2(tile - camera_origin) * CELL + Vector2(CELL / 2.0, CELL / 2.0)

func _inside(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < GRID_W and tile.y < GRID_H

func _is_wall(tile: Vector2i) -> bool:
	if tile in DOORS:
		return not doors_open.has(tile)
	if tile.y == 12 and tile.x >= 20 and tile.x <= 43:
		return true
	if tile.y == 29 and tile.x >= 20 and tile.x <= 43:
		return true
	if tile.x == 20 and tile.y >= 13 and tile.y <= 28:
		return true
	if tile.x == 43 and tile.y >= 13 and tile.y <= 28:
		return true
	return false

func _occupied(tile: Vector2i, exclude_cop: int = -1) -> bool:
	for i in range(cops.size()):
		if i != exclude_cop and cops[i]["pos"] == tile:
			return true
	for guard in guards:
		if guard["state"] != "已逮捕" and guard["pos"] == tile:
			return true
	return false

func _path_to(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not _inside(goal) or _is_wall(goal) or _occupied(goal, selected_cop):
		return empty
	var queue: Array[Vector2i] = [start]
	var parents: Dictionary = {start: start}
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		if current == goal:
			break
		for direction in DIRECTIONS:
			var next_tile: Vector2i = current + direction
			if not _inside(next_tile) or _is_wall(next_tile) or _occupied(next_tile, selected_cop) or parents.has(next_tile):
				continue
			parents[next_tile] = current
			queue.append(next_tile)
	if not parents.has(goal):
		return empty
	var path: Array[Vector2i] = []
	var cursor := goal
	while cursor != start:
		path.push_front(cursor)
		cursor = parents[cursor]
	return path

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				selected_cop = event.keycode - KEY_1
				_follow_selected()
			KEY_M:
				_set_mode("移动")
			KEY_O:
				_set_mode("开门")
			KEY_F:
				_set_mode("喝止")
			KEY_R:
				_set_mode("逮捕")
			KEY_ENTER, KEY_KP_ENTER:
				_end_turn()
			KEY_LEFT:
				camera_origin.x = maxi(0, camera_origin.x - 3)
			KEY_RIGHT:
				camera_origin.x = mini(GRID_W - 5, camera_origin.x + 3)
			KEY_UP:
				camera_origin.y = maxi(0, camera_origin.y - 3)
			KEY_DOWN:
				camera_origin.y = mini(GRID_H - 5, camera_origin.y + 3)
		_update_ui()
		queue_redraw()

func _on_world_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_origin.y = maxi(0, camera_origin.y - 2)
		_sync_world()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_origin.y = mini(GRID_H - 5, camera_origin.y + 2)
		_sync_world()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_click_tile(bank_world.pick_tile(event.position))

func _click_tile(tile: Vector2i) -> void:
	if finished or failed or not _inside(tile):
		return
	for i in range(cops.size()):
		if cops[i]["pos"] == tile:
			selected_cop = i
			_show_notice("已选择 %s。" % cops[i]["name"])
			return
	match mode:
		"移动": _move_to(tile)
		"开门": _open_door(tile)
		"喝止": _freeze_guard(tile)
		"逮捕": _arrest_guard(tile)

func _move_to(tile: Vector2i) -> void:
	var cop: Dictionary = cops[selected_cop]
	var path := _path_to(cop["pos"], tile)
	if path.is_empty():
		_show_notice("该格子无法到达；先开门，或选择空地。")
		return
	var cost := 1 if path.size() <= 5 else 2
	if path.size() > 10:
		_show_notice("一次最多移动 10 格，请分段前进。")
		return
	if int(cop["ap"]) < cost:
		_show_notice("行动力不足。按 Enter 结束回合。")
		return
	cop["pos"] = tile
	cop["ap"] -= cost
	_play_click()
	_show_notice("%s 移动了 %d 格，消耗 %d 点行动力。" % [cop["name"], path.size(), cost])
	_check_spotted()
	_check_lesson()
	_follow_selected()

func _open_door(tile: Vector2i) -> void:
	if not tile in DOORS or doors_open.has(tile):
		_show_notice("请选择一扇关闭的银行门。")
		return
	if not _can_act(1, tile, 1):
		return
	doors_open[tile] = true
	cops[selected_cop]["ap"] -= 1
	_play_click()
	_show_notice("门已打开。让警员进入银行并利用掩体。")
	_check_lesson()
	queue_redraw()

func _freeze_guard(tile: Vector2i) -> void:
	var index := _guard_at(tile)
	if index < 0 or guards[index]["state"] == "举手":
		_show_notice("请选择一名尚未举手的守卫。")
		return
	if not _can_act(1, tile, 5):
		return
	guards[index]["state"] = "举手"
	cops[selected_cop]["ap"] -= 1
	_play_click()
	_show_notice("%s 已举手；靠近后进行逮捕。" % guards[index]["name"])
	_check_lesson()
	queue_redraw()

func _arrest_guard(tile: Vector2i) -> void:
	var index := _guard_at(tile)
	if index < 0 or guards[index]["state"] != "举手":
		_show_notice("先让守卫举手，才能逮捕。")
		return
	if not _can_act(1, tile, 1):
		return
	guards[index]["state"] = "已逮捕"
	cops[selected_cop]["ap"] -= 1
	_play_click()
	_show_notice("%s 已逮捕。" % guards[index]["name"])
	_check_lesson()
	queue_redraw()

func _guard_at(tile: Vector2i) -> int:
	for i in range(guards.size()):
		if guards[i]["pos"] == tile and guards[i]["state"] != "已逮捕":
			return i
	return -1

func _can_act(cost: int, target: Vector2i, reach: int) -> bool:
	var cop: Dictionary = cops[selected_cop]
	if int(cop["hp"]) <= 0:
		_show_notice("该警员已失去行动能力。")
		return false
	if int(cop["ap"]) < cost:
		_show_notice("行动力不足。按 Enter 结束回合。")
		return false
	var distance: int = absi(cop["pos"].x - target.x) + absi(cop["pos"].y - target.y)
	if distance > reach:
		_show_notice("目标太远；先移动到有效距离。")
		return false
	return true

func _check_spotted() -> void:
	var pos: Vector2i = cops[selected_cop]["pos"]
	for guard in guards:
		if guard["state"] != "巡逻":
			continue
		var distance: int = absi(pos.x - guard["pos"].x) + absi(pos.y - guard["pos"].y)
		if distance <= 3 and not _near_cover(pos):
			alarm = true
			_show_notice("警戒！守卫发现了警员。结束回合后敌人会行动。")
			return

func _near_cover(pos: Vector2i) -> bool:
	for cover_tile in COVER:
		if absi(pos.x - cover_tile.x) + absi(pos.y - cover_tile.y) <= 1:
			return true
	return false

func _check_lesson() -> void:
	var previous_lesson := lesson
	if lesson == 0:
		for cop in cops:
			if cop["pos"].x >= 17:
				lesson = 1
				break
	elif lesson == 1 and not doors_open.is_empty():
		lesson = 2
	elif lesson == 2:
		for cop in cops:
			if cop["pos"].x >= 21 and _near_cover(cop["pos"]):
				lesson = 3
				break
	elif lesson == 3:
		for guard in guards:
			if guard["state"] == "举手":
				lesson = 4
				break
	elif lesson == 4:
		for guard in guards:
			if guard["state"] == "已逮捕":
				lesson = 5
				break
	if lesson == 5:
		var remaining := 0
		for guard in guards:
			if guard["state"] != "已逮捕":
				remaining += 1
		if remaining == 0:
			finished = true
			_show_notice("任务完成：三名守卫已被逮捕，银行安全。")
	if lesson != previous_lesson:
		lesson_player.play()
	_update_ui()
	queue_redraw()

func _end_turn() -> void:
	if finished or failed:
		return
	var enemy_notice := ""
	if alarm:
		_enemy_turn()
		enemy_notice = notice
	for cop in cops:
		cop["ap"] = 2 if cop["hp"] > 0 else 0
	turn_number += 1
	if not failed:
		_show_notice("第 %d 回合，行动力已恢复。%s" % [turn_number, enemy_notice])
	_update_ui()
	queue_redraw()

func _enemy_turn() -> void:
	var active_guard: Dictionary = {}
	for guard in guards:
		if guard["state"] == "巡逻":
			active_guard = guard
			break
	if active_guard.is_empty():
		return
	var nearest := -1
	var nearest_distance := 999
	for i in range(cops.size()):
		if cops[i]["hp"] <= 0:
			continue
		var distance: int = absi(cops[i]["pos"].x - active_guard["pos"].x) + absi(cops[i]["pos"].y - active_guard["pos"].y)
		if distance < nearest_distance:
			nearest = i
			nearest_distance = distance
	if nearest < 0:
		failed = true
		_show_notice("任务失败：小队失去行动能力。点击“重新开始”再试。")
		return
	if nearest_distance <= 4 and not _near_cover(cops[nearest]["pos"]):
		cops[nearest]["hp"] -= 1
		_show_notice("%s 开火！%s 受伤。" % [active_guard["name"], cops[nearest]["name"]])
		if cops[nearest]["hp"] <= 0:
			_show_notice("%s 失去行动能力；可以继续指挥其他警员。" % cops[nearest]["name"])
	else:
		_show_notice("守卫正在搜索小队；利用掩体靠近。")
	var able := 0
	for cop in cops:
		if cop["hp"] > 0:
			able += 1
	if able == 0:
		failed = true
		_show_notice("任务失败：所有警员失去行动能力。点击“重新开始”再试。")

func _set_mode(new_mode: String) -> void:
	mode = new_mode
	_show_notice("已选择“%s”。点击地图上的目标。" % mode)
	_update_ui()
	queue_redraw()

func _follow_selected() -> void:
	var pos: Vector2i = cops[selected_cop]["pos"]
	var visible_cols := maxi(8, floori(board_rect.size.x / CELL))
	var visible_rows := maxi(8, floori(board_rect.size.y / CELL))
	if pos.x < camera_origin.x + 3 or pos.x > camera_origin.x + visible_cols - 4:
		camera_origin.x = clampi(pos.x - visible_cols / 2, 0, GRID_W - visible_cols)
	if pos.y < camera_origin.y + 3 or pos.y > camera_origin.y + visible_rows - 4:
		camera_origin.y = clampi(pos.y - visible_rows / 2, 0, GRID_H - visible_rows)
	_update_ui()
	queue_redraw()

func _show_notice(message: String) -> void:
	notice = message
	_update_ui()

func _play_click() -> void:
	sound_player.play()

func _update_ui() -> void:
	if status_label == null:
		return
	var arrested := 0
	for guard in guards:
		if guard["state"] == "已逮捕":
			arrested += 1
	status_label.text = "回合 %d   ·   守卫 %d/3 已逮捕\n警戒：%s" % [turn_number, arrested, "已触发" if alarm else "未触发"]
	if failed:
		lesson_label.text = "任务失败。点击“重新开始”重试。"
	elif finished:
		lesson_label.text = "任务完成！三名守卫已被逮捕。"
	else:
		lesson_label.text = "教学 %d/6\n%s" % [lesson + 1, LESSONS[lesson]]
	if not cops.is_empty():
		var cop: Dictionary = cops[selected_cop]
		cop_label.text = "%s   HP %d/3   AP %d/2\n当前动作：%s" % [cop["name"], cop["hp"], cop["ap"], mode]
	notice_label.text = notice
	for key in action_buttons:
		action_buttons[key].button_pressed = key == mode
	_sync_world()

func _sync_world() -> void:
	if bank_world != null and bank_world.is_node_ready() and not cops.is_empty():
		bank_world.sync(cops, guards, doors_open, selected_cop, lesson, camera_origin)
