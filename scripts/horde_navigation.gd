extends RefCounted

# Source edge encoding, 1.4 m cells and stair checks. Dimensions are mission data.
const DIRS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]
var width: int
var height: int
var cells: Dictionary = {}
var edges: Array = []
var opened: Dictionary = {}
var neighbors: Dictionary = {}
var assault_neighbors: Dictionary = {}
var room_ids: Array = []
var revision := 0
var search_calls := 0

func configure(data: Dictionary) -> void:
	width = int(data.grid_size[0])
	height = int(data.grid_size[1])
	edges = data.grid_edges.duplicate()
	if data.has("room_ids"):
		room_ids = data.room_ids.duplicate()
	elif FileAccess.file_exists("res://assets/horde/room_ids.json"):
		room_ids = JSON.parse_string(FileAccess.get_file_as_string("res://assets/horde/room_ids.json"))
	for c in data.grid_cells: cells[Vector2i(int(c.PositionX), int(c.PositionY))] = c
	rebuild()

func inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

func passable(p: Vector2i) -> bool:
	return cells.has(p) and int(cells[p].IsPassable) != 0

func edge(a: Vector2i, b: Vector2i) -> int:
	if not inside(a) or not inside(b) or absi(a.x - b.x) + absi(a.y - b.y) != 1: return -1
	return (maxi(a.y, b.y) * width + maxi(a.x, b.x)) * 2 + (1 if a.x != b.x else 0)

func edge_pair(index: int) -> Array:
	var a := Vector2i((index / 2) % width, index / (width * 2))
	return [a, a + (Vector2i.LEFT if index % 2 else Vector2i.UP)]

func kind(index: int) -> int:
	if index < 0 or index >= edges.size(): return -1
	var k := int(edges[index])
	if opened.has(index):
		if k == 10: return 3
		if k == 11: return 4
	return k

func crossing(a: Vector2i, b: Vector2i) -> Array:
	var d := b - a
	if absi(d.x) > 1 or absi(d.y) > 1 or d == Vector2i.ZERO: return []
	if d.x == 0 or d.y == 0: return [edge(a, b)]
	var h := a + Vector2i(d.x, 0)
	var v := a + Vector2i(0, d.y)
	return [edge(a, h), edge(a, v), edge(h, b), edge(v, b)]

func stairs_allow(a: Vector2i, b: Vector2i) -> bool:
	var ha := int(cells[a].Height)
	var hb := int(cells[b].Height)
	if ha == hb:
		if ha == 1: return false
		if a.x == b.x or a.y == b.y: return true
		return int(cells[Vector2i(a.x, b.y)].Height) == ha and int(cells[Vector2i(b.x, a.y)].Height) == ha
	if ha != 1 and hb != 1: return kind(edge(a, b)) == 13
	var stair: Vector2i = a if ha == 1 else b
	var other: Vector2i = b if ha == 1 else a
	var raised := int(cells[other].Height) == 2
	match int(cells[stair].LookDirection):
		0: return stair.x == other.x and (other.y <= stair.y or raised)
		1: return stair.y == other.y and (other.x <= stair.x or raised)
		2: return stair.x == other.x and (other.y >= stair.y or raised)
		3: return stair.y == other.y and (other.x >= stair.x or raised)
	return false

func can_cross(a: Vector2i, b: Vector2i, assault := false) -> bool:
	if not passable(a) or not passable(b) or not stairs_allow(a, b): return false
	var crossings := crossing(a, b)
	if crossings.is_empty(): return false
	for index in crossings:
		var k := kind(index)
		if crossings.size() > 1:
			if k not in [0, 4]: return false
		elif k not in [0, 3, 4, 5, 9, 13] and not (assault and k in [10, 11]): return false
	return true

func step_cost(a: Vector2i, b: Vector2i) -> float:
	var cost := Vector2(a).distance_to(Vector2(b)) * 1.4
	for index in crossing(a, b):
		if kind(index) in [3, 5, 9, 10, 11]: cost += 1.4
	return cost

