extends RefCounted

const PATH = "user://horde_continue.dat"
const VERSION = 1
const FIELDS = ["cops","enemies","loot","turn","wave","points","killed","arrested","collected","next_id","next_item_id","seed_value","backup_spawned","log"]
const OPTIONAL = ["last_seen","observed_events"]

static func snapshot(s) -> Dictionary:
	var result := {"version":VERSION,"rng_seed":s.rng.seed,"rng_state":s.rng.state,"edges":s.nav.edges.duplicate(),"opened":s.nav.opened.duplicate(),"phase":s.phase}
	for key in FIELDS+OPTIONAL:
		var value = s.get(key)
		result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result

static func validate(value) -> String:
	if not value is Dictionary: return "存档格式损坏"
	if value.get("version",0) != VERSION: return "存档版本不兼容，原文件已保留"
	for key in FIELDS+["rng_seed","rng_state","edges","opened","phase"]:
		if not value.has(key): return "存档缺少字段："+key
	if value.phase != "player" or not value.cops is Array or value.cops.is_empty() or not value.enemies is Array or not value.loot is Dictionary: return "战局数据损坏"
	if not value.edges is Array or not value.opened is Dictionary or not value.rng_state is int or not value.rng_seed is int: return "地图或随机状态损坏"
	if value.has("last_seen"):
		if not value.last_seen is Dictionary: return "目击记录损坏"
		for memory in value.last_seen.values():
			if not memory is Dictionary or not memory.get("pos") is Vector2i or not memory.get("turn") is int or not memory.get("name") is String: return "目击记录损坏"
	if value.has("observed_events"):
		if not value.observed_events is Array: return "战报记录损坏"
		for event in value.observed_events:
			if not event is Dictionary or not event.get("tile") is Vector2i or not event.get("turn") is int or not event.get("text") is String: return "战报记录损坏"
	var ids := {}
	for unit in value.cops+value.enemies:
		if not unit is Dictionary: return "人物数据损坏"
		for key in ["id","pos","name","side","dead","captured","stun","wound","ap","weapons","reserve","supplies","bag","gun","skills","armor","helmet","bleed"]:
			if not unit.has(key): return "人物字段不完整"
		if not unit.pos is Vector2i or ids.has(unit.id): return "人物坐标或编号损坏"
		ids[unit.id] = true
	for tile in value.loot:
		if not tile is Vector2i or not value.loot[tile] is Dictionary or not value.loot[tile].has("item"): return "补给数据损坏"
	return ""

static func read_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"error":"没有可继续的存档"}
	var f := FileAccess.open(path,FileAccess.READ)
	if f == null or f.get_length()<40 or f.get_length()>16000000: return {"ok":false,"error":"存档无法读取或大小异常"}
	if f.get_32()!=0x484F5244: return {"ok":false,"error":"存档头损坏"}
	var digest := f.get_buffer(32)
	var bytes := f.get_buffer(f.get_length()-36)
	f.close()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish()!=digest: return {"ok":false,"error":"存档校验失败"}
	var value = bytes_to_var(bytes)
	var error := validate(value)
	return {"ok":error.is_empty(),"error":error,"data":value}

static func read_save(path := PATH) -> Dictionary:
	var result := read_one(path)
	if result.ok: return result
	var previous := read_one(path+".bak")
	if previous.ok:
		previous.backup = true
		return previous
	return result

static func write_save(s,path := PATH) -> Dictionary:
	if s.phase != "player" or not s.viewing_positions.is_empty() or not s.presentation_events.is_empty(): return {"ok":false,"error":"请等待动作或敌方回合结束后保存"}
	var value := snapshot(s)
	var error := validate(value)
	if not error.is_empty(): return {"ok":false,"error":error}
	var bytes := var_to_bytes(value)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var f := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f == null: return {"ok":false,"error":"无法创建临时存档"}
	f.store_32(0x484F5244)
	f.store_buffer(hash.finish())
	f.store_buffer(bytes)
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error!=OK or not read_one(path+".tmp").ok: return {"ok":false,"error":"写入校验失败，旧存档未改变"}
	if read_one(path).ok:
		if DirAccess.copy_absolute(path,path+".bak")!=OK: return {"ok":false,"error":"无法保留上一份存档，旧存档未改变"}
	var renamed := DirAccess.rename_absolute(path+".tmp",path)
	return {"ok":renamed==OK,"error":"" if renamed==OK else "无法替换存档，旧文件和临时文件已保留"}

static func restore(s,value: Dictionary) -> String:
	var error := validate(value)
	if not error.is_empty(): return error
	if value.edges.size()!=s.nav.edges.size(): return "地图版本不同，不能恢复此存档"
	for unit in value.cops+value.enemies:
		if not s.nav.cells.has(unit.pos): return "存档人物超出地图"
	for key in FIELDS: s.set(key,value[key].duplicate(true) if value[key] is Array or value[key] is Dictionary else value[key])
	for key in OPTIONAL:
		s.set(key,value[key].duplicate(true) if value.has(key) else {} if key=="last_seen" else [])
	s.phase = "player"
	s.rng.seed = value.rng_seed
	s.rng.state = value.rng_state
	s.nav.edges = value.edges.duplicate()
	s.nav.opened = value.opened.duplicate()
	s.nav.rebuild()
	s.flow.clear()
	s.presentation_events.clear()
	s.reaction_queue.clear()
	s.viewing_positions.clear()
	return ""
