extends RefCounted

static func build(campus) -> Dictionary:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/horde/horde_data.json"))
	data.grid_size=[campus.WIDTH,campus.DEPTH]
	data.grid_cells=[]
	data.grid_edges=[]
	data.grid_edges.resize(campus.WIDTH*campus.DEPTH*2)
	data.grid_edges.fill(0)
	data.room_ids=[]
	data.doors=[]
	data.windows=[]
	data.loot_spawns=[]
	data.enemy_spawns=[]
	data.cop_spawns=[]
	for p in [Vector2i(46,6),Vector2i(48,6),Vector2i(50,6),Vector2i(52,6)]:
		data.cop_spawns.append({"X":p.x,"Y":p.y})
	var tiers: Dictionary={}
	for y in range(campus.DEPTH):
		for x in range(campus.WIDTH):
			var tile:=Vector2i(x,y)
			var solid: bool=campus.nav.is_point_solid(tile)
			tiers[tile]=campus.combat_cover_at(tile) if solid else 0
			data.grid_cells.append({"PositionX":x,"PositionY":y,"Height":0,"LookDirection":0,"IsPassable":0 if solid else 1})
			var room_id:=0
			for i in range(campus.indoor_rects.size()):
				if campus.indoor_rects[i].has_point(Vector2(tile)+Vector2(.5,.5)): room_id=i+1
			data.room_ids.append(room_id)
	for tile: Vector2i in tiers:
		for delta in [Vector2i.UP,Vector2i.LEFT]:
			var other: Vector2i=tile+delta
			var tier:=maxi(int(tiers[tile]),int(tiers.get(other,2)))
			var index: int=(tile.y*campus.WIDTH+tile.x)*2+(1 if delta.x!=0 else 0)
			data.grid_edges[index]=1 if tier==2 else 2 if tier==1 else 0
	data.parameters.HordeCops=4
	data.parameters.HordeWarmUpTurns=100000
	for prefix in ["HordeInitial","HordeWave"]:
		for kind in ["Weapon","Ammo","Equipment","RebelPoint"]: data.parameters[prefix+kind+"Loot"]=0
	return data
