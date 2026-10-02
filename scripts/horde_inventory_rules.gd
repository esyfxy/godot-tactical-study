extends RefCounted

# Equipment instances retain their own ammunition/durability while stored.
# Reserve ammunition stays with its owner until explicitly transferred.
static func allowed(s, c: Dictionary) -> bool:
	return s.phase == "player" and c in s.cops and s.conscious(c)

static func group(item: String) -> String:
	if item in ["Glock", "Revolver"]: return "sidearm"
	if item in ["Rifle", "Shotgun"]: return "longarm"
	return item

static func store(s, c: Dictionary, item: String, ammo := 0, durability := 0) -> Dictionary:
	s.next_item_id += 1
	var entry := {"uid": s.next_item_id, "item": item, "ammo": ammo, "durability": durability}
	c.bag.append(entry)
	return entry

static func bag_item(c: Dictionary, uid: int) -> Dictionary:
	for entry in c.bag:
		if int(entry.uid) == uid: return entry
	return {}

static func stow(s, c: Dictionary, item: String) -> bool:
	if not allowed(s, c): return false
	if c.weapons.has(item):
		store(s, c, item, int(c.weapons[item]))
		c.weapons.erase(item)
		if c.gun == item: c.gun = "" if c.weapons.is_empty() else c.weapons.keys()[0]
	elif item == "BodyArmor" and int(c.armor) > 0:
		store(s, c, item, 0, int(c.armor))
		c.armor = 0
	elif item == "Helmet" and c.helmet:
		store(s, c, item, 0, 1)
		c.helmet = false
	else: return false
	s.say("%s 将%s收入背包（0 AP）。" % [c.name, s.NAMES[item]])
	return true

static func equip(s, c: Dictionary, uid: int) -> bool:
	if not allowed(s, c): return false
	var entry := bag_item(c, uid)
	if entry.is_empty(): return false
	var item: String = entry.item
	if item not in s.GUNS and item not in ["BodyArmor", "Helmet"]: return false
	c.bag.erase(entry)
	if item in s.GUNS:
		for old: String in c.weapons.keys():
			if group(old) == group(item): stow(s, c, old)
		c.weapons[item] = int(entry.ammo)
		c.gun = item
	elif item == "BodyArmor":
		if int(c.armor) > 0: stow(s, c, item)
		c.armor = int(entry.durability)
	else:
		if c.helmet: stow(s, c, item)
		c.helmet = true
	s.say("%s 装备%s；原装备已收入背包（0 AP）。" % [c.name, s.NAMES[item]])
	return true

static func collect(s, c: Dictionary, tile: Vector2i, mode: String) -> bool:
	if not allowed(s, c) or not s.loot.has(tile) or mode not in ["equip", "bag", "ammo"]: return false
	if not s.can_collect_at(c.pos, tile):
		s.say("先移动到补给箱旁边，再搜集。")
		return false
	var record: Dictionary = s.loot[tile]
	var item: String = record.item
	if mode == "ammo" and record.category != "Weapon": return false
	match str(record.category):
		"Weapon":
			var ammo := int(record.get("ammo", s.CAPACITY[item]))
			var extra := int(record.get("extra", 2 if item in ["Rifle", "Shotgun"] else 0))
			if mode == "ammo":
				if ammo + extra <= 0:
					s.say("这把枪已经没有可取出的弹药。")
					return false
				c.reserve[item] = int(c.reserve.get(item, 0)) + ammo + extra
				record.ammo = 0
				record.extra = 0
				s.say("%s 只取走 %d 发%s弹药；空枪仍留在箱内（0 AP）。" % [c.name, ammo+extra, s.NAMES[item]])
				return true
			var entry := store(s, c, item, ammo)
			if mode == "equip": equip(s, c, int(entry.uid))
			c.reserve[item] = int(c.reserve.get(item, 0)) + extra
		"Ammo": c.reserve[item] = int(c.reserve.get(item, 0)) + int(record.get("amount",3 if item in ["Rifle", "Shotgun"] else int(s.CAPACITY[item])))
		"Equipment":
			if item in ["BodyArmor", "Helmet"]:
				var entry := store(s, c, item, 0, 2 if item == "BodyArmor" else 1)
				if mode == "equip": equip(s, c, int(entry.uid))
			else: c.supplies[item] = int(c.supplies.get(item, 0)) + 1
		"RebelPoint": s.points += 100
		_: return false
	s.loot.erase(tile)
	if not record.get("dropped",false): s.collected += 1
	s.say("%s 获得%s%s（0 AP）。" % [c.name, s.loot_name(record), "，已收入背包" if mode == "bag" else ""])
	return true

