extends RefCounted

# Source-driven mode orchestration; combat coefficients below are explicitly
# a playable study implementation, not the original Unity combat/AI solver.
const NAV = preload("res://scripts/horde_navigation.gd")
const INVENTORY = preload("res://scripts/horde_inventory_rules.gd")
const BALLISTICS = preload("res://scripts/horde_ballistics.gd")
const ENEMY_AI = preload("res://scripts/horde_enemy_ai.gd")
var ai_cache_enabled := true
const SKILLS = ["AimedShot", "OrderToSurrender", "SeeFar", "Fortification", "SecondCheek", "AdrenalineRush", "Bide", "SmoothOps", "Resilience"]
const GUNS = ["Revolver", "Glock", "Rifle", "Shotgun"]
const CAPACITY = {"Revolver": 6, "Glock": 9, "Rifle": 1, "Shotgun": 1}
const RANGES = {"Revolver": 9, "Glock": 11, "Rifle": 17, "Shotgun": 6}
const NAMES = {"Knife": "匕首", "Revolver": "左轮", "Glock": "手枪", "Rifle": "步枪", "Shotgun": "霰弹枪", "BodyArmor": "防弹衣", "Helmet": "头盔", "Grenade": "震撼弹", "Taser": "泰瑟枪", "BigMedkit": "急救包", "SmallMedkit": "小急救包", "Points": "反抗点数"}
var data: Dictionary
var enemy_loadouts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/horde/enemy_loadouts.json"))
var params: Dictionary
var nav = NAV.new()
var rng := RandomNumberGenerator.new()
var cops: Array = []
var enemies: Array = []
var loot: Dictionary = {}
var turn := 1
var wave := 0
var points := 50
var killed := 0
var arrested := 0
var collected := 0
var next_id := 0
var next_item_id := 0
var phase := "player"
var log: Array[String] = []
var seed_value := 0
var backup_spawned := false
var flow: Dictionary = {}
var flow_revision := -1
var ai_objectives: Array[Vector2i] = []
var presentation_events: Array = []
var viewing_positions: Dictionary = {}
var reaction_queue: Array = []
var last_seen: Dictionary = {}
var observed_events: Array = []
var awareness_cache_signature: Array = []
var awareness_cache: Dictionary = {}
var awareness_cache_builds := 0
const COMMAND_COST = {"Overwatch":20,"Accuracy":40,"Haste":50,"ShockAndAwe":300}

func command_reason(command: String) -> String:
	if phase != "player": return "等待你的回合"
	if not COMMAND_COST.has(command): return "未知指令"
	if points<int(COMMAND_COST[command]): return "义军点数不足"
	for c: Dictionary in living_cops():
		if not conscious(c): continue
		if command=="Overwatch" and (int(c.ap)<=0 or c.wound=="手臂" or c.gun=="" or int(c.weapons.get(c.gun,0))<=0): continue
		if command=="Accuracy" and c.wound=="手臂": continue
		return ""
	return "没有可执行指令的警员"

func use_command(command: String) -> bool:
	if not command_reason(command).is_empty(): return false
	points -= int(COMMAND_COST[command])
	for c: Dictionary in living_cops():
		if not conscious(c): continue
		match command:
			"Overwatch":
				if int(c.ap)>0 and c.wound!="手臂" and c.gun!="" and int(c.weapons.get(c.gun,0))>0:
					c.ap = 0
					c.overwatch = true
			"Accuracy":
				if c.wound!="手臂": c.accuracy_buff = int(c.get("accuracy_buff",0))+1
			"Haste":
				c.ap += 1
				c.max_ap = maxi(int(c.max_ap),int(c.ap))
	if command=="ShockAndAwe":
		for e: Dictionary in active_enemies():
			if visible_enemy(e) and e.wound != "躯干":
				# EnemyBattlePhase.ShockAndAwe calls Arrest(null), not the
				# point-awarding ArrestTacticsAction.
				e.captured = true
				e.stun = 0
				arrested += 1
				action_event(e,e,"capture","已逮捕")
	say({"Overwatch":"一级战备：有弹药的警员用剩余行动点进入警戒。","Accuracy":"稳定的手：本回合精准度提高。","Haste":"反抗精神：所有清醒警员获得 1 AP。","ShockAndAwe":"震骇效应：视野中的罪犯已被逮捕。"}[command])
	return true

func reaction_ready(c: Dictionary,e: Dictionary,maximum: float) -> bool:
	return conscious(c) and not e.dead and not e.captured and int(e.stun)==0 and effective_wound(c)!="手臂" and c.gun!="" and int(c.weapons.get(c.gun,0))>0 and nav.targeting(c.pos,e.pos,maximum,cover_enabled(c),cover_enabled(e),occupied(c.id)).clear

func request_reaction(c: Dictionary,e: Dictionary,kind: String) -> Dictionary:
	var request := {"cop":c,"enemy":e,"kind":kind,"resolved":false}
	return request

func overwatch_requests(e: Dictionary, shot_target_id := -1) -> Array:
	var result: Array = []
	for c: Dictionary in living_cops():
		if not c.get("overwatch",false) or c.counter: continue
		var targeted: bool = int(c.id) == shot_target_id
		var maximum := current_shot_range(c) if targeted else minf(8,current_shot_range(c))
		if reaction_ready(c,e,maximum): result.append(request_reaction(c,e,"警戒"))
	return result

