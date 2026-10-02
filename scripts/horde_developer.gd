extends RefCounted

# Debug-only controls. Closing this panel does NOT make a mutated run normal.
const UI = preload("res://scripts/horde_ui_theme.gd")
const SAVE = preload("res://scripts/horde_save.gd")
var game
var modal
var wave: SpinBox
var count: SpinBox
var enemy: OptionButton
var cop: OptionButton
var item: OptionButton
var amount: SpinBox
var points: SpinBox
var response: Label
var items: Array = []
var prefabs: Array = []

func number(title: String,at: Vector2,minimum: int,maximum: int,value: int) -> SpinBox:
	UI.text(modal.content,title,Rect2(at,Vector2(260,40)),25,UI.GOLD)
	var n := SpinBox.new()
	n.position = at+Vector2(270,0)
	n.size = Vector2(200,46)
	n.min_value = minimum
	n.max_value = maximum
	n.step = 1
	n.value = value
	n.add_theme_font_size_override("font_size",26)
	modal.content.add_child(n)
	return n

func choice(title: String,at: Vector2,labels: Array) -> OptionButton:
	UI.text(modal.content,title,Rect2(at,Vector2(260,40)),25,UI.GOLD)
	var n := OptionButton.new()
	n.position = at+Vector2(270,0)
	n.size = Vector2(280,46)
	n.add_theme_font_size_override("font_size",24)
	for text in labels: n.add_item(str(text))
	modal.content.add_child(n)
	return n

func present() -> void:
	if not OS.is_debug_build() or game.busy or game.state.phase!="player": return
	modal.begin("developer")
	modal.paper(Rect2(320,35,1280,1005),Color("#10120ff4"))
	UI.heading_paper(modal.content,Rect2(485,40,950,100))
	UI.text(modal.content,"开发者测试",Rect2(495,45,930,89),46,UI.INK,true)
	UI.text(modal.content,"修改后切换独立测试存档 / 战绩；关面板仍是测试局。重新开始恢复正式局。",Rect2(365,145,1190,60),23,UI.GOLD,true)
	wave = number("目标波数",Vector2(375,220),1,100,maxi(1,game.state.wave))
	count = number("生成数量（0=原规则）",Vector2(375,285),0,100,0)
	prefabs = [""]
	var labels: Array = ["原版波次混合"]
	for key in game.state.enemy_loadouts.prefabs:
		prefabs.append(key)
		var loadout: Dictionary = game.state.enemy_loadouts.prefabs[key]
		labels.append("%s · %s" % [key,"斧头" if loadout.melee=="Ax" else "自动步枪" if loadout.machinegun else game.state.NAMES.get(loadout.gun,loadout.gun)])
	enemy = choice("敌人类型",Vector2(375,350),labels)
	UI.text(modal.content,"替换会清除现有敌人，保留队员/物资。跳转到该波刚入场的回合；出生点遵守原距离限制。",Rect2(375,420,550,96),23)
	modal.buttons.replace_wave = UI.button(modal.content,"替换敌人并跳到该波",Rect2(375,535,550,54),replace_wave,27)
	modal.buttons.add_enemies = UI.button(modal.content,"追加敌人（不改波数/回合）",Rect2(375,599,550,54),add_enemies,25)
	var names: Array = []
	for c: Dictionary in game.state.cops: names.append(c.name+("（阵亡）" if c.dead else ""))
	cop = choice("操作队员",Vector2(995,220),names)
	cop.select(game.selected)
	items = game.state.GUNS.duplicate()
	for gun: String in game.state.GUNS: items.append(gun+"Ammo")
	items.append_array(["BodyArmor","Helmet","Grenade","Taser","BigMedkit","SmallMedkit"])
	labels = []
	for key: String in items:
		labels.append(str(game.state.NAMES.get(key.trim_suffix("Ammo"),key))+("弹药" if key.ends_with("Ammo") else ""))
	item = choice("物资种类",Vector2(995,285),labels)
	amount = number("数量（弹药为发数）",Vector2(995,350),1,50,1)
	UI.text(modal.content,"生成到队员脚边空格，不覆盖旧补给，不跨墙。枪/护甲进背包；弹药进备用，消耗品进用品栏。",Rect2(995,420,550,96),23)
	modal.buttons.loot = UI.button(modal.content,"在脚边生成补给",Rect2(995,535,550,54),place_loot,27)
	modal.buttons.bag = UI.button(modal.content,"直接加入队员物品栏",Rect2(995,599,550,54),give_items,25)
	modal.buttons.ap = UI.button(modal.content,"恢复该队员本回合行动点",Rect2(995,663,550,54),restore_ap,25)
	points = number("反抗点数",Vector2(375,687),0,99999,game.state.points)
	modal.buttons.points = UI.button(modal.content,"设置反抗点数",Rect2(375,751,550,54),set_points,25)
	modal.buttons.load_test = UI.button(modal.content,"载入上次测试存档",Rect2(995,751,550,54),load_test,25)
	response = UI.text(modal.content,"仅己方空闲时可操作；不会改变敌人视野规则。",Rect2(375,829,1170,88),25,UI.GOLD,true)
	modal.buttons.back = UI.button(modal.content,"返回战场 [F8 / Esc]",Rect2(685,945,550,60),modal.close,29)

