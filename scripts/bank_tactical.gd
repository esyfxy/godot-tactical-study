extends "res://scripts/bank_tutorial_guided.gd"

# Free interaction layer. The exported 49 prompts are reference pages, NOT
# an input whitelist or a victory condition. Combat below is a study model,
# not a claim to reproduce the original AI, inventory or hit-probability rules.
var context_panel: PanelContainer
var context_column: VBoxContainer
var feedback: Label
var context_target: Dictionary = {}
var action_busy := false
var mission_generation := 0
var inspected: Dictionary = {}
var reference_page := 0
var was_moving := false
const GUIDANCE = preload("res://scripts/bank_guidance.gd")
var guide_index := 0
var guide_enabled := true
var guide_visited: Dictionary = {}
var recommendation: Dictionary = {}
var guide_controls: HBoxContainer
var guide_marker: Label
var guide_line: MeshInstance3D
const ACTION_WHEEL = preload("res://scripts/bank_action_wheel.gd")
var action_wheel: Control
var completed_actions: Dictionary = {}
var hover_tile := Vector2i(-1, -1)
var preview_label: Label
var notice_age := 0.0
const DIALOG = preload("res://scripts/bank_dialog.gd")
const RIBBON = preload("res://scripts/bank_hud_ribbon.gd")
var dialog: Control
var interaction_data: Dictionary = {}
var note_records: Dictionary = {}
var verified_codes: Dictionary = {}
var pending_password: Dictionary = {}
var card_ribbons: Array[Control] = []
var turn_ribbon: Control
var gear_ribbon: Control
var turn_banner: Label
var turn_banner_tween: Tween
var inventory_label: Label
const COMPLETION=preload("res://scripts/bank_completion.gd")
var room_data: Dictionary={}
var scouted_rooms: Dictionary={}
var healed_cops: Dictionary={}
var sniper_active:=false
var sniper_cooldown:=0
var closing_check:=false

func _load_source() -> void:
	super._load_source()
	interaction_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/bank/interaction_data.json")) as Dictionary
	room_data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/bank/room_data.json"))
	room_data.no_sniper_rooms=room_data.no_sniper_rooms.map(func(id): return int(id))
	for record in interaction_data["notes"]:
		note_records[Vector2i(int(record["x"]), int(record["y"]))] = record

func room_id(tile: Vector2i) -> int:
	# BattleGrid.GetCellIndex is X-major, unlike the tactical edge array.
	return int(room_data.room_ids[tile.x*GRID_H+tile.y]) if _inside(tile) else 0

func note_target(hint: Vector2i) -> Dictionary:
	for tile: Vector2i in note_records:
		if Vector2(tile-hint).length()<=1.45: return {"kind":"note","tile":tile}
	return {"kind":"note","tile":hint}

func _observe_room(tile: Vector2i) -> void:
	var room:=room_id(tile)
	scouted_rooms[room]=true
	sniper_active=false
	sniper_cooldown=3
	var threats:=0
	var civilians:=0
	for e in guards:
		if room_id(e.pos)==room and e.state not in ["倒地","已逮捕","逃离"]: threats+=1
	for h in hostages:
		if room_id(h.pos)==room and h.state!="已获救": civilians+=1
	camera_origin=tile-Vector2i(14,9)
	bank_world.show_room_scout(room_data.room_ids,room)
	dialog.present("scout","什韦茨 · 房间侦察","房间 %d 已观察：罪犯 %d，人质 %d。\n警员行动点未消耗；狙击侦察冷却 3 回合。\n关闭报告后继续行动。"%[room,threats,civilians],"收到，继续")
	_sync_world()

func _check_completion() -> void:
	if finished or closing_check or _busy() or title_overlay.visible: return
	if not guards.all(func(e): return e.state in ["倒地","已逮捕","逃离"]) or not hostages.all(func(h): return h.state=="已获救"): return
	closing_check=true
	finished=true
	_close_menu()
	action_player.stream=VICTORY_SOUND;action_player.play()
	dialog.present("victory","银行行动完成","全部威胁已解除，全部人质已解救。\n行动回合：%d\n\n任务完成，可重新挑战或返回模式选择。"%turn_number,"返回模式选择")
	dialog.add_choice("重新开始银行教学关","replay_bank")
	closing_check=false

func _dialog_open() -> bool:
	return dialog != null and dialog.visible

func _show_pause_menu() -> void:
	if _busy():
		_show_notice("请等当前动作结束后再打开菜单。")
		return
	_close_menu()
	var inventory := ""
	for i in range(cops.size()): inventory += "%s：手枪 %d/9 发 · 急救包 ×%d · 撬锁工具 ×%d\n" % [CARD_NAMES[i + 1], int(cops[i].ammo), int(cops[i].get("medkits", 0)), int(cops[i].get("lockpicks", 0))]
	dialog.present("pause", "银行 · 游戏菜单", "回合 %d\n\n%s\n可重读已收集的纸条；重开关卡会清除本局进度。" % [turn_number, inventory], "重新开始关卡…")
	dialog.add_choice("返回模式选择…", "mode_menu")
	for tile in note_records:
		if inspected.has(tile): dialog.add_choice("阅读纸条：" + str(note_records[tile]["title"]), "note:" + str(note_records[tile]["id"]))
	_sync_world()

func _dialog_confirm(value: String) -> void:
	if value=="replay_bank": dialog.hide();_reset_mission();_start_tutorial();return
	if dialog.mode=="victory": get_tree().change_scene_to_file("res://scenes/mode_menu.tscn");return
	if value == "mode_menu":
		dialog.present("mode_menu_confirm", "返回模式选择？", "当前银行关进度将清除；可选择银行或义军呐喊重新开始。", "返回模式选择")
		dialog.cancel.show()
		return
	if dialog.mode == "mode_menu_confirm":
		get_tree().change_scene_to_file("res://scenes/mode_menu.tscn")
		return
	if value.begins_with("note:"):
		for record in note_records.values():
			if str(record["id"]) == value.substr(5):
				dialog.present("note", "纸条 · " + str(record["title"]), str(record["text"]), "返回游戏")
		return
	if dialog.mode == "pause":
		dialog.present("restart", "重新开始银行关？", "本局行动、纸条和物品收集都会重置。原始游戏文件不会受到影响。", "确认重新开始")
		return
	if dialog.mode == "restart":
		dialog.hide()
		_reset_mission()
		_start_tutorial()
		return
	if dialog.mode == "password":
		var target: Dictionary = pending_password.duplicate()
		var expected := str(interaction_data["doors"][str(target["edge"])]["password"])
		if value != expected:
			dialog.body.text = "密码不正确。未消耗行动点或物品。\n可在已收集的纸条中查找线索，再输入四位密码。"
			dialog.entry.select_all()
			dialog.entry.grab_focus()
			return
		dialog.hide()
		pending_password.clear()
		verified_codes[target["edge"]] = true
		_perform_action(38, target)
		return
	dialog.close()

