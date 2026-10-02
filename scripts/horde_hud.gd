extends Control

const UI = preload("res://scripts/horde_ui_theme.gd")
const PAPER = preload("res://scripts/horde_paper.gd")
const CARD = preload("res://scripts/horde_portrait.gd")
const SLOT = preload("res://scripts/horde_item_slot.gd")
const MOTION = preload("res://scripts/horde_ui_motion.gd")
const PORTRAITS = preload("res://scripts/cop_portraits.gd")
const SKILLS = ["AimedShot", "OrderToSurrender", "SeeFar", "Fortification", "SecondCheek", "AdrenalineRush", "Bide", "SmoothOps", "Resilience"]
var game
var cards: Control
var card_nodes: Array = []
var turn_button: Button
var turn_paper: Control
var points: Label
var points_icon: TextureRect
var top: ColorRect
var compact: ColorRect
var equipment: Control
var drawer: ColorRect
var sections: Control
var gear: Button
var command: Button
var journal: Button
var awareness_label: Label
var awareness_clock:=0.0
var last_awareness:=""
var pinned := false
var drawer_hover := false
var leave_delay := 0.0
var ui_scale := 1.0
var pointer_position := Vector2(-1000, -1000)
var drawer_open := false
var hover_suppressed := false
var drawer_tween: Tween
var drawer_progress := 0.0:
	set(value):
		drawer_progress = value
		if drawer != null: drawer.position.y = size.y-76-164*value

func paper(parent: Node, rect: Rect2, color := UI.GOLD) -> Control:
	var p := PAPER.new()
	p.position = rect.position
	p.size = rect.size
	p.tint = color
	p.teeth = clampi(int(rect.size.x/15), 4, 20)
	parent.add_child(p)
	return p

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top = ColorRect.new()
	top.color = Color("#080809eb")
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	paper(self, Rect2(29, 1, 68, 103))
	paper(self, Rect2(160, 1, 69, 103))
	gear = UI.button(self, "", Rect2(29, 1, 68, 91), game.show_menu)
	gear.tooltip_text = "暂停 / 菜单 [Esc]"
	UI.icon(gear, "Options", Rect2(11, 23, 46, 46), UI.INK)
	command = UI.button(self, "", Rect2(160, 1, 69, 91), game.show_command)
	command.tooltip_text = "指挥中心 [C]"
	UI.icon(command, "Spellbook", Rect2(12, 22, 45, 49), UI.INK)
	journal = UI.button(self,"战报 [J]",Rect2(250,8,130,42),game.show_journal,22)
	journal.tooltip_text="查看已知战斗事件；点击记录定位"
	awareness_label=UI.text(self,"未确认暴露",Rect2(250,54,260,64),19)
	awareness_label.add_theme_color_override("font_shadow_color",Color("#080a08"))
	awareness_label.add_theme_constant_override("shadow_offset_x",1)
	awareness_label.add_theme_constant_override("shadow_offset_y",1)
	awareness_label.tooltip_text="注意敌人朝向。黄色 ? 表示怀疑或调查；红色 ! 表示确认发现；失去目击后仍可能追踪最后位置。"
	cards = Control.new()
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cards)
	turn_paper = paper(self, Rect2(1606, 1, 276, 82))
	turn_button = UI.button(self, "结束回合", Rect2(1606, 1, 276, 68), game.end_turn, 26)
	turn_button.add_theme_color_override("font_color", UI.INK)
	turn_button.add_theme_color_override("font_hover_color", UI.INK)
	turn_button.tooltip_text = "结束回合 [Enter]"
	points_icon = UI.icon(self, "RebelPoint", Rect2(1490, 7, 32, 32))
	points = UI.text(self, "0", Rect2(1530, 4, 66, 34), 23, UI.GOLD)
	compact = ColorRect.new()
	compact.color = Color("#090909eb")
	compact.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(compact)
	compact.mouse_entered.connect(func():
		if hover_suppressed: return
		drawer_hover = true
		leave_delay=.2
		set_drawer(true))
	compact.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pinned = not pinned
			set_drawer(pinned or drawer_hover))
	compact.tooltip_text = "移入查看装备 · I 固定 / 收起 · M 战况地图 · F1 操作说明"
	equipment = Control.new()
	equipment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compact.add_child(equipment)
	drawer = ColorRect.new()
	drawer.color = Color("#070707f9")
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(drawer)
	sections = Control.new()
	sections.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.add_child(sections)
	drawer.hide()
	drawer.clip_contents = true
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	set_process(true)

