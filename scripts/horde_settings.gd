extends RefCounted
const PATH = "user://horde_settings.cfg"
const DEFAULTS = {"music":1.0,"voice":1.0,"effects":1.0,"enemy_speed":1.0,"follow":true,"ui_scale":1.0,"weather":4,"window_mode":0,"resolution":0}
static func read_settings(path := PATH) -> Dictionary:
	var result := DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path)!=OK: return result
	for key in DEFAULTS: result[key] = config.get_value("settings",key,DEFAULTS[key])
	for key in ["music","voice","effects"]: result[key] = clampf(float(result[key]),0,1)
	result.enemy_speed = clampf(float(result.enemy_speed),1,2)
	result.ui_scale = clampf(float(result.ui_scale),.85,1.0)
	result.weather = clampi(int(result.weather),0,4)
	result.follow = bool(result.follow)
	result.window_mode = clampi(int(result.window_mode),0,1)
	result.resolution = clampi(int(result.resolution),0,6)
	return result
static func write_settings(values: Dictionary,path := PATH) -> Error:
	var config := ConfigFile.new()
	for key in DEFAULTS: config.set_value("settings",key,values.get(key,DEFAULTS[key]))
	return config.save(path)
