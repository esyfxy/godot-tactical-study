extends RefCounted

# User-selected fair tracking variant, not the original all-alarm omniscience.
# Cover scoring follows PossibleCover; hearing/memory durations are local tuning.
const MEMORY_TURNS := 4
const HEARING = {"shot":18.0,"move":3.0,"door":4.0,"reload":3.0,"knife":2.0,"grenade":20.0}
const SEARCH_RADIUS := 6.0
const COMMUNICATION_RADIUS := 6.0

static func alerted(s,e: Dictionary) -> bool:
	# Horde waves start under alarm; campus sentries start unaware.
	return bool(e.get("alerted",s.data==null or not s.data.get("guard_patrol",false)))

static func vision_area(s,e: Dictionary,at: Vector2i) -> int:
	# Enemy.GetObjectsDistanceInVision: 3/8/11 cells, 135/90/60 degree cones.
	# Adjacent uncovered units can be noticed even outside the forward cone.
	var offset:=at-Vector2i(e.pos)
	var distance:=Vector2(offset).length()
	if distance>11 or not s.nav.can_see(e.pos,at,s.cover_enabled(e)): return 0
	var tier:=1 if distance<=3.5 else 2 if distance<=8.5 else 3
	if alerted(s,e): return tier
	if s.nav.shot_cover(at,e.pos)>0: return 0
	if absi(offset.x)<=1 and absi(offset.y)<=1: return 1
	var facing: Vector2=Vector2(e.get("facing",Vector2i.DOWN)).normalized()
	var width:=60.0 if tier==3 else 90.0 if tier==2 else 95.0 if e.get("ai_moving",false) else 135.0
	if absf(facing.angle_to(Vector2(offset)))>=deg_to_rad(width*.5)-.0001: return 0
	return tier

static func awareness(s,e: Dictionary) -> String:
	if not s.conscious(e) or e.surrender: return "inactive"
	if not e.get("visible_ids",[]).is_empty(): return "combat"
	if e.get("known",{}).values().any(func(m): return s.turn-int(m.turn)<=MEMORY_TURNS): return "track"
	if not e.get("suspected",{}).is_empty() and s.turn-int(e.suspected.last_turn)<=1: return "suspicious"
	if e.has("heard") and s.turn-int(e.heard.turn)<=MEMORY_TURNS: return "investigate"
	if e.has("search_origin") and s.turn-int(e.get("search_turn",0))<=MEMORY_TURNS: return "search"
	return "patrol" if s.data!=null and s.data.get("guard_patrol",false) else "sweep"

# Fixed deployment areas and map sectors, never the current positions of cops.
# Searching an entire battlefield is different from omniscient pursuit.
static func map_objectives(s) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for spawn: Dictionary in s.data.get("cop_spawns",[]):
		var tile := Vector2i(int(spawn.X),int(spawn.Y))
		if s.nav.passable(tile) and tile not in result: result.append(tile)
	for y in range(3):
		for x in range(3):
			var center := Vector2i((x*2+1)*s.nav.width/6,(y*2+1)*s.nav.height/6)
			var best := Vector2i(-1,-1)
			var distance := INF
			for dx in range(-8,9):
				for dy in range(-8,9):
					var tile := center+Vector2i(dx,dy)
					var d := Vector2(tile-center).length_squared()
					if d<distance and s.nav.passable(tile): best=tile; distance=d
			if best.x>=0 and best not in result: result.append(best)
	return result

static func sweep_goal(s,e: Dictionary) -> Vector2i:
	if s.ai_objectives.is_empty(): s.ai_objectives=map_objectives(s)
	if s.ai_objectives.is_empty(): return e.pos
	var index: int = int(e.get("sweep_index",int(e.id)))%s.ai_objectives.size()
	for attempt in range(s.ai_objectives.size()):
		var target: Vector2i = s.ai_objectives[index]
		var costs: Dictionary = field(s,target).costs
		var inspected: bool = float(costs.get(e.pos,INF))<=2.8 and s.nav.can_see(e.pos,target)
		if not inspected and costs.has(e.pos):
			e.sweep_index=index
			e.behavior="sweep"; e.intent="搜索部署区 / 推进战区"
			return target
		index=(index+1)%s.ai_objectives.size()
	e.sweep_index=index
	return e.pos