func _on_dialog_dismissed() -> void:
	pending_password.clear()
	_update_ui()

func _read_note(tile: Vector2i, actor: int) -> void:
	var record: Dictionary = note_records.get(tile, {})
	if record.is_empty():
		_show_notice("未找到该纸条的原始文本。")
		return
	var reward := ""
	if not inspected.has(tile) and int(record["item"]) == 18:
		cops[actor]["lockpicks"] = int(cops[actor].get("lockpicks", 0)) + 1
		reward = "\n\n获得：撬锁工具 ×1（%s携带）。" % CARD_NAMES[actor + 1]
	inspected[tile] = true
	for step: Dictionary in steps:
		var hint:=Vector2i(int(step.X),int(step.Y))
		if int(step.AllowedAction)==33 and Vector2(tile-hint).length()<=1.45: inspected[hint]=true
	_show_notice("已收集纸条，可在齿轮菜单重新阅读。")
	dialog.present("note", "纸条 · " + str(record["title"]), str(record["text"]) + reward, "收好纸条，继续")
	_sync_world()

func _opening_label(target: Dictionary) -> String:
	if target["kind"] == "window": return "开窗"
	if opened_edges.has(target["edge"]): return "开门"
	if not str(target.get("password", "")).is_empty(): return "输入密码开门"
	if target.get("locked", false): return "撬锁开门（工具 ×1）"
	return "开门"

func _update_hud_layout() -> void:
	if card_ribbons.size() != 4: return
	var s := clampf(size.x / 1920.0, 0.5, 1.35)
	top_hud.size.y = 44 * s
	top_hud.get_node("GoldLine").position.y = 42 * s
	restart_button.position = Vector2(28 * s, 0)
	restart_button.size = Vector2(68, 106) * s
	gear_ribbon.size = restart_button.size
	gear_ribbon.queue_redraw()
	var icon := restart_button.get_child(0) as TextureRect
	icon.position = Vector2(10, 23) * s
	icon.size = Vector2(48, 48) * s
	title_label.position = Vector2(110, 9) * s
	title_label.add_theme_font_size_override("font_size", maxi(11, roundi(17 * s)))
	for i in range(4):
		var active := i == 0 if sniper_active else i == selected_cop + 1
		var width := (106.0 if active else 78.0) * s
		var height := (210.0 if active else 154.0) * s
		var center_x := size.x * 0.5 + (-265 + i * 132) * s
		cop_cards[i].position = Vector2(center_x - width * 0.5, 0)
		cop_cards[i].size = Vector2(width, height)
		cop_cards[i].clip_contents = false
		cop_cards[i].add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		cop_cards[i].add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		cop_cards[i].add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		card_ribbons[i].size = cop_cards[i].size
		card_ribbons[i].tint = Color("#ffe12d") if active or i == 0 else Color("#918653")
		card_ribbons[i].ap = int(cops[i - 1]["ap"]) if i > 0 and not cops.is_empty() else -1
		card_ribbons[i].queue_redraw()
		card_portraits[i].size = Vector2(width, height * 0.71)
		var bar := card_labels[i].get_parent() as ColorRect
		bar.position = Vector2(-9 * s, height * 0.7)
		bar.size = Vector2(width + 18 * s, 19 * s)
		bar.color = Color("#ffe12d") if active else Color("#332c17")
		card_labels[i].text = CARD_NAMES[i]
		card_labels[i].position = Vector2.ZERO
		card_labels[i].size = bar.size
		card_labels[i].add_theme_font_size_override("font_size", maxi(10, roundi(13 * s)))
		card_labels[i].add_theme_color_override("font_color", Color("#211c12") if active else Color("#fff1bd"))
		cop_cards[i].tooltip_text = "房间侦察 · 冷却 %d 回合"%sniper_cooldown if i == 0 else "%s · %d/2 行动点" % [CARD_NAMES[i], int(cops[i - 1]["ap"])]
	turn_button.position = Vector2(size.x - 315 * s, 0)
	turn_button.size = Vector2(276, 82) * s
	turn_button.add_theme_font_size_override("font_size", maxi(14, roundi(22 * s)))
	turn_ribbon.size = turn_button.size
	turn_ribbon.queue_redraw()
	if turn_banner != null:
		turn_banner.position = Vector2(0, size.y * 0.43)
		turn_banner.size = Vector2(size.x, 76 * s)
	if inventory_label != null:
		inventory_label.position = Vector2(145, 8)
		inventory_label.size = Vector2(410, 24)
		inventory_label.text = "%s · 急救包 ×%d · 撬锁工具 ×%d" % [CARD_NAMES[selected_cop + 1], int(cops[selected_cop].get("medkits", 0)), int(cops[selected_cop].get("lockpicks", 0))] if not cops.is_empty() else ""

func _process(delta: float) -> void:
	if bank_world == null or cops.is_empty(): return
	notice_age += delta
	var moving := not bank_world.cop_motion_tweens.is_empty()
	if was_moving and not moving and not action_busy:
		for i in range(cops.size()):
			var tile: Vector2i = cops[i]["pos"]
			guide_visited[Vector3i(i, tile.x, tile.y)] = true
		hover_tile = Vector2i(-1, -1)
		_show_notice("移动完成。下一步见目标旁提示；仍可自由选择角色和目的地。")
	was_moving = moving
	_check_completion()
	_update_guide_marker()
	if feedback != null: feedback.visible = notice_age < 4.0 and not title_overlay.visible and not action_wheel.visible and not sidebar.visible and not _dialog_open()

func _show_notice(message: String) -> void:
	notice_age = 0.0
	super._show_notice(message)