func resolve_reaction(request: Dictionary,part: String) -> bool:
	if request.get("resolved",true): return false
	request.resolved = true
	request.cop.counter = true
	if part not in ["头","躯干","手臂","腿"]: return false
	var c: Dictionary = request.cop
	var e: Dictionary = request.enemy
	if not reaction_ready(c,e,current_shot_range(c)): return false
	fire(c,e,part)
	return true

func take_events() -> Array:
	var result := presentation_events.duplicate(true)
	presentation_events.clear()
	return result

func action_event(c: Dictionary, e: Dictionary, kind: String, result := "",trace: Dictionary = {}) -> void:
	presentation_events.append({"kind":kind,"actor":c.id,"target":e.id,"from":c.pos,"to":e.pos,"gun":c.gun,"result":result,"dead":e.dead,"shot_from":trace.get("from",c.pos),"shot_to":trace.get("to",e.pos)})

func initialize(source: Dictionary, random_seed: int = -1) -> void:
	data = source
	params = data.parameters
	if random_seed < 0: rng.randomize()
	else: rng.seed = random_seed
	seed_value = rng.seed
	nav.configure(data)
	ai_objectives = ENEMY_AI.map_objectives(self)
	points = int(params.InitialRebelPointsHordeMode)
	var pool: Array = data.employees.slice(0, 26).duplicate(true)
	var types: Dictionary = {}
	var positions: Array = data.cop_spawns.duplicate()
	while cops.size() < int(params.HordeCops) and not pool.is_empty():
		var e: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var kind := str(e.age) + ":" + str(e.gender)
		if types.has(kind): continue
		types[kind] = true
		var spawn: Dictionary = positions.pop_at(rng.randi_range(0, positions.size() - 1))
		var cop := unit(e.name, Vector2i(int(spawn.X), int(spawn.Y)), "cop")
		cop.employee = e.id
		cop.gender = int(e.gender)
		cop.age = int(e.age)
		cop.speed = int(e.speed)
		cop.strength = int(e.strength)
		cop.shooting = int(e.shooting)
		var skills: Array = SKILLS.duplicate()
		for i in range(5):
			var stat: String = ["shooting", "speed", "strength"][rng.randi_range(0, 2)]
			cop[stat] += 1
			cop.skills.append(skills.pop_at(rng.randi_range(0, skills.size() - 1)))
		cops.append(cop)
	spawn_loot(true)
	say("准备阶段：先搜集红色补给箱；第 3 回合结束行动后首波敌人入场。")

func unit(unit_name: String, tile: Vector2i, side: String) -> Dictionary:
	next_id += 1
	return {"id": next_id, "name": unit_name, "pos": tile, "side": side, "ap": 2, "max_ap": 2,
		"dead": false, "captured": false, "stun": 0, "surrender": false, "bleed": 0, "wound": "",
		"armor": 0, "helmet": false, "skills": [], "speed": 0, "strength": 0, "shooting": 0,
		"weapons": {}, "reserve": {}, "supplies": {}, "bag": [], "gun": "", "counter": false, "skill_used": false,"facing":Vector2i.DOWN}

func say(message: String) -> void:
	log.append(message)
	if log.size() > 100: log.pop_front()

func remember_enemy(e: Dictionary,tile: Vector2i) -> void:
	if e.dead or e.captured:
		last_seen.erase(e.id)
		return
	last_seen[e.id]={"pos":tile,"turn":turn,"name":str(e.name)}

func remember_event(event: Dictionary,actor_visible: bool,target_visible: bool) -> void:
	if not actor_visible and not target_visible: return
	var actor_name := "未知来源"
	var target_name := "视野外目标"
	for u: Dictionary in cops+enemies:
		if actor_visible and u.id==event.actor: actor_name=u.name
		if target_visible and u.id==event.target: target_name=u.name
	var text := ""
	match str(event.kind):
		"shoot","knife","death": text="%s → %s：%s" % [actor_name,target_name,event.result if target_visible else "结果未知"]
		"reload": text=actor_name+" 装填弹药"
		"capture": text=actor_name+" 已被逮捕"
	if text.is_empty(): return
	observed_events.append({"turn":turn,"text":text,"tile":event.to if target_visible else event.from})
	if observed_events.size()>30: observed_events.pop_front()

func living_cops() -> Array:
	return cops.filter(func(c): return not c.dead)

func cop_awareness(c: Dictionary) -> String:
	return awareness_snapshot().cops.get(c.id,"unknown")

