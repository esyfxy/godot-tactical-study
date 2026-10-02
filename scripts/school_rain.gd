extends Control

var viewer
var target:=0.0
var amount:=0.0
var drops: Array=[]
var rng:=RandomNumberGenerator.new()
var audio: AudioStreamPlayer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	rng.seed=20261001
	audio=AudioStreamPlayer.new()
	audio.stream=preload("res://assets/horde/audio/ambient/Rain.ogg").duplicate()
	audio.stream.loop=true
	add_child(audio)
	set_process(false)

func _exit_tree() -> void:
	audio.stop()
	audio.stream=null

func set_raining(value: bool) -> void:
	target=1.0 if value else 0.0
	if drops.is_empty():
		for i in range(160):
			var pos: Vector3=viewer.campus.rain_sites[rng.randi_range(0,viewer.campus.rain_sites.size()-1)]
			drops.append({"base":pos,"height":rng.randf_range(0,7),"speed":rng.randf_range(11,17)})
	set_process(true)
	if value: audio.play()

func _process(delta: float) -> void:
	amount=move_toward(amount,target,delta*.8)
	audio.volume_db=linear_to_db(maxf(.0001,amount*.1))
	for drop: Dictionary in drops:
		drop.height-=delta*float(drop.speed)
		if drop.height<0: drop.height=7.0
	queue_redraw()
	if target==0 and amount==0:
		audio.stop()
		set_process(false)

func _draw() -> void:
	if amount<=0: return
	for drop: Dictionary in drops:
		var at: Vector3=drop.base+Vector3.UP*float(drop.height)
		if viewer.camera.is_position_behind(at): continue
		var pixel: Vector2=viewer.camera.unproject_position(at)
		if not Rect2(Vector2.ZERO,size).has_point(pixel): continue
		var floor_at: Variant=viewer.ground_at(pixel)
		if floor_at==null or viewer.campus.indoor(floor_at): continue
		var head: Vector2=viewer.camera.unproject_position(at+Vector3.UP*.75)
		draw_line(head,pixel,Color(.77,.88,.92,.28*amount),1.0,true)