func rebuild() -> void:
	revision += 1
	neighbors.clear()
	assault_neighbors.clear()
	for p in cells:
		if not passable(p): continue
		var normal: Array = []
		var assault: Array = []
		for d in DIRS:
			var n: Vector2i = p + d
			if can_cross(p, n): normal.append(n)
			if can_cross(p, n, true): assault.append(n)
		neighbors[p] = normal
		assault_neighbors[p] = assault

func open_edge(index: int) -> void:
	revision += 1
	opened[index] = true
	# Only the endpoints and their diagonal neighbors can change connectivity.
	for p in edge_pair(index):
		for d in DIRS + [Vector2i.ZERO]:
			var a: Vector2i = p + d
			if not passable(a): continue
			var ns: Array = []
			for offset in DIRS:
				if can_cross(a, a + offset): ns.append(a + offset)
			neighbors[a] = ns

func _push(heap: Array, value: Array) -> void:
	heap.append(value)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if float(heap[parent][0]) <= float(value[0]): break
		heap[i] = heap[parent]
		i = parent
	heap[i] = value

func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var tail: Array = heap.pop_back()
	if not heap.is_empty():
		var i := 0
		while i * 2 + 1 < heap.size():
			var child := i * 2 + 1
			if child + 1 < heap.size() and float(heap[child + 1][0]) < float(heap[child][0]): child += 1
			if float(tail[0]) <= float(heap[child][0]): break
			heap[i] = heap[child]
			i = child
		heap[i] = tail
	return top

func search(starts: Array, limit: float, blocked: Dictionary = {}, assault := false) -> Dictionary:
	search_calls += 1
	var costs: Dictionary = {}
	var parents: Dictionary = {}
	var heap: Array = []
	for p in starts:
		costs[p] = 0.0
		parents[p] = p
		_push(heap, [0.0, p])
	var graph: Dictionary = assault_neighbors if assault else neighbors
	while not heap.is_empty():
		var item := _pop(heap)
		var p: Vector2i = item[1]
		if float(item[0]) > float(costs[p]) + 0.001: continue
		for n in graph.get(p, []):
			if blocked.has(n): continue
			var cost := float(item[0]) + step_cost(p, n)
			if cost > limit + 0.001: continue
			if cost + 0.001 < float(costs.get(n, INF)):
				costs[n] = cost
				parents[n] = p
				_push(heap, [cost, n])
	return {"costs": costs, "parents": parents}

func path(start: Vector2i, goal: Vector2i, parents: Dictionary) -> Array:
	var result: Array = []
	if not parents.has(goal): return result
	var p := goal
	while p != start:
		result.push_front(p)
		p = parents[p]
	return result

func clear_shot(a: Vector2i, b: Vector2i) -> bool:
	if not inside(a) or not inside(b): return false
	# Battleground.DoTargeting checks crossed edges, not cell walkability.
	# Low obstacles may be shot over; full cover and barred windows block.
	for index in ray_edges(a,b):
		if cover_kind(index) == 2 or kind(index) == 12: return false
	return true

func ray_edges(a: Vector2i,b: Vector2i) -> Array:
	# GridRayCaster: exact cell-centre crossings with source corner priorities.
	var hits: Array = []
	var d := b-a
	var p := a
	var step := Vector2i(signi(d.x),signi(d.y))
	var tx := .5/absf(d.x) if d.x != 0 else INF
	var ty := .5/absf(d.y) if d.y != 0 else INF
	var dx := 1.0/absf(d.x) if d.x != 0 else INF
	var dy := 1.0/absf(d.y) if d.y != 0 else INF
	while p != b:
		if absf(tx-ty)<.00001:
			var cr := crossing(p,p+step)
			# At an exact corner a lone edge is not crossed. Connected edge
			# pairs use the lower source priority (GetPriority), never all four.
			for pair in [[0,3],[1,2],[0,1],[2,3]]:
				var i: int = cr[pair[0]]
				var j: int = cr[pair[1]]
				if kind(i) <= 0 or kind(j) <= 0: continue
				var priority := [0,14,10,6,2,3,11,9,13,4,7,12,8,1,5]
				var chosen: int = i if priority[kind(i)]<priority[kind(j)] else j
				if chosen not in hits: hits.append(chosen)
			p += step
			tx += dx
			ty += dy
		elif tx<ty:
			var next := p+Vector2i(step.x,0)
			var index := edge(p,next)
			if kind(index)>0: hits.append(index)
			p = next
			tx += dx
		else:
			var next := p+Vector2i(0,step.y)
			var index := edge(p,next)
			if kind(index)>0: hits.append(index)
			p = next
			ty += dy
	return hits