func awareness_snapshot() -> Dictionary:
	# State dictionaries are also edited by AI, save restore and developer tools.
	# Fingerprint their values, not just a timer/frame, so same-frame mutations
	# and tween viewing positions invalidate the shared read-only UI snapshot.
	var signature: Array = [turn,nav.revision,viewing_positions.hash(),awareness_extra_signature()]
	for u: Dictionary in cops+enemies: signature.append(u.hash())
	if signature == awareness_cache_signature and not awareness_cache.is_empty(): return awareness_cache
	awareness_cache_signature=signature
	awareness_cache_builds+=1
	var visible: Dictionary={}
	var enemy_kinds: Dictionary={}
	for e: Dictionary in active_enemies():
		enemy_kinds[e.id]=ENEMY_AI.awareness(self,e)
		# Incapacitated enemies never contribute to cop awareness.
		if conscious(e) and not e.surrender: visible[e.id]=visible_enemy(e)
	var cop_kinds: Dictionary={}
	for c: Dictionary in living_cops(): cop_kinds[c.id]=_cop_awareness(c,visible,enemy_kinds)
	awareness_cache={"cops":cop_kinds,"enemies":enemy_kinds,"summary":_awareness_summary(cop_kinds)}
	return awareness_cache

func awareness_extra_signature() -> int:
	return 0

func _cop_awareness(c: Dictionary,visible: Dictionary,enemy_kinds: Dictionary) -> String:
	var rank:=0
	for e: Dictionary in active_enemies():
		if not conscious(e) or e.surrender: continue
		if int(c.id) in e.get("visible_ids",[]): return "combat"
		var memory: Dictionary=e.get("known",{}).get(c.id,{})
		if not memory.is_empty() and turn-int(memory.turn)<=ENEMY_AI.MEMORY_TURNS: rank=maxi(rank,3)
		# Suspicion/hearing of hidden enemies must not expose their location/state.
		if not visible.get(e.id,false): continue
		var suspicion: Dictionary=e.get("suspected",{})
		if not suspicion.is_empty() and int(suspicion.cop)==int(c.id) and turn-int(suspicion.last_turn)<=1: rank=maxi(rank,2)
		if enemy_kinds.get(e.id,"inactive") in ["investigate","search"]: rank=maxi(rank,1)
	return ["unknown","investigate","suspicious","track"][rank]

func awareness_event(e: Dictionary,c: Dictionary,confirmed: bool) -> void:
	var visible:=visible_enemy(e)
	if not confirmed and not visible: return
	var text: String=(str(e.name) if visible else "视野外敌人")+(" 已发现 "+str(c.name)+"。" if confirmed else " 对 "+str(c.name)+" 起疑，尚未确认身份。")
	# Own officer's location is known; never record a hidden witness's tile.
	var at: Vector2i=viewing_positions.get(c.id,c.pos)
	observed_events.append({"turn":turn,"text":text,"tile":at})
	if observed_events.size()>30: observed_events.pop_front()
	say(text)

func awareness_summary() -> Dictionary:
	return awareness_snapshot().summary

func _awareness_summary(cop_kinds: Dictionary) -> Dictionary:
	var result:={"kind":"unknown","text":"未确认暴露","detail":"不代表安全，注意朝向与声响"}
	var ranking:={"unknown":0,"investigate":1,"suspicious":2,"track":3,"combat":4}
	for c: Dictionary in living_cops():
		var kind: String=cop_kinds.get(c.id,"unknown")
		if int(ranking[kind])<=int(ranking[result.kind]): continue
		result.kind=kind
		match kind:
			"combat": result.text="已被发现 · "+str(c.name);result.detail="敌人已确认警员身份"
			"track": result.text="脱离目击 · 仍被追踪";result.detail="敌人记得最后位置，不等于当前位置"
			"suspicious": result.text="引起怀疑 · "+str(c.name);result.detail="尚未确认身份，及时脱离视线"
			"investigate": result.text="敌人调查或搜索中";result.detail="听到声响不等于看见警员"
	return result

func conscious(u: Dictionary) -> bool:
	return not u.dead and not u.captured and int(u.stun)==0 and u.wound!="躯干"

func effective_wound(u: Dictionary) -> String:
	return "" if u.wound in ["手臂","腿"] and "Resilience" in u.skills else str(u.wound)

func active_enemies() -> Array:
	return enemies.filter(func(e): return not e.dead and not e.captured)

func occupied(ignore_id := -1) -> Dictionary:
	var blocked: Dictionary = {}
	for u in cops + enemies:
		if not u.dead and not u.captured and int(u.id) != ignore_id: blocked[u.pos] = true
	return blocked

func move_distance(c: Dictionary) -> int:
	return maxi(3, 5 + int(c.speed) - (2 if c.wound == "腿" else 0))

func reachable(c: Dictionary) -> Dictionary:
	if not conscious(c) or effective_wound(c)=="腿" or phase != "player": return {"costs": {}, "parents": {}}
	return nav.search([c.pos], move_distance(c) * 1.4 * int(c.ap), occupied(c.id))

func move(c: Dictionary, tile: Vector2i, presented := false) -> Array:
	if phase != "player" or c.dead or int(c.ap) <= 0 or tile == c.pos: return []
	var found := reachable(c)
	if not found.costs.has(tile):
		say("无法到达：目标被占用、行动点不足或需要先打开门窗。")
		return []
	var cost := int(ceil((float(found.costs[tile]) - 0.001) / (move_distance(c) * 1.4)))
	var route: Array = nav.path(c.pos, tile, found.parents)
	c.ap -= cost
	viewing_positions[c.id] = c.pos
	if not presented:
		for step: Vector2i in route: player_movement_step(c,step)
		viewing_positions.erase(c.id)
	c.pos = tile
	say("%s 移动，消耗 %d AP。" % [c.name, cost])
	return route

