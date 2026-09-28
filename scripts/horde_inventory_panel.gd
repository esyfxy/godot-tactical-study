extends Control

const UI = preload("res://scripts/horde_ui_theme.gd")
const RULES = preload("res://scripts/horde_inventory_rules.gd")
const MOTION = preload("res://scripts/horde_ui_motion.gd")
var game
var cop: Dictionary = {}
var partner: Dictionary = {}
var panel: PanelContainer
var body: VBoxContainer
var columns: HBoxContainer
var message: Label
var working := false
var controls: Array[Button] = []
var item_filter := "全部"
var action_dock: VBoxContainer
var selected_row: Dictionary = {}
var selected_owner: Dictionary = {}
var selected_receiver: Dictionary = {}
var item_cards: Array[Button] = []
var ground_selection: Dictionary = {}
const FILTERS = ["全部","枪械","防具","弹药","道具"]

func _ready() -> void:
	z_index = 60
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.02,0.02,0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", game.box_style(Color("#141512"), UI.GOLD))
	add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	resized.connect(fit)
	hide()

func show_for(owner_unit: Dictionary, other: Dictionary = {}) -> void:
	cop = owner_unit
	partner = other
	selected_row = {}
	selected_owner = {}
	ground_selection.clear()
	show()
	preload("res://scripts/horde_ui_motion.gd").reveal(self)
	redraw()

func fit() -> void:
	if panel == null: return
	panel.position = Vector2(24, 70)
	panel.size = Vector2(maxf(300, size.x-48), maxf(200,size.y-95))

func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func add_text(parent: Node, text: String, font_size := 18) -> Label:
	var label := game.label(text, font_size, parent) as Label
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func action(parent: Node, text: String, callback: Callable) -> Button:
	var b: Button = game.button(text, parent, callback)
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size.y = 34
	controls.append(b)
	return b

func icon_name(item: String) -> String:
	return {"BodyArmor":"Armor", "BigMedkit":"MedkitBig", "SmallMedkit":"MedkitSmall"}.get(item,item)

func redraw() -> void:
	var scroll_positions: Array[int]=[]
	if columns!=null and is_instance_valid(columns):
		for scroll in columns.find_children("*","ScrollContainer",true,false): scroll_positions.append(scroll.scroll_vertical)
	clear(body)
	controls.clear()
	item_cards.clear()
	var header := HBoxContainer.new()
	body.add_child(header)
	add_text(header, "装备与背包 · " + str(cop.name) if partner.is_empty() else "交换物品 · %s ↔ %s" % [cop.name, partner.name], 25)
	action(header, "返回 [Esc / B]", close)
	add_text(body, "更换保留原装备 · 整理与相邻交换 0 AP · 双击物品快速操作", 14)
	var toolbar := HBoxContainer.new()
	body.add_child(toolbar)
	if partner.is_empty():
		add_text(toolbar, "交换对象：", 16)
		for other: Dictionary in game.state.cops:
			if other.id == cop.id or other.dead: continue
			var b := action(toolbar, str(other.name), func(): show_for(cop, other))
			b.tooltip_text = RULES.trade_reason(game.state,cop,other)
			b.disabled = not b.tooltip_text.is_empty()
	else: action(toolbar, "返回个人背包", func(): show_for(cop))
	var filters := HBoxContainer.new()
	body.add_child(filters)
	for i in range(FILTERS.size()):
		var title: String = FILTERS[i]
		var b := action(filters,"%d %s%s" % [i+1,title," ✓" if item_filter==title else ""],func(): item_filter=title; redraw())
		b.tooltip_text = "数字键 %d 筛选%s" % [i+1,title]
	columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	action_dock = VBoxContainer.new()
	body.add_child(action_dock)
	if partner.is_empty():
		add_column(cop, {}, "equipped")
		add_column(cop, {}, "storage")
		add_ground_column()
	else:
		add_column(cop, partner)
		add_column(partner, cop)
	if action_dock.get_child_count()==0: add_text(action_dock,"单击物品查看操作；双击 / Enter 执行主要操作。",16)
	message = add_text(body, "整理与交换 0 AP · 1–5 筛选 · Esc 返回", 14)
	message.custom_minimum_size.y = 24
	fit()
	# Keep the player's list position after equipping, transferring or filtering.
	var index := 0
	for scroll in columns.find_children("*","ScrollContainer",true,false):
		if index<scroll_positions.size(): scroll.set_deferred("scroll_vertical",scroll_positions[index])
		index+=1
	MOTION.reveal(columns)