static func guard_goal(s,e: Dictionary) -> Vector2i:
	var origin: Vector2i=e.get("guard_origin",e.pos)
	if not e.has("guard_route"):
		e.guard_route=[]
		for offset in [Vector2i(-2,0),Vector2i(0,2),Vector2i(2,0),Vector2i(0,-2),Vector2i.ZERO]:
			var tile: Vector2i=origin+offset
			if s.nav.passable(tile) and s.nav.can_see(origin,tile): e.guard_route.append(tile)
	if e.guard_route.is_empty(): return origin
	var index: int=int(e.get("guard_index",0))%e.guard_route.size()
	if Vector2(e.pos).distance_to(Vector2(e.guard_route[index]))<1.5: index=(index+1)%e.guard_route.size()
	e.guard_index=index
	e.behavior="patrol";e.intent="巡查岗位附近"
	return e.guard_route[index]

static func search_origin(s,e: Dictionary,at: Vector2i) -> void:
	if e.get("search_origin",Vector2i(-1,-1)) != at:
		e.erase("patrol")
		e.search_visited = []
	e.search_origin = at
	e.search_turn = s.turn

static func observe(s,e: Dictionary) -> Array:
	if not e.has("known"): e.known = {}
	if not s.conscious(e) or e.surrender:
		e.visible_ids=[]
		return []
	if not e.get("suspected",{}).is_empty() and s.turn-int(e.suspected.last_turn)>1: e.erase("suspected")
	var visible: Array = []
	for c: Dictionary in s.living_cops():
		var at: Vector2i = s.viewing_positions.get(c.id,c.pos)
		var area:=vision_area(s,e,at)
		if area>0:
			if not alerted(s,e) and area>1:
				var suspicion: Dictionary=e.get("suspected",{})
				if suspicion.is_empty():
					e.suspected={"cop":c.id,"pos":at,"turn":s.turn,"last_turn":s.turn}
					s.awareness_event(e,c,false)
				elif int(suspicion.cop)!=int(c.id):
					# Multiple distant officers must not reset caution every frame.
					continue
				elif int(suspicion.turn)>=s.turn:
					e.suspected.pos=at;e.suspected.last_turn=s.turn
				else:
					e.alerted=true
				if not alerted(s,e):
					e.behavior="suspicious";e.intent="怀疑人影，前往核实"
					continue
			e.alerted=true;e.erase("suspected")
			visible.append(c)
			if not e.known.has(c.id): s.awareness_event(e,c,true)
			var changed: bool = not e.known.has(c.id) or e.known[c.id].pos != at or int(e.known[c.id].turn) != s.turn
			e.known[c.id] = {"pos":at,"turn":s.turn,"source":"sight"}
			search_origin(s,e,at)
			if changed:
				# One-hop communication from a direct witness only. Recipients
				# cannot relay a report and turn it into map-wide omniscience.
				for ally: Dictionary in s.active_enemies():
					if ally.id==e.id or not s.conscious(ally) or ally.surrender or Vector2(e.pos).distance_to(Vector2(ally.pos))>COMMUNICATION_RADIUS or not s.nav.can_see(e.pos,ally.pos): continue
					if not ally.has("known"): ally.known = {}
					var old: Dictionary = ally.known.get(c.id,{})
					if old.is_empty() or int(old.turn)<s.turn or (old.get("source","")!="sight" and int(old.turn)<=s.turn):
						ally.known[c.id] = {"pos":at,"turn":s.turn,"source":"report","witness":e.id}
						ally.alerted=true
						search_origin(s,ally,at)
	for id in e.known.keys():
		var memory: Dictionary = e.known[id]
		var seen_now: bool = visible.any(func(c): return c.id==id)
		if s.turn-int(memory.turn)>MEMORY_TURNS or (not seen_now and Vector2(e.pos).distance_to(Vector2(memory.pos))<=2 and s.nav.can_see(e.pos,memory.pos)):
			e.known.erase(id)
	visible.sort_custom(func(a,b): return Vector2(e.pos).distance_squared_to(Vector2(a.pos))<Vector2(e.pos).distance_squared_to(Vector2(b.pos)))
	e.visible_ids = visible.map(func(c): return c.id)
	if not visible.is_empty():
		e.behavior="combat";e.intent="已确认警员，交战"
	elif not e.get("suspected",{}).is_empty(): e.behavior="suspicious"
	else: e.behavior=awareness(s,e)
	return visible

static func noise(s,at: Vector2i,kind: String) -> void:
	var listeners: Array = s.active_enemies().filter(func(e): return s.conscious(e) and not e.surrender and Vector2(e.pos).distance_to(Vector2(at))<=float(HEARING[kind]))
	if listeners.is_empty(): return
	# Sound follows accessible terrain; walls cannot be bypassed by distance alone.
	var reach: Dictionary = s.nav.search([at],float(HEARING[kind])*1.4,{},true)
	for e: Dictionary in listeners:
		if not reach.costs.has(e.pos): continue
		var old: Dictionary = e.get("heard",{})
		# A faint footstep does not erase a still-recent gunshot investigation.
		if not old.is_empty() and s.turn-int(old.turn)<=1 and float(HEARING.get(old.kind,0))>float(HEARING[kind]): continue
		e.heard = {"pos":at,"turn":s.turn,"kind":kind}