func player_movement_step(c: Dictionary, tile: Vector2i) -> void:
	if viewing_positions.get(c.id,c.pos)==tile: return
	viewing_positions[c.id]=tile
	ENEMY_AI.noise(self,tile,"move")
	for e: Dictionary in active_enemies(): ENEMY_AI.observe(self,e)

func adjacent(a: Vector2i, b: Vector2i) -> bool:
	if a == b: return true
	if Vector2(a).distance_to(Vector2(b)) > 1.42: return false
	for index in nav.crossing(a, b):
		if nav.kind(index) not in [0, 4]: return false
	return true

func can_collect_at(a: Vector2i, b: Vector2i) -> bool:
	# Battleground.HasAccessDiagonal(..., true) / CanInteractOver from the source:
	# loot on a cabinet remains reachable over its blockage edge, but not a wall.
	if not nav.cells.has(a) or not nav.cells.has(b) or int(nav.cells[a].Height) != int(nav.cells[b].Height): return false
	if a == b: return true
	if Vector2(a).distance_to(Vector2(b)) > 1.42: return false
	var crossed: Array = nav.crossing(a, b)
	# Validate the target side too: a diagonal must not reach through the
	# opposite wall of an enclosure. Cabinet edges remain interactable.
	for index in crossed:
		if nav.kind(index) not in [0, 2, 3, 4, 5, 8, 9]: return false
	return true

func weighted(keys: Array, weights: Array) -> String:
	var total := 0
	for w in weights: total += int(w)
	var value := rng.randi_range(1, maxi(1, total))
	for i in range(keys.size()):
		value -= int(weights[i])
		if value <= 0: return str(keys[i])
	return str(keys.back())

func spawn_loot(first := false) -> void:
	var spots: Array = data.loot_spawns.filter(func(p): return not loot.has(Vector2i(int(p.x), int(p.y))))
	var prefix := "HordeInitial" if first else "HordeWave"
	for category in ["Weapon", "Ammo", "Equipment", "RebelPoint"]:
		for i in range(int(params[prefix + category + "Loot"])):
			if spots.is_empty(): break
			var p: Dictionary = spots.pop_at(rng.randi_range(0, spots.size() - 1))
			var item := "Points"
			if category in ["Weapon", "Ammo"]:
				item = weighted(GUNS, [params.HordeRevolverChance, params.HordeGlockChance, params.HordeRifleChance, params.HordeShotgunChance])
			elif category == "Equipment":
				item = weighted(["BodyArmor", "Helmet", "Grenade", "Taser", "BigMedkit", "SmallMedkit"], [params.HordeBodyArmorChance, params.HordeHelmetChance, params.HordeGrenadeChance, params.HordeTaserChance, params.HordeBigMedkitChance, params.HordeSmallMedkitChance])
			loot[Vector2i(int(p.x), int(p.y))] = {"category": category, "item": item}

func loot_name(record: Dictionary) -> String:
	return str(NAMES.get(record.item, record.item)) + ("弹药" if record.category == "Ammo" else "")

func collect(c: Dictionary, tile: Vector2i, mode := "equip") -> bool:
	return INVENTORY.collect(self, c, tile, mode)
func open(c: Dictionary, index: int) -> bool:
	if phase != "player" or not conscious(c) or int(c.ap) < 1 or nav.kind(index) not in [10, 11]: return false
	if c.pos not in nav.edge_pair(index):
		say("先移动到门窗的相邻格。")
		return false
	# Horde closed entries in this export are unlocked. Lock metadata is retained.
	for d in data.doors + data.windows:
		if int(d.EdgeIndex) == index and int(d.IsLocked) != 0:
			say("此入口上锁，当前版本尚未接入该模式的撬锁动作。")
			return false
	nav.open_edge(index)
	ENEMY_AI.noise(self,c.pos,"door")
	for enemy: Dictionary in active_enemies(): ENEMY_AI.observe(self,enemy)
	c.ap -= 1
	say("%s 打开入口，消耗 1 AP。" % c.name)
	return true

func close_entry(c: Dictionary, index: int) -> bool:
	if phase != "player" or not conscious(c) or int(c.ap) < 1 or nav.kind(index) not in [3, 4]: return false
	if c.pos not in nav.edge_pair(index): return false
	var k: int = nav.kind(index)
	nav.opened.erase(index)
	nav.edges[index] = 10 if k == 3 else 11
	nav.rebuild()
	ENEMY_AI.noise(self,c.pos,"door")
	for enemy: Dictionary in active_enemies(): ENEMY_AI.observe(self,enemy)
	c.ap -= 1
	say("%s 关闭入口，消耗 1 AP。" % c.name)
	return true

func visible_enemy(e: Dictionary) -> bool:
	if e.dead or e.captured: return false
	return enemy_visible_at(e,e.pos)