func add_column(owner_unit: Dictionary, receiver: Dictionary, category := "all") -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(column)
	add_text(column, "穿戴与武器" if category == "equipped" else "背包与弹药" if category == "storage" else str(owner_unit.name) + " · 装备 / 背包 / 弹药", 20)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var rows: Array = RULES.rows(game.state, owner_unit)
	if category == "equipped": rows = rows.filter(func(row): return row.kind == "equipped")
	elif category == "storage": rows = rows.filter(func(row): return row.kind != "equipped")
	rows = rows.filter(func(row): return item_filter == "全部" or (item_filter == "弹药" and row.kind == "ammo") or (item_filter == "枪械" and row.item in game.STATE.GUNS and row.kind != "ammo") or (item_filter == "防具" and row.item in ["BodyArmor","Helmet"]) or (item_filter == "道具" and row.kind == "supply"))
	for i in range(rows.size()): rows[i]._order = i
	rows.sort_custom(func(a,b):
		if a.kind == "ammo" and b.kind != "ammo": return true
		if b.kind == "ammo" and a.kind != "ammo": return false
		if a.kind == "ammo" and b.kind == "ammo": return game.STATE.GUNS.find(a.item)<game.STATE.GUNS.find(b.item)
		return int(a._order)<int(b._order))
	if rows.is_empty(): add_text(list, "背包是空的。靠近补给箱后可选择装备、存入或只取弹药。")
	for row: Dictionary in rows:
		var title := "%s%s\n%s" % [game.STATE.NAMES[row.item], "弹药" if row.kind == "ammo" else "", row.detail]
		if row.item in game.STATE.GUNS and row.kind!="ammo": title += " · 备用 %d 发" % int(owner_unit.reserve.get(row.item,0))
		var card := action(list,title,func(): select_row(owner_unit,receiver,row))
		card.custom_minimum_size.y = 66
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.icon = UI.texture(UI.ammo_icon(row.item) if row.kind=="ammo" else icon_name(row.item))
		card.expand_icon = true
		card.add_theme_constant_override("icon_max_width",34)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.focus_mode = Control.FOCUS_ALL
		card.set_meta("row",row)
		card.set_meta("owner_id",owner_unit.id)
		item_cards.append(card)
		card.focus_entered.connect(func(): select_row(owner_unit,receiver,row))
		card.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.double_click and event.button_index==MOUSE_BUTTON_LEFT:
				select_row(owner_unit,receiver,row)
				primary_action())
		if selected_owner.get("id",-1)==owner_unit.id and selected_row.get("kind","")==row.kind and selected_row.get("key") == row.key:
			select_row(owner_unit,receiver,row)

