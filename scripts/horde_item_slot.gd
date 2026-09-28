extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	for corner in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var dx := 12.0 if corner.x == 0 else -12.0
		var dy := 12.0 if corner.y == 0 else -12.0
		draw_polyline(PackedVector2Array([corner+Vector2(dx, 0), corner, corner+Vector2(0, dy)]), Color("#9c956c"), 2, true)
