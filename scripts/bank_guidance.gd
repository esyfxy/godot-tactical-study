extends RefCounted

# Recommendations are derived from source tutorial records and live state.
# They never gate input, spend AP, or declare mission victory.
const NAV = preload("res://scripts/bank_navigation.gd")

static func satisfied(game: Node, index: int, visited: Dictionary) -> bool:
	var step: Dictionary = game.steps[index]
	var actor := int(step["CopIndex"]) - 1
	if actor < 0: return false
	var tile := Vector2i(int(step["X"]), int(step["Y"]))
	var action := int(step["AllowedAction"])
	if action == -1:
		return game.cops[actor]["pos"] == tile or visited.has(Vector3i(actor, tile.x, tile.y))
	if action == 38:
		return game.opened_edges.has(game.OPENING_EDGES_BY_STEP.get(index, -1))
	if action == 33: return game.inspected.has(tile)
	if action == 55:
		for hostage in game.hostages:
			if hostage["pos"] == tile: return hostage["state"] == "已获救"
	if action in [1, 3, 5, 10, 14]:
		# A result is not evidence that the requested action took place:
		# surrender != baton/taser, and death != arrest. Remember actual actions
		# even when the target has since advanced to a later state.
		return game.completed_actions.has(Vector4i(actor, action, tile.x, tile.y))
	return false

static func recommend(game: Node, index: int) -> Dictionary:
	if index >= game.steps.size():
		return {"text": "当前建议已浏览完，可继续自由操作。", "tile": Vector2i(-1, -1), "route": []}
	var step: Dictionary = game.steps[index]
	var actor := int(step["CopIndex"]) - 1
	var action := int(step["AllowedAction"])
	var tile := Vector2i(int(step["X"]), int(step["Y"]))
	var heading := str(game.locale.get("TacticsTutorial%d" % int(step["TooltipId"]), "前进"))
	var result := {"actor": actor, "action": action, "tile": tile, "route": [], "heading": heading}
	if actor < 0 or action == 35:
		result["text"] = "此建议所需系统尚未实现；可跳过。"
		return result
	var cop: Dictionary = game.cops[actor]
	var origin: Vector2i = cop["pos"]
	var blocked := {}
	for i in range(game.cops.size()):
		if i != actor: blocked[game.cops[i]["pos"]] = true
	for enemy in game.guards:
		if not enemy["state"] in ["已逮捕", "逃离"]: blocked[enemy["pos"]] = true
	for hostage in game.hostages:
		if hostage["state"] != "已获救": blocked[hostage["pos"]] = true
	var target: Dictionary = {"kind": "ground", "tile": tile}
	var opening_tiles: Array = []
	if action == 38:
		var edge: int = game.OPENING_EDGES_BY_STEP.get(index, -1)
		for kind in ["door", "window"]:
			for data in game.source_data["doors" if kind == "door" else "windows"]:
				if int(data["EdgeIndex"]) == edge: target = game._opening_target(data, kind)
		if target.get("locked", false) and str(target.get("password", "")).is_empty() and int(cop.get("lockpicks", 0)) <= 0:
			result["text"] = "需要撬锁工具：先阅读 (30,22) 的纸条，由拾取工具的警员来开门。"
			return result
		opening_tiles = game._edge_tiles(edge)
	elif action != -1:
		target = game._target_at(tile)
		if action in [1, 3, 5, 10, 14] and target.get("kind") != "enemy":
			result["text"] = "目标已不在原位置；请跳过建议或自由行动。"
			return result
		if action == 55 and target.get("kind") != "hostage":
			result["text"] = "此处已无人质；请跳过建议。"
			return result
	var search := NAV.search(origin, 150.0, game.cells, game.grid_edges, game.opened_edges, blocked)
	var destination := tile
	if action != -1:
		var reach := 8.0 if action == 10 else (4.0 if action == 14 else (3.0 if action == 3 else 1.45))
		var best_cost := INF
		destination = Vector2i(-1, -1)
		for candidate in search["costs"]:
			var usable: bool = candidate in opening_tiles if action == 38 else (Vector2(candidate).distance_to(Vector2(tile)) <= reach and game._clear_line(candidate, tile))
			if usable and float(search["costs"][candidate]) < best_cost:
				best_cost = float(search["costs"][candidate])
				destination = candidate
		if destination == origin:
			result["target"] = target
			result["tile"] = target["tile"]
			result["text"] = "点击提示下的目标，选择“%s”。" % game.ACTION_NAMES.get(action, "互动")
			if int(cop["ap"]) == 0 and action != 33: result["text"] = "行动力用尽：按 Enter 换回合，再互动。"
			return result
	if not search["costs"].has(destination):
		if action == -1:
			var clearance := clear_teammate(game, actor, origin, tile, blocked)
			if not clearance.is_empty(): return clearance
		result["text"] = "路线被挡：先开门窗或移开队友；也可跳过建议。"
		return result
	var route: Array[Vector2i] = NAV.path(origin, destination, search["parents"])
	if int(cop["ap"]) <= 0:
		result["text"] = "行动力用尽：按 Enter 换回合，再前往提示位置。"
		return result
	var budget := float(cop["ap"] * cop["max_move"]) * 1.4
	var waypoint := origin
	var preview: Array[Vector2i] = [origin]
	for next in route:
		if float(search["costs"][next]) > budget + 0.001: break
		preview.append(next)
		waypoint = next
	if waypoint == origin:
		result["text"] = "剩余行动力不足，请按 Enter 换回合。"
		return result
	result["tile"] = waypoint
	result["route"] = preview
	result["target"] = {"kind": "ground", "tile": waypoint}
	var cost := NAV.movement_ap_cost(float(search["costs"][waypoint]), int(cop["max_move"]))
	result["text"] = "单击蓝色虚影脚下 (%d, %d) · %d AP" % [waypoint.x, waypoint.y, cost]
	if waypoint != destination: result["text"] += "\n这是本回合落点，到达后继续指引。"
	return result

