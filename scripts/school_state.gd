extends "res://scripts/horde_state.gd"

var hostages: Array=[]
var rescued_count:=0
var discovered_hostages: Dictionary={}

func awareness_extra_signature() -> int:
	# Hostages occupy potential lean-out cells as well.
	return hostages.hash()

func initialize(source: Dictionary,random_seed: int=-1) -> void:
	super.initialize(source,41001 if random_seed<0 else random_seed)
	loot.clear()
	log.clear()
	wave=1
	backup_spawned=true
	data["guard_patrol"]=true
	var guns: Array=["Glock","Revolver","Rifle","Glock"]
	for i in range(cops.size()):
		var c: Dictionary=cops[i]
		c.pos=Vector2i(46+i*2,6)
		c.speed=2
		c.shooting=3
		c.strength=2
		c.skills=["AimedShot","SecondCheek","SeeFar"]
		c.gun=guns[i]
		c.weapons={c.gun:int(CAPACITY[c.gun])}
		c.reserve={c.gun:int(CAPACITY[c.gun])*3}
		c.armor=2
		c.supplies={"Taser":1,"SmallMedkit":1}
	var deployments: Array=[
		[Vector2i(45,22),"Glock","庭院哨兵"],[Vector2i(55,25),"Revolver","花坛守卫"],
		[Vector2i(37,48),"Glock","走廊守卫"],[Vector2i(27,62),"Revolver","教学楼哨兵"],
		[Vector2i(30,71),"Glock","教室守卫"],[Vector2i(61,59),"Revolver","图书馆守卫"],
		[Vector2i(86,54),"Glock","食堂守卫"],[Vector2i(90,75),"Rifle","操场守卫"]]
	for entry in deployments:
		var e:=unit(entry[2],free_near(entry[0]),"enemy")
		e.gun=entry[1]
		e.weapons={e.gun:int(CAPACITY[e.gun])}
		e.reserve={e.gun:int(CAPACITY[e.gun])*2}
		e.shooting=1
		e.source_prefab=""
		e.guard_origin=e.pos
		e.alerted=false
		e.facing=Vector2i.UP
		enemies.append(e)
	for entry in [["值班教师",Vector2i(54,23),0],["图书管理员",Vector2i(60,55),1],["授课教师",Vector2i(25,71),0]]:
		var h:=unit(entry[0],free_near(entry[1]),"hostage")
		h.gender=entry[2]
		h.rescued=false
		hostages.append(h)
	for entry in [[Vector2i(49,14),"Ammo","Glock"],[Vector2i(50,14),"Equipment","BigMedkit"],[Vector2i(38,54),"Ammo","Rifle"],[Vector2i(73,56),"Equipment","BodyArmor"]]:
		loot[free_near(entry[0])]={"category":entry[1],"item":entry[2]}
	say("潜入开局：警员在校门外部署，守卫尚未发现你。利用建筑与掩体接近，枪声和近处脚步会引起调查。解救 3 位教职工，制服全部 8 名敌人。")

func free_near(origin: Vector2i) -> Vector2i:
	var blocked:=occupied()
	for radius in range(8):
		for y in range(origin.y-radius,origin.y+radius+1):
			for x in range(origin.x-radius,origin.x+radius+1):
				var at:=Vector2i(x,y)
				if nav.passable(at) and not blocked.has(at): return at
	return Vector2i(-1,-1)

func occupied(ignore_id: int=-1) -> Dictionary:
	var result:=super.occupied(ignore_id)
	for h: Dictionary in hostages:
		if int(h.id)!=ignore_id: result[h.pos]=true
	return result

func hostage_visible(h: Dictionary) -> bool:
	var seen:=tile_visible(h.pos)
	if seen: discovered_hostages[h.id]=true
	return seen

func rescue_reason(c: Dictionary,h: Dictionary) -> String:
	if h.rescued: return "已解救"
	if phase!="player" or not conscious(c): return "等待清醒警员的行动回合"
	if int(c.ap)<1: return "需要 1 AP"
	if not hostage_visible(h): return "人质不在警员视野中"
	if not nav.knife_access(c.pos,h.pos): return "请从通道走到人质相邻格；不能隔墙解救"
	for e: Dictionary in active_enemies():
		if conscious(e) and not e.surrender and Vector2(e.pos).distance_to(Vector2(h.pos))<=5 and nav.can_see(e.pos,h.pos):
			return "先制服人质附近的看守（5 格内可见威胁）"
	return ""

func rescue(c: Dictionary,h: Dictionary) -> bool:
	var reason:=rescue_reason(c,h)
	if not reason.is_empty(): say(reason);return false
	c.ap-=1
	h.rescued=true
	rescued_count+=1
	say("%s 解救了%s · 消耗 1 AP · 已解救 %d/3"%[c.name,h.name,rescued_count])
	return true

func check_mission() -> void:
	if phase=="player" and rescued_count==hostages.size() and active_enemies().is_empty():
		phase="victory"
		say("校园行动完成：全部教职工获救，敌人已被制服。")

func wave_due() -> bool: return false
func next_wave_in() -> int: return 0
func spawn_backup() -> void: pass