func select_row(owner_unit: Dictionary,receiver: Dictionary,row: Dictionary) -> void:
	if working: return
	if selected_owner.get("id",-1)==owner_unit.id and selected_row==row and action_dock.get_child_count()>0: return
	selected_row = row.duplicate()
	selected_owner = owner_unit
	selected_receiver = receiver
	for card in item_cards:
		var r: Dictionary = card.get_meta("row")
		MOTION.tint(card,UI.GOLD if card.get_meta("owner_id")==owner_unit.id and r.kind==row.kind and r.key==row.key else Color.WHITE)
	clear(action_dock)
	controls = controls.filter(func(b): return is_instance_valid(b) and b.is_inside_tree())
	add_text(action_dock,"%s · %s · %s" % [owner_unit.name,game.STATE.NAMES[row.item],row.detail],16)
	var buttons := HFlowContainer.new()
	action_dock.add_child(buttons)
	if receiver.is_empty():
		if row.kind=="bag": action(buttons,"装备 / 更换",primary_action)
		elif row.kind=="equipped":
			action(buttons,"收入背包",primary_action)
			if row.item in game.STATE.GUNS and owner_unit.gun!=row.item:
				action(buttons,"切为手持",func(): mutate(func():
					if not RULES.allowed(game.state,owner_unit) or not owner_unit.weapons.has(row.item): return false
					owner_unit.gun=row.item
					return true))
		if row.kind in ["bag","equipped"] and row.item in game.STATE.GUNS:
			var loaded := int(owner_unit.weapons.get(row.item,0)) if row.kind=="equipped" else int(RULES.bag_item(owner_unit,int(row.key)).get("ammo",0))
			var unload_button := action(buttons,"卸下弹药",func(): mutate(func(): return RULES.unload(game.state,owner_unit,row)))
			unload_button.disabled=loaded==0
			unload_button.tooltip_text="枪内没有弹药" if loaded==0 else "取出弹药，保留枪支"
			action(buttons,"丢到地上",func(): mutate(func(): return RULES.drop_gun(game.state,owner_unit,row)))
			action(buttons,"保留弹药并丢枪",func(): mutate(func(): return RULES.unload_and_drop(game.state,owner_unit,row)))
		elif row.kind=="ammo": add_text(buttons,"选择上方相邻队友，可分配指定数量。",14)
	else:
		var arrow := " →" if owner_unit.id==cop.id else " ←"
		if row.kind in ["ammo","supply"]:
			var count := SpinBox.new()
			count.min_value=1
			count.max_value=int(row.amount)
			count.value=mini(int(game.STATE.CAPACITY.get(row.item,1)),int(row.amount))
			count.custom_minimum_size=Vector2(95,34)
			buttons.add_child(count)
			action(buttons,"给予所选"+arrow,func(): transfer(owner_unit,receiver,row,int(count.value)))
			if int(row.amount)>1: action(buttons,"给予半数"+arrow,func(): transfer(owner_unit,receiver,row,maxi(1,int(row.amount)/2)))
			action(buttons,"给予全部"+arrow,func(): transfer(owner_unit,receiver,row,int(row.amount)))
		else: action(buttons,"给予"+arrow,primary_action)
	MOTION.reveal(action_dock)

func primary_action() -> void:
	if working or selected_row.is_empty(): return
	var row := selected_row.duplicate()
	var owner_unit := selected_owner
	if not selected_receiver.is_empty(): transfer(owner_unit,selected_receiver,row,1)
	elif row.kind=="bag": mutate(func(): return RULES.equip(game.state,owner_unit,int(row.key)))
	elif row.kind=="equipped": mutate(func(): return RULES.stow(game.state,owner_unit,row.item))

func add_ground_column() -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	columns.add_child(column)
	add_text(column,"脚边与补给",20)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var accessible: Array = []
	for tile: Vector2i in game.state.loot:
		if not game.state.can_collect_at(cop.pos,tile): continue
		accessible.append(tile)
		var record: Dictionary = game.state.loot[tile]
		var b := CheckBox.new()
		b.text=game.state.loot_name(record)
		b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		b.button_pressed=ground_selection.has(tile)
		b.toggled.connect(func(on):
			if on: ground_selection[tile]=record.duplicate(true)
			else: ground_selection.erase(tile))
		list.add_child(b)
	for tile in ground_selection.keys():
		if tile not in accessible: ground_selection.erase(tile)
	if accessible.is_empty(): add_text(list,"附近没有可拿取物品。需走到物品同侧；不能隔墙取物。",16)
	else:
		action(column,"全选附近",func():
			for tile in accessible: ground_selection[tile]=game.state.loot[tile].duplicate(true)
			redraw())
		action(column,"取走所选 · 存入背包",collect_selected)
		var ammo_button := action(column,"只取当前枪械弹药",collect_matching_ammo)
		ammo_button.disabled=cop.gun==""
		ammo_button.tooltip_text="先装备枪械" if cop.gun=="" else "只取适配弹药，留下枪支"

