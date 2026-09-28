extends Control

const STATE = preload("res://scripts/horde_state.gd")
const SAVE = preload("res://scripts/horde_save.gd")
const SETTINGS = preload("res://scripts/horde_settings.gd")
var save_path := SAVE.PATH
var settings_path := SETTINGS.PATH
var settings: Dictionary = SETTINGS.DEFAULTS.duplicate()
const WORLD = preload("res://scripts/horde_world.gd")
const MINIMAP = preload("res://scripts/horde_minimap.gd")
const DIALOG = preload("res://scripts/bank_dialog.gd")
const PORTRAITS = preload("res://assets/bank/ui/portraits_small_original.png")
const GUN_SOUND = preload("res://assets/bank/audio/assetbundles_sounds_tactics_gunshots_TacticsGunshot.wav")
var state = STATE.new()
var world
var selected := 0
var busy := false
var quick_enemy := false
var viewport: SubViewport
var surface: SubViewportContainer
var hud: Control
const HUD = preload("res://scripts/horde_hud.gd")
const WHEEL = preload("res://scripts/horde_action_wheel.gd")
const MODAL = preload("res://scripts/horde_ui_modal.gd")
const INVENTORY_PANEL = preload("res://scripts/horde_inventory_panel.gd")
const UI_MOTION = preload("res://scripts/horde_ui_motion.gd")
const BODY_SELECTOR = preload("res://scripts/horde_body_selector.gd")
var body_selector
var inventory_panel
var ui
var wheel
var modal
var last_notice := ""
var notice_time := 0.0
var cards: Control
var card_nodes: Array = []
var turn_button: Button
var stats: Label
var notice: Label
var preview_label: Label
var action_scroll: ScrollContainer
var minimap
var action_panel: PanelContainer
var action_column: VBoxContainer
var dialog
var sound: AudioStreamPlayer
var battle_audio
var action_player
var reaction_waiting := false
var reaction_serial := 0
signal reaction_chosen(part: String)
var phase_banner: Label
var phase_paper: Control
var turn_summary: Label
var phase_banner_tween: Tween
var phase_banner_serial := 0
var result_written := false
var pending_target: Dictionary = {}
var auto_start := false
var random_seed := -1
var results_path := "user://horde_results.json"
var camera_drag_held := false
var camera_drag_started := false
var camera_drag_origin := Vector2.ZERO
var camera_drag_last := Vector2.ZERO
const CAMERA_DRAG_THRESHOLD := 4.0

func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/horde/horde_data.json"))
	state.initialize(data, random_seed)
	settings = SETTINGS.read_settings(settings_path)
	var resumed := false
	if get_tree().has_meta("horde_resume"):
		get_tree().remove_meta("horde_resume")
		var saved := SAVE.read_save(save_path)
		if saved.ok:
			var error := SAVE.restore(state,saved.data)
			resumed = error.is_empty()
			state.say("已从上一次有效备份恢复战局。" if error.is_empty() and saved.get("backup",false) else "已继续保存的战局。" if error.is_empty() else error)
		else: state.say(saved.error)
	_build()
	battle_audio = preload("res://scripts/horde_audio.gd").new()
	add_child(battle_audio)
	action_player = preload("res://scripts/horde_action_player.gd").new()
	action_player.world = world
	action_player.audio = battle_audio
	add_child(action_player)
	apply_settings()
	get_window().focus_exited.connect(_end_camera_drag)
	resized.connect(_layout)
	_layout()
	refresh()
	if not auto_start and not resumed: show_help()

func apply_settings() -> void:
	quick_enemy = float(settings.enemy_speed)>1
	world.follow_actions = bool(settings.follow)
	world.effects_gain = float(settings.effects)
	battle_audio.music_gain = float(settings.music)
	battle_audio.voice.volume_db = linear_to_db(maxf(.0001,float(settings.voice)))-3
	battle_audio.effects.volume_db = linear_to_db(maxf(.0001,float(settings.effects)))-10
	action_player.enemy_speed = float(settings.enemy_speed)
	_layout()

func change_setting(key: String,value: Variant) -> void:
	settings[key] = value
	apply_settings()
	var error := SETTINGS.write_settings(settings,settings_path)
	if error != OK: state.say("设置未能写入磁盘："+error_string(error))

func save_game(automatic := false) -> bool:
	if busy: return false
	var result := SAVE.write_save(state,save_path)
	if not automatic or not result.ok:
		state.say("战局已保存。" if result.ok else result.error)
		refresh()
	return result.ok

