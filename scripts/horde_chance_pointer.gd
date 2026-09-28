extends Control

const UI = preload("res://scripts/horde_ui_theme.gd")
var chance := 0.0
var progress := 0.0
var fill := 0.0
var point_scale := 0.0
var delay_left := 0.0
var radius := 14.0
var active := false
var disk := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func():
		if not is_visible_in_tree(): active=false; set_process(false))
	set_process(false)

func restart(value: float, delay := 0.0) -> void:
	chance=clampf(value,0,1)
	progress=0
	fill=0
	point_scale=0
	delay_left=delay
	active=true
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if not active or not is_visible_in_tree(): return
	if delay_left>0:
		delay_left=maxf(0,delay_left-delta)
		return
	# RadialMenuItem.AnimateChanceUI: pop at bottom, then SmoothStep along
	# chance * HALF a circle. 100% ends at the top, not a full revolution.
	progress=minf(1,progress+delta*clampf(2.0/maxf(chance,0.0001),0.1,2.0))
	if progress<1.0/3.0:
		point_scale=progress*4.5
	else:
		var t := (progress-1.0/3.0)/(2.0/3.0)
		fill=t*t*(3-2*t)*chance*0.5
		point_scale=lerpf(1.5,1,t)
	queue_redraw()
	if progress>=1: active=false; set_process(false)

func point_position() -> Vector2:
	return size*0.5+Vector2.from_angle(PI*0.5+TAU*fill)*radius

func _draw() -> void:
	var center := size*0.5
	if disk: draw_circle(center,radius+2,Color(0.08,0.08,0.06,0.8))
	draw_arc(center,radius,0,TAU,48,Color(1,1,1,0.85),1.5,true)
	if fill>0:
		var points := PackedVector2Array([center])
		for i in range(33): points.append(center+Vector2.from_angle(PI*0.5+TAU*fill*i/32.0)*radius)
		if disk: draw_colored_polygon(points,UI.GOLD)
		draw_arc(center,radius,PI*0.5,PI*0.5+TAU*fill,32,UI.GOLD,2,true)
	if point_scale>0:
		draw_circle(point_position(),3.8*point_scale,Color.WHITE)
		draw_circle(point_position(),2.6*point_scale,UI.GOLD)
