extends RefCounted

# TacticsUnit.GetShotChance + Cop.GetShotChance, InjuryBodyPartsExtensions,
# and the unweighted Hermite keys in TacticsDatabase.asset.
static func distance_factor(distance: float, maximum: float, enemy: bool) -> float:
	if distance > maximum: return 0.0
	if distance <= 2.0: return 1.0
	var x := distance / maximum
	if x <= 0.15: return 1.0
	var t := clampf((x-0.15)/0.85, 0, 1)
	var start_slope := -0.82352936 if enemy else 0.0
	var end_slope := -0.82352936 if enemy else -2.2121038
	return (2*t*t*t-3*t*t+1) + (t*t*t-2*t*t+t)*0.85*start_slope + (-2*t*t*t+3*t*t)*0.3 + (t*t*t-t*t)*0.85*end_slope

static func evaluate(c: Dictionary, target: Dictionary, distance: float, maximum: float, cover: int, fence: float, part: String, aimed: bool) -> Dictionary:
	if distance > maximum or str(c.gun).is_empty(): return {"chance":0.0,"base":0.0,"cover":cover,"fence":fence}
	var cover_factor := [1.0,0.5,0.25][cover] as float
	var fortification: bool = target.side == "cop" and "Fortification" in target.skills
	if fortification and cover == 1: cover_factor = 0.25
	var part_factor := float({"头":0.6,"躯干":0.9,"手臂":0.8,"腿":1.0}.get(part,0.9))
	var base := distance_factor(distance, maximum, c.side != "cop" and target.side == "cop")*part_factor*cover_factor*fence
	var factors: Array[String] = ["距离 ×%.2f · 部位 ×%.2f · 掩体 ×%.2f · 栅栏 ×%.2f" % [distance_factor(distance,maximum,c.side != "cop" and target.side == "cop"),part_factor,cover_factor,fence]]
	if c.side == "cop":
		match str(c.gun):
			"Rifle":
				base = (0.75 if cover == 1 else cover_factor)*fence
				factors = ["步枪射程内：掩体 ×%.2f · 栅栏 ×%.2f" % [0.75 if cover == 1 else cover_factor,fence]]
			"Shotgun":
				base = 1.0
				factors = ["霰弹枪射程内基础命中 100%"]
			"Glock":
				base = distance_factor(distance,maximum,false)*part_factor*(0.6 if cover == 1 else cover_factor)*fence*1.05
				factors = ["距离 ×%.2f · 部位 ×%.2f · 掩体 ×%.2f\n栅栏 ×%.2f · 手枪 ×1.05" % [distance_factor(distance,maximum,false),part_factor,0.6 if cover == 1 else cover_factor,fence]]
	if fortification: base -= 0.1
	if fortification: factors.append("目标固若金汤：基础 −10 个百分点")
	base = clampf(base,0,1)
	var probability := base
	if c.side == "cop":
		if aimed and base > 0:
			probability = 1.0
			factors.append("精准射击：有效射线命中提升至 100%")
		else:
			if c.get("multiple_shots",false): probability *= 0.5
			if c.get("multiple_shots",false): factors.append("连射 ×0.50")
			probability *= 1.0 + 0.05*int(c.shooting) + (0.05 if int(c.shooting)>0 else 0.0)
			factors.append("射击属性 ×%.2f" % (1.0 + 0.05*int(c.shooting) + (0.05 if int(c.shooting)>0 else 0.0)))
			probability *= 1.0 + 0.2*int(c.get("accuracy_buff",0))
			if int(c.get("accuracy_buff",0))>0: factors.append("指挥精度 ×%.2f" % (1.0+0.2*int(c.accuracy_buff)))
			if int(c.weapons.get(c.gun,0)) == 1: probability += 0.25
			if int(c.weapons.get(c.gun,0)) == 1: factors.append("最后一发 +25 个百分点")
		probability = clampf(probability,0,1)
		if c.get("tired",false) and not aimed: probability -= 0.15
		if c.get("tired",false) and not aimed: factors.append("疲劳 −15 个百分点（封顶后）")
	return {"chance":clampf(probability,0,1),"base":base,"cover":cover,"fence":fence,"factors":factors}