func enemy_visible_at(e: Dictionary,tile: Vector2i) -> bool:
	if tile_visible(tile): return true
	# IsEnemyVisible also reveals alerted enemies able to shoot a conscious cop.
	# This prevents a wall-edge peek shot from an invisible armed opponent.
	if e.dead or e.captured or str(e.gun).is_empty(): return false
	for c: Dictionary in living_cops():
		if not conscious(c): continue
		var at: Vector2i = viewing_positions.get(c.id,c.pos)
		# Each cover opening shifts at most one cell. Both ends may lean,
		# so distance > range+2 is provably unreachable, even around cover.
		if Vector2(tile).distance_to(Vector2(at))>current_shot_range(e)+2.0: continue
		if nav.targeting(tile,at,current_shot_range(e),cover_enabled(e),cover_enabled(c),occupied(e.id)).clear: return true
	return false

func tile_visible(tile: Vector2i) -> bool:
	# Also used at the rendered position while an enemy's logical position is
	# already at its destination. Never reveal a hidden route just for playback.
	for c in living_cops():
		if not conscious(c): continue
		var origin: Vector2i = viewing_positions.get(c.id,c.pos)
		var sight := 20.0 if "SeeFar" in c.skills else 16.0
		if Vector2(origin).distance_to(Vector2(tile)) <= sight and nav.can_see(origin,tile,c.wound != "腿"): return true
	return false

func chance(c: Dictionary, e: Dictionary, part := "躯干", aimed := false) -> int:
	return roundi(float(shot_details(c,e,part,aimed).chance)*100.0)

func shot_details(c: Dictionary, e: Dictionary, part := "躯干", aimed := false) -> Dictionary:
	var trace := shot_trace(c,e)
	var distance := Vector2(trace.from).distance_to(Vector2(trace.to))
	var detail := BALLISTICS.evaluate(c,e,distance,float(RANGES.get(c.gun,0)),int(trace.cover),float(trace.fence),part,aimed)
	if not trace.clear: detail.chance = 0.0
	detail.trace = trace
	detail.distance = distance
	detail.range = current_shot_range(c)
	return detail

func cover_enabled(u: Dictionary) -> bool:
	return not u.get("moving_exposed",false) and not u.dead and not u.captured and int(u.stun)==0 and u.wound not in ["腿","躯干"]

func current_shot_range(u: Dictionary) -> float:
	var sight := 11.0 if u.side == "enemy" else 20.0 if "SeeFar" in u.skills else 16.0
	return minf(float(RANGES.get(u.gun,0)),sight)

func shot_trace(c: Dictionary,e: Dictionary) -> Dictionary:
	return nav.targeting(c.pos,e.pos,current_shot_range(c),cover_enabled(c),cover_enabled(e),occupied(c.id))

func action_reason(c: Dictionary, e: Dictionary, action: String) -> String:
	if c.wound=="躯干": return "躯干重伤倒地，需要队友使用大急救包"
	if phase != "player" or not conscious(c): return "当前不能行动"
	if effective_wound(c)=="手臂" and action in ["shoot","aim","knife","taser","grenade"]: return "手臂受伤，无法使用武器"
	if e.dead or e.captured: return "目标已退出战斗"
	if not visible_enemy(e) and not (action == "knife" and nav.knife_access(c.pos,e.pos)): return "目标不在视野中"
	var cost := 2 if action == "aim" else 1
	if int(c.ap) < cost: return "行动点不足"
	var distance := Vector2(c.pos).distance_to(Vector2(e.pos))
	if action in ["knife", "arrest"]:
		if action == "knife":
			if Vector2(c.pos).distance_to(Vector2(e.pos)) > 1.42: return "需要走到目标相邻格（含对角）"
			if not nav.knife_access(c.pos,e.pos): return "近身路线被障碍阻挡；请绕到目标同侧"
			if effective_wound(c)=="手臂": return "手臂受伤，无法使用匕首"
		elif not adjacent(c.pos, e.pos): return "需要靠近目标"
		if action == "arrest" and not e.surrender and int(e.stun) == 0 and int(e.bleed) == 0 and e.wound!="躯干": return "先喝止或击晕目标"
	elif action in ["shoot", "aim"]:
		if c.gun == "": return "需要先搜集枪械"
		if int(c.weapons.get(c.gun, 0)) <= 0: return "需要装填弹药"
		if distance > current_shot_range(c)+2: return "超出当前射程（%d 格）" % int(current_shot_range(c))
		if action == "aim" and "AimedShot" not in c.skills: return "没有精准射击技能"
	elif action == "surrender":
		if distance > 5: return "距离过远（5 格）"
		if e.surrender: return "目标已投降，请靠近逮捕"
	elif action == "remote_arrest":
		if "OrderToSurrender" not in c.skills: return "没有远距离逮捕技能"
		if c.skill_used: return "本回合已使用"
		if distance > 5: return "距离过远（5 格）"
	elif action in ["taser", "grenade"]:
		var item := "Taser" if action == "taser" else "Grenade"
		if int(c.supplies.get(item, 0)) <= 0: return "没有对应装备"
		if distance > (5 if action == "taser" else 8): return "超出投射距离"
	if action in ["shoot","aim"]:
		if not shot_trace(c,e).clear:
			if nav.targeting(c.pos,e.pos,INF,cover_enabled(c),cover_enabled(e),occupied(c.id)).clear: return "超出当前射程（%d 格）" % int(current_shot_range(c))
			return "墙体或高掩体挡住射击，且没有侧身开口"
	elif action != "knife" and not nav.clear_shot(c.pos, e.pos): return "目标被墙体或高掩体阻挡"
	return ""

