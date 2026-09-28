extends Button

const UI = preload("res://scripts/horde_ui_theme.gd")
var portrait: Texture2D
var cop: Dictionary
var active := false

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(kind, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)

func _draw() -> void:
	if cop.is_empty(): return
	var middle := size.x * 0.5
	var w := 106.0 if active else 78.0
	var ribbon := PackedVector2Array([Vector2(middle-w/2, 0), Vector2(middle+w/2, 0), Vector2(middle+w/2, size.y)])
	for i in range(9, -1, -1): ribbon.append(Vector2(middle-w/2+w*i/9, size.y - (10 if i % 2 else 0)))
	draw_colored_polygon(ribbon, UI.GOLD if active else Color("#f6e79e"))
	var portrait_h := size.y - 60.0
	if portrait: draw_texture_rect(portrait, Rect2(0, 10, size.x, portrait_h), false, Color("#686260") if cop.dead else Color.WHITE)
	var name_y := size.y - 63.0
	draw_rect(Rect2(6, name_y+3, size.x-6, 24), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(3, name_y, size.x-6, 22), UI.GOLD if active else Color("#58401c"))
	var font := get_theme_default_font()
	var name_size := 17 if active else 14
	var text_w := font.get_string_size(str(cop.name), HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	draw_string(font, Vector2(middle-text_w/2+4, name_y+17), str(cop.name), HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, UI.INK if active else Color.WHITE)
	var hex_center := Vector2(2, name_y+11)
	var hexagon := PackedVector2Array()
	for i in range(7): hexagon.append(hex_center+Vector2(cos(i*TAU/6), sin(i*TAU/6))*18)
	draw_colored_polygon(hexagon, Color("#17160f"))
	draw_polyline(hexagon, UI.GOLD, 2, true)
	# Horde recruits start at level six; no XP progression is implied here.
	draw_string(font, hex_center+Vector2(-6, 7), "6", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	for i in range(int(cop.max_ap)):
		var p := Vector2(middle + (i-(cop.max_ap-1)*0.5)*20, size.y-27)
		draw_circle(p, 7, Color.WHITE if i < int(cop.ap) else Color("#706641"))
		draw_arc(p, 7, 0, TAU, 20, Color("#9d956f"), 1, true)
	if cop.dead:
		draw_line(Vector2(30, 32), Vector2(size.x-25, portrait_h), Color("#d34935"), 4)
		draw_line(Vector2(size.x-25, 32), Vector2(30, portrait_h), Color("#d34935"), 4)
