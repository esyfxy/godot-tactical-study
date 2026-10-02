extends "res://scripts/horde_mode.gd"

var prepared_campus

func mission_data() -> Dictionary:
	prepared_campus=preload("res://scripts/school_map.gd").new()
	prepared_campus.tactical=true
	add_child(prepared_campus)
	var source: Dictionary=preload("res://scripts/school_mission_data.gd").build(prepared_campus)
	remove_child(prepared_campus)
	return source

func create_state(): return preload("res://scripts/school_state.gd").new()
func create_world():
	var result=preload("res://scripts/school_combat_world.gd").new()
	result.campus=prepared_campus
	return result
func allows_resume() -> bool: return false

func music_override() -> String:
	# Read existing confirmed alert only; no extra visibility/AI queries in UI.
	for e: Dictionary in state.enemies:
		if state.conscious(e) and not e.surrender and e.get("alerted",false): return "m04"
	return "stealth"

func _ready() -> void:
	super._ready()
	var plate:=box_style(Color("#172d2bed"),Color.TRANSPARENT)
	plate.set_content_margin_all(7)
	turn_summary.add_theme_stylebox_override("normal",plate)
	turn_summary.add_theme_color_override("font_color",Color("#f4e6bc"))

func mission_summary() -> String:
	return "校园解救 · 第 %d 回合\n敌人 %d · 获救 %d/%d"%[state.turn,state.active_enemies().size(),state.rescued_count,state.hostages.size()]

func mission_stats() -> String:
	return "平南县中学 · 解救行动\n制服全部敌人并解救教职工\n获救 %d/%d · 敌人 %d\n黄色：待救人质；绿色：已解救\n低掩体：半盾；高掩体：全盾"%[state.rescued_count,state.hostages.size(),state.active_enemies().size()]

func refresh() -> void:
	state.check_mission()
	super.refresh()
	if state.phase=="victory": show_result()

func show_enemy(unit: Dictionary) -> void:
	world.reveal_interaction(unit)
	if unit.side!="hostage": super.show_enemy(unit);return
	begin_actions("教职工 · "+unit.name,unit)
	var c: Dictionary=state.cops[selected]
	var reason: String=state.rescue_reason(c,unit)
	if unit.rescued:
		label("已解除看守，留在原地等待救援队接应。",15,action_column)
	else:
		var choice:=button("解救 · 1 AP",action_column,rescue_hostage.bind(unit))
		choice.disabled=not reason.is_empty()
		label("点击解救，解除看守。" if reason.is_empty() else reason,15,action_column)
		if not state.nav.knife_access(c.pos,unit.pos):
			var approach:=Vector2i(-1,-1)
			var best:=INF
			for tile: Vector2i in world.reached.costs:
				var cost: float=world.reached.costs[tile]
				if state.nav.knife_access(tile,unit.pos) and cost<best:
					approach=tile;best=cost
			if approach.x>=0: button("移动到人质旁",action_column,func(): action_panel.hide(); do_move(approach))
	close_action_button()

func _process(delta: float) -> void:
	super._process(delta)
	if world!=null and not wheel.visible and not action_panel.visible:
		world.interaction_target={}

func rescue_hostage(h: Dictionary) -> void:
	if blocked(): return
	var c: Dictionary=state.cops[selected]
	if not state.rescue_reason(c,h).is_empty(): show_enemy(h);return
	busy=true
	action_panel.hide()
	await action_player.interact(c,h.pos,func(): state.rescue(c,h),.55)
	busy=false
	refresh()

func enemy_banner_text() -> String: return "敌方行动 · 保持掩护"

func show_help() -> void:
	if busy: return
	wheel.hide()
	action_panel.hide()
	dialog.present("school_help","平南县中学 · 解救行动","潜入开局：四名警员在校门外携枪械、防弹衣与急救物资部署，守卫尚未发现你。\n\n目标：解救 3 位教职工，制服全部 8 名敌人。\n人质需相邻且有 1 AP；先解除 5 格内能看见人质的看守。\n未警觉守卫使用前向视野：远处先 ? 怀疑，持续暴露或近处目击才 ! 已发现。悬停可见敌人查看视野格，左上显示全队暴露状态。\n听到声响只触发调查；失去目击后追踪最后位置，不读取隐藏当前位置。未确认暴露不代表安全。\n\n点击头像选择警员；左键移动或打开敌人/人质菜单。\n半盾为低掩体，全盾为高掩体；高墙不透视，墙角可探身射击。\n滚轮缩放、右键拖动、中键全景；Enter 结束回合。\nB 背包，M 地图，J 战报。当前校园不提供存档。","开始行动")

func show_menu() -> void:
	super.show_menu()
	modal.buttons.save.disabled=true
	modal.buttons.save.text="校园关暂不支持存档"
	if modal.buttons.has("developer"):
		modal.buttons.developer.disabled=true
		modal.buttons.developer.text="校园使用固定部署"

func show_developer() -> void:
	state.say("校园使用固定警员、敌人和人质部署；开发者波次工具仅适用于义军模式。")
	refresh()

func save_game(automatic: bool=false) -> bool:
	if not automatic:
		state.say("校园关暂不支持存档；不会覆盖义军呐喊的继续战局。")
		refresh()
	return false

func _dialog_confirm(value: String) -> void:
	if value in ["restart","menu"]:
		modal.hide()
		dialog.present("confirm_"+value,"确认离开校园行动？","校园当前没有存档。离开后再进入会重新部署警员、敌人和人质。","确认")
		dialog.cancel.show()
	else: super._dialog_confirm(value)

func show_result() -> void:
	if result_written: return
	result_written=true
	dialog.present("school_result","校园行动完成" if state.phase=="victory" else "校园行动失败","获救 %d/%d · 制服 %d/8\n历时 %d 回合 · 存活警员 %d/%d\n\n%s"%[state.rescued_count,state.hostages.size(),state.killed+state.arrested,state.turn,state.living_cops().size(),state.cops.size(),"全部教职工已解除看守，等待救援队接应。" if state.phase=="victory" else "可重新部署并尝试利用掩体、警戒和非致命装备。"],"查看战场")
	dialog.add_choice("重新行动","confirm_restart")
	dialog.add_choice("返回模式选择","result_menu")