func allowed() -> bool:
	return OS.is_debug_build() and modal.visible and modal.mode=="developer" and not game.busy and game.state.phase=="player"

func finish(text: String) -> void:
	game.state.say("[开发者] "+text)
	game.refresh()
	response.text = text+" · 测试局，不影响正式存档"

func replace_wave() -> void:
	if not allowed(): return
	game.start_developer_session()
	var s = game.state
	s.enemies.clear()
	s.last_seen.clear()
	s.presentation_events.clear()
	s.wave = int(wave.value)-1
	s.turn = int(s.params.HordeWarmUpTurns)+(int(wave.value)-1)*int(s.params.HordeEnemySpawnTurns)+1
	s.spawn_wave(-1 if count.value==0 else int(count.value),str(prefabs[enemy.selected]))
	s.build_flow()
	finish("已跳至第 %d 波 / 回合 %d，实际生成 %d 名敌人" % [s.wave,s.turn,s.enemies.size()])

func add_enemies() -> void:
	if not allowed(): return
	game.start_developer_session()
	var s = game.state
	var old_wave: int = s.wave
	var old_size: int = s.active_enemies().size()
	# Reuse spawn safety/loadouts, without advancing the wave or spawning loot.
	s.wave = int(wave.value)-1
	s.spawn_wave(-1 if count.value==0 else int(count.value),str(prefabs[enemy.selected]),false)
	s.wave = old_wave
	s.build_flow()
	finish("实际追加 %d 名敌人；原出生点不足或太近时不会强行生成" % (s.active_enemies().size()-old_size))

func target() -> Dictionary:
	var c: Dictionary = game.state.cops[cop.selected]
	if not game.state.conscious(c):
		response.text = "请选择清醒且存活的队员。"
		return {}
	return c

func place_loot() -> void:
	if not allowed(): return
	var c := target()
	if c.is_empty(): return
	var s = game.state
	var spots: Array[Vector2i] = []
	for offset in [Vector2i.ZERO]+s.nav.DIRS:
		var tile: Vector2i = c.pos+offset
		if s.nav.passable(tile) and not s.loot.has(tile) and s.can_collect_at(c.pos,tile): spots.append(tile)
	if spots.is_empty():
		response.text = "脚边无可用空格，请先移动；未覆盖任何物资。"
		return
	game.start_developer_session()
	var key: String = items[item.selected]
	var ammo := key.ends_with("Ammo")
	var kind := key.trim_suffix("Ammo")
	var boxes := 1 if ammo else mini(int(amount.value),spots.size())
	for i in range(boxes):
		var record := {"item":kind,"category":"Ammo" if ammo else "Weapon" if kind in s.GUNS else "Equipment","dropped":true}
		if ammo: record.amount = int(amount.value)
		s.loot[spots[i]] = record
	finish("已在 %s 脚边生成 %d 箱%s%s" % [c.name,boxes,s.NAMES[kind],"（共 %d 发）" % int(amount.value) if ammo else "；数量受空格限制"])

func give_items() -> void:
	if not allowed(): return
	var c := target()
	if c.is_empty(): return
	game.start_developer_session()
	var s = game.state
	var key: String = items[item.selected]
	var kind := key.trim_suffix("Ammo")
	var n := int(amount.value)
	if key.ends_with("Ammo"): c.reserve[kind] = int(c.reserve.get(kind,0))+n
	elif kind in s.GUNS or kind in ["BodyArmor","Helmet"]:
		for i in range(n): s.INVENTORY.store(s,c,kind,int(s.CAPACITY.get(kind,0)),2 if kind=="BodyArmor" else 1 if kind=="Helmet" else 0)
	else: c.supplies[kind] = int(c.supplies.get(kind,0))+n
	finish("%s 获得 %s × %d（弹药进入备用弹药，装备收入背包）" % [c.name,s.NAMES[kind]+("弹药" if key.ends_with("Ammo") else ""),n])

func restore_ap() -> void:
	if not allowed(): return
	var c := target()
	if c.is_empty(): return
	game.start_developer_session()
	c.ap = c.max_ap
	finish(c.name+" 行动点已恢复（不治疗伤势）")

func set_points() -> void:
	if not allowed(): return
	game.start_developer_session()
	game.state.points = int(points.value)
	finish("反抗点数已设为 %d" % game.state.points)

func load_test() -> void:
	if not allowed(): return
	var saved: Dictionary = SAVE.read_save(game.developer_save_path)
	if not saved.ok:
		response.text = str(saved.error)
		return
	var error: String = SAVE.restore(game.state,saved.data)
	if not error.is_empty():
		response.text = error
		return
	game.start_developer_session()
	game.selected = 0
	game.result_written = false
	finish("已载入独立测试存档 · 第 %d 波 / 回合 %d" % [game.state.wave,game.state.turn])