static func goal(s,e: Dictionary) -> Vector2i:
	if not e.get("visible_ids",[]).is_empty():
		var id: int=e.visible_ids[0]
		if e.get("known",{}).has(id):
			e.behavior="combat";e.intent="逼近已确认目标"
			return e.known[id].pos
	if not e.get("suspected",{}).is_empty():
		if s.turn-int(e.suspected.last_turn)<=1:
			e.behavior="suspicious";e.intent="前往核实人影"
			return e.suspected.pos
		e.erase("suspected")
	var best: Vector2i = e.pos
	var distance := INF
	var newest := -1
	for memory: Dictionary in e.get("known",{}).values():
		var d := Vector2(e.pos).distance_squared_to(Vector2(memory.pos))
		if int(memory.turn)>newest or (int(memory.turn)==newest and d<distance):
			distance=d; best=memory.pos; newest=int(memory.turn)
	if e.has("heard"):
		var heard_age: int=s.turn-int(e.heard.turn)
		if heard_age>MEMORY_TURNS or (Vector2(e.pos).distance_to(Vector2(e.heard.pos))<=1.5 and s.nav.can_see(e.pos,e.heard.pos)):
			if heard_age<=MEMORY_TURNS: search_origin(s,e,e.heard.pos)
			e.erase("heard")
		elif heard_age>=0 and (int(e.heard.turn)>newest or (int(e.heard.turn)==newest and e.heard.kind in ["shot","grenade"])) and e.get("visible_ids",[]).is_empty():
			# Footsteps, doors, and reloads are evidence too. Previously they were
			# recorded in `heard` but only gunfire/grenades could ever select that
			# destination, so stealth approaches produced meaningless local patrol.
			e.behavior="investigate"
			e.intent="调查脚步声" if e.heard.kind=="move" else "调查开门声" if e.heard.kind=="door" else "调查声响"
			return e.heard.pos
	if best!=e.pos:
		e.behavior="track"; e.intent="追踪最后目击位置"; return best
	var searching: bool = e.has("search_origin") and s.turn-int(e.get("search_turn",0))<=MEMORY_TURNS
	if not searching:
		if e.has("search_origin"):
			e.erase("patrol")
			e.erase("search_visited")
			e.erase("search_origin")
			e.erase("search_turn")
		if s.data.get("guard_patrol",false):
			e.alerted=false
			return guard_goal(s,e)
		return sweep_goal(s,e)
	if not e.has("patrol") or Vector2(e.pos).distance_to(Vector2(e.patrol))<1.5:
		var origin: Vector2i = e.get("search_origin",e.pos)
		var reach: Dictionary = s.nav.search([origin],SEARCH_RADIUS*1.4,{},true)
		var visited: Array = e.get("search_visited",[])
		if e.has("patrol"): visited.append(e.patrol)
		var occupied: Dictionary = s.occupied(e.id)
		var tiles: Array = reach.costs.keys().filter(func(tile): return tile!=e.pos and tile not in visited and s.nav.passable(tile) and not occupied.has(tile))
		tiles.sort_custom(func(a,b): return a.y<b.y if a.y!=b.y else a.x<b.x)
		if tiles.is_empty(): visited.clear(); e.patrol=e.pos
		else: e.patrol=tiles[(int(e.id)*31+visited.size()*7)%tiles.size()]
		e.search_visited=visited.slice(maxi(0,visited.size()-12))
	e.behavior="search" if searching else "patrol"
	e.intent="搜索最后位置附近" if searching else "附近巡查"
	return e.patrol

# Occupancy-aware A*: the static field is a lower bound, not a rule that every
# step must reduce distance. This permits backing up around a blocked lane.
static func route_to(s,start: Vector2i,target: Vector2i,blocked: Dictionary,costs: Dictionary) -> Array:
	if start==target or not costs.has(start): return []
	var heap: Array=[]
	var traveled := {start:0.0}
	var parents := {start:start}
	s.nav._push(heap,[float(costs[start]),start])
	var expanded := 0
	while not heap.is_empty() and expanded<4000:
		var item: Array=s.nav._pop(heap)
		var tile: Vector2i=item[1]
		if float(item[0])>float(traveled[tile])+float(costs.get(tile,INF))+.001: continue
		if tile==target:
			var route: Array=s.nav.path(start,target,parents)
			if blocked.has(target): route.pop_back()
			return route
		expanded+=1
		for n: Vector2i in s.nav.assault_neighbors.get(tile,[]):
			if (blocked.has(n) and n!=target) or not costs.has(n): continue
			var distance: float=float(traveled[tile])+s.nav.step_cost(tile,n)
			if distance+.001>=float(traveled.get(n,INF)): continue
			traveled[n]=distance; parents[n]=tile
			s.nav._push(heap,[distance+float(costs[n]),n])
	return []