func _build_ui() -> void:
	super._build_ui()
	restart_button.pressed.disconnect(_reset_mission)
	restart_button.pressed.connect(_show_pause_menu)
	restart_button.tooltip_text = "游戏菜单 · 收集的纸条与物品 · 重开需确认"
	for card in cop_cards:
		var ribbon := RIBBON.new()
		ribbon.show_behind_parent = true
		card.add_child(ribbon)
		card_ribbons.append(ribbon)
	for button in [restart_button, turn_button]:
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		var ribbon := RIBBON.new()
		ribbon.show_behind_parent = true
		button.add_child(ribbon)
		if button == restart_button: gear_ribbon = ribbon
		else: turn_ribbon = ribbon
	inventory_label = Label.new()
	inventory_label.add_theme_font_size_override("font_size", 14)
	inventory_label.add_theme_color_override("font_color", Color("#e5d590"))
	inventory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_hud.add_child(inventory_label)
	for i in range(4):
		cop_cards[i].mouse_filter = Control.MOUSE_FILTER_STOP
		cop_cards[i].focus_mode = Control.FOCUS_NONE
		cop_cards[i].pressed.connect(_select_cop.bind(i - 1))
	turn_button.focus_mode = Control.FOCUS_NONE
	action_button.focus_mode = Control.FOCUS_NONE
	(title_overlay.get_node("Intro") as Label).text = "银行 · 学习复刻版\n蓝色虚影预览落点，白线表示可移动范围；单击地面移动。\n点罪犯打开动作轮盘，点门窗打开小菜单。空格定位，F1 查看教学说明。"
	(title_overlay.get_node("StartButton") as Button).text = "进入银行  [Enter]"
	feedback = Label.new()
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 17)
	feedback.add_theme_color_override("font_color", Color("#fff0b0"))
	feedback.add_theme_color_override("font_shadow_color", Color.BLACK)
	feedback.add_theme_constant_override("shadow_offset_x", 2)
	feedback.add_theme_constant_override("shadow_offset_y", 2)
	add_child(feedback)
	context_panel = PanelContainer.new()
	context_panel.add_theme_stylebox_override("panel", _hud_style(Color("#171513")))
	context_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	context_panel.z_index = 10
	add_child(context_panel)
	context_column = VBoxContainer.new()
	context_column.add_theme_constant_override("separation", 5)
	context_panel.add_child(context_column)
	context_panel.hide()
	action_wheel = ACTION_WHEEL.new()
	add_child(action_wheel)
	action_wheel.action_requested.connect(func(id: int): _perform_action(id, context_target.duplicate()))
	action_wheel.dismissed.connect(_dismiss_context)
	preview_label = Label.new()
	preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_label.add_theme_color_override("font_color", Color("#bdeaff"))
	preview_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	preview_label.add_theme_constant_override("shadow_offset_x", 2)
	preview_label.add_theme_constant_override("shadow_offset_y", 2)
	preview_label.add_theme_font_size_override("font_size", 16)
	add_child(preview_label)
	preview_label.hide()
	world_container.mouse_exited.connect(func():
		hover_tile = Vector2i(-1, -1)
		_update_destination_preview())
	# Reference pages are manually browsable, independent of gameplay.
	var reference_controls := HBoxContainer.new()
	lesson_label.get_parent().add_child(reference_controls)
	for direction in [-1, 1]:
		var page := Button.new()
		page.text = "上一条说明" if direction < 0 else "下一条说明"
		page.pressed.connect(func():
			reference_page = wrapi(reference_page + direction, 0, steps.size())
			_update_ui())
		reference_controls.add_child(page)
	guide_controls = HBoxContainer.new()
	guide_controls.add_theme_constant_override("separation", 5)
	add_child(guide_controls)
	for caption in ["定位并选人 [空格]", "跳过建议", "隐藏指引"]:
		var button := Button.new()
		button.text = caption
		button.focus_mode = Control.FOCUS_NONE
		guide_controls.add_child(button)
	(guide_controls.get_child(0) as Button).pressed.connect(_locate_guidance)
	(guide_controls.get_child(1) as Button).pressed.connect(func():
		guide_index = mini(guide_index + 1, steps.size())
		_close_menu()
		_update_ui())
	(guide_controls.get_child(2) as Button).pressed.connect(func():
		guide_enabled = not guide_enabled
		_update_ui())
	guide_marker = Label.new()
	guide_marker.text = "接近银行大楼"
	guide_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide_marker.add_theme_color_override("font_color", Color("#24221c"))
	var marker_style := StyleBoxFlat.new()
	marker_style.bg_color = Color("#fff9e8")
	marker_style.content_margin_left = 9
	marker_style.content_margin_right = 9
	marker_style.content_margin_top = 4
	marker_style.content_margin_bottom = 4
	guide_marker.add_theme_stylebox_override("normal", marker_style)
	guide_marker.add_theme_color_override("font_shadow_color", Color.BLACK)
	guide_marker.add_theme_constant_override("shadow_offset_x", 0)
	guide_marker.add_theme_constant_override("shadow_offset_y", 0)
	guide_marker.add_theme_font_size_override("font_size", 16)
	guide_marker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_marker.custom_minimum_size.x = 290
	add_child(guide_marker)
	guide_line = MeshInstance3D.new()
	guide_line.mesh = ImmediateMesh.new()
	var route_material := StandardMaterial3D.new()
	route_material.albedo_color = Color("#d8eef6")
	route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	route_material.no_depth_test = true
	guide_line.material_override = route_material
	bank_world.add_child(guide_line)
	dialog = DIALOG.new()
	add_child(dialog)
	dialog.confirmed.connect(_dialog_confirm)
	dialog.dismissed.connect(_on_dialog_dismissed)
	turn_banner = Label.new()
	turn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_banner.z_index = 25
	turn_banner.add_theme_stylebox_override("normal", _hud_style(Color("#ffe12d")))
	turn_banner.add_theme_color_override("font_color", Color("#17140c"))
	turn_banner.add_theme_font_size_override("font_size", 32)
	add_child(turn_banner)
	turn_banner.hide()
	title_overlay.move_to_front()

func _layout_ui() -> void:
	super._layout_ui()
	if feedback != null:
		feedback.position = Vector2(24, size.y - 137)
		feedback.size = Vector2(maxf(360, size.x - 48), 56)
		_close_menu()
	if guide_controls != null:
		objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		objective_label.custom_minimum_size = Vector2(320, 92)
		objective_panel.size = Vector2(348, 112)
		guide_controls.position = Vector2(maxf(220, size.x - 405), size.y - 42)
		guide_controls.size = Vector2(390, 32)
		action_button.position = Vector2(160, 12)
		action_button.size = Vector2(250, 38)
		action_button.add_theme_font_size_override("font_size", 15)
	_update_hud_layout()

func _reset_mission() -> void:
	mission_generation += 1
	action_busy = false
	was_moving = false
	guide_index = 0
	guide_enabled = true
	guide_visited.clear()
	completed_actions.clear()
	scouted_rooms.clear();healed_cops.clear();sniper_active=false;sniper_cooldown=0
	hover_tile = Vector2i(-1, -1)
	recommendation.clear()
	inspected.clear()
	reference_page = 0
	verified_codes.clear()
	pending_password.clear()
	if dialog != null: dialog.hide()
	if turn_banner_tween != null: turn_banner_tween.kill()
	if turn_banner != null: turn_banner.hide()
	_close_menu()
	super._reset_mission()
	for cop in cops: cop["lockpicks"] = 0;cop["medkits"]=1
	notice = "先用利维接近银行：蓝色人物是落点预览，单击其脚下格子移动。"
	_update_ui()

func _focus_step() -> void:
	# Do not let source tutorial records take over selection/camera.
	if not cops.is_empty():
		var tile: Vector2i = cops[selected_cop]["pos"]
		camera_origin = Vector2i(maxi(0, tile.x - 14), maxi(0, tile.y - 9))
	_sync_world()

