extends RefCounted

# Continue the playable objectives after the source hint list; never award
# victory just because 49 pages were visited or skipped.
static func task(actor: int,action: int,tile: Vector2i,heading: String) -> Dictionary:
	return {"CopIndex":actor+1,"AllowedAction":action,"X":tile.x,"Y":tile.y,"TooltipId":0,"heading":heading}

static func recommend(game) -> Dictionary:
	var actor: int=game.selected_cop
	var source: Dictionary={}
	for e: Dictionary in game.guards:
		if e.state in ["已逮捕","倒地","逃离"]: continue
		source=task(actor,5 if e.state in ["举手","昏迷"] else 14,e.pos,"逮捕剩余罪犯" if e.state in ["举手","昏迷"] else "制服剩余罪犯")
		break
	if source.is_empty():
		for h: Dictionary in game.hostages:
			if h.state!="已获救": source=task(actor,55,h.pos,"解救剩余人质");break
	if source.is_empty(): return {"text":"全部敌人已制服、人质已解救。","tile":Vector2i(-1,-1),"route":[],"heading":"行动完成"}
	var hint: Dictionary=game.GUIDANCE.for_step(game,source)
	if hint.has("target"): return hint
	# Find the first closed opening on a relaxed route to the objective. Do
	# not silently unlock it; recommend the actual door/window interaction.
	var opened: Dictionary=game.opened_edges.duplicate()
	for kind: String in ["doors","windows"]:
		for entry: Dictionary in game.source_data[kind]: opened[int(entry.EdgeIndex)]=true
	var blocked: Dictionary=game._blocked_for_move()
	var destination:=Vector2i(int(source.X),int(source.Y))
	blocked.erase(destination)
	var start: Vector2i=game.cops[actor].pos
	var search: Dictionary=game.NAV.search(start,300.0,game.cells,game.grid_edges,opened,blocked)
	var route: Array=[start]
	route.append_array(game.NAV.path(start,destination,search.parents))
	for i in range(1,route.size()):
		for edge in game.NAV.crossing_edges(route[i-1],route[i]):
			if game.opened_edges.has(edge): continue
			for kind: String in ["doors","windows"]:
				for entry: Dictionary in game.source_data[kind]:
					if int(entry.EdgeIndex)!=edge or int(entry.IsGenerated)==0: continue
					var opening: Dictionary=game._opening_target(entry,"door" if kind=="doors" else "window")
					var door_step:=task(actor,38,opening.tile,"输入密码开门" if not str(opening.password).is_empty() else "打开通道")
					door_step.edge=edge
					return game.GUIDANCE.for_step(game,door_step)
	return hint