func _kill(u: Dictionary) -> void:
	if u.dead: return
	u.dead = true
	u.ap = 0
	if u.side == "enemy": killed += 1
	say("%s 阵亡。" % u.name)
	if living_cops().is_empty(): phase = "defeat"

func hit(attacker: Dictionary, target: Dictionary, part: String) -> void:
	if part == "头" and target.helmet:
		target.helmet = false
		say("%s 的头盔挡下了这一枪。" % target.name)
	elif part == "躯干" and int(target.armor) > 0:
		target.armor -= 1
		say("%s 的防弹衣受损（剩余 %d）。" % [target.name, target.armor])
	elif part == "头" or target.wound != "": _kill(target)
	else:
		target.bleed = 3 if part=="躯干" else 5
		target.wound = part
		if part=="躯干": target.ap=0; target.overwatch=false
		say("%s 的%s受伤，需在失血前急救。" % [target.name, part])

func fire(c: Dictionary, e: Dictionary, part := "躯干", aimed := false, retry := false) -> void:
	if c.gun == "" or int(c.weapons.get(c.gun, 0)) <= 0: return
	c.facing=Vector2i(e.pos)-Vector2i(c.pos)
	var detail := shot_details(c,e,part,aimed)
	var probability: float = detail.chance
	c.weapons[c.gun] -= 1
	if c.side=="cop": ENEMY_AI.noise(self,c.pos,"shot")
	if rng.randf() < probability:
		var armor_before: int = e.armor
		var helmet_before: bool = e.helmet
		hit(c, e, part)
		if e.dead: e["death_animation"] = "damage_head" if part == "头" else "idle_body_damage"
		action_event(c,e,"shoot","防具抵挡" if int(e.armor)<armor_before or helmet_before != bool(e.helmet) else "击倒" if e.dead else part+"受伤",detail.trace)
		presentation_events.back()["body_part"] = part
	else:
		action_event(c,e,"shoot","未命中",detail.trace)
		say("%s 射击未命中 %s。" % [c.name, e.name])
		if not retry and "AdrenalineRush" in c.skills and int(c.weapons[c.gun]) > 0:
			say("肾上腺素：追加一枪。")
			fire(c, e, part, aimed, true)

func attack(c: Dictionary, e: Dictionary, action: String, part := "躯干", presented := false) -> bool:
	var reason := action_reason(c, e, action)
	if not reason.is_empty():
		say(reason)
		return false
	c.ap -= 2 if action == "aim" else 1
	match action:
		"knife":
			ENEMY_AI.noise(self,c.pos,"knife")
			_kill(e)
			action_event(c,e,"knife","击倒")
		"shoot", "aim": fire(c, e, part, action == "aim")
		"surrender", "remote_arrest":
			var probability := 55 + int(c.strength) * 6 + (15 if "SmoothOps" in c.skills else 0)
			if action == "remote_arrest": c.skill_used = true
			if e.surrender or int(e.stun) > 0 or rng.randi_range(1, 100) <= probability:
				e.surrender = true
				if action == "remote_arrest": _arrest(e)
				else: say("%s 举手投降，靠近后可逮捕。" % e.name)
			else: say("%s 拒绝投降。" % e.name)
		"arrest": _arrest(e)
		"taser":
			c.supplies.Taser -= 1
			e.stun = 2
			say("%s 被电击，暂时失去行动能力。" % e.name)
		"grenade":
			c.supplies.Grenade -= 1
			if presented: action_event(c,e,"grenade","震撼弹")
			else: grenade_impact(e.pos)
	return true

func grenade_impact(tile: Vector2i) -> Array:
	ENEMY_AI.noise(self,tile,"grenade")
	var affected: Array = []
	for target in active_enemies() + living_cops():
		if Vector2(target.pos).distance_to(Vector2(tile)) <= 2.5 and nav.clear_shot(tile,target.pos):
			target.stun = 2
			affected.append(target.id)
	say("震撼弹爆炸：范围内 %d 名敌我单位被击晕。" % affected.size())
	return affected

func _arrest(e: Dictionary) -> void:
	e.captured = true
	arrested += 1
	points += int(params.ArrestRebelPointsHorde)
	say("%s 已逮捕，获得 %d 反抗点数。" % [e.name, params.ArrestRebelPointsHorde])

func reload(c: Dictionary) -> bool:
	if phase != "player" or not conscious(c) or effective_wound(c)=="手臂" or c.gun == "": return false
	var n := mini(int(CAPACITY[c.gun]) - int(c.weapons[c.gun]), int(c.reserve.get(c.gun, 0)))
	if n <= 0:
		say("弹匣已满或没有对应备用弹药。")
		return false
	c.weapons[c.gun] += n
	c.reserve[c.gun] -= n
	ENEMY_AI.noise(self,c.pos,"reload")
	say("%s 装填了 %d 发子弹。" % [c.name, n])
	action_event(c,c,"reload")
	return true