func _select_cop(index: int) -> void:
	if _dialog_open(): return
	if index < 0:
		if _busy(): return
		if sniper_cooldown>0: _show_notice("狙击侦察冷却：%d 回合。"%sniper_cooldown);return
		_close_menu();sniper_active=true
		_show_notice("什韦茨已就位：点击有外窗的室内房间侦察。Esc 取消。")
		return
	sniper_active=false
	selected_cop = index
	hover_tile = Vector2i(-1, -1)
	_close_menu()
	_show_notice("已选择%s。点击目标查看动作及条件。" % CARD_NAMES[index + 1])

func _busy() -> bool:
	return finished or action_busy or not bank_world.cop_motion_tweens.is_empty() or _dialog_open()

func _close_menu() -> void:
	context_target = {}
	if context_panel != null:
		context_panel.hide()
	if action_wheel != null: action_wheel.hide()
	if feedback != null: feedback.visible = not title_overlay.visible
	if action_button != null: action_button.show()
	if turn_button != null: turn_button.text = "结束回合  [Enter]"
	if action_button != null and not cops.is_empty():
		action_button.text = "行动力用尽 → 结束回合 [Enter]" if int(cops[selected_cop]["ap"]) <= 0 else "不知道往哪走？定位建议目标 [空格]"

func _dismiss_context() -> void:
	_close_menu()
	hover_tile = Vector2i(-1, -1)
	_sync_world()

func _on_world_input(event: InputEvent) -> void:
	if _dialog_open(): return
	if event is InputEventMouseMotion and not title_overlay.visible and not _busy():
		var pixel: Vector2 = event.position * Vector2(world_viewport.size) / world_container.size
		var tile := bank_world.pick_tile(pixel)
		if tile != hover_tile:
			hover_tile = tile
			_update_destination_preview()
		return
	if title_overlay.visible or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_close_menu()
		_sync_world()
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		var pixel: Vector2 = event.position * Vector2(world_viewport.size) / world_container.size
		if _busy():
			_show_notice("角色正在行动，请等动作结束后再点击。")
			return
		if context_panel.visible and context_target.get("kind") == "ground" and bank_world.pick_tile(pixel) == context_target["tile"]:
			_confirm_movement()
			return
		var target := _pick_target(pixel)
		# The suggested floor tile takes priority over a nearby door's generous
		# screen-space hit area. Interacting with the door still uses its menu.
		var floor_tile := bank_world.pick_tile(pixel)
		var suggested: Dictionary = recommendation.get("target", {})
		if guide_enabled and suggested.get("kind") == "ground" and suggested.get("tile") == floor_tile:
			target = {"kind": "ground", "tile": floor_tile}
		if target.get("kind") == "cop":
			if int(target["index"])==selected_cop or (int(cops[int(target["index"])].hp)<3 and Vector2(cops[selected_cop].pos-target.tile).length()<=1.45): _open_menu(target,event.position)
			else: _select_cop(int(target["index"]))
		elif target.get("kind") == "ground":
			if not _inside(target["tile"]): return
			var reason := _action_reason(-1, target)
			if reason.is_empty():
				_perform_action(-1, target)
			else:
				_close_menu()
				_show_notice("无法移动：%s。白线内是当前可达范围。" % reason)
		else:
			_open_menu(target, event.position)
		return
	_close_menu()
	super._on_world_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if _dialog_open(): return
	if event is InputEventKey and event.pressed and not event.echo and not title_overlay.visible:
		if event.keycode == KEY_F1:
			_close_menu()
			if not sidebar.visible:
				reference_page = mini(guide_index, steps.size() - 1)
			sidebar.visible = not sidebar.visible
			_update_ui()
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and (context_panel.visible or action_wheel.visible):
			if context_target.get("kind") == "ground":
				_confirm_movement()
			else:
				_show_notice("请在菜单选择具体动作；按 Esc 取消后，Enter 才会结束回合。")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SPACE:
			_locate_guidance()
			return
		if event.keycode == KEY_ESCAPE:
			sniper_active=false
			_close_menu()
			_sync_world()
			return
		if event.keycode in [KEY_1, KEY_2, KEY_3]:
			_select_cop(int(event.keycode) - KEY_1)
			return
		if event.keycode==KEY_R:
			_perform_action(11,{"kind":"cop","index":selected_cop,"tile":cops[selected_cop].pos});return
	super._unhandled_input(event)

func _edge_tiles(edge: int) -> Array[Vector2i]:
	var a := Vector2i((edge % 120) / 2, edge / 120)
	return [a, a + (Vector2i.LEFT if edge % 2 == 1 else Vector2i.UP)]

func _opening_target(data: Dictionary, kind: String) -> Dictionary:
	var edge := int(data["EdgeIndex"])
	return {"kind": kind, "edge": edge, "tile": _edge_tiles(edge)[0], "locked": int(data.get("IsLocked", 0)) != 0,
		"password": str(interaction_data.get("doors", {}).get(str(edge), {}).get("password", ""))}

func _pick_target(pixel: Vector2) -> Dictionary:
	if sniper_active: return {"kind":"sniper","tile":bank_world.pick_tile(pixel)}
	# Screen-space capsules include the head/body, not just a ray to the floor.
	var best: Dictionary = {}
	var best_depth := INF
	for group in [{"kind": "cop", "nodes": bank_world.cop_nodes, "data": cops},
		{"kind": "enemy", "nodes": bank_world.guard_nodes, "data": guards},
		{"kind": "hostage", "nodes": bank_world.hostage_nodes, "data": hostages}]:
		for i in range(group["nodes"].size()):
			var actor: Node3D = group["nodes"][i]
			if not actor.visible:
				continue
			var foot := bank_world.camera.unproject_position(actor.global_position + Vector3.UP * 0.15)
			var head := bank_world.camera.unproject_position(actor.global_position + Vector3.UP * 1.65)
			var nearest := Geometry2D.get_closest_point_to_segment(pixel, foot, head)
			var depth := bank_world.camera.global_position.distance_squared_to(actor.global_position)
			if pixel.distance_to(nearest) <= maxf(8.0, foot.distance_to(head) * 0.28) and depth < best_depth:
				best_depth = depth
				best = {"kind": group["kind"], "index": i, "tile": group["data"][i]["pos"]}
	if not best.is_empty():
		return best
	var closest := 24.0
	for kind in ["door", "window"]:
		var nodes: Dictionary = bank_world.source_door_nodes if kind == "door" else bank_world.source_window_nodes
		for data in source_data["doors" if kind == "door" else "windows"]:
			var edge := int(data["EdgeIndex"])
			if not nodes.has(edge):
				continue
			var node: Node3D = nodes[edge]
			var foot := bank_world.camera.unproject_position(node.position + Vector3.UP * 0.3)
			var top := bank_world.camera.unproject_position(node.position + Vector3.UP * 1.5)
			var distance := pixel.distance_to(Geometry2D.get_closest_point_to_segment(pixel, foot, top))
			if distance < closest:
				closest = distance
				best = _opening_target(data, kind)
	if not best.is_empty():
		return best
	return _target_at(bank_world.pick_tile(pixel))