func fit(view_size: Vector2) -> void:
	ui_scale = minf(view_size.x / 1920.0, view_size.y / 1080.0)*minf(1.0,float(game.settings.ui_scale))
	scale = Vector2.ONE * ui_scale
	size = view_size / ui_scale
	top.size = Vector2(size.x, 43)
	turn_paper.position.x = size.x - 314
	turn_button.position.x = size.x - 314
	points.position.x = size.x - 390
	points_icon.position.x = size.x - 430
	compact.position = Vector2(0, size.y - 76)
	compact.size = Vector2(size.x, 76)
	drawer.position = Vector2(0, size.y - 76 - 164*drawer_progress)
	drawer.size = Vector2(size.x, 240)
	sections.size = drawer.size
	# Four original recruits fit at their reference size; fifth reinforcement uses the same spacing.
	var span := 156.0 + maxf(0, card_nodes.size()-1)*130
	cards.position = Vector2((size.x-span)*0.5-50, 1)
	var x := 0.0
	for i in range(card_nodes.size()):
		var card: Control = card_nodes[i]
		MOTION.target(card,"position",^"position",Vector2(x,0))
		MOTION.target(card,"size",^"size",Vector2(156,210) if i == game.selected else Vector2(118,156))
		card.queue_redraw()
		x += 168 if i == game.selected else 130
	queue_redraw()

func refresh() -> void:
	var used_portraits: Array = []
	for existing in card_nodes: used_portraits.append(int(existing.get_meta("portrait_slot",-1)))
	while card_nodes.size() < game.state.cops.size():
		var index := card_nodes.size()
		var card := CARD.new()
		var cop: Dictionary = game.state.cops[index]
		var slot: int = PORTRAITS.choose(int(cop.get("gender",0)),cop.get("employee",cop.name),used_portraits)
		used_portraits.append(slot)
		card.set_meta("portrait_slot",slot)
		card.portrait = PORTRAITS.texture(slot)
		card.pressed.connect(game.select_cop.bind(index))
		cards.add_child(card)
		card_nodes.append(card)
	for i in range(card_nodes.size()):
		var c: Dictionary = game.state.cops[i]
		card_nodes[i].cop = c
		card_nodes[i].active = i == game.selected
		card_nodes[i].disabled = c.dead or game.busy
		card_nodes[i].tooltip_text = "%s · %d/%d AP · 数字键 %d\n%s" % [c.name, c.ap, c.max_ap, i+1, "阵亡" if c.dead else "点击选中；点击战场中的本人打开动作菜单"]
		card_nodes[i].queue_redraw()
	points.text = str(game.state.points)
	turn_button.text = "敌人行动中" if game.state.phase=="enemy" else "请稍候…" if game.busy else "结束回合"
	turn_button.disabled = game.busy or game.state.phase != "player"
	turn_paper.modulate = Color("#a9a49a") if game.busy else Color.WHITE
	_rebuild_equipment()
	fit(game.size)

func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func tip_icon(parent: Node, key: String, rect: Rect2, tip: String, enabled := true) -> Control:
	var hit := Control.new()
	hit.position = rect.position
	hit.size = rect.size
	hit.tooltip_text = tip
	parent.add_child(hit)
	UI.icon(hit, key, Rect2(Vector2.ZERO, rect.size), UI.GOLD if enabled else Color("#655d2f"))
	if key in game.STATE.GUNS or key in ["Armor", "Helmet"]:
		hit.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				game.show_inventory()
				hit.accept_event())
	return hit