func heal_reason(c: Dictionary,target: Dictionary,item: String) -> String:
	if phase!="player" or not conscious(c): return "当前队员无法急救；倒地后需要队友救援"
	if target.dead or target.captured: return "目标已退出战斗"
	if item not in ["SmallMedkit","BigMedkit"] or int(c.supplies.get(item,0))<=0: return "没有对应急救包"
	if int(c.ap)<1: return "行动点不足"
	if not adjacent(c.pos,target.pos): return "需要靠近目标同侧，不能隔墙急救"
	if target.wound=="" and int(target.bleed)<=0: return "目标没有伤口"
	if item=="SmallMedkit" and target.wound=="躯干" and int(target.bleed)<=0: return "已经止血；需要大急救包治疗倒地伤势"
	return ""

func heal(c: Dictionary, target: Dictionary, item := "") -> bool:
	if item.is_empty(): item="BigMedkit" if int(c.supplies.get("BigMedkit",0))>0 else "SmallMedkit"
	var reason := heal_reason(c,target,item)
	if not reason.is_empty(): say(reason); return false
	c.supplies[item] -= 1
	c.ap -= 1
	target.bleed = 0
	var down: bool = target.wound=="躯干"
	if not down or item=="BigMedkit":
		target.wound = ""
		if down: target.ap=int(target.max_ap)
		say("%s 已治愈 %s。" % [c.name,target.name])
	else: say("%s 已为 %s 止血；仍然倒地，需要大急救包。" % [c.name,target.name])
	return true

func wave_due() -> bool:
	return turn >= int(params.HordeWarmUpTurns) and (turn - int(params.HordeWarmUpTurns)) % int(params.HordeEnemySpawnTurns) == 0

func next_wave_in() -> int:
	if turn < int(params.HordeWarmUpTurns): return int(params.HordeWarmUpTurns) - turn
	return (int(params.HordeEnemySpawnTurns) - (turn - int(params.HordeWarmUpTurns)) % int(params.HordeEnemySpawnTurns)) % int(params.HordeEnemySpawnTurns)

func spawn_wave(count_override := -1, prefab_override := "", with_loot := true) -> void:
	# The original mission removes previous corpses before the next wave.
	enemies = enemies.filter(func(e): return not e.dead and not e.captured)
	wave += 1
	var count := int(params.HordeEnemyCount) + wave - 1
	if count_override >= 0: count = clampi(count_override, 0, 100)
	var spots: Array = data.enemy_spawns.duplicate()
	var occupied_cells := occupied()
	var spawned := 0
	var variants := [3 if wave >= 2 else 0, 2 if wave >= 3 else 0, 4 if wave >= 4 else 0]
	if wave >= 5:
		for i in range(3): variants[i] = rng.randi_range(0, maxi(0, count / 3 - 1))
	while spawned < count and not spots.is_empty():
		var spot: Dictionary = spots.pop_at(rng.randi_range(0, spots.size() - 1))
		var tile := Vector2i(int(spot.x), int(spot.y))
		if not nav.passable(tile) or occupied_cells.has(tile): continue
		var close := false
		for c in living_cops():
			if Vector2(c.pos).distance_to(Vector2(tile)) < 15.0: close = true
		if close: continue
		var e := unit("罪犯 %d" % next_id, tile, "enemy")
		e.alerted=true
		var tier := 0
		for i in range(3):
			if variants[i] > 0:
				variants[i] -= 1
				tier = i + 1
				break
		e.tier = tier
		var prefab: String = enemy_loadouts.tiers[tier-1] if tier>0 else enemy_loadouts.random[rng.randi_range(0,enemy_loadouts.random.size()-1)]
		if enemy_loadouts.prefabs.has(prefab_override):
			prefab = prefab_override
			e.tier = enemy_loadouts.tiers.find(prefab)+1
		var loadout: Dictionary = enemy_loadouts.prefabs[prefab]
		e.source_prefab = prefab
		e.gun = loadout.gun
		e.melee = loadout.melee
		e.machinegun = loadout.machinegun
		if not e.gun.is_empty():
			e.weapons[e.gun] = int(CAPACITY[e.gun])
			e.reserve[e.gun] = int(CAPACITY[e.gun]) * 3
		enemies.append(e)
		occupied_cells[tile] = true
		spawned += 1
	if wave > 1 and with_loot: spawn_loot()
	say("第 %d 波：%d 名敌人入场；搜集补给并保持队员存活。" % [wave, spawned])

func begin_enemy_turn() -> void:
	if phase != "player": return
	phase = "enemy"
	for c in cops:
		c.next_bonus = 1 if not c.dead and int(c.ap) > 0 and "Bide" in c.skills else 0
		c.counter = false
	if wave_due(): spawn_wave()
	for e: Dictionary in active_enemies():
		e.ap = enemy_action_limit(e)
		e.moves_used = 0
	build_flow()

func enemy_action_limit(e: Dictionary) -> int:
	# Enemy.MaxActionPointsCount: melee has 3; long guns gain 3 against >4 cops.
	if e.get("melee","") in ["Ax","Knife"]: return 3
	if e.gun in ["Rifle","Shotgun"] and living_cops().size()>4: return 3
	return 2

