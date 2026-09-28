extends Control

const UI = preload("res://scripts/horde_ui_theme.gd")
const PAPER = preload("res://scripts/horde_paper.gd")
var game
var mode := ""
var content: Control
var buttons: Dictionary = {}
var subtitle: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 30
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap; void fragment() { vec3 c = textureLod(screen_texture, SCREEN_UV, 3.2).rgb; float gray = dot(c, vec3(0.299, 0.587, 0.114)); COLOR = vec4(vec3(gray * 0.61), 1.0); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	backdrop.material = material
	add_child(backdrop)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	resized.connect(fit)
	hide()

func paper(rect: Rect2, tint: Color) -> Control:
	var p := PAPER.new()
	p.position = rect.position
	p.size = rect.size
	p.tint = tint
	content.add_child(p)
	return p

func begin(kind: String) -> void:
	mode = kind
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	buttons.clear()
	show()
	fit()
	preload("res://scripts/horde_ui_motion.gd").reveal(content)
	game.ui.collapse()
	game.wheel.hide()
	game.action_panel.hide()
	game.preview_label.hide()

func fit() -> void:
	if content == null: return
	var factor := minf(size.x/1920.0, size.y/1080.0)
	content.scale = Vector2.ONE*factor
	content.size = Vector2(1920, 1080)
	content.position = (size-content.size*factor)*0.5

func present_pause() -> void:
	begin("pause")
	paper(Rect2(715, 0, 490, 920), Color("#050505e8"))
	UI.heading_paper(content, Rect2(530, 38, 860, 124))
	UI.text(content, "游戏暂停", Rect2(540, 44, 840, 109), 57, UI.INK, true)
	buttons.resume = UI.button(content, "继续游戏", Rect2(728, 181, 464, 55), close, 31)
	buttons.restart = UI.button(content, "重新开始…", Rect2(728, 242, 464, 55), func(): game._dialog_confirm("restart"), 29)
	var separator := ColorRect.new()
	separator.position = Vector2(735, 317)
	separator.size = Vector2(450, 1)
	separator.color = Color("#938d7e")
	content.add_child(separator)
	buttons.speed = UI.button(content, "敌方播放速度：" + ("2×" if game.quick_enemy else "1×"), Rect2(728, 341, 464, 55), func(): game.change_setting("enemy_speed",1.0 if game.quick_enemy else 2.0); present_pause(), 26)
	buttons.menu = UI.button(content, "主菜单…", Rect2(728, 404, 464, 55), func(): game._dialog_confirm("menu"), 29)
	buttons.help = UI.button(content, "操作说明", Rect2(728, 467, 464, 55), func(): close(); game.show_help(), 29)
	buttons.weather = UI.button(content, "天气：" + game.world.WEATHER_NAMES[game.world.weather_index] + "（无遮挡）", Rect2(728, 527, 464, 55), func(): game.world.cycle_weather(); present_pause(), 25)
	buttons.save = UI.button(content,"保存战局",Rect2(728,590,464,55),func():
		var ok: bool = game.save_game()
		buttons.save.text = "已保存" if ok else "保存失败，请查看提示",29)
	buttons.settings = UI.button(content,"声音与视角设置",Rect2(728,653,464,55),present_settings,29)
	UI.text(content, "义军呐喊 · 第 %d 回合 / 第 %d 波" % [game.state.turn, game.state.wave], Rect2(730, 744, 460, 38), 22, Color("#b3ab96"), true)
	UI.text(content, "你的回合开始时自动保存 · Esc 返回", Rect2(724, 796, 472, 35), 20, Color("#b3ab96"), true)

func settings_slider(title: String,key: String,y: float,minimum: float,maximum: float,step: float) -> void:
	var caption := UI.text(content,title,Rect2(590,y,740,45),29,UI.GOLD)
	var slider := HSlider.new()
	slider.name = key
	slider.position = Vector2(590,y+51)
	slider.size = Vector2(740,36)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(game.settings[key])
	caption.text = "%s  %d%%" % [title,roundi(slider.value*100)]
	content.add_child(slider)
	slider.value_changed.connect(func(value: float):
		game.change_setting(key,value)
		caption.text = "%s  %d%%" % [title,roundi(value*100)])

func present_settings() -> void:
	begin("settings")
	paper(Rect2(525,45,870,935),Color("#080808ee"))
	UI.heading_paper(content,Rect2(520,40,880,108))
	UI.text(content,"声音与视角",Rect2(540,46,840,94),49,UI.INK,true)
	settings_slider("音乐","music",187,0,1,.05)
	settings_slider("警员语音","voice",302,0,1,.05)
	settings_slider("枪声与脚步","effects",417,0,1,.05)
	settings_slider("HUD 大小","ui_scale",532,.85,1,.05)
	buttons.follow = UI.button(content,"行动镜头跟随："+("开" if game.settings.follow else "关"),Rect2(590,654,740,57),func(): game.change_setting("follow",not game.settings.follow); present_settings(),29)
	buttons.speed = UI.button(content,"敌方播放速度："+("2×" if game.quick_enemy else "1×"),Rect2(590,724,740,57),func(): game.change_setting("enemy_speed",1.0 if game.quick_enemy else 2.0); present_settings(),29)
	buttons.back = UI.button(content,"返回暂停菜单",Rect2(690,851,540,64),present_pause,31)

func present_command() -> void:
	begin("command")
	UI.heading_paper(content, Rect2(290, 139, 654, 112))
	UI.text(content, "指挥中心", Rect2(300, 145, 634, 96), 55, UI.INK, true)
	paper(Rect2(403, 275, 423, 48), Color("#080808"))
	UI.text(content, "义军点数   %d" % game.state.points, Rect2(403, 270, 423, 46), 29, UI.GOLD, true)
	var powers := [["SpellBook_Overwatch", "一级战备", 20, "有剩余动作点数的警察进入防御姿态，在敌方回合射击最先看到的罪犯。"],
		["SpellBook_Accuracy", "稳定的手", 40, "在当前回合中，提升所有警察的精准度。"],
		["SpellBook_Haste", "反抗精神", 50, "在当前回合中，赋予所有警察一个额外的动作点数。"],
		["SpellBook_ShockAndAwe", "震骇效应", 300, "你视野中的所有罪犯都会立即入狱。"]]
	for i in range(powers.size()):
		var x := 85.0+i*273
		var y := 400.0 if i in [0, 3] else 359.0
		paper(Rect2(x, y, 248, 536), Color("#c4c2b9"))
		UI.icon(content, powers[i][0], Rect2(x+44, y+34, 160, 130), UI.INK)
		UI.text(content, powers[i][1], Rect2(x+8, y+186, 232, 55), 31, UI.INK, true)
		var desc := UI.text(content, powers[i][3], Rect2(x+24, y+249, 200, 151), 23, UI.INK, true)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var command: String = str(powers[i][0]).trim_prefix("SpellBook_")
		var reason: String = game.state.command_reason(command)
		UI.text(content, "点击下达指令" if reason.is_empty() else reason, Rect2(x+8, y+413, 232, 30), 19, Color("#39362b"), true)
		UI.icon(content, "RebelPoint", Rect2(x+84, y+464, 30, 35), UI.INK)
		UI.text(content, str(powers[i][2]), Rect2(x+120, y+461, 90, 43), 30, UI.INK)
		var hit := UI.button(content, "", Rect2(x, y, 248, 525), game.use_command.bind(command))
		hit.disabled = not reason.is_empty()
		hit.tooltip_text = str(powers[i][3]) if reason.is_empty() else reason
		buttons[powers[i][0]] = hit
	subtitle = UI.text(content, "指令影响全队。警戒会用掉合格警员的剩余行动点；触发时选择射击部位。精准度与额外行动点只在当前回合有效。", Rect2(1280, 458, 515, 260), 27, Color("#fff0bc"), true)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paper(Rect2(471, 999, 293, 67), UI.GOLD)
	buttons.back = UI.button(content, "返回", Rect2(471, 996, 293, 59), close, 31)
	buttons.back.add_theme_color_override("font_color", UI.INK)

func close() -> void:
	hide()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE: close()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton: accept_event()