static func field(s,target: Vector2i,limit := 10000.0) -> Dictionary:
	s.build_flow()
	var key := Vector4i(target.x,target.y,s.nav.revision,ceili(limit*10))
	if s.ai_cache_enabled and s.flow.has(key): return s.flow[key]
	var result: Dictionary = s.nav.search([target],limit,{},true)
	if s.ai_cache_enabled:
		if s.flow.size()>=64: s.flow.erase(s.flow.keys()[0])
		s.flow[key] = result
	return result

static func cover_score(s,e: Dictionary,tile: Vector2i,targets: Array,passive: bool) -> float:
	var nearest := INF
	var incoming := 0
	var exposed := 0
	var outgoing := 0
	for c: Dictionary in targets:
		nearest = minf(nearest,Vector2(tile).distance_to(Vector2(c.pos))*1.4)
		var toward: Dictionary = s.nav.targeting(c.pos,tile,s.current_shot_range(c),s.cover_enabled(c),s.cover_enabled(e))
		if toward.clear:
			incoming+=1
			if int(toward.cover)==0: exposed+=1
		if s.nav.targeting(tile,c.pos,s.current_shot_range(e),s.cover_enabled(e),s.cover_enabled(c)).clear: outgoing+=1
	return (Vector2(e.pos).distance_to(Vector2(tile))*1.4 if passive else nearest)+incoming*10+exposed*10-outgoing*5

static func move(s,e: Dictionary,targets: Array,presented := false) -> Dictionary:
	if not s.conscious(e) or s.effective_wound(e)=="腿": e.intent="受伤，无法移动"; return {"kind":"wait"}
	var blocked: Dictionary = s.occupied(e.id)
	var start: Vector2i = e.pos
	var route: Array = []
	var passive: bool = e.wound=="手臂"
	if not targets.is_empty() and (e.gun!="" or passive):
		var reach: Dictionary = s.nav.search([start],7.0,blocked,true)
		var best := start
		var score := cover_score(s,e,start,targets,passive)
		for tile: Vector2i in reach.costs:
			if tile==start or s.nav.covers_at(tile).is_empty(): continue
			# A safe dead-end with no shot is not an offensive firing position.
			if not passive and not targets.any(func(c): return s.nav.targeting(tile,c.pos,s.current_shot_range(e),s.cover_enabled(e),s.cover_enabled(c)).clear): continue
			var candidate := cover_score(s,e,tile,targets,passive)
			if candidate<score-.01: best=tile; score=candidate
		if best!=start:
			route = s.nav.path(start,best,reach.parents)
			e.intent="寻找安全掩体" if passive else "绕向侧翼掩体"
		elif passive: return {"kind":"wait"}
	if route.is_empty():
		var target := goal(s,e)
		# Returning from a distant investigation must not use a local search cap.
		var local_search: bool = e.get("behavior","")=="search"
		var costs: Dictionary = field(s,target,(SEARCH_RADIUS*2+5)*1.4 if local_search else 10000.0).costs
		var remaining := 7.0
		var current := start
		for next: Vector2i in route_to(s,start,target,blocked,costs):
			var step: float=s.nav.step_cost(current,next)
			if step>remaining+.001: break
			remaining-=step
			current=next
			route.append(current)
			# Stop as soon as an observed target can be attacked: no blind full sprint.
			if not passive and targets.any(func(c): return s.nav.knife_access(current,c.pos) if e.gun=="" else s.nav.targeting(current,c.pos,s.current_shot_range(e)).clear): break
	var traversed: Array = []
	var previous := start
	for tile: Vector2i in route:
		var index: int = s.nav.edge(previous,tile)
		if s.nav.kind(index) in [10,11]:
			if traversed.is_empty(): s.nav.open_edge(index); return {"kind":"open","edge":index}
			break
		traversed.append(tile)
		if not presented: e.facing=tile-previous
		previous=tile
		if not presented:
			e.pos=tile
			e.ai_moving=true
			var was_suspicious: bool=not e.get("suspected",{}).is_empty()
			var seen := observe(s,e)
			e.ai_moving=false
			if seen.any(func(c): return not targets.any(func(old): return old.id==c.id)) or (not was_suspicious and not e.get("suspected",{}).is_empty()):
				e.intent="发现目标，重新判断"; break
	e.pos=previous
	return {"kind":"move","route":traversed,"from":start}