func _target_at(tile: Vector2i) -> Dictionary:
	if note_records.has(tile): return {"kind":"note","tile":tile}
	for i in range(cops.size()):
		if cops[i]["pos"] == tile:
			return {"kind": "cop", "index": i, "tile": tile}
	var enemy := _guard_at(tile)
	if enemy >= 0:
		return {"kind": "enemy", "index": enemy, "tile": tile}
	for i in range(hostages.size()):
		if hostages[i]["pos"] == tile and hostages[i]["state"] != "已获救":
			return {"kind": "hostage", "index": i, "tile": tile}
	for step in steps:
		if int(step["AllowedAction"]) == 33 and Vector2i(int(step["X"]), int(step["Y"])) == tile:
			return {"kind": "note", "tile": tile, "tooltip": int(step["TooltipId"])}
	return {"kind": "ground", "tile": tile}

func _click_tile(tile: Vector2i) -> void:
	var target := _target_at(tile)
	if target["kind"] == "cop":
		_select_cop(target["index"])
	else:
		_open_menu(target, get_local_mouse_position())

func _open_menu(target: Dictionary, at: Vector2) -> void:
	if not _inside(target["tile"]):
		return
	if _busy():
		_show_notice("动作执行中，请等角色停稳后再下指令。")
		return
	_close_menu()
	context_target = target
	if target["kind"] in ["enemy", "hostage"]:
		var entries: Array = []
		for item in _menu_actions(target):
			entries.append({"id": item[0], "label": item[1], "reason": _action_reason(item[0], target), "cost": _action_cost(item[0], target)})
		var preferred := int(recommendation.get("action", -99))
		var title := "人质" if target["kind"] == "hostage" else "罪犯 · " + str(guards[int(target["index"])]["state"])
		action_wheel.present(entries, at, size, title, preferred)
		turn_button.text = "结束回合"
		feedback.hide()
		action_button.hide()
		_sync_world()
		return
	for child in context_column.get_children():
		context_column.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	var names := {"enemy": "罪犯", "hostage": "人质", "door": "门", "window": "窗", "ground": "移动目的地", "note": "场景线索"}
	heading.text = "  %s  ·  %s  " % [names.get(target["kind"], "目标"), CARD_NAMES[selected_cop + 1]]
	heading.add_theme_color_override("font_color", Color("#ffe065"))
	context_column.add_child(heading)
	for item in _menu_actions(target):
		_add_action_button(item[0], str(item[1]), target)
	if target["kind"] in ["door", "window"]:
		var nearby: Dictionary = _movement_search()["costs"]
		var approach := Vector2i(-1, -1)
		var best_cost := INF
		for side in _edge_tiles(int(target["edge"])):
			if nearby.has(side) and float(nearby[side]) < best_cost:
				approach = side
				best_cost = float(nearby[side])
		if approach.x >= 0 and approach != cops[selected_cop]["pos"]:
			_add_action_button(-1, "走到门窗旁", {"kind": "ground", "tile": approach})
	# Ground beside an opening also exposes it, so a small door is never a pixel hunt.
	if target["kind"] == "ground":
		for kind in ["door", "window"]:
			for data in source_data["doors" if kind == "door" else "windows"]:
				if int(data["IsGenerated"]) != 0 and target["tile"] in _edge_tiles(int(data["EdgeIndex"])):
					var opening := _opening_target(data, kind)
					_add_action_button(38, "开门" if kind == "door" else "开窗", opening)
	var cancel := Button.new()
	cancel.text = "取消  [右键 / Esc]"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_dismiss_context)
	context_column.add_child(cancel)
	context_panel.reset_size()
	context_panel.position = Vector2(clampf(at.x + 14, 8, maxf(8, size.x - context_panel.size.x - 8)), clampf(at.y, 112, maxf(112, size.y - context_panel.size.y - 145)))
	context_panel.show()
	# Z order controls rendering, not GUI hit order. Keep the popup last in
	# sibling order too, ahead of help/guide overlays added after it.
	context_panel.move_to_front()
	turn_button.text = "结束回合"
	if target["kind"] == "ground":
		_show_notice("等待确认：点黄色“确认移动”，或再次点同一格，也可按 Enter。Esc 取消。")
	else:
		_sync_world()

func _menu_actions(target: Dictionary) -> Array:
	match str(target["kind"]):
		"sniper": return [[60,"侦察房间"]]
		"cop": return [[35,"使用急救包"],[11,"装填手枪"]] if int(target.index)==selected_cop else [[35,"为警员包扎"]]
		"enemy": return [[14, "喝止"], [1, "警棍"], [3, "泰瑟枪"], [10, "射击"], [5, "逮捕"]]
		"hostage": return [[55, "解救人质"]]
		"door": return [[38, _opening_label(target)]]
		"window": return [[38, "开窗"]]
		"note": return [[33, "查看线索"], [-1, "移动到这里"]]
	return [[-1, "确认移动"]]

func _add_action_button(id: int, label: String, target: Dictionary) -> void:
	var reason := _action_reason(id, target)
	var button := Button.new()
	button.custom_minimum_size = Vector2(320, 38)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.text = "  %s  ·  %s" % [label, reason if not reason.is_empty() else ("查看" if id == 33 else "%d AP" % _action_cost(id, target))]
	button.disabled = not reason.is_empty()
	button.add_theme_color_override("font_disabled_color", Color("#b4ab93"))
	button.add_theme_color_override("font_color", Color("#ffe065"))
	if id == -1 and context_target.get("kind") == "ground" and reason.is_empty():
		button.text += "  [Enter]"
		button.add_theme_stylebox_override("normal", _hud_style(Color("#f1cd3b")))
		button.add_theme_stylebox_override("hover", _hud_style(Color("#ffe276")))
		button.add_theme_stylebox_override("pressed", _hud_style(Color("#c9aa2d")))
		button.add_theme_color_override("font_color", Color("#1c1b15"))
		button.add_theme_color_override("font_hover_color", Color("#1c1b15"))
	button.tooltip_text = reason
	button.pressed.connect(_perform_action.bind(id, target.duplicate()))
	context_column.add_child(button)

func _movement_search() -> Dictionary:
	var cop: Dictionary = cops[selected_cop]
	return NAV.search(cop["pos"], float(cop["ap"] * cop["max_move"]) * 1.4, cells, grid_edges, opened_edges, _blocked_for_move())

