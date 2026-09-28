extends RefCounted

static func animate(control: Control, channel: String, property: NodePath, value: Variant, duration := 0.16) -> Tween:
	# One owner per property: a quick hover/reopen replaces, never queues, motion.
	var key := "ui_motion_"+channel
	if control.has_meta(key):
		var old: Tween = control.get_meta(key)
		if old.is_valid(): old.kill()
	var tween := control.create_tween()
	control.set_meta(key,tween)
	tween.tween_property(control,property,value,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween

static func tint(control: Control, color: Color) -> void:
	animate(control,"tint",^"modulate",color,0.14)

static func surface(button: Button, style: StyleBoxFlat, color: Color, border: Color, duration: float) -> void:
	if button.has_meta("ui_surface_tween"):
		var old: Tween=button.get_meta("ui_surface_tween")
		if old.is_valid(): old.kill()
	var tween := button.create_tween().set_parallel(true)
	button.set_meta("ui_surface_tween",tween)
	tween.tween_property(style,"bg_color",color,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(style,"border_color",border,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

static func bind_button(button: Button) -> void:
	# Animate decoration only; neither the Container nor the input rectangle moves.
	if button.has_meta("ui_feedback"): return
	var glow := ColorRect.new()
	glow.name = "SmoothFeedback"
	glow.color = Color(1,0.88,0.2,1)
	glow.modulate.a = 0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(glow)
	button.set_meta("ui_feedback",glow)
	var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
	var hover := button.get_theme_stylebox("hover") as StyleBoxFlat
	var pressed := button.get_theme_stylebox("pressed") as StyleBoxFlat
	var live: StyleBoxFlat
	if normal!=null and hover!=null and pressed!=null:
		live=normal.duplicate()
		button.set_meta("ui_live_style",live)
		for state in ["normal","hover","pressed"]: button.add_theme_stylebox_override(state,live)
	var settle := func():
		var hot := button.is_hovered() or button.has_focus()
		animate(glow,"alpha",^"modulate:a",0.065 if hot and not button.disabled else 0.0,0.12)
		if live!=null:
			var target := hover if hot and not button.disabled else normal
			surface(button,live,target.bg_color,target.border_color,0.14)
	button.mouse_entered.connect(settle)
	button.mouse_exited.connect(settle)
	button.focus_entered.connect(settle)
	button.focus_exited.connect(settle)
	button.button_down.connect(func():
		if not button.disabled:
			animate(glow,"alpha",^"modulate:a",0.19,0.055)
			if live!=null: surface(button,live,pressed.bg_color,pressed.border_color,0.055))
	button.button_up.connect(settle)
	button.visibility_changed.connect(func():
		if not button.is_visible_in_tree():
			if glow.has_meta("ui_motion_alpha"):
				var old: Tween = glow.get_meta("ui_motion_alpha")
				if old.is_valid(): old.kill()
			glow.modulate.a=0)

static func reveal(control: Control) -> void:
	# Fade only: the hit regions stay fixed, so entry animation never makes
	# buttons slide out from under the pointer. Reopening cancels stale tweens.
	if control.has_meta("reveal_tween"):
		var old: Tween = control.get_meta("reveal_tween")
		if old.is_valid(): old.kill()
	control.modulate.a = 0.0
	var tween := control.create_tween()
	control.set_meta("reveal_tween", tween)
	tween.tween_property(control, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