func _rebuild_equipment() -> void:
	clear(equipment)
	clear(sections)
	var c: Dictionary = game.state.cops[game.selected]
	var width: float = maxf(1920, size.x)
	var sx := width / 1920.0
	var status := [["Helmet", c.helmet, "头盔：" + ("已装备" if c.helmet else "无")],
		["Armor", c.armor > 0, "护甲耐久 %d" % c.armor], ["Death", c.dead, "阵亡" if c.dead else "生命状态正常"],
		["TorsoInjury", c.bleed > 0, "失血剩余 %d 回合" % c.bleed if c.bleed > 0 else "没有失血伤口"]]
	for i in range(status.size()):
		tip_icon(equipment, status[i][0], Rect2((365+i*72)*sx, 13, 49, 49), status[i][2], status[i][1])
	if c.gun != "":
		UI.text(equipment, str(c.weapons[c.gun]), Rect2(25, 13, 52, 49), 31)
		tip_icon(equipment, c.gun, Rect2(85, 13, 80, 48), "%s · 备用弹药 %d · 装填 [R]" % [game.STATE.NAMES[c.gun], c.reserve.get(c.gun, 0)])
	tip_icon(equipment, "Knife", Rect2(width-120, 9, 65, 60), "匕首 · 点击本人 / 敌人选择动作")
	var band := ColorRect.new()
	band.color = UI.GOLD
	band.size = Vector2(width, 33)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sections.add_child(band)
	var columns := [[0, 300, "枪支"], [300, 380, "护甲和伤情"], [680, 255, "技能"], [935, 505, "特技"], [1440, 140, "特殊能力"], [1580, 340, "物品栏"]]
	for col in columns:
		if col[2] != "物品栏": UI.text(sections, col[2], Rect2(col[0]*sx, 0, col[1]*sx, 33), 25, UI.INK, true)
	var manage := UI.button(sections,"物品栏 [B] ▸",Rect2(1580*sx,0,340*sx,33),game.show_inventory,23)
	manage.add_theme_color_override("font_color",UI.INK)
	manage.add_theme_color_override("font_hover_color",UI.INK)
	var guns: Array = c.weapons.keys()
	for i in range(maxi(2, guns.size())):
		var gun: String = guns[i] if i < guns.size() else "Rifle" if i == 0 else "Revolver"
		var y := 59.0 + (i%2)*78
		var x := (60.0 + floori(i/2.0)*128)*sx
		var owned := i < guns.size()
		tip_icon(sections, gun, Rect2(x, y, 118, 60), "%s · %s" % [game.STATE.NAMES[gun], "%d 发 / 备用 %d" % [c.weapons[gun], c.reserve.get(gun, 0)] if owned else "尚未持有"], owned)
		if owned: UI.text(sections, str(c.weapons[gun]), Rect2(x+116, y, 35, 60), 22, UI.GOLD)
	for i in range(2): tip_icon(sections, status[i][0], Rect2((398+i*91)*sx, 53, 64, 65), status[i][2], status[i][1])
	var wounds := [["Death", c.dead, "死亡"], ["TorsoInjury", c.bleed > 0, "失血"], ["LegInjury", c.wound == "腿", "腿部"], ["HandInjury", c.wound == "手臂", "手臂"], ["Armor", c.wound == "躯干", "躯干"]]
	for i in range(wounds.size()): tip_icon(sections, wounds[i][0], Rect2((336+i*65)*sx, 151, 50, 54), wounds[i][2] + ("受伤" if wounds[i][1] else "正常"), wounds[i][1])
	for i in range(3):
		var value := int(c[["strength", "shooting", "speed"][i]])
		UI.text(sections, ["力量", "射击", "速度"][i], Rect2(695*sx, 88+i*33, 65*sx, 27), 21)
		for n in range(3):
			var bar := ColorRect.new()
			bar.color = UI.GOLD if n < value else Color("#454545")
			bar.position = Vector2((776+n*42)*sx, 97+i*33)
			bar.size = Vector2(33*sx, 9)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sections.add_child(bar)
	for i in range(SKILLS.size()):
		var skill: String = SKILLS[i]
		var owned: bool = skill in c.skills
		var tip := str(game.state.data.texts.get(skill+"_ActionName", skill)) + (" · 已拥有" if owned else " · 未学习")
		tip += "\n" + str(game.state.data.texts.get(skill+"_ActionDescription", ""))
		tip_icon(sections, skill, Rect2((963+(i%5)*87)*sx, 62+floori(i/5.0)*90, 63, 65), tip, owned)
	add_slot(Rect2(1476*sx, 96, 70, 68))
	var items: Array = [["Knife", "匕首", 1]]
	for entry in c.bag:
		items.append([{"BodyArmor":"Armor"}.get(entry.item,entry.item), game.STATE.NAMES[entry.item] + (" · %d 发" % entry.ammo if entry.item in game.STATE.GUNS else " · 耐久 %d" % entry.durability), 1])
	for ammo in c.reserve:
		if int(c.reserve[ammo]) > 0: items.append([UI.ammo_icon(ammo),game.STATE.NAMES[ammo]+"备用弹药",int(c.reserve[ammo])])
	for item in c.supplies:
		if int(c.supplies[item]) > 0:
			var icon_name: String = {"BigMedkit": "MedkitBig", "SmallMedkit": "MedkitSmall"}.get(item, item)
			items.append([icon_name, game.STATE.NAMES.get(item, item), int(c.supplies[item])])
	for i in range(6):
		var rect := Rect2((1603+(i%3)*92)*sx, 54+floori(i/3.0)*86, 70, 68)
		add_slot(rect)
		if i == 5 and items.size() > 6:
			UI.button(sections,"+%d\n[B]" % (items.size()-5),rect,game.show_inventory,20)
			continue
		if i < items.size():
			tip_icon(sections, items[i][0], rect.grow(-9), "%s × %d" % [items[i][1], items[i][2]])
			if items[i][2] > 1: UI.text(sections, str(items[i][2]), Rect2(rect.end-Vector2(22, 23), Vector2(24, 24)), 18, UI.GOLD)