func _action_cost(id: int, target: Dictionary) -> int:
	if id in [11,33,60]:
		return 0
	if id == -1:
		var distance := float(_movement_search()["costs"].get(target["tile"], INF))
		return NAV.movement_ap_cost(distance, int(cops[selected_cop]["max_move"]))
	return 1

func _action_reason(id: int, target: Dictionary) -> String:
	if _busy(): return "动作执行中"
	if id==60:
		if sniper_cooldown>0: return "狙击侦察冷却中"
		var room:=room_id(target.tile)
		return "该区域没有可供狙击手观察的外窗" if room==0 or room in room_data.no_sniper_rooms else ""
	var cop: Dictionary = cops[selected_cop]
	var tile: Vector2i = target["tile"]
	var origin: Vector2i = cop["pos"]
	if id not in [11,33] and int(cop["ap"]) <= 0: return "行动力不足"
	if id==11:
		if int(target.get("index",-1))!=selected_cop: return "先选择此警员"
		return "弹匣已满" if int(cop.ammo)>=9 else ""
	if id==35:
		if target.kind!="cop" or int(cops[int(target.index)].hp)>=3: return "目标没有伤势"
		if int(cop.get("medkits",0))<=0: return "没有急救包"
	if id == -1:
		if tile == origin: return "已在此处"
		if _blocked_for_move().has(tile): return "此格有人"
		if not _movement_search()["costs"].has(tile): return "超出范围或路径被挡"
		return ""
	if id == 38:
		if opened_edges.has(target["edge"]): return "已经打开"
		if target.get("locked", false) and str(target.get("password", "")).is_empty() and int(cop.get("lockpicks", 0)) <= 0: return "已上锁，需要撬锁工具（纸条旁可获得）"
		if not origin in _edge_tiles(target["edge"]): return "请走到门窗旁"
		return ""
	if id in [1, 3, 5, 10, 14]:
		var state := str(guards[int(target["index"])]["state"])
		if state in ["倒地", "已逮捕", "逃离"]: return "目标已失去行动能力"
		if id == 5 and not state in ["昏迷", "举手"]: return "须先制服目标"
		if id != 5 and state in ["昏迷", "举手"]: return "目标已被制服，请逮捕"
		if id == 10 and int(cop["ammo"]) <= 0: return "没有弹药"
	# Glock uses the source 11-cell range; other bank interactions are simplified.
	var reach := 11.0 if id == 10 else (4.0 if id == 14 else (3.0 if id == 3 else 1.45))
	if Vector2(origin).distance_to(Vector2(tile)) > reach: return "距离太远，先靠近"
	if id==33: return "" if _interaction_line(origin,tile) else "墙壁或关闭门窗阻挡"
	if not _clear_line(origin, tile): return "墙壁或关闭门窗阻挡"
	return ""

func _interaction_line(a: Vector2i,b: Vector2i) -> bool:
	if a==b: return true
	if Vector2(a-b).length()>1.45: return false
	var allowed: Array=[0,2,3,4,5,9,13,14]
	if a.x==b.x or a.y==b.y: return NAV.edge_type(NAV.edge_index(a,b),grid_edges,opened_edges) in allowed
	for corner in [Vector2i(a.x,b.y),Vector2i(b.x,a.y)]:
		if NAV.edge_type(NAV.edge_index(a,corner),grid_edges,opened_edges) in allowed and NAV.edge_type(NAV.edge_index(corner,b),grid_edges,opened_edges) in allowed: return true
	return false

func _clear_line(a: Vector2i, b: Vector2i) -> bool:
	# Conservative grid sight check. Covers walls/closed openings; full original
	# cover, visibility and hit-region rules remain unimplemented.
	var count := maxi(absi(b.x - a.x), absi(b.y - a.y))
	var previous := a
	for i in range(1, count + 1):
		var next := Vector2i(Vector2(a).lerp(Vector2(b), float(i) / float(count)).round())
		for edge in NAV.crossing_edges(previous, next):
			if not NAV.edge_type(edge, grid_edges, opened_edges) in [0, 3, 4, 5, 9, 13]: return false
		previous = next
	return true

func _perform_action(id: int, target: Dictionary) -> void:
	var reason := _action_reason(id, target)
	if not reason.is_empty():
		_show_notice(reason)
		return
	if id==60: _close_menu();_observe_room(target.tile);return
	var actor := selected_cop
	var tile: Vector2i = target["tile"]
	var cop: Dictionary = cops[actor]
	var cost := _action_cost(id, target)
	_close_menu()
	if id == 33:
		_read_note(tile, actor)
		return
	if id == 38 and not str(target.get("password", "")).is_empty() and not verified_codes.has(target["edge"]):
		pending_password = target.duplicate()
		dialog.present("password", "密码门", "请输入四位密码。取消或输错不会消耗行动点。\n可从银行内的纸条寻找线索。", "确认并开门")
		_sync_world()
		return
	if id == -1:
		var route: Array[Vector2i] = NAV.path(cop["pos"], tile, _movement_search()["parents"])
		bank_world.planned_routes[actor] = route
		cop["ap"] -= cost
		cop["pos"] = tile
		hover_tile = Vector2i(-1, -1)
		_sync_world() # Start visual motion before checking completed guide goals.
		action_player.stream = ACTION_SOUNDS[-1]
		action_player.volume_db = -14
		action_player.play()
		_show_notice("%s移动中，消耗 %d AP。" % [CARD_NAMES[actor + 1], cost])
		return
	cop["ap"] -= cost
	if id == 38 and target.get("locked", false) and str(target.get("password", "")).is_empty():
		cop["lockpicks"] = int(cop.get("lockpicks", 0)) - 1
	action_busy = true
	var generation := mission_generation
	var face_tile := tile
	if id == 38 and face_tile == cop["pos"]:
		face_tile = _edge_tiles(target["edge"])[1]
	var timing: Dictionary = bank_world.play_cop_gesture(actor, face_tile, id)
	_show_notice("%s正在%s……" % [CARD_NAMES[actor + 1], ACTION_NAMES.get(id, "互动")])
	await get_tree().create_timer(float(timing["impact"])).timeout
	if generation != mission_generation: return
	match id:
		38:
			opened_edges[target["edge"]] = true
			opened[tile] = true
		1, 3, 5, 10, 14:
			guards[int(target["index"])]["state"] = {1: "昏迷", 3: "昏迷", 5: "已逮捕", 10: "倒地", 14: "举手"}[id]
			if id == 10: cop["ammo"] -= 1
		55: hostages[int(target["index"])]["state"] = "已获救"
		35:
			cops[int(target.index)].hp=3
			cop.medkits-=1
			healed_cops[actor]=true
		11: cop.ammo=9
	if id==38 and int(target.edge)==2943 and not shootout_occurred: _play_scripted_shootout()
	completed_actions[Vector4i(actor, id, tile.x, tile.y)] = true
	_play_action_sound(id, 9 if target["kind"] == "window" else 0)
	_sync_world()
	await get_tree().create_timer(maxf(0.01, float(timing["duration"]) - float(timing["impact"]))).timeout
	if generation != mission_generation: return
	action_busy = false
	_show_notice("%s已完成%s。可以继续选人或选择其他目标。" % [CARD_NAMES[actor + 1], ACTION_NAMES.get(id, "互动")])
	_check_completion()