static func clear_teammate(game: Node, actor: int, origin: Vector2i, goal: Vector2i, blocked: Dictionary) -> Dictionary:
	# The source sequence allowed units to overlap in the old prototype.
	# In free play, suggest moving an obstructing teammate instead of sending
	# the player towards an unreachable gold tile or moving anyone silently.
	var relaxed := blocked.duplicate()
	for cop in game.cops: relaxed.erase(cop["pos"])
	var probe := NAV.search(origin, 150.0, game.cells, game.grid_edges, game.opened_edges, relaxed)
	var passage: Array[Vector2i] = NAV.path(origin, goal, probe["parents"])
	for tile in passage:
		for i in range(game.cops.size()):
			if i == actor or game.cops[i]["pos"] != tile: continue
			var cop: Dictionary = game.cops[i]
			var result := {"actor": i, "action": -1, "tile": tile, "route": [], "heading": "让开通道"}
			if int(cop["ap"]) <= 0:
				result["text"] = "此警员挡住通道；按 Enter 恢复 AP 后让路。"
				return result
			var occupied := blocked.duplicate()
			occupied.erase(tile)
			occupied[origin] = true
			var search := NAV.search(tile, float(cop["ap"] * cop["max_move"]) * 1.4, game.cells, game.grid_edges, game.opened_edges, occupied)
			var best := INF
			var destination := Vector2i(-1, -1)
			for candidate in search["costs"]:
				if candidate == tile or candidate in passage: continue
				if float(search["costs"][candidate]) < best:
					best = float(search["costs"][candidate])
					destination = candidate
			if destination.x < 0: continue
			var route: Array[Vector2i] = [tile]
			route.append_array(NAV.path(tile, destination, search["parents"]))
			result["tile"] = destination
			result["route"] = route
			result["target"] = {"kind": "ground", "tile": destination}
			result["text"] = "单击蓝色虚影脚下，为%s让路。\n腾出通道后会恢复原目标。" % game.CARD_NAMES[actor + 1]
			return result
	return {}
