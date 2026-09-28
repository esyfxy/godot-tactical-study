extends Control

var tint := Color("#ffe12d")
var ap := -1
var pips_y := 0.82

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var points := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y - 8)])
	for i in range(16, -1, -1):
		points.append(Vector2(size.x * i / 16.0, size.y - (3.0 if i % 2 == 0 else 10.0)))
	draw_colored_polygon(points, tint)
	if ap >= 0:
		for i in range(2):
			var point := Vector2(size.x * 0.5 + (i - 0.5) * 17.0, size.y * pips_y)
			draw_circle(point, 5.0, Color("#625523"))
			draw_circle(point, 3.8, Color("#fff5b9") if i < ap else Color("#76682b"))
