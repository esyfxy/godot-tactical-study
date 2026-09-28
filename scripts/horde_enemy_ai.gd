extends RefCounted

# User-selected fair tracking variant, not the original all-alarm omniscience.
# Cover scoring follows PossibleCover; hearing/memory durations are local tuning.
const MEMORY_TURNS := 4
const HEARING = {"shot":18.0,"move":3.0,"door":4.0,"reload":3.0,"knife":2.0,"grenade":20.0}
const SEARCH_RADIUS := 6.0
const COMMUNICATION_RADIUS := 6.0

static func search_origin(s,e: Dictionary,at: Vector2i) -> void:
	if e.get("search_origin",Vector2i(-1,-1)) != at:
		e.erase("patrol")
		e.search_visited = []
	e.search_origin = at
	e.search_turn = s.turn

static func observe(s,e: Dictionary) -> Array:
	if not e.has("known"): e.known = {}
	if not s.conscious(e):
		e.visible_ids=[]
		return []
	var visible: Array = []
	for c: Dictionary in s.living_cops():
		var at: Vector2i = s.viewing_positions.get(c.id,c.pos)
		if Vector2(e.pos).distance_to(Vector2(at))<=11 and s.nav.can_see(e.pos,at,s.cover_enabled(e)):
			visible.append(c)
			var changed: bool = not e.known.has(c.id) or e.known[c.id].pos != at or int(e.known[c.id].turn) != s.turn
			e.known[c.id] = {"pos":at,"turn":s.turn,"source":"sight"}
			search_origin(s,e,at)
			if changed:
				# One-hop communication from a direct witness only. Recipients
				# cannot relay a report and turn it into map-wide omniscience.
				for ally: Dictionary in s.active_enemies():
					if ally.id==e.id or int(ally.stun)>0 or Vector2(e.pos).distance_to(Vector2(ally.pos))>COMMUNICATION_RADIUS or not s.nav.can_see(e.pos,ally.pos): continue
					if not ally.has("known"): ally.known = {}
					var old: Dictionary = ally.known.get(c.id,{})
					if old.is_empty() or int(old.turn)<s.turn or (old.get("source","")!="sight" and int(old.turn)<=s.turn):
						ally.known[c.id] = {"pos":at,"turn":s.turn,"source":"report","witness":e.id}
						search_origin(s,ally,at)
	for id in e.known.keys():
		var memory: Dictionary = e.known[id]
		var seen_now: bool = visible.any(func(c): return c.id==id)
		if s.turn-int(memory.turn)>MEMORY_TURNS or (not seen_now and Vector2(e.pos).distance_to(Vector2(memory.pos))<=2 and s.nav.can_see(e.pos,memory.pos)):
			e.known.erase(id)
	visible.sort_custom(func(a,b): return Vector2(e.pos).distance_squared_to(Vector2(a.pos))<Vector2(e.pos).distance_squared_to(Vector2(b.pos)))
	e.visible_ids = visible.map(func(c): return c.id)
	if not visible.is_empty(): e.behavior="combat"
	return visible

static func noise(s,at: Vector2i,kind: String) -> void:
	var listeners: Array = s.active_enemies().filter(func(e): return int(e.stun)==0 and Vector2(e.pos).distance_to(Vector2(at))<=float(HEARING[kind]))
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
	var best: Vector2i = e.pos
	var distance := INF
	var newest := -1
	for memory: Dictionary in e.get("known",{}).values():
		var d := Vector2(e.pos).distance_squared_to(Vector2(memory.pos))
		if int(memory.turn)>newest or (int(memory.turn)==newest and d<distance):
			distance=d; best=memory.pos; newest=int(memory.turn)
	if e.has("heard"):
		var heard_age: int=s.turn-int(e.heard.turn)
		if heard_age>MEMORY_TURNS or Vector2(e.pos).distance_to(Vector2(e.heard.pos))<=1.5:
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
			var candidate := cover_score(s,e,tile,targets,passive)
			if candidate<score-.01: best=tile; score=candidate
		if best!=start:
			route = s.nav.path(start,best,reach.parents)
			e.intent="寻找安全掩体" if passive else "绕向侧翼掩体"
		elif passive: return {"kind":"wait"}
	if route.is_empty():
		var target := goal(s,e)
		var local_search: bool = e.get("behavior","") in ["search","patrol"]
		var costs: Dictionary = field(s,target,(SEARCH_RADIUS*2+5)*1.4 if local_search else 10000.0).costs
		var current := start
		var remaining := 7.0
		while remaining>0:
			var best := current
			var best_cost := float(costs.get(current,INF))
			for n: Vector2i in s.nav.assault_neighbors.get(current,[]):
				if blocked.has(n): continue
				if float(costs.get(n,INF))<best_cost and s.nav.step_cost(current,n)<=remaining+.001:
					best=n; best_cost=float(costs[n])
			if best==current: break
			remaining-=s.nav.step_cost(current,best)
			current=best
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
		previous=tile
		if not presented:
			e.pos=tile
			var seen := observe(s,e)
			if seen.any(func(c): return not targets.any(func(old): return old.id==c.id)):
				e.intent="发现目标，重新判断"; break
	e.pos=previous
	return {"kind":"move","route":traversed,"from":start}