func cover_openings(tile: Vector2i,only_edge := -1,for_shooter := true,occupied: Dictionary = {}) -> Array:
	var result: Array = []
	for cover in covers_at(tile):
		if only_edge >= 0 and int(cover.edge) != only_edge: continue
		var along := Vector2i(0,1) if cover.direction.x != 0 else Vector2i(1,0)
		for shift: Vector2i in [along,-along]:
			var at := tile+shift
			if not inside(at) or kind(edge(tile,at)) not in [0,4]: continue
			if for_shooter and (not passable(at) or occupied.has(at)): continue
			if for_shooter and int(cells[at].Height) != int(cells[tile].Height): continue
			if cover_kind(edge(at,at+cover.direction)) == 2: continue
			if at not in result: result.append(at)
	return result

func direct_sight(a: Vector2i,b: Vector2i) -> bool:
	if not inside(a) or not inside(b): return false
	var indoor := not room_ids.is_empty() and int(room_ids[b.y*width+b.x]) != 0
	for index in ray_edges(a,b):
		var k := kind(index)
		var endpoints := edge_pair(index)
		var distance := Vector2(a).distance_to((Vector2(endpoints[0])+Vector2(endpoints[1]))*.5)
		if cover_kind(index) == 2: return false
		if k in [10,12,14] and a not in endpoints: return false
		if k == 3 and distance>1: return false
		if k == 4 and indoor and distance>2: return false
	return true

func can_see(a: Vector2i,b: Vector2i,can_lean := true) -> bool:
	if direct_sight(a,b): return true
	if can_lean:
		for hit: int in ray_edges(a,b):
			var cover := cover_edge_for(a,hit)
			if cover<0: continue
			var openings := cover_openings(a,cover)
			if openings.is_empty(): continue
			for at: Vector2i in openings:
				if direct_sight(at,b): return true
			break
	return false

func cover_edge_for(tile: Vector2i,hit: int) -> int:
	# UnitCover.GetCoverEdgeIndex matches tier and the infinite edge line.
	for cover in covers_at(tile):
		var own: int = cover.edge
		if own%2 != hit%2 or cover_kind(own) != cover_kind(hit): continue
		var p: Vector2i = edge_pair(own)[0]
		var q: Vector2i = edge_pair(hit)[0]
		if (own%2 == 0 and p.y == q.y) or (own%2 == 1 and p.x == q.x): return own
	return -1

func do_targeting(origin: Vector2i,target: Vector2i,shooter: Vector2i,victim: Vector2i,maximum: float,shooter_cover: bool,target_cover: bool) -> Dictionary:
	var result := {"clear":false,"from":origin,"to":target,"shooter_edge":-1,"target_edge":-1,"cover":0,"fence":1.0}
	if not inside(origin) or not inside(target) or Vector2(origin).distance_to(Vector2(target))>maximum: return result
	result.clear = true
	for hit: int in ray_edges(origin,target):
		var tier := cover_kind(hit)
		if kind(hit) == 12: result.clear = false
		if tier == 0: continue
		var own := cover_edge_for(shooter,hit) if shooter_cover else -1
		var other := cover_edge_for(victim,hit) if target_cover else -1
		if own>=0: result.shooter_edge = own
		if other>=0: result.target_edge = other
		if tier == 2: result.clear = false
	result.cover = cover_kind(result.target_edge)
	result.fence = fence_factor(origin,target,shooter)
	return result