static func unload(s, c: Dictionary, row: Dictionary) -> bool:
	if not allowed(s, c): return false
	var item: String = row.item
	var count := 0
	if row.kind == "equipped" and c.weapons.has(item):
		count = int(c.weapons[item])
		c.weapons[item] = 0
	elif row.kind == "bag":
		var entry := bag_item(c, int(row.key))
		if entry.is_empty() or entry.item != item or entry.item not in s.GUNS: return false
		item = entry.item
		count = int(entry.ammo)
		entry.ammo = 0
	if count <= 0: return false
	c.reserve[item] = int(c.reserve.get(item, 0)) + count
	s.say("%s 取出 %d 发%s弹药（0 AP）。" % [c.name, count, s.NAMES[item]])
	return true

static func drop_spot(s,c: Dictionary) -> Vector2i:
	for offset in [Vector2i.ZERO] + s.nav.DIRS:
		var tile: Vector2i = c.pos+offset
		if s.nav.passable(tile) and not s.loot.has(tile) and s.can_collect_at(c.pos,tile): return tile
	return Vector2i(-1,-1)

static func unload_and_drop(s,c: Dictionary,row: Dictionary) -> bool:
	if not allowed(s,c) or row.item not in s.GUNS: return false
	if drop_spot(s,c).x<0:
		s.say("脚边没有空位放枪；枪支和弹药均未改变。")
		return false
	if row.kind=="bag":
		var entry := bag_item(c,int(row.key))
		if entry.is_empty() or entry.item!=row.item: return false
	elif row.kind!="equipped" or not c.weapons.has(row.item): return false
	# All possible failures checked before either mutation; no yield between them.
	unload(s,c,row)
	return drop_gun(s,c,row)

static func collect_batch(s,c: Dictionary,requests: Array) -> bool:
	if not allowed(s,c) or requests.is_empty(): return false
	var seen := {}
	for request: Dictionary in requests:
		var tile: Vector2i = request.tile
		if seen.has(tile) or not s.loot.has(tile) or not s.can_collect_at(c.pos,tile): return false
		seen[tile]=true
		var record: Dictionary = s.loot[tile]
		if record!=request.expected or request.mode not in ["bag","ammo"]: return false
		if record.category not in ["Weapon","Ammo","Equipment","RebelPoint"]: return false
		if request.mode=="ammo" and (record.category!="Weapon" or int(record.get("ammo",s.CAPACITY.get(record.item,0)))+int(record.get("extra",2 if record.item in ["Rifle","Shotgun"] else 0))<=0): return false
	for request: Dictionary in requests: collect(s,c,request.tile,request.mode)
	return true