func build_flow() -> void:
	# Per-goal, topology-versioned flow fields; never seed from hidden cops.
	if flow_revision != nav.revision:
		flow.clear()
		flow_revision = nav.revision

func enemy_targets(e: Dictionary) -> Array:
	return ENEMY_AI.observe(self,e)

# Overwatch's extended range applies only to the actual intended shot target,
# not every officer the enemy could theoretically shoot (Overwatch.CanShoot).
func enemy_shot_target(e: Dictionary) -> int:
	if not conscious(e) or e.surrender or effective_wound(e)=="手臂": return -1
	for c: Dictionary in enemy_targets(e):
		if e.gun=="" and adjacent(e.pos,c.pos): return -1
		if e.gun!="" and shot_trace(e,c).clear:
			if int(e.weapons.get(e.gun,0))>0: return int(c.id)
			if int(e.reserve.get(e.gun,0))>0: return -1
	return -1

func enemy_action(e: Dictionary, presented := false) -> Dictionary:
	if int(e.ap)<=0: return {}
	var outcome := enemy_decision(e,presented)
	if outcome.is_empty(): e.ap=0
	elif outcome.get("kind","")!="reload": e.ap=maxi(0,int(e.ap)-1)
	if outcome.get("kind","")=="move": e.moves_used=int(e.get("moves_used",0))+1
	return outcome

func enemy_decision(e: Dictionary, presented := false) -> Dictionary:
	if phase != "enemy" or not conscious(e) or e.surrender: return {}
	var targets := enemy_targets(e)
	if living_cops().is_empty():
		phase = "defeat"
		return {}
	for c in targets:
		if e.wound=="手臂": break
		if e.gun=="" and adjacent(e.pos, c.pos):
			_kill(c)
			action_event(e,c,"knife","击倒")
			return {"kind": "attack", "from": e.pos, "to": c.pos}
		if e.gun != "" and shot_trace(e,c).clear:
			if int(e.weapons[e.gun]) <= 0:
				var n := mini(int(CAPACITY[e.gun]), int(e.reserve.get(e.gun, 0)))
				if n > 0:
					e.weapons[e.gun] = n
					e.reserve[e.gun] -= n
					action_event(e,e,"reload")
					return {"kind": "reload"}
			else:
				fire(e, c, ["躯干", "躯干", "手臂", "腿"][rng.randi_range(0, 3)])
				if not c.get("overwatch",false) and "SecondCheek" in c.skills and not c.counter and reaction_ready(c,e,current_shot_range(c)):
					reaction_queue.append(request_reaction(c,e,"反击"))
				return {"kind": "attack", "from": e.pos, "to": c.pos}
	if int(e.get("moves_used",0))>=2: return {"kind":"wait"}
	return ENEMY_AI.move(self,e,targets,presented)

func finish_enemy_turn() -> void:
	if phase == "defeat": return
	for u in cops + enemies:
		if u.dead or u.captured: continue
		if int(u.stun) > 0: u.stun -= 1
		if int(u.bleed) > 0:
			u.bleed -= 1
			if int(u.bleed) == 0:
				_kill(u)
				action_event(u,u,"death","失血阵亡")
	if phase == "defeat": return
	turn += 1
	phase = "player"
	if turn == 40 and not backup_spawned: spawn_backup()
	for c in cops:
		c.max_ap = 2 + int(c.get("next_bonus", 0))
		c.ap = 0 if not conscious(c) else int(c.max_ap)
		if c.wound != "" and "Resilience" not in c.skills: c.ap = mini(1, int(c.ap))
		c.skill_used = false
		c.overwatch = false
		c.accuracy_buff = 0
	reaction_queue.clear()
	say("回合 %d · 你的行动%s" % [turn, " · 本回合结束将有新敌人入场" if wave_due() else ""])

func spawn_backup() -> void:
	var blocked := occupied()
	var spots: Array = data.cop_spawns.filter(func(p): return not blocked.has(Vector2i(int(p.X), int(p.Y))))
	if spots.is_empty():
		say("增援暂时没有可用部署位置。")
		return
	var p: Dictionary = spots[rng.randi_range(0, spots.size() - 1)]
	var record: Dictionary = data.employees[26]
	var c := unit(record.name, Vector2i(int(p.X), int(p.Y)), "cop")
	c.employee = record.id
	c.gender = int(record.gender)
	c.age = int(record.age)
	c.skills = SKILLS.duplicate()
	c.speed = 3
	c.strength = 3
	c.shooting = 3
	c.weapons = {"Glock": 9, "Rifle": 1}
	c.reserve = {"Glock": 18, "Rifle": 5}
	c.gun = "Rifle"
	c.armor = 2
	c.helmet = true
	c.supplies = {"Taser": 1, "Grenade": 1, "BigMedkit": 1}
	cops.append(c)
	backup_spawned = true
	say("第 40 回合：%s 携带装备前来增援。" % c.name)

func result() -> Dictionary:
	return {"turns": turn, "waves": wave, "kills": killed, "arrests": arrested, "loot": collected, "points": points, "seed": seed_value}
