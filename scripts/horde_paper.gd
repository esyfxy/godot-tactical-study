extends Control

var tint := Color("#ffe126")
var teeth := 14
var depth := 13.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var points := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y)])
	for i in range(teeth, -1, -1):
		points.append(Vector2(size.x * float(i) / teeth, size.y - depth * (0.35 + fmod(i * 0.618, 1.0))))
		if i > 0: points.append(Vector2(size.x * (i - 0.45) / teeth, size.y))
	draw_colored_polygon(points, tint)