func box_style(color: Color, border := Color("#a49042")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func label(text: String, font_size: int, parent: Node) -> Label:
	var n := Label.new()
	n.text = text
	n.add_theme_font_size_override("font_size", font_size)
	n.add_theme_color_override("font_color", Color("#f1e6c9"))
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(n)
	return n

func button(text: String, parent: Node, callback: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.custom_minimum_size.y = 37
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", box_style(Color("#24231eef")))
	b.add_theme_stylebox_override("hover", box_style(Color("#5a5134"), Color("#ffe12c")))
	b.add_theme_stylebox_override("pressed", box_style(Color("#75643b")))
	b.pressed.connect(callback)
	parent.add_child(b)
	UI_MOTION.bind_button(b)
	return b

func _build() -> void:
	surface = SubViewportContainer.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.stretch = true
	add_child(surface)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	surface.add_child(viewport)
	world = WORLD.new()
	viewport.add_child(world)
	world.initialize(state)
	surface.gui_input.connect(_world_input)
	surface.mouse_exited.connect(func(): world.clear_preview(); preview_label.hide())
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	ui = HUD.new()
	ui.game = self
	hud.add_child(ui)
	cards = ui.cards
	card_nodes = ui.card_nodes
	turn_button = ui.turn_button
	turn_summary = label("",17,hud)
	turn_summary.add_theme_color_override("font_color",Color("#e6d7ad"))
	stats = label("", 15, hud)
	stats.add_theme_stylebox_override("normal", box_style(Color("#171914da")))
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.size.x = 212
	stats.hide()
	minimap = MINIMAP.new()
	hud.add_child(minimap)
	minimap.initialize(state)
	minimap.hide()
	minimap.focused.connect(func(tile): world.center_on(tile))
	var legend := label("指挥地图 · 点击定位\n蓝：队员  红：敌人  橙：补给", 12, hud)
	legend.name = "Legend"
	legend.hide()
	notice = label("", 16, hud)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_color_override("font_color", Color("#ffe39a"))
	notice.add_theme_stylebox_override("normal", box_style(Color("#191b17d9"), Color.TRANSPARENT))
	preview_label = label("", 16, hud)
	preview_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	preview_label.custom_minimum_size.x=300
	preview_label.size.x=300
	preview_label.add_theme_color_override("font_color", Color("#b8e6ff"))
	preview_label.add_theme_stylebox_override("normal", box_style(Color("#141e26e8"), Color("#76b2d2")))
	preview_label.hide()
	action_panel = PanelContainer.new()
	action_panel.add_theme_stylebox_override("panel", box_style(Color("#191b17fa"), Color("#e8cf51")))
	hud.add_child(action_panel)
	action_column = VBoxContainer.new()
	action_column.add_theme_constant_override("separation", 4)
	action_scroll = ScrollContainer.new()
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_panel.add_child(action_scroll)
	action_scroll.add_child(action_column)
	action_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_panel.hide()
	phase_paper = preload("res://scripts/horde_paper.gd").new()
	phase_paper.tint=Color("#e6c83b")
	phase_paper.teeth=18
	hud.add_child(phase_paper)
	phase_banner = label("",20,phase_paper)
	phase_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_banner.add_theme_color_override("font_color", Color("#1b1a16"))
	phase_banner.add_theme_font_size_override("font_size",22)
	phase_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	phase_banner.offset_left=20
	phase_banner.offset_top=3
	phase_banner.offset_right=-20
	phase_banner.offset_bottom=-10
	phase_paper.hide()
	wheel = WHEEL.new()
	hud.add_child(wheel)
	wheel.camera_drag_requested.connect(_begin_camera_drag)
	modal = MODAL.new()
	modal.game = self
	hud.add_child(modal)
	dialog = DIALOG.new()
	hud.add_child(dialog)
	dialog.confirmed.connect(_dialog_confirm)
	dialog.dismissed.connect(func(): refresh())
	inventory_panel = INVENTORY_PANEL.new()
	inventory_panel.game = self
	hud.add_child(inventory_panel)
	sound = AudioStreamPlayer.new()
	sound.volume_db = -12
	add_child(sound)

func _layout() -> void:
	if hud == null: return
	ui.fit(size)
	turn_summary.position=Vector2(16,80)
	turn_summary.size=Vector2(205,48)
	stats.position = Vector2(20, 155)
	minimap.position = Vector2(size.x-186, 155)
	minimap.size = Vector2(166, 185)
	hud.get_node("Legend").position = Vector2(size.x-210, 345)
	notice.position = Vector2(20, size.y-115)
	notice.size = Vector2(minf(920, size.x-40), 48)
	phase_paper.position=Vector2((size.x-520)*0.5,size.y*.21+8)
	phase_paper.size=Vector2(520,58)
	if action_panel.visible: position_actions()
	if wheel.visible: wheel.present(wheel.entries, wheel.anchor_pixel, size)

func blocked() -> bool:
	return busy or state.phase != "player" or dialog.visible or modal.visible or (inventory_panel != null and inventory_panel.visible)

func select_cop(index: int) -> void:
	if blocked() or state.cops[index].dead: return
	selected = index
	action_panel.hide()
	wheel.hide()
	world.center_on(state.cops[index].pos)
	refresh()

func refresh() -> void:
	if battle_audio != null: battle_audio.sync(state.wave, state.phase)
	if state.cops[selected].dead:
		for i in range(state.cops.size()):
			if not state.cops[i].dead:
				selected = i
				break
	ui.refresh()
	stats.text = "回合 %d  /  第 %d 波\n存活 %d/%d · 敌人 %d\n击杀 %d · 逮捕 %d\n反抗点数 %d\n\n%s" % [state.turn, state.wave, state.living_cops().size(), state.cops.size(), state.active_enemies().size(), state.killed, state.arrested, state.points, "本回合结束：新一波入场" if state.wave_due() else "距下一波还有 %d 回合" % state.next_wave_in()]
	var summary := "罪犯 %d · 第 %d 波\n第 %d 回合" % [state.active_enemies().size(),state.wave,state.turn]
	if turn_summary.text!=summary:
		turn_summary.text=summary
		var ticker:=turn_summary.create_tween()
		ticker.tween_property(turn_summary,"modulate:a",.55,.055)
		ticker.tween_property(turn_summary,"modulate:a",1.0,.17).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var message: String = str(state.log.back()) if not state.log.is_empty() else ""
	if message != last_notice:
		last_notice = message
		notice.text = message
		notice_time = 5.0
		notice.show()
	world.sync(selected)
	minimap.selected = selected
	minimap.queue_redraw()
	_layout()
	if state.phase == "defeat": show_result()

func _world_input(event: InputEvent) -> void:
	if blocked() or wheel.visible: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _camera_hits_hud(event.position): return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			world.toggle_zoom()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			world.zoom(0.9)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			world.zoom(1.1)
			return
	if event is InputEventMouseMotion:
		if camera_drag_held: return
		if action_panel.visible: return
		var tile: Vector2i = world.pick_tile(event.position)
		var cost: int = world.draw_preview(tile)
		preview_label.visible = cost > 0
		preview_label.text = "移动 %d AP · 剩余 %d AP\n%s\n单击确认；未知威胁不计入预览" % [cost,maxi(0,int(state.cops[selected].ap)-cost),world.movement_hint(tile) if cost>0 else ""]
		preview_label.position = Vector2(clampf(event.position.x + 20, 5, size.x - 320), clampf(event.position.y + 18, 120, size.y - 220))
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_begin_camera_drag(event.position)
		surface.accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT: return
	var marked_loot: Vector2i = world.pick_loot_marker(event.position)
	if marked_loot.x >= 0:
		show_loot(marked_loot)
		return
	var unit: Dictionary = world.pick_unit(event.position)
	if not unit.is_empty():
		if unit.side == "cop":
			if (int(unit.bleed) > 0 or unit.wound!="") and int(unit.id) != int(state.cops[selected].id): show_heal(unit)
			elif int(unit.id) == int(state.cops[selected].id): show_self()
			else: select_cop(state.cops.find(unit))
		else: show_enemy(unit)
		return
	var tile: Vector2i = world.pick_tile(event.position)
	# Prefer actual case hitboxes over floor selection.
	for p in state.loot:
		var case_position: Vector3 = world.cases[p].global_position if world.cases.has(p) else world.grid(p, 0.35)
		if event.position.distance_to(world.camera.unproject_position(case_position)) < 20:
			show_loot(p)
			return
	var edge: int = world.pick_opening(event.position)
	if edge >= 0:
		show_opening(edge)
		return
	if state.loot.has(tile):
		show_loot(tile)
		return
	action_panel.hide()
	await do_move(tile)

func _camera_hits_hud(at: Vector2) -> bool:
	# Some HUD buttons ignore right-clicks and pass them to the viewport.
	# Hit-test their visible bounds so an ignored UI click cannot grab the map.
	for control in card_nodes + [ui.gear, ui.command, turn_button, ui.compact, ui.drawer, minimap, action_panel]:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(at): return true
	return false

func _begin_camera_drag(at: Vector2) -> void:
	if blocked() or _camera_hits_hud(at): return
	camera_drag_held = true
	camera_drag_started = false
	camera_drag_origin = at
	camera_drag_last = at
	action_panel.hide()
	wheel.hide()
	preview_label.hide()
	world.clear_preview()
	ui.collapse()

func _end_camera_drag() -> void:
	camera_drag_held = false
	camera_drag_started = false
	if surface != null: surface.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _input(event: InputEvent) -> void:
	if reaction_waiting and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		choose_reaction("")
		get_viewport().set_input_as_handled()
		return
	# Once a battlefield drag starts, receive motion/release even over the HUD.
	# Never start a drag from a normal HUD button or through a pause dialog.
	if not camera_drag_held: return
	if blocked():
		_end_camera_drag()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			_end_camera_drag()
			# GUI must also see release, to clear its captured mouse target.
			# World input ignores button-up, so this cannot issue a move.
		elif event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) == 0 or not Rect2(Vector2.ZERO, size).has_point(event.position):
			_end_camera_drag()
			return
		if not camera_drag_started and event.position.distance_to(camera_drag_origin) >= CAMERA_DRAG_THRESHOLD:
			camera_drag_started = true
			surface.mouse_default_cursor_shape = Control.CURSOR_DRAG
		if camera_drag_started:
			world.drag_view(camera_drag_last, event.position)
			camera_drag_last = event.position
		get_viewport().set_input_as_handled()

func do_move(tile: Vector2i) -> void:
	if blocked(): return
	var c: Dictionary = state.cops[selected]
	var route: Array = state.move(c, tile, true)
	if route.is_empty():
		refresh()
		return
	busy = true
	preview_label.hide()
	battle_audio.confirm_move(c)
	await world.move_unit(c, route)
	busy = false
	refresh()

func begin_actions(title: String, target: Dictionary) -> void:
	wheel.hide()
	ui.collapse()
	for child in action_column.get_children():
		action_column.remove_child(child)
		child.queue_free()
	pending_target = target
	body_selector=null
	label(title, 19, action_column)
	action_panel.custom_minimum_size.x = 365
	action_panel.show()
	UI_MOTION.reveal(action_panel)
	preview_label.hide()
	position_actions.call_deferred()

func position_actions() -> void:
	action_scroll.custom_minimum_size = Vector2(550 if body_selector != null and size.x>=1100 else 365,minf(action_column.get_combined_minimum_size().y,maxf(160,size.y-210)))
	action_panel.reset_size()
	var top := minf(122,size.y*.17)
	action_panel.position = Vector2(clampf(size.x * 0.5 - action_panel.size.x * 0.5, 10, size.x - action_panel.size.x - 10), clampf(size.y * 0.5 - action_panel.size.y * 0.5, top, maxf(top, size.y - 85 - action_panel.size.y)))
	if pending_target.has("pos"):
		var target_x: float = world.camera.unproject_position(world.grid(pending_target.pos)).x
		action_panel.position.x = 16 if target_x > size.x*.5+20 else size.x-action_panel.size.x-16

func close_action_button() -> void:
	button("取消 [右键 / Esc]", action_column, func(): action_panel.hide())

func show_loot(tile: Vector2i) -> void:
	if not state.loot.has(tile): return
	var record: Dictionary = state.loot[tile]
	begin_actions("补给 · " + state.loot_name(record), {"tile": tile})
	if state.can_collect_at(state.cops[selected].pos, tile):
		if record.category == "Weapon" or record.item in ["BodyArmor", "Helmet"]:
			button("搜集并装备 / 更换 · 0 AP", action_column, collect_loot.bind(tile,"equip"))
			button("收入物品栏，保留当前装备 · 0 AP", action_column, collect_loot.bind(tile,"bag"))
			label("更换时，旧装备及其弹药 / 耐久会收入背包。", 14, action_column)
			if record.category == "Weapon":
				var ammo: int = int(record.get("ammo", STATE.CAPACITY[record.item])) + int(record.get("extra", 2 if record.item in ["Rifle","Shotgun"] else 0))
				var b := button("只取弹药（%d 发），留下枪 · 0 AP" % ammo, action_column, collect_loot.bind(tile,"ammo"))
				b.disabled = ammo <= 0
		else: button("搜集 · 0 AP", action_column, collect_loot.bind(tile,"equip"))
	else:
		label("先移动到箱子旁，再搜集。", 15, action_column)
		var approach := approach_to(tile)
		if approach.x >= 0:
			button("移动到补给旁", action_column, func(): action_panel.hide(); do_move(approach))
		else: label("本回合无法到达，请靠近或结束回合。", 14, action_column)
	close_action_button()

func collect_loot(tile: Vector2i, mode: String) -> void:
	if blocked(): return
	if not state.loot.has(tile) or not state.can_collect_at(state.cops[selected].pos,tile): return
	busy = true
	action_panel.hide()
	await action_player.interact(state.cops[selected],tile,func(): state.collect(state.cops[selected],tile,mode))
	busy = false
	refresh()
	if mode == "ammo" and state.loot.has(tile): show_loot(tile)

func show_inventory() -> void:
	if blocked(): return
	wheel.hide()
	action_panel.hide()
	ui.collapse()
	inventory_panel.show_for(state.cops[selected])

func show_trade() -> void:
	if blocked(): return
	var c: Dictionary = state.cops[selected]
	begin_actions("选择交换物品的队员 · 0 AP", c)
	for other: Dictionary in state.cops:
		if other.id == c.id or other.dead: continue
		var reason: String = STATE.INVENTORY.trade_reason(state,c,other)
		var b := button(str(other.name) + (" · " + reason if not reason.is_empty() else " · 交换"),action_column,func():
			action_panel.hide()
			inventory_panel.show_for(c,other))
		b.disabled = not reason.is_empty()
	close_action_button()

func approach_to(tile: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var cost := INF
	for p in world.reached.costs:
		if state.can_collect_at(p, tile) and float(world.reached.costs[p]) < cost and p != state.cops[selected].pos:
			best = p
			cost = float(world.reached.costs[p])
	return best

func show_opening(edge: int) -> void:
	var is_open: bool = state.nav.kind(edge) in [3, 4]
	begin_actions(("关闭" if is_open else "打开") + "门窗 · 1 AP", {"edge": edge})
	var c: Dictionary = state.cops[selected]
	if c.pos in state.nav.edge_pair(edge):
		var b := button("关闭入口" if is_open else "打开入口", action_column, func():
			if is_open: state.close_entry(c, edge)
			else: state.open(c, edge)
			action_panel.hide()
			refresh())
		b.disabled = int(c.ap) < 1
	else:
		label("请先移动到入口旁的相邻格。", 15, action_column)
		for tile in state.nav.edge_pair(edge):
			if world.reached.costs.has(tile): button("移动到入口旁", action_column, func(): action_panel.hide(); do_move(tile)); break
	close_action_button()

func show_enemy(e: Dictionary) -> void:
	var c: Dictionary = state.cops[selected]
	pending_target = e
	var entries: Array = []
	var choices := [["knife", "匕首"], ["shoot", "射击"], ["aim", "精准射击"], ["surrender", "喝止"], ["arrest", "逮捕"], ["remote_arrest", "远距离逮捕"], ["taser", "泰瑟枪"], ["grenade", "震撼弹"]]
	var icons := {"knife": "Knife", "shoot": "Gun", "aim": "AimedShot", "surrender": "MisterFreeze", "arrest": "Arrest", "remote_arrest": "OrderToSurrender", "taser": "Taser", "grenade": "Grenade"}
	var descriptions := {"knife": "近身攻击目标。", "shoot": "选择射击部位，查看当前命中率。", "aim": "消耗两点行动力进行精准射击。", "surrender": "喝令目标举手投降。", "arrest": "逮捕已投降或昏迷的敌人。", "remote_arrest": "使用技能从远处逮捕目标。", "taser": "使用泰瑟枪使目标昏迷。", "grenade": "范围内所有人都可能被波及，包括队友。"}
	for choice in choices:
		var action: String = choice[0]
		if action == "aim" and "AimedShot" not in c.skills: continue
		if action == "remote_arrest" and "OrderToSurrender" not in c.skills: continue
		var callback := func():
			if action in ["shoot", "aim"]: show_aim(e, action)
			else: execute_attack(e, action)
		entries.append({"id": action, "label": choice[1], "icon": icons[action], "reason": state.action_reason(c, e, action), "cost": 2 if action == "aim" else 1, "description": descriptions[action], "run": callback, "loud": action in ["shoot", "aim", "grenade"]})
		if action in ["shoot","aim"]: entries.back()["chance"]=state.shot_details(c,e,"躯干",action=="aim").chance
	if not state.action_reason(c,e,"shoot").is_empty() and int(c.ap)>=2 and c.gun!="" and int(c.weapons.get(c.gun,0))>0:
		var destination := firing_position(c,e)
		if destination.x>=0:
			entries.append({"id":"reposition","label":"移动到可射击位置","icon":"Interact","reason":"","cost":1,"description":"移动到 (%d, %d)，保留行动点；到位后再选择目标射击。" % [destination.x,destination.y],"run":func(): do_move(destination)})
	present_wheel(entries, e.pos)

func firing_position(c: Dictionary,e: Dictionary) -> Vector2i:
	var tiles: Array = world.reached.costs.keys()
	tiles.sort_custom(func(a,b): return float(world.reached.costs[a])<float(world.reached.costs[b]))
	var scanned := 0
	for tile: Vector2i in tiles:
		if tile==c.pos or float(world.reached.costs[tile])>state.move_distance(c)*1.4 or not state.tile_visible(tile): continue
		scanned+=1
		var candidate: Dictionary=c.duplicate()
		candidate.pos=tile
		candidate.ap=int(c.ap)-1
		if state.action_reason(candidate,e,"shoot").is_empty(): return tile
		if scanned>=32: break
	return Vector2i(-1,-1)

func present_wheel(entries: Array, tile: Vector2i) -> void:
	action_panel.hide()
	preview_label.hide()
	ui.collapse()
	wheel.present(entries, world.camera.unproject_position(world.grid(tile, 0.8)), size)

func show_self() -> void:
	if blocked(): return
	var c: Dictionary = state.cops[selected]
	pending_target = c
	var reload_reason := "尚未持有枪械" if c.gun == "" else "手臂受伤，不能装填" if c.wound == "手臂" else "暂时无法行动" if int(c.stun)>0 else "弹匣已满" if int(c.weapons[c.gun]) >= int(STATE.CAPACITY[c.gun]) else "没有备用弹药" if int(c.reserve.get(c.gun, 0)) <= 0 else ""
	var entries := [
		{"id": "trade", "label": "交换物品", "icon": "Trade", "description": "与相邻队员交换枪械、防具、弹药和补给。", "reason": "", "cost": 0, "run": show_trade},
		{"id": "small_heal", "label": "小急救包", "icon": "MedkitSmall", "cost": 1, "description": "治愈手脚伤；躯干伤仅止血，仍然倒地。", "reason": state.heal_reason(c,c,"SmallMedkit"), "run": do_heal.bind(c,"SmallMedkit")},
		{"id": "big_heal", "label": "大急救包", "icon": "MedkitBig", "cost": 1, "description": "治愈伤势；躯干重伤者恢复行动。", "reason": state.heal_reason(c,c,"BigMedkit"), "run": do_heal.bind(c,"BigMedkit")},
		{"id": "switch", "label": "装备与背包", "icon": "SwitchWeapon", "description": "选择手枪 / 左轮、长枪和防具；支持存入、换装和卸下弹药。", "reason": "", "run": show_inventory},
		{"id": "throw", "label": "扔", "icon": "PassAmmo", "description": "扔一个弹夹给目标。", "reason": "投递弹夹尚未接入"},
		{"id": "skills", "label": "警员特技", "icon": "AimedShot", "description": "查看这名警员的属性与已拥有的特技。", "reason": "", "run": show_skills},
		{"id": "supply", "label": "寻找补给", "icon": "Interact", "description": "定位最近的可达补给箱，显示靠近路线。", "reason": "", "run": locate_loot},
		{"id": "reload", "label": "装填", "icon": "Reload", "cost": 0, "description": "使用备用弹药装填，不消耗行动点。手臂受伤时不能装填。", "reason": reload_reason, "run": do_reload},
		{"id": "grenade", "label": "震撼手雷", "icon": "Grenade", "cost": 1, "loud": true, "description": "关闭菜单后点击敌人，再选择震撼弹指定目标。", "reason": "没有震撼手雷" if c.supplies.get("Grenade", 0) <= 0 else "", "run": func(): state.say("点击敌人，在动作菜单中选择震撼弹指定目标。"); refresh()}
	]
	present_wheel(entries, c.pos)

func show_aim(e: Dictionary, action: String) -> void:
	begin_actions("选择射击部位 · " + str(e.name), e)
	var c: Dictionary = state.cops[selected]
	label("%s · %d AP · 消耗 1 发（已装 %d 发）" % [STATE.NAMES.get(c.gun,c.gun),2 if action == "aim" else 1,int(c.weapons.get(c.gun,0))],14,action_column)
	var reason: String = state.action_reason(c,e,action)
	var explanations := add_body_choices(c,e,action=="aim",reason,func(part): execute_attack(e,action,part))
	var shot: Dictionary = state.shot_details(c,e,"躯干",action == "aim")
	label("%s · 射击距离 %.1f / %d 格 · %s" % [STATE.NAMES.get(c.gun,c.gun),float(shot.distance),int(shot.range),["无遮蔽","低掩体","高掩体"][int(shot.cover)]], 12, action_column)
	if shot.trace.from != c.pos: label("从掩体侧边探身射击",12,action_column)
	if shot.trace.to != e.pos: label("瞄准目标掩体侧边；仍受掩体保护",12,action_column)
	if float(shot.fence) < 1: label("射线穿过栅栏，命中率降低。",12,action_column)
	if not reason.is_empty(): label("不可用："+reason,12,action_column)
	var details_button := button("查看命中依据（也可悬停部位）",action_column,func(): pass)
	var factors := label("\n".join(explanations),11,action_column)
	factors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	factors.custom_minimum_size.x = 350
	factors.hide()
	details_button.pressed.connect(func():
		factors.visible = not factors.visible
		details_button.text = "收起命中依据" if factors.visible else "查看命中依据（也可悬停部位）"
		position_actions.call_deferred())
	close_action_button()

func add_body_choices(c: Dictionary,e: Dictionary,aim: bool,reason: String,execute: Callable) -> Array[String]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	action_column.add_child(row)
	body_selector=BODY_SELECTOR.new()
	row.add_child(body_selector)
	var values: Dictionary={}
	for part in BODY_SELECTOR.PARTS: values[part]=state.shot_details(c,e,part,aim).chance
	body_selector.setup(values,not reason.is_empty(),execute)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	choices.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	row.add_child(choices)
	var explanations: Array[String]=[]
	for part in BODY_SELECTOR.PARTS:
		var detail: Dictionary=state.shot_details(c,e,part,aim)
		var effect := "致命（防具可挡）" if part=="头" or e.wound!="" else "倒地 / 失血 3 回合" if part=="躯干" else "受伤 / 失血 5 回合"
		var choice := button("%s · 命中 %d%% · %s" % [part,roundi(float(detail.chance)*100),effect],choices,execute.bind(part))
		choice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		choice.disabled=not reason.is_empty()
		choice.focus_mode=Control.FOCUS_ALL
		choice.tooltip_text=reason if not reason.is_empty() else "\n".join(detail.get("factors",[]))
		choice.mouse_entered.connect(body_selector.select.bind(part))
		choice.focus_entered.connect(body_selector.select.bind(part))
		explanations.append(part+"："+"；".join(detail.get("factors",[])))
	return explanations

func execute_attack(e: Dictionary, action: String, part := "躯干") -> void:
	if blocked(): return
	state.take_events()
	var accepted: bool = state.attack(state.cops[selected], e, action, part)
	action_panel.hide()
	if accepted:
		busy = true
		await action_player.play(state.take_events())
		busy = false
	refresh()

func show_heal(target: Dictionary) -> void:
	begin_actions("%s · %s" % [target.name,"失血 %d 回合" % target.bleed if target.bleed>0 else "已止血，伤势尚未治愈"], target)
	for item: String in ["SmallMedkit","BigMedkit"]:
		var reason: String = state.heal_reason(state.cops[selected],target,item)
		var treatment := "止血，仍然倒地" if item=="SmallMedkit" and target.wound=="躯干" else "治愈伤势"
		var option := button("%s · %s · 1 AP%s" % [STATE.NAMES[item],treatment,"" if reason.is_empty() else " · "+reason],action_column,do_heal.bind(target,item))
		option.disabled = not reason.is_empty()
	button("选择这名队员", action_column, select_cop.bind(state.cops.find(target)))
	close_action_button()

func do_reload() -> void:
	if blocked(): return
	var c: Dictionary = state.cops[selected]
	if c.gun == "": state.say("尚无枪械，先搜集武器箱。")
	elif c.wound == "手臂": state.say("手臂受伤，不能装填。")
	else:
		state.take_events()
		if state.reload(c):
			busy = true
			await action_player.play(state.take_events())
			busy = false
	refresh()

func switch_gun() -> void:
	if blocked(): return
	var c: Dictionary = state.cops[selected]
	var guns: Array = c.weapons.keys()
	if guns.is_empty(): state.say("尚未找到枪械，点击红色补给箱搜集。")
	else: c.gun = guns[(guns.find(c.gun) + 1) % guns.size()]
	refresh()

func heal_self() -> void:
	if blocked(): return
	var c: Dictionary = state.cops[selected]
	show_heal(c)

func do_heal(target: Dictionary,item: String) -> void:
	if blocked(): return
	var c: Dictionary = state.cops[selected]
	var reason: String = state.heal_reason(c,target,item)
	if not reason.is_empty(): state.say(reason); refresh(); return
	action_panel.hide()
	wheel.hide()
	busy=true
	var was_down: bool = target.wound=="躯干"
	await action_player.interact(c,target.pos,func(): state.heal(c,target,item))
	if was_down and target.wound=="":
		var motion = world.actors[target.id].get_node("Motion")
		motion.wounded=""
		motion.start_clip("damage_body_getup_to_idle")
		await get_tree().create_timer(motion.duration("damage_body_getup_to_idle")).timeout
	busy=false
	refresh()

func locate_loot() -> void:
	if blocked(): return
	var c: Dictionary = state.cops[selected]
	var found: Dictionary = state.nav.search([c.pos], 10000, state.occupied(c.id))
	var best := Vector2i(-1, -1)
	var goal := best
	var distance := INF
	for p in state.loot:
		for offset in state.nav.DIRS + [Vector2i.ZERO]:
			var near: Vector2i = p + offset
			if found.costs.has(near) and state.can_collect_at(near, p) and float(found.costs[near]) < distance:
				best = p
				goal = near
				distance = float(found.costs[near])
	if best.x < 0:
		state.say("暂时没有可通行到达的补给；请打开门窗或换一名队员。")
		refresh()
		return
	world.center_on(Vector2i((Vector2(c.pos) + Vector2(best)) * 0.5))
	var route: Array = state.nav.path(c.pos, goal, found.parents)
	var waypoint: Vector2i = c.pos
	for p in route:
		if world.reached.costs.has(p): waypoint = p
	state.say("最近可达补给：%s；蓝线指向本回合可到达的位置。" % state.loot_name(state.loot[best]))
	refresh()
	world.draw_preview(waypoint)
	begin_actions("搜集补给 · " + state.loot_name(state.loot[best]), {"tile": best})
	if state.can_collect_at(c.pos, best): button("查看补给 / 选择拾取方式", action_column, show_loot.bind(best))
	elif waypoint != c.pos: button("沿路线靠近补给", action_column, func(): action_panel.hide(); do_move(waypoint))
	else: label("行动点不足，结束回合后继续。", 15, action_column)
	close_action_button()

func end_turn() -> void:
	if blocked(): return
	wheel.hide()
	ui.collapse()
	busy = true
	action_panel.hide()
	preview_label.hide()
	var previous_wave: int=state.wave
	state.begin_enemy_turn()
	announce_phase("第 %d 波 · 敌方行动" % state.wave if state.wave>previous_wave else "敌人行动 · 可见行动会跟随镜头",false)
	refresh()
	await get_tree().create_timer(0.25).timeout
	for e in state.active_enemies():
		for action in range(state.enemy_action_limit(e)+2):
			if int(e.ap)<=0: break
			if state.phase == "defeat": break
			await offer_overwatch(e,state.enemy_shot_target(e))
			if e.dead or e.captured: break
			state.take_events()
			var outcome: Dictionary = state.enemy_action(e,true)
			if outcome.get("kind") == "move" and not outcome.route.is_empty():
				e.pos = outcome.from
				e.moving_exposed = true
				await world.play_enemy_move(e, outcome.route, outcome.from, quick_enemy,_enemy_step.bind(e))
				e.erase("moving_exposed")
			await action_player.play(state.take_events())
			var reactions: Array = state.reaction_queue.duplicate()
			state.reaction_queue.clear()
			await play_reactions(reactions)
			refresh()
		await get_tree().process_frame
	state.finish_enemy_turn()
	await action_player.play(state.take_events())
	phase_paper.hide()
	busy = false
	refresh()
	if state.phase=="player": announce_phase("第 %d 回合 · 你的行动" % state.turn,true,.95)
	if state.phase == "player" and world.follow_actions: world.center_on(state.cops[selected].pos)
	if state.phase == "player" and not auto_start: save_game(true)

func show_help() -> void:
	if busy: return
	wheel.hide()
	action_panel.hide()
	dialog.present("help", "义军呐喊 · 生存规则", "四名警员持匕首开局，先搜集补给。第 3 回合结束后首波敌人入场，此后每隔 5 回合一波，第 40 回合获得增援。\n\n1–5 选人；左键地面移动，点击敌人、补给和门窗选择动作。\n低掩体降低命中率；高掩体有侧边开口时可以探身射击。\nL 定位补给，B 背包，I 展开装备，C 指挥中心，M 战况地图。\n枪械、防具可存入背包；可只取弹药、卸弹、丢枪和相邻交换。\n搜集、整理、交换、装填为 0 AP；开门与普通攻击为 1 AP。\n滚轮缩放，按住右键拖动；WASD 平移，空格定位，Enter 结束回合。\n\nF5 保存；你的回合开始时自动保存。暂停菜单可调音量、播放速度和镜头跟随。全员阵亡后结算。", "进入战场")

func show_skills() -> void:
	if blocked(): return
	var c: Dictionary = state.cops[selected]
	var text := "速度 %d · 力量 %d · 射击 %d\n\n" % [c.speed, c.strength, c.shooting]
	for skill in c.skills: text += "%s：%s\n\n" % [state.data.texts.get(skill + "_ActionName", skill), state.data.texts.get(skill + "_ActionDescription", "")]
	text += "技能效果已接入学习版战斗；概率、冷却与原版仍有差异。"
	dialog.present("skills", str(c.name) + " · 随机技能", text, "返回战场")

func show_menu() -> void:
	if busy: return
	modal.present_pause()

func show_command() -> void:
	if blocked(): return
	modal.present_command()

func use_command(command: String) -> void:
	if busy or state.phase != "player": return
	state.take_events()
	if not state.use_command(command): return
	modal.close()
	busy = true
	await action_player.play(state.take_events())
	busy = false
	refresh()

func choose_reaction(part: String, serial := -1) -> void:
	if not reaction_waiting or (serial >= 0 and serial != reaction_serial): return
	reaction_waiting = false
	action_panel.hide()
	reaction_chosen.emit(part)

func play_reactions(requests: Array) -> void:
	for request: Dictionary in requests:
		if request.get("resolved",true): continue
		var c: Dictionary = request.cop
		var e: Dictionary = request.enemy
		if not state.reaction_ready(c,e,state.current_shot_range(c)): continue
		c.counter = true
		begin_actions("%s · %s → %s" % [request.kind,c.name,e.name],e)
		phase_banner_serial+=1
		if phase_banner_tween!=null and phase_banner_tween.is_valid(): phase_banner_tween.kill()
		reaction_serial += 1
		reaction_waiting = true
		phase_banner.text = request.kind+"：选择部位，或放弃射击"
		phase_paper.show()
		phase_paper.modulate.a=1
		if world.follow_actions: world.center_on(e.pos)
		var serial := reaction_serial
		add_body_choices(c,e,false,"",func(part): choose_reaction(part,serial))
		button("放弃本次射击 [右键 / Esc]",action_column,choose_reaction.bind("",reaction_serial))
		var part: String = await reaction_chosen
		state.take_events()
		if state.resolve_reaction(request,part): await action_player.play(state.take_events())
		phase_banner.text = "敌人回合"

func announce_phase(text: String,player_turn: bool,hold := .78) -> void:
	phase_banner_serial+=1
	var serial:=phase_banner_serial
	if phase_banner_tween!=null and phase_banner_tween.is_valid(): phase_banner_tween.kill()
	phase_banner.text=text
	phase_banner.add_theme_color_override("font_color",Color("#211d10") if player_turn else Color("#fff3e7"))
	phase_paper.tint=Color("#efd139") if player_turn else Color("#b74c40")
	phase_paper.modulate.a=0
	phase_paper.position.y=size.y*.21+2
	phase_paper.show()
	phase_banner_tween=create_tween()
	phase_banner_tween.set_parallel(true)
	phase_banner_tween.tween_property(phase_paper,"modulate:a",1,.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	phase_banner_tween.tween_property(phase_paper,"position:y",size.y*.21+8,.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	phase_banner_tween.set_parallel(false)
	phase_banner_tween.tween_interval(hold)
	phase_banner_tween.tween_property(phase_paper,"modulate:a",0,.2)
	phase_banner_tween.tween_callback(func():
		if phase_banner_serial==serial: phase_paper.hide())

func offer_overwatch(e: Dictionary, shot_target_id := -1) -> void:
	await play_reactions(state.overwatch_requests(e,shot_target_id))

func _enemy_step(tile: Vector2i,e: Dictionary) -> bool:
	e.pos = tile
	var before: Array = e.get("visible_ids",[]).duplicate()
	var seen: Array = state.enemy_targets(e)
	if world.actors.has(e.id) and world.actors[e.id].visible:
		phase_banner.text = "%s · %s" % [e.name,e.get("intent","移动")]
	await offer_overwatch(e)
	return e.dead or e.captured or int(e.stun)>0 or seen.any(func(c): return c.id not in before)

func _dialog_confirm(value: String) -> void:
	modal.hide()
	if value in ["restart", "menu"]:
		dialog.present("confirm_" + value, "确认离开当前局？", "继续游戏将恢复最近一次手动或回合自动存档。离开前可返回暂停菜单保存当前战局。", "确认")
		dialog.cancel.show()
	elif value == "confirm_restart": get_tree().reload_current_scene()
	elif value == "confirm_menu" or value == "result_menu": get_tree().change_scene_to_file("res://scenes/mode_menu.tscn")
	elif value == "speed":
		quick_enemy = not quick_enemy
		show_menu()
	else: dialog.close()

func show_journal() -> void:
	if blocked(): return
	begin_actions("战报 · 仅记录当时可知的信息",{})
	if state.observed_events.is_empty(): label("尚无已观察到的战斗事件。",15,action_column)
	var records: Array = state.observed_events.duplicate()
	records.reverse()
	for record: Dictionary in records:
		var b := button("第 %d 回合 · %s" % [record.turn,record.text],action_column,func(): world.center_on(record.tile); action_panel.hide())
		b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size",14)
	close_action_button()

func show_result() -> void:
	if result_written: return
	result_written = true
	var result: Dictionary = state.result()
	# Only the completed run is persisted, never source assets or original saves.
	var history: Array = []
	var path := results_path
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array: history = parsed
	history.push_front(result)
	history = history.slice(0, 20)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(history, "\t"))
	dialog.present("result", "行动结束 · 全员阵亡", "坚持 %d 回合 · 遭遇 %d 波\n击杀 %d · 逮捕 %d\n搜集 %d 个补给箱 · 反抗点数 %d\n\n%s" % [state.turn, state.wave, state.killed, state.arrested, state.collected, state.points, "已保存本地战绩；可重新部署随机小队。" if file else "战绩文件无法写入，当前结算仍可查看。"], "查看战场")
	dialog.add_choice("重新挑战", "confirm_restart")
	dialog.add_choice("返回模式选择", "result_menu")

func _unhandled_key_input(event: InputEvent) -> void:
	if reaction_waiting:
		if event.is_pressed() and event.keycode == KEY_ESCAPE: choose_reaction("")
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed() or event.is_echo() or dialog.visible or modal.visible or wheel.visible: return
	if event.keycode == KEY_ESCAPE:
		if action_panel.visible: action_panel.hide()
		else: show_menu()
		return
	if blocked(): return
	if event.keycode >= KEY_1 and event.keycode <= KEY_5:
		var index: int = event.keycode - KEY_1
		if index < state.cops.size(): select_cop(index)
	match event.keycode:
		KEY_ENTER: end_turn()
		KEY_SPACE: world.center_on(state.cops[selected].pos)
		KEY_L: locate_loot()
		KEY_R: do_reload()
		KEY_I: ui.toggle_equipment()
		KEY_B: show_inventory()
		KEY_C: show_command()
		KEY_J: show_journal()
		KEY_M:
			minimap.visible = not minimap.visible
			stats.visible = minimap.visible
			hud.get_node("Legend").visible = minimap.visible
		KEY_F1: show_help()
		KEY_F5: save_game()

func _process(delta: float) -> void:
	if camera_drag_held and blocked(): _end_camera_drag()
	if world != null and (blocked() or wheel.visible or action_panel.visible):
		world.clear_preview()
		preview_label.hide()
	notice_time -= delta
	if notice != null: notice.visible = notice_time > 0 and not ui.drawer.visible and not wheel.visible and not modal.visible
	if world == null or blocked() or wheel.visible or camera_drag_held: return
	var move := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if move != Vector2.ZERO: world.pan(move.normalized() * delta * world.camera.size * 0.65)