func target_from(origin: Vector2i,a: Vector2i,b: Vector2i,maximum: float,shooter_cover: bool,target_cover: bool) -> Dictionary:
	# Battleground.CanGetShotAt: try the body first, then only openings on
	# the intersected target cover. Retain that cover's penalty when exposed.
	var direct := do_targeting(origin,b,a,b,maximum,shooter_cover,target_cover)
	if direct.clear or int(direct.target_edge)<0: return direct
	var best := direct
	var distance := INF
	for at: Vector2i in cover_openings(b,int(direct.target_edge),false):
		var candidate := do_targeting(origin,at,a,b,maximum,shooter_cover,target_cover)
		if candidate.clear and Vector2(origin).distance_squared_to(Vector2(at))<=distance:
			distance = Vector2(origin).distance_squared_to(Vector2(at))
			best = candidate
			best.target_edge = direct.target_edge
			best.cover = direct.cover
	return best

func targeting(a: Vector2i,b: Vector2i,maximum: float,shooter_lean := true,target_lean := true,occupied: Dictionary = {}) -> Dictionary:
	# Battleground.CanShoot: direct shot first, then intersected shooter-cover
	# openings, picking the shorter valid ray. Range is measured after leaning.
	var initial := do_targeting(a,b,a,b,INF,shooter_lean,target_lean)
	var result := target_from(a,a,b,maximum,shooter_lean,target_lean)
	if result.clear or int(initial.shooter_edge)<0: return result
	var distance := INF
	for origin: Vector2i in cover_openings(a,int(initial.shooter_edge),true,occupied):
		var candidate := target_from(origin,a,b,maximum,shooter_lean,target_lean)
		if candidate.clear and Vector2(origin).distance_squared_to(Vector2(candidate.to))<=distance:
			distance = Vector2(origin).distance_squared_to(Vector2(candidate.to))
			result = candidate
	return result

func cover_at(target: Vector2i, from: Vector2i) -> bool:
	return shot_cover(target,from) > 0

func shot_cover(target: Vector2i, from: Vector2i) -> int:
	var delta := from - target
	if delta == Vector2i.ZERO: return 0
	var horizontal := cover_kind(edge(target,target+Vector2i(signi(delta.x),0))) if delta.x != 0 else 0
	var vertical := cover_kind(edge(target,target+Vector2i(0,signi(delta.y)))) if delta.y != 0 else 0
	# At an exact corner either exposed side can be targeted. The Unity
	# cover-opening solver is more elaborate; do not penalize an open flank.
	if absi(delta.x) == absi(delta.y): return mini(horizontal,vertical)
	return horizontal if absi(delta.x)>absi(delta.y) else vertical

func fence_factor(a: Vector2i,b: Vector2i,standing := Vector2i(-1,-1)) -> float:
	if standing.x<0: standing = a
	var crossed := {}
	for index in ray_edges(a,b):
		if kind(index) in [5,7] and standing not in edge_pair(index): crossed[index] = true
	return pow(0.75,crossed.size())

func knife_access(a: Vector2i,b: Vector2i) -> bool:
	if not cells.has(a) or not cells.has(b) or a == b: return false
	if Vector2(a).distance_to(Vector2(b)) > 1.42: return false
	# Verified from Assembly-CSharp.dll IL: AreClearConnected(..., true)
	# requires one clear edge of EACH orientation at a diagonal corner.
	var edges_to_cross := crossing(a,b)
	if edges_to_cross.size() == 1: return kind(edges_to_cross[0]) in [0,4]
	if edges_to_cross.size() != 4: return false
	return (kind(edges_to_cross[0]) in [0,4] or kind(edges_to_cross[3]) in [0,4]) and (kind(edges_to_cross[1]) in [0,4] or kind(edges_to_cross[2]) in [0,4])

func cover_kind(index: int) -> int:
	# Original EdgeTypesExtensions.GetCover / CoverTypes: none=0, half=1, full=2.
	match kind(index):
		1, 6, 8, 11: return 2
		2, 3, 9, 10, 14: return 1
	return 0

func covers_at(tile: Vector2i) -> Array:
	var result: Array = []
	if not passable(tile): return result
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var index := edge(tile, tile + direction)
		var tier := cover_kind(index)
		if tier > 0: result.append({"direction": direction, "tier": tier, "edge": index})
	return result