func _blocked_for_move() -> Dictionary:
	var blocked := super._blocked_for_move()
	for i in range(cops.size()):
		if i != selected_cop: blocked[cops[i]["pos"]] = true
	for hostage in hostages:
		if hostage["state"] != "已获救": blocked[hostage["pos"]] = true
	return blocked

func _end_turn() -> void:
	if _busy():
		_show_notice("请等当前动作结束再换回合。")
		return
	_close_menu()
	super._end_turn()
	sniper_cooldown=maxi(0,sniper_cooldown-1)
	if bank_world.scout_mesh!=null: bank_world.scout_mesh.hide()
	if turn_banner_tween != null: turn_banner_tween.kill()
	turn_banner.text = "回合 %d" % turn_number
	turn_banner.modulate.a = 1.0
	turn_banner.show()
	turn_banner_tween = create_tween()
	turn_banner_tween.tween_interval(0.65)
	turn_banner_tween.tween_property(turn_banner, "modulate:a", 0.0, 0.25)
	turn_banner_tween.tween_callback(turn_banner.hide)

func _action_button_pressed() -> void:
	if context_panel.visible and context_target.get("kind") == "ground":
		_confirm_movement()
		return
	if int(cops[selected_cop]["ap"]) <= 0:
		_end_turn()
	else:
		_locate_guidance()

func _confirm_movement() -> void:
	if not context_panel.visible or context_target.get("kind") != "ground": return
	_perform_action(-1, context_target.duplicate())

func _locate_guidance() -> void:
	if _dialog_open(): return
	guide_enabled = true
	_close_menu()
	var actor := int(recommendation.get("actor", -1))
	if actor >= 0: selected_cop = actor
	elif recommendation.get("target",{}).get("kind","")=="sniper": _select_cop(-1)
	var tile: Vector2i = recommendation.get("tile", Vector2i(-1, -1))
	if _inside(tile):
		# Keep both the officer and this turn's destination in view.
		var center := tile
		if actor >= 0: center = Vector2i((Vector2(cops[actor]["pos"]) + Vector2(tile)) * 0.5)
		camera_origin = center - Vector2i(14, 9)
		bank_world.set_zoomed_out(false)
		zoomed_out = false
	if actor >= 0:
			notice = "已选中%s并定位目标。单击蓝色虚影脚下移动；点人物选轮盘动作，点门窗打开小菜单。" % CARD_NAMES[actor + 1]
	_update_ui()
	# When already in interaction range, present the correct object menu.
	# This avoids asking the user to click a floor square under a door/character.
	if not _busy() and recommendation.has("target") and recommendation.get("route", []).is_empty():
		_open_menu(recommendation["target"], Vector2(size.x * 0.55, size.y * 0.4))

func _refresh_guidance() -> void:
	if _busy(): return
	var previous_index := guide_index
	if not _busy():
		while guide_index < steps.size() and GUIDANCE.satisfied(self, guide_index, guide_visited):
			guide_index += 1
	recommendation = GUIDANCE.recommend(self, guide_index)
	if guide_enabled and guide_index != previous_index and not title_overlay.visible:
		# Advance only after a completed action, not when the player manually
		# selects another officer. No input whitelist and no forced AP spending.
		var actor := int(recommendation.get("actor", -1))
		if actor >= 0:
			selected_cop = actor
			hover_tile = Vector2i(-1, -1)
			var target: Vector2i = recommendation.get("tile", cops[actor]["pos"])
			if _inside(target): camera_origin = Vector2i((Vector2(cops[actor]["pos"]) + Vector2(target)) * 0.5) - Vector2i(14, 9)

func _update_guide_marker() -> void:
	if guide_marker == null: return
	guide_marker.visible = guide_enabled and not title_overlay.visible and not _busy() and not context_panel.visible and not action_wheel.visible and not sidebar.visible
	if not guide_marker.visible or size.x < 180 or size.y < 280: return
	var tile: Vector2i = recommendation.get("tile", Vector2i(-1, -1))
	if not _inside(tile):
		guide_marker.hide()
		return
	var world_point := bank_world._grid(tile, 0.1)
	var suggested: Dictionary = recommendation.get("target", {})
	if suggested.get("kind", "") in ["door", "window"]:
		var models: Dictionary = bank_world.source_door_nodes if suggested["kind"] == "door" else bank_world.source_window_nodes
		if models.has(suggested["edge"]): world_point = models[suggested["edge"]].position + Vector3.UP * 0.7
	var pixel := bank_world.camera.unproject_position(world_point)
	pixel *= world_container.size / Vector2(world_viewport.size)
	var on_screen := Rect2(20, 115, size.x - 150, size.y - 260).has_point(pixel)
	var actor := int(recommendation.get("actor", -1))
	var caption := str(recommendation.get("heading", "下一步"))
	if actor >= 0: caption = "%s · %s" % [CARD_NAMES[actor + 1], caption]
	var text := str(recommendation.get("text", ""))
	if guide_index < steps.size():
		var key := "TacticsTutorial%dDescription" % int(steps[guide_index]["TooltipId"])
		var description := str(locale.get(key, ""))
		if not description.is_empty(): caption += "\n" + description
	# Always explain blocked/no-AP instructions in situ, never just an unreachable marker.
	if actor >= 0 and int(cops[actor]["ap"]) <= 0 or not recommendation.has("target"):
		caption += "\n" + text
	else:
		caption += "\n" + ("单击蓝色落点移动" if suggested.get("kind") == "ground" else "点击目标，选择“%s”" % ACTION_NAMES.get(int(recommendation.get("action", -1)), "互动"))
	guide_marker.text = caption if on_screen else caption + "\n目标在画外 · 按空格定位"
	(guide_marker.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = Color("#ffe52a")
	guide_marker.size.x = 290
	guide_marker.reset_size()
	guide_marker.position = pixel + Vector2(-guide_marker.size.x * 0.5, -guide_marker.size.y - 50) if on_screen else Vector2(size.x * 0.5 - 145, 125)
	guide_marker.position.x = clampf(guide_marker.position.x, 8, maxf(8, size.x - guide_marker.size.x - 8))
	guide_marker.position.y = clampf(guide_marker.position.y, 120, maxf(120, size.y - 100 - guide_marker.size.y))

func _update_destination_preview() -> void:
	if preview_label == null or cops.is_empty() or not is_inside_tree() or not bank_world.camera.is_inside_tree(): return
	preview_label.hide()
	bank_world.hide_destination_preview()
	if title_overlay.visible or sidebar.visible or _busy() or context_panel.visible or action_wheel.visible: return
	var tile := hover_tile
	var actor := selected_cop
	if not _inside(tile):
		var target: Dictionary = recommendation.get("target", {})
		if not guide_enabled or target.get("kind") != "ground": return
		if int(recommendation.get("actor", -1)) != actor: return
		tile = target["tile"]
	var target := {"kind": "ground", "tile": tile}
	if not _action_reason(-1, target).is_empty(): return
	var route: Array = [cops[actor]["pos"]]
	route.append_array(NAV.path(cops[actor]["pos"], tile, _movement_search()["parents"]))
	bank_world.show_destination_preview(tile, actor, route)
	var point := bank_world.camera.unproject_position(bank_world._grid(tile))
	point *= world_container.size / Vector2(world_viewport.size)
	if not Rect2(10, 115, size.x - 150, size.y - 270).has_point(point): return
	preview_label.text = "%d AP · 单击移动" % _action_cost(-1, target)
	preview_label.position = point + Vector2(-50, 18)
	preview_label.show()

func _draw_guide_route() -> void:
	if guide_line == null: return
	var mesh := guide_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if not guide_enabled or _busy() or context_panel.visible or (action_wheel != null and action_wheel.visible): return
	var route: Array = recommendation.get("route", [])
	if route.size() < 2: return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, route.size()):
		var a := bank_world._grid(route[i - 1], 0.12)
		var b := bank_world._grid(route[i], 0.12)
		var width := (b - a).normalized().cross(Vector3.UP) * 0.04
		for vertex in [a - width, b - width, a + width, a + width, b - width, b + width]:
			mesh.surface_add_vertex(vertex)
	mesh.surface_end()

