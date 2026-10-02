extends RefCounted

const RESOLUTIONS: Array[Vector2i]=[Vector2i.ZERO,Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]

static func usable(window: Window) -> Rect2i:
	var rect:=DisplayServer.screen_get_usable_rect(window.current_screen)
	return rect if rect.size.x>0 else Rect2i(0,0,1280,720)

static func window_size(index: int,available: Vector2i) -> Vector2i:
	var requested: Vector2i=RESOLUTIONS[clampi(index,0,RESOLUTIONS.size()-1)]
	var limit:=Vector2i(maxi(640,available.x-48),maxi(360,available.y-72))
	if requested==Vector2i.ZERO:
		var factor:=minf(float(limit.x)/1280.0,float(limit.y)/720.0)*.9
		return Vector2i(Vector2(1280,720)*factor)
	var factor:=minf(1.0,minf(float(limit.x)/requested.x,float(limit.y)/requested.y))
	return Vector2i(Vector2(requested)*factor)

static func snapshot(window: Window) -> Dictionary:
	return {"mode":window.mode,"size":window.size,"position":window.position,"scale_mode":window.content_scale_mode,"scale_size":window.content_scale_size,"scale_aspect":window.content_scale_aspect}

static func restore(window: Window,old: Dictionary) -> void:
	window.mode=Window.MODE_WINDOWED
	window.content_scale_mode=old.scale_mode
	window.content_scale_size=old.scale_size
	window.content_scale_aspect=old.scale_aspect
	window.size=old.size;window.position=old.position
	window.mode=old.mode

static func apply(window: Window,mode: int,index: int) -> void:
	var screen:=usable(window)
	# Fullscreen presets choose the render viewport; native keeps sharp UI.
	# Existing game layouts follow the viewport, including wide screens.
	window.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	if mode==0:
		window.mode=Window.MODE_WINDOWED
		window.size=window_size(index,screen.size)
		window.position=screen.position+(screen.size-window.size)/2
	else:
		var target: Vector2i=RESOLUTIONS[clampi(index,0,RESOLUTIONS.size()-1)]
		if target!=Vector2i.ZERO:
			window.content_scale_size=target
			window.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
			window.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
		window.mode=Window.MODE_EXCLUSIVE_FULLSCREEN