func toggle_equipment() -> void:
	pinned = not pinned
	drawer_hover = false
	if not pinned: hover_suppressed = compact.get_global_rect().has_point(pointer_position)
	set_drawer(pinned)

func set_drawer(open: bool) -> void:
	if drawer_open == open: return
	drawer_open = open
	if drawer_tween != null and drawer_tween.is_valid(): drawer_tween.kill()
	if open: drawer.show()
	# Closing is visual only: immediately release its input blocking region.
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	drawer.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED if open else Control.MOUSE_BEHAVIOR_DISABLED
	sections.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compact.visible = not open
	drawer_tween = create_tween()
	drawer_tween.tween_property(self,"drawer_progress",1.0 if open else 0.0,.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	drawer_tween.tween_callback(func():
		if not drawer_open: drawer.hide())

func add_slot(rect: Rect2) -> void:
	var slot := SLOT.new()
	slot.position = rect.position
	slot.size = rect.size
	sections.add_child(slot)

func collapse() -> void:
	pinned = false
	drawer_hover = false
	hover_suppressed = compact.get_global_rect().has_point(pointer_position)
	set_drawer(false)
	compact.show()

func _process(delta: float) -> void:
	if game == null: return
	awareness_clock-=delta
	if awareness_clock<=0 and game.state!=null:
		awareness_clock=.1
		var info: Dictionary=game.state.awareness_summary()
		var signature:=str(info)
		if signature!=last_awareness:
			last_awareness=signature
			awareness_label.text=info.text
			awareness_label.tooltip_text=info.detail+"\n黄色 ? 为怀疑，红色 ! 为已发现；未确认暴露不代表安全。"
			awareness_label.add_theme_color_override("font_color",Color("#ff7865") if info.kind=="combat" else UI.GOLD if info.kind!="unknown" else Color("#c1c7be"))
			awareness_label.modulate.a=.55
			MOTION.animate(awareness_label,"awareness",^"modulate:a",1.0,.18)
	if game.dialog.visible or (game.inventory_panel != null and game.inventory_panel.visible) or (game.wheel != null and game.wheel.visible) or (game.modal != null and game.modal.visible):
		set_drawer(false)
		compact.visible = game.wheel == null or not game.wheel.visible
		return
	var inside := drawer.get_global_rect().has_point(pointer_position)
	if drawer_open and inside: leave_delay = 0.2
	elif not pinned:
		leave_delay -= delta
		if leave_delay <= 0:
			drawer_hover = false
			set_drawer(false)
	if pinned: set_drawer(true)
	compact.visible = not drawer_open

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_position = event.position
		if compact != null and not compact.get_global_rect().has_point(pointer_position): hover_suppressed = false

func _draw() -> void:
	draw_line(Vector2(0, 43), Vector2(size.x, 43), UI.GOLD, 1)
	draw_line(Vector2(0, size.y-76), Vector2(size.x, size.y-76), UI.GOLD, 1)