func _update_ui() -> void:
	if status_label == null or cops.is_empty(): return
	_refresh_guidance()
	var arrested := 0
	var rescued := 0
	for guard in guards:
		if guard["state"] == "已逮捕": arrested += 1
	for hostage in hostages:
		if hostage["state"] == "已获救": rescued += 1
	var cop: Dictionary = cops[selected_cop]
	status_label.text = "自由操作 · 回合 %d\n逮捕 %d/%d · 解救 %d/%d" % [turn_number, arrested, guards.size(), rescued, hostages.size()]
	var reference: Dictionary = steps[reference_page]
	var key := "TacticsTutorial%d" % int(reference["TooltipId"])
	lesson_label.text = "本步说明（可翻页；不限制操作）\n%s\n\n%s\n\nF1 返回场景" % [locale.get(key, ""), locale.get(key + "Description", "按目标旁的提示选择角色与动作。")]
	objective_label.text = "%s · AP %d/2 · 回合 %d\n选人 → 点击目标 → 选择动作\n逮捕 %d/%d · 解救 %d/%d · F1 帮助" % [CARD_NAMES[selected_cop + 1], cop["ap"], turn_number, arrested, guards.size(), rescued, hostages.size()]
	if guide_enabled:
		var actor := int(recommendation.get("actor", -1))
		var actor_name: String = CARD_NAMES[actor + 1] if actor >= 0 else CARD_NAMES[0]
		objective_label.text = "建议：%s · %s\n%s\n灰蓝区 1 AP · 灰粉区 2 AP" % [actor_name, recommendation.get("heading", "自由行动"), recommendation.get("text", "")]
		if actor >= 0 and actor != selected_cop:
			objective_label.text += "\n先按空格切换到%s并定位。" % actor_name
	guide_controls.visible = not sidebar.visible and not title_overlay.visible
	(guide_controls.get_child(2) as Button).text = "隐藏指引" if guide_enabled else "显示指引"
	cop_label.text = "%s   HP %d/3   AP %d/2" % [CARD_NAMES[selected_cop + 1], cop["hp"], cop["ap"]]
	action_button.text = "行动力用尽 → 结束回合 [Enter]" if int(cop["ap"]) <= 0 else "不知道往哪走？定位建议目标 [空格]"
	if context_panel.visible and context_target.get("kind") == "ground":
		action_button.text = "确认所选移动  [Enter] · Esc 取消"
	action_button.disabled = false
	ammo_label.text = str(cop["ammo"])
	for i in range(4):
		var active := i == 0 if sniper_active else i == selected_cop + 1
		card_portraits[i].modulate = Color.WHITE if active else Color(0.68, 0.63, 0.55, 0.74)
		cop_cards[i].add_theme_stylebox_override("normal", _hud_style(Color("#f1cd3b") if active else Color("#211d19")))
		if i > 0: card_labels[i].text = "%s  %d AP" % [CARD_NAMES[i], cops[i - 1]["ap"]]
	_update_hud_layout()
	notice_label.text = notice
	if feedback != null:
		feedback.text = notice
		feedback.visible = not title_overlay.visible and not action_wheel.visible
	if action_wheel != null: action_button.visible = not action_wheel.visible and int(cop["ap"]) <= 0
	_sync_world()

func _sync_world() -> void:
	if bank_world == null or not bank_world.is_node_ready() or cops.is_empty(): return
	var target: Vector2i = context_target.get("tile", Vector2i(-1, -1))
	if context_target.is_empty() and guide_enabled:
		target = recommendation.get("tile", Vector2i(-1, -1))
	bank_world.sync_source(cops, guards, hostages, opened, opened_edges, cells, grid_edges, selected_cop, target, camera_origin, source_data["doors"], source_data["windows"])
	(bank_world.objective_ring.material_override as StandardMaterial3D).albedo_color = Color("#bdeaff") if recommendation.get("target", {}).get("kind") == "ground" else Color("#ffe394")
	if context_target.is_empty() and guide_enabled:
		var suggested: Dictionary = recommendation.get("target", {})
		if suggested.get("kind", "") in ["door", "window"]:
			var models: Dictionary = bank_world.source_door_nodes if suggested["kind"] == "door" else bank_world.source_window_nodes
			if models.has(suggested["edge"]): bank_world.objective_ring.position = models[suggested["edge"]].position + Vector3.UP * 0.05
	bank_world._update_movement_outline(cops, guards, opened_edges, cells, grid_edges, selected_cop, true, _blocked_for_move())
	_draw_guide_route()
	_update_destination_preview()
	_update_guide_marker()
	if guide_controls != null: guide_controls.visible = not sidebar.visible and not title_overlay.visible and not action_wheel.visible
	# Explanations now live beside the actual target; F1 retains the full reference.
	objective_panel.hide()
	action_button.visible = int(cops[selected_cop]["ap"]) <= 0 and not title_overlay.visible and not sidebar.visible and not action_wheel.visible and not context_panel.visible
	if _dialog_open():
		bank_world.hide_destination_preview()
		guide_marker.hide()
		guide_controls.hide()
		preview_label.hide()
		feedback.hide()
