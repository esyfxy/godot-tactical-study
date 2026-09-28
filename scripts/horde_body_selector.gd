extends Control

const UI = preload("res://scripts/horde_ui_theme.gd")
const MOTION = preload("res://scripts/horde_ui_motion.gd")
const POINTER = preload("res://scripts/horde_chance_pointer.gd")
const PARTS = ["头","躯干","手臂","腿"]
# Source Body sprite coordinate ratios, not positions on the game map.
const POINTS = [Vector2(.53,.065),Vector2(.60,.275),Vector2(.17,.34),Vector2(.565,.735)]
var buttons: Dictionary = {}
var chances: Dictionary = {}
var selected := ""
var pointer
var figure: TextureRect
var caption: Label

func setup(values: Dictionary, disabled: bool, execute: Callable) -> void:
	custom_minimum_size=Vector2(130,272)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var paper := UI.icon(self,"paper",Rect2(0,60,130,115),UI.GOLD)
	paper.rotation=-.35
	figure=UI.icon(self,"Body",Rect2(2,0,122,244))
	for i in range(PARTS.size()):
		var part: String=PARTS[i]
		chances[part]=values[part]
		var b := Button.new()
		b.name="BodyPoint"+str(i)
		b.position=figure.position+POINTS[i]*figure.size-Vector2(12,12)
		b.size=Vector2(24,24)
		b.disabled=disabled
		b.focus_mode=Control.FOCUS_ALL
		b.tooltip_text="%s · 命中 %d%%" % [part,roundi(float(values[part])*100)]
		for state in ["normal","hover","pressed","disabled","focus"]:
			b.add_theme_stylebox_override(state,UI.flat(Color.TRANSPARENT))
		add_child(b)
		var dot := Panel.new()
		dot.size=Vector2(8,8)
		dot.position=Vector2(8,8)
		var dot_style := UI.flat(UI.GOLD if not disabled else Color("#aaa99c"))
		dot_style.set_corner_radius_all(4)
		dot.add_theme_stylebox_override("panel",dot_style)
		dot.mouse_filter=Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
		b.mouse_entered.connect(select.bind(part))
		b.focus_entered.connect(select.bind(part))
		b.pressed.connect(func(): execute.call(part))
		buttons[part]=b
	pointer=POINTER.new()
	pointer.size=Vector2(38,38)
	add_child(pointer)
	caption=UI.text(self,"",Rect2(0,246,130,26),13,UI.GOLD,true)
	select("躯干",true)

func select(part: String, instant := false) -> void:
	if selected==part: return
	selected=part
	var target: Vector2=buttons[part].position+buttons[part].size*.5-pointer.size*.5
	if instant: pointer.position=target
	else: MOTION.animate(pointer,"location",^"position",target,0.17)
	pointer.restart(float(chances[part]))
	caption.text="%s · %d%%" % [part,roundi(float(chances[part])*100)]
