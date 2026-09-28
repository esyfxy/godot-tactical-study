extends RefCounted
class_name BankNavigation

# The edge encoding, diagonal corner checks and costs follow the extracted
# BattleGrid, NeighborsCellsMask and EdgeTypes C# sources for Bank.unity.
const GRID_W := 60
const GRID_H := 40
const CELL_SIZE := 1.4

static func movement_ap_cost(distance: float, max_move: int) -> int:
	# Shared by rendering, preview and payment, including threshold tolerance.
	return 1 if distance <= float(max_move) * CELL_SIZE + 0.001 else 2

const DIRECTIONS := [
	Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)
]

static func inside(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < GRID_W and tile.y < GRID_H

static func edge_index(a: Vector2i, b: Vector2i) -> int:
	if not inside(a) or not inside(b) or absi(a.x - b.x) + absi(a.y - b.y) != 1:
		return -1
	var x := maxi(a.x, b.x)
	var y := maxi(a.y, b.y)
	return (y * GRID_W + x) * 2 + (1 if a.x != b.x else 0)

static func edge_type(index: int, edges: Array, opened_edges: Dictionary) -> int:
	if index < 0 or index >= edges.size():
		return -1
	var kind := int(edges[index])
	if opened_edges.has(index):
		if kind == 10: # WindowClosed -> WindowOpen
			return 3
		if kind == 11: # DoorClosed -> DoorOpen
			return 4
	return kind

static func crossing_edges(a: Vector2i, b: Vector2i) -> Array[int]:
	var dx := b.x - a.x
	var dy := b.y - a.y
	if absi(dx) > 1 or absi(dy) > 1 or (dx == 0 and dy == 0):
		return []
	if dx == 0 or dy == 0:
		return [edge_index(a, b)]
	var horizontal := a + Vector2i(dx, 0)
	var vertical := a + Vector2i(0, dy)
	return [edge_index(a, horizontal), edge_index(a, vertical),
		edge_index(horizontal, b), edge_index(vertical, b)]

static func _stairs_allow(a: Vector2i, b: Vector2i, cells: Dictionary, edges: Array, opened_edges: Dictionary) -> bool:
	var a_height := int(cells[a]["Height"])
	var b_height := int(cells[b]["Height"])
	if a_height == b_height:
		if a_height == 1: # Stairs cannot be traversed sideways.
			return false
		if a.x == b.x or a.y == b.y:
			return true
		return int(cells[Vector2i(a.x, b.y)]["Height"]) == a_height and int(cells[Vector2i(b.x, a.y)]["Height"]) == a_height
	if a_height != 1 and b_height != 1:
		return edge_type(edge_index(a, b), edges, opened_edges) == 13 # Drop
	var stair: Vector2i = a if a_height == 1 else b
	var other: Vector2i = b if a_height == 1 else a
	var other_height := int(cells[other]["Height"])
	match int(cells[stair]["LookDirection"]):
		0:
			return stair.x == other.x and (other.y <= stair.y or other_height == 2)
		1:
			return stair.y == other.y and (other.x <= stair.x or other_height == 2)
		2:
			return stair.x == other.x and (other.y >= stair.y or other_height == 2)
		3:
			return stair.y == other.y and (other.x >= stair.x or other_height == 2)
	return false

static func can_cross(a: Vector2i, b: Vector2i, cells: Dictionary, edges: Array, opened_edges: Dictionary) -> bool:
	if not inside(a) or not inside(b) or not cells.has(b) or int(cells[b]["IsPassable"]) == 0:
		return false
	var crossing := crossing_edges(a, b)
	if crossing.is_empty() or not _stairs_allow(a, b, cells, edges, opened_edges):
		return false
	var diagonal := crossing.size() > 1
	for index in crossing:
		var kind := edge_type(index, edges, opened_edges)
		if diagonal:
			if kind != 0 and kind != 4:
				return false
		elif kind != 0 and kind != 3 and kind != 4 and kind != 5 and kind != 9 and kind != 13:
			return false
	return true

static func step_cost(a: Vector2i, b: Vector2i, edges: Array, opened_edges: Dictionary) -> float:
	var cost := Vector2(a).distance_to(Vector2(b)) * CELL_SIZE
	for index in crossing_edges(a, b):
		if edge_type(index, edges, opened_edges) in [3, 5, 6, 9]:
			cost += CELL_SIZE
	return cost

static func search(start: Vector2i, max_cost: float, cells: Dictionary, edges: Array, opened_edges: Dictionary, blocked: Dictionary) -> Dictionary:
	var costs: Dictionary = {start: 0.0}
	var parents: Dictionary = {start: start}
	var pending: Dictionary = {start: true}
	while not pending.is_empty():
		var current: Vector2i = pending.keys()[0]
		for candidate in pending:
			if float(costs[candidate]) < float(costs[current]):
				current = candidate
		pending.erase(current)
		for direction in DIRECTIONS:
			var next_tile: Vector2i = current + direction
			if blocked.has(next_tile) or not can_cross(current, next_tile, cells, edges, opened_edges):
				continue
			var next_cost := float(costs[current]) + step_cost(current, next_tile, edges, opened_edges)
			if next_cost > max_cost + 0.001:
				continue
			if not costs.has(next_tile) or next_cost + 0.001 < float(costs[next_tile]):
				costs[next_tile] = next_cost
				parents[next_tile] = current
				pending[next_tile] = true
	return {"costs": costs, "parents": parents}

static func path(start: Vector2i, goal: Vector2i, parents: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not parents.has(goal):
		return result
	var cursor := goal
	while cursor != start:
		result.push_front(cursor)
		cursor = parents[cursor]
	return result