static func drop_gun(s, c: Dictionary, row: Dictionary) -> bool:
	if not allowed(s,c) or row.item not in s.GUNS: return false
	var entry: Dictionary = {}
	if row.kind == "bag":
		entry = bag_item(c,int(row.key))
		if entry.is_empty() or entry.item != row.item: return false
	elif row.kind != "equipped" or not c.weapons.has(row.item): return false
	var spot := drop_spot(s,c)
	if spot.x < 0:
		s.say("脚边没有空位放置枪支，请移动一格后再丢弃。")
		return false
	var loaded := int(entry.ammo) if row.kind == "bag" else int(c.weapons[row.item])
	s.loot[spot] = {"category":"Weapon","item":row.item,"ammo":loaded,"extra":0,"dropped":true}
	if row.kind == "bag": c.bag.erase(entry)
	else:
		c.weapons.erase(row.item)
		if c.gun == row.item: c.gun = "" if c.weapons.is_empty() else c.weapons.keys()[0]
	s.say("%s 将%s放在脚边（枪内 %d 发）；备用弹药保留，可重新拾取（0 AP）。" % [c.name,s.NAMES[row.item],loaded])
	return true

static func rows(s, c: Dictionary) -> Array:
	var result: Array = []
	for item: String in c.weapons:
		result.append({"kind":"equipped", "key":item, "item":item, "amount":1, "detail":"%s · 已装 %d 发" % ["手持" if c.gun == item else "已装备", c.weapons[item]]})
	if c.armor > 0: result.append({"kind":"equipped", "key":"BodyArmor", "item":"BodyArmor", "amount":1, "detail":"已穿戴 · 耐久 %d/2" % c.armor})
	if c.helmet: result.append({"kind":"equipped", "key":"Helmet", "item":"Helmet", "amount":1, "detail":"已穿戴"})
	for entry in c.bag:
		result.append({"kind":"bag", "key":entry.uid, "item":entry.item, "amount":1, "detail":"背包 · " + ("已装 %d 发" % entry.ammo if entry.item in s.GUNS else "耐久 %d" % entry.durability)})
	for item: String in c.reserve:
		if int(c.reserve[item]) > 0: result.append({"kind":"ammo", "key":item, "item":item, "amount":int(c.reserve[item]), "detail":"备用弹药 · %d 发" % c.reserve[item]})
	for item: String in c.supplies:
		if int(c.supplies[item]) > 0: result.append({"kind":"supply", "key":item, "item":item, "amount":int(c.supplies[item]), "detail":"背包 · ×%d" % c.supplies[item]})
	return result

static func trade_reason(s, a: Dictionary, b: Dictionary) -> String:
	if not allowed(s, a) or not allowed(s, b): return "当前不能交换物品"
	if a.id == b.id: return "请选择另一名队员"
	if not s.adjacent(a.pos, b.pos): return "需要走到队友相邻格，且中间没有障碍"
	return ""

static func transfer(s, a: Dictionary, b: Dictionary, row: Dictionary, quantity := 1) -> bool:
	var reason := trade_reason(s, a, b)
	if not reason.is_empty():
		s.say(reason)
		return false
	if quantity < 1: return false
	var item: String = row.item
	match str(row.kind):
		"bag":
			var entry := bag_item(a, int(row.key))
			if entry.is_empty() or entry.item != item or quantity != 1: return false
			a.bag.erase(entry)
			b.bag.append(entry)
		"equipped":
			if quantity != 1: return false
			if a.weapons.has(item):
				store(s, b, item, int(a.weapons[item]))
				a.weapons.erase(item)
				if a.gun == item: a.gun = "" if a.weapons.is_empty() else a.weapons.keys()[0]
			elif item == "BodyArmor" and a.armor > 0:
				store(s, b, item, 0, int(a.armor))
				a.armor = 0
			elif item == "Helmet" and a.helmet:
				store(s, b, item, 0, 1)
				a.helmet = false
			else: return false
		"ammo", "supply":
			var field := "reserve" if row.kind == "ammo" else "supplies"
			if int(a[field].get(item, 0)) < quantity: return false
			a[field][item] -= quantity
			b[field][item] = int(b[field].get(item, 0)) + quantity
		_: return false
	s.say("%s → %s：%s%s ×%d（0 AP）。" % [a.name, b.name, s.NAMES[item], "弹药" if row.kind == "ammo" else "", quantity])
	return true