func collect_selected() -> void:
	if ground_selection.is_empty():
		message.text="先勾选脚边物品，或点击全选附近。"
		return
	var requests: Array = []
	for tile in ground_selection: requests.append({"tile":tile,"mode":"bag","expected":ground_selection[tile]})
	mutate(func(): return RULES.collect_batch(game.state,cop,requests))
	ground_selection.clear()

func collect_matching_ammo() -> void:
	var requests: Array = []
	for tile: Vector2i in game.state.loot:
		var record: Dictionary = game.state.loot[tile]
		if record.item!=cop.gun or not game.state.can_collect_at(cop.pos,tile): continue
		if record.category=="Ammo": requests.append({"tile":tile,"mode":"bag","expected":record.duplicate(true)})
		elif record.category=="Weapon" and int(record.get("ammo",game.STATE.CAPACITY[cop.gun]))+int(record.get("extra",2 if cop.gun in ["Rifle","Shotgun"] else 0))>0:
			requests.append({"tile":tile,"mode":"ammo","expected":record.duplicate(true)})
	if requests.is_empty():
		message.text="附近没有可取的当前枪械弹药。"
		return
	mutate(func(): return RULES.collect_batch(game.state,cop,requests))

func mutate(callback: Callable) -> void:
	if working or game.busy: return
	var old_message: String = str(game.state.log.back()) if not game.state.log.is_empty() else ""
	var success: bool = callback.call()
	game.refresh()
	redraw()
	var latest: String = str(game.state.log.back()) if not game.state.log.is_empty() else ""
	message.text = latest if success or latest != old_message else "操作未完成：物品已变化或当前无法操作。"

func transfer(from: Dictionary, to: Dictionary, row: Dictionary, amount: int) -> void:
	if working or game.busy: return
	working = true
	for b in controls: b.disabled = true
	# Play the source Interact gesture concurrently with the transfer UI.
	game.world.actors[from.id].get_node("Motion").face(game.world.grid(to.pos))
	game.world.actors[from.id].get_node("Motion").start_clip("interact")
	await get_tree().create_timer(game.world.actors[from.id].get_node("Motion").event_time("interact")).timeout
	if not RULES.transfer(game.state,from,to,row,amount):
		working = false
		redraw()
		message.text = "无法交换：请确认相邻、物品和数量。"
		return
	working = true
	for b in controls: b.disabled = true
	message.text = str(game.state.log.back())
	# Visible confirmation of ownership transfer; input is locked until it ends.
	var icon := UI.icon(self,UI.ammo_icon(row.item) if row.kind == "ammo" else icon_name(row.item),Rect2(size.x*0.28,size.y*0.5,52,52),UI.GOLD)
	var left_to_right: bool = from.id == cop.id
	icon.position.x = size.x*(0.28 if left_to_right else 0.72)
	var tween := create_tween()
	tween.tween_property(icon,"position:x",size.x*(0.72 if left_to_right else 0.28),0.32).set_trans(Tween.TRANS_SINE)
	await tween.finished
	icon.queue_free()
	working = false
	game.refresh()
	redraw()
	message.text = str(game.state.log.back())

func close() -> void:
	if working: return
	hide()
	game.refresh()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ENTER:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or (focus is Button and focus not in item_cards): return
		primary_action()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode>=KEY_1 and event.keycode<=KEY_5:
		if not working:
			item_filter = FILTERS[event.keycode-KEY_1]
			redraw()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE,KEY_B]:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		close()
		get_viewport().set_input_as_handled()
