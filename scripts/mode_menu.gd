extends Control

const SETTINGS=preload("res://scripts/horde_settings.gd")
const DISPLAY=preload("res://scripts/display_settings.gd")
const GOLD=Color("#f4d345")
var settings_path:=SETTINGS.PATH
var settings: Dictionary
var content: VBoxContainer
var status: Label
var buttons: Array[Button]=[]
var artwork: Array=[]
var pointer:=Vector2.ZERO
var pointer_target:=Vector2.ZERO
var overlay: ColorRect
var loading:=""
var changing:=false
var can_resume:=false
var options_panel: PanelContainer
var options_shade: ColorRect
var display_mode: OptionButton
var resolution_choice: OptionButton
var display_apply: Button
var display_note: Label
var previous_display: Dictionary={}
var pending_display: Dictionary={}
var confirmation_left:=0.0
var indicator: ColorRect
var selected_button: Button
var content_origin:=Vector2.ZERO
var intro_offset:=18.0
var music: AudioStreamPlayer
var music_fade:=0.0
var option_tween: Tween
var font: SystemFont

func _ready() -> void:
	get_window().title="REBEL COPS"
	settings=SETTINGS.read_settings(settings_path)
	if settings_path==SETTINGS.PATH and not get_tree().has_meta("display_initialized"):
		DISPLAY.apply(get_window(),int(settings.window_mode),int(settings.resolution))
		get_tree().set_meta("display_initialized",true)
	font=SystemFont.new();font.font_names=PackedStringArray(["Bahnschrift","Microsoft YaHei UI","Arial"]);font.font_weight=600
	var background:=ColorRect.new()
	background.color=Color("#151914");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
	var layers: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/menu/layers.json"))
	for layer: Dictionary in layers:
		var art:=TextureRect.new()
		art.texture=load(layer.file);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		art.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(art)
		artwork.append({"node":art,"data":layer})
	var gradient:=Gradient.new()
	gradient.colors=PackedColorArray([Color("#101810f5"),Color("#101810e8"),Color("#10181091"),Color("#10181000")])
	gradient.offsets=PackedFloat32Array([0,.2,.43,.8])
	var texture:=GradientTexture2D.new();texture.gradient=gradient
	texture.fill_from=Vector2(0,.5);texture.fill_to=Vector2(1,.5)
	var scrim:=TextureRect.new();scrim.texture=texture
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);scrim.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(scrim)
	content=VBoxContainer.new();content.add_theme_constant_override("separation",8);add_child(content)
	var title:=text("REBEL\nCOPS",76,GOLD)
	title.add_theme_constant_override("line_spacing",-15)
	var accent:=ColorRect.new();accent.color=GOLD;accent.custom_minimum_size=Vector2(44,3)
	accent.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;accent.mouse_filter=Control.MOUSE_FILTER_IGNORE;content.add_child(accent)
	var gap:=Control.new();gap.custom_minimum_size.y=28;content.add_child(gap)
	var saved:=preload("res://scripts/horde_save.gd").read_save();can_resume=saved.ok
	var resume:=menu_button("继续游戏",func(): get_tree().set_meta("horde_resume",true);start("res://scenes/horde_mode.tscn"))
	resume.disabled=not can_resume
	resume.tooltip_text="暂无存档" if not can_resume else ""
	add_mode("义军呐喊","","res://scenes/horde_mode.tscn")
	# Keep the scene and old test index; no visible or focusable entry.
	add_mode("银行教学关","","res://scenes/bank_tutorial.tscn")
	buttons[2].hide();buttons[2].focus_mode=Control.FOCUS_NONE
	add_mode("中学解救人质行动","","res://scenes/school_combat.tscn")
	menu_button("选项",show_options)
	menu_button("退出游戏",func(): get_tree().quit())
	status=text("",14,Color("#dfd6bc"));status.hide()
	indicator=ColorRect.new();indicator.color=GOLD;indicator.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(indicator)
	selected_button=resume if can_resume else buttons[1]
	overlay=ColorRect.new();overlay.color=Color.BLACK;overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(overlay)
	content.modulate.a=0
	var enter:=create_tween().set_parallel(true)
	enter.tween_property(overlay,"modulate:a",0.0,.45)
	enter.tween_property(content,"modulate:a",1.0,.5)
	enter.tween_property(self,"intro_offset",0.0,.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	music=AudioStreamPlayer.new();music.name="MenuMusic";add_child(music)
	var audio:=load("res://assets/horde/audio/music/m05.ogg").duplicate() as AudioStreamOggVorbis
	audio.loop=true;audio.loop_offset=179.142;music.stream=audio;music.volume_db=-80;music.play()
	create_tween().tween_property(self,"music_fade",1.0,1.0)
	resized.connect(layout)
	content.minimum_size_changed.connect(func(): layout.call_deferred())
	layout()
	selected_button.grab_focus()

func text(value: String,font_size: int,color: Color,parent: Node=null) -> Label:
	var label:=Label.new();label.text=value
	label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	(parent if parent!=null else content).add_child(label)
	return label

func button_style(color: Color) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color
	style.content_margin_left=18;style.content_margin_right=18
	style.content_margin_top=8;style.content_margin_bottom=8
	style.set_corner_radius_all(2)
	return style

func menu_button(title: String,action: Callable) -> Button:
	var button:=Button.new();button.text=title
	button.custom_minimum_size=Vector2(350,48);button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font",font);button.add_theme_font_size_override("font_size",24)
	button.add_theme_color_override("font_color",Color("#e9e6d8"))
	button.add_theme_color_override("font_hover_color",GOLD);button.add_theme_color_override("font_focus_color",GOLD)
	button.add_theme_color_override("font_pressed_color",Color("#ffec99"))
	button.add_theme_color_override("font_disabled_color",Color("#8b9387"))
	for variant in ["normal","disabled"]: button.add_theme_stylebox_override(variant,button_style(Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover",button_style(Color(1,.82,.2,.08)))
	button.add_theme_stylebox_override("pressed",button_style(Color(1,.82,.2,.15)))
	button.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	button.mouse_entered.connect(func(): if not button.disabled: button.grab_focus())
	button.focus_entered.connect(func(): selected_button=button)
	button.pressed.connect(action);content.add_child(button);buttons.append(button)
	return button

func add_mode(title: String,_description: String,scene: String) -> void:
	menu_button(title,func():
		if get_tree().has_meta("horde_resume"): get_tree().remove_meta("horde_resume")
		start(scene))

func layout() -> void:
	if content==null: return
	var factor:=maxf(.3,minf(size.x/1280.0,size.y/720.0))
	content.scale=Vector2.ONE*factor;content.custom_minimum_size.x=350;content.size.x=350;content.reset_size()
	content_origin=Vector2(72*factor,maxf(24*factor,(size.y-content.size.y*factor)*.5))
	content.position=content_origin+Vector2(intro_offset*factor,0)
	layout_art()
	if is_instance_valid(options_panel):
		options_panel.reset_size()
		var fit:=minf(factor,minf((size.x-32)/options_panel.size.x,(size.y-32)/options_panel.size.y))
		options_panel.scale=Vector2.ONE*fit
		options_panel.position=(size-options_panel.size*fit)*.5

func layout_art() -> void:
	var factor:=maxf(size.x/1920.0,size.y/1080.0)*1.08
	var origin:=(size-Vector2(1920,1080)*factor)*.5
	for layer: Dictionary in artwork:
		var rect: Array=layer.data.rect
		layer.node.position=origin+Vector2(rect[0],rect[1])*factor+pointer*float(layer.data.parallax)*42*factor
		layer.node.size=Vector2(rect[2],rect[3])*factor

func show_options() -> void:
	if is_instance_valid(options_panel) or not loading.is_empty(): return
	options_shade=ColorRect.new();options_shade.color=Color(0,0,0,.45)
	options_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	options_shade.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(options_shade)
	options_panel=PanelContainer.new()
	var style:=button_style(Color("#131b16f5"));style.set_content_margin_all(28)
	style.border_color=Color("#c5ab4670");style.set_border_width_all(1)
	style.shadow_color=Color(0,0,0,.4);style.shadow_size=16
	options_panel.add_theme_stylebox_override("panel",style);options_panel.custom_minimum_size.x=570;add_child(options_panel)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",12);options_panel.add_child(column)
	text("选项",30,GOLD,column)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",18);column.add_child(row)
	var mode_column:=VBoxContainer.new();mode_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(mode_column)
	text("显示模式",16,Color("#e8e5d8"),mode_column)
	display_mode=OptionButton.new();display_mode.add_item("窗口");display_mode.add_item("全屏")
	display_mode.selected=int(settings.window_mode);display_mode.custom_minimum_size=Vector2(184,38);mode_column.add_child(display_mode)
	var resolution_column:=VBoxContainer.new();resolution_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(resolution_column)
	text("分辨率",16,Color("#e8e5d8"),resolution_column)
	resolution_choice=OptionButton.new();resolution_choice.add_item("自动适配屏幕")
	for dimensions: Vector2i in DISPLAY.RESOLUTIONS.slice(1): resolution_choice.add_item("%d × %d"%[dimensions.x,dimensions.y])
	resolution_choice.selected=int(settings.resolution);resolution_choice.custom_minimum_size=Vector2(260,38);resolution_column.add_child(resolution_choice)
	display_note=text("",13,Color("#a7af9f"),column)
	display_apply=Button.new();display_apply.text="应用显示设置";display_apply.custom_minimum_size.y=36
	display_apply.pressed.connect(func():
		if previous_display.is_empty(): preview_display()
		else: confirm_display())
	column.add_child(display_apply)
	display_mode.item_selected.connect(func(_index): update_display_note())
	resolution_choice.item_selected.connect(func(_index): update_display_note())
	update_display_note()
	for entry in [["music","音乐"],["voice","语音"],["effects","音效"],["ui_scale","界面大小"]]:
		var name_label:=text("",16,Color("#e8e5d8"),column)
		var slider:=HSlider.new();slider.min_value=.85 if entry[0]=="ui_scale" else 0;slider.max_value=1;slider.step=.01
		slider.value=float(settings[entry[0]]);slider.custom_minimum_size=Vector2(480,22);column.add_child(slider)
		var update:=func(value: float): name_label.text="%s  %d%%"%[entry[1],roundi(value*100)]
		update.call(slider.value);slider.value_changed.connect(func(value: float): update.call(value);setting(entry[0],value))
	var toggles:=HBoxContainer.new();column.add_child(toggles)
	var follow:=CheckButton.new();follow.text="镜头跟随";follow.button_pressed=bool(settings.follow)
	follow.toggled.connect(func(value): setting("follow",value));toggles.add_child(follow)
	var speed:=CheckButton.new();speed.text="敌方快速播放";speed.button_pressed=float(settings.enemy_speed)>1
	speed.toggled.connect(func(value): setting("enemy_speed",2.0 if value else 1.0));toggles.add_child(speed)
	var back:=Button.new();back.text="返回";back.custom_minimum_size.y=42;back.pressed.connect(close_options);column.add_child(back)
	for control in [display_mode,resolution_choice,display_apply,back]:
		control.add_theme_font_override("font",font);control.add_theme_font_size_override("font_size",17)
		control.add_theme_color_override("font_color",Color("#e9e6d8"));control.add_theme_color_override("font_hover_color",GOLD)
		control.add_theme_stylebox_override("normal",button_style(Color("#29342b")))
		control.add_theme_stylebox_override("hover",button_style(Color("#394736")))
	content.hide();indicator.hide();layout.call_deferred()
	options_panel.modulate.a=0;options_shade.modulate.a=0
	option_tween=create_tween().set_parallel(true)
	option_tween.tween_property(options_panel,"modulate:a",1.0,.2)
	option_tween.tween_property(options_shade,"modulate:a",1.0,.2)
	back.grab_focus()

func update_display_note() -> void:
	if display_note==null or not previous_display.is_empty(): return
	display_note.text="窗口自动限制在当前屏幕内" if display_mode.selected==0 else "自动使用原生分辨率；预设调整渲染精度"

func preview_display() -> void:
	previous_display=DISPLAY.snapshot(get_window())
	pending_display={"window_mode":display_mode.selected,"resolution":resolution_choice.selected}
	DISPLAY.apply(get_window(),display_mode.selected,resolution_choice.selected)
	confirmation_left=15.0
	display_mode.disabled=true;resolution_choice.disabled=true
	display_apply.text="保留此设置";display_apply.grab_focus()
	layout.call_deferred()

func confirm_display() -> void:
	if previous_display.is_empty(): return
	settings.merge(pending_display,true);previous_display.clear();pending_display.clear();confirmation_left=0
	setting("window_mode",settings.window_mode)
	display_mode.disabled=false;resolution_choice.disabled=false;display_apply.text="应用显示设置";update_display_note()

func revert_display() -> void:
	if previous_display.is_empty(): return
	DISPLAY.restore(get_window(),previous_display);previous_display.clear();pending_display.clear();confirmation_left=0
	if is_instance_valid(options_panel):
		display_mode.disabled=false;resolution_choice.disabled=false
		display_mode.selected=int(settings.window_mode);resolution_choice.selected=int(settings.resolution)
		display_apply.text="应用显示设置";update_display_note();layout.call_deferred()

func setting(key: String,value: Variant) -> void:
	settings[key]=value
	var error:=SETTINGS.write_settings(settings,settings_path)
	if error!=OK:
		status.text="设置保存失败";status.show()
		if is_instance_valid(options_panel): display_note.text="设置无法保存，请检查文件权限"

func close_options() -> void:
	revert_display()
	if option_tween!=null and option_tween.is_valid(): option_tween.kill()
	if is_instance_valid(options_panel):
		# Release input immediately; animate detached panels, not new ones.
		var panel:=options_panel;var shade:=options_shade
		panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
		for child in panel.find_children("*","Control",true,false): child.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var leave:=create_tween().set_parallel(true)
		leave.tween_property(panel,"modulate:a",0.0,.15);leave.tween_property(shade,"modulate:a",0.0,.15)
		leave.chain().tween_callback(func(): panel.queue_free();shade.queue_free())
	options_panel=null;options_shade=null;content.show();indicator.show()
	if selected_button!=null: selected_button.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE and is_instance_valid(options_panel):
			if previous_display.is_empty(): close_options()
			else: revert_display()
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and size.x>0 and size.y>0:
		pointer_target=(event.position/size*2-Vector2.ONE).clamp(-Vector2.ONE,Vector2.ONE)

func start(scene: String) -> void:
	if not loading.is_empty() or is_instance_valid(options_panel): return
	loading=scene
	for button in buttons: button.disabled=true
	status.text="载入中…";status.show();indicator.hide()
	if ResourceLoader.load_threaded_request(scene)!=OK: load_failed()

func load_failed() -> void:
	loading="";changing=false;status.text="载入失败，请重试";status.show()
	if get_tree().has_meta("horde_resume"): get_tree().remove_meta("horde_resume")
	for button in buttons: button.disabled=false
	buttons[0].disabled=not can_resume;indicator.show()

func _process(delta: float) -> void:
	pointer=pointer.lerp(pointer_target,1-exp(-delta*7));layout_art()
	if content!=null:
		content.position=content_origin+Vector2(intro_offset*content.scale.x,0)
		for button in buttons:
			var emphasis:=lerpf(float(button.get_meta("emphasis",0.0)),1.0 if button==selected_button else 0.0,1-exp(-delta*16))
			button.set_meta("emphasis",emphasis)
			var color:=Color("#e9e6d8").lerp(GOLD,emphasis)
			for state_name in ["font_color","font_focus_color","font_hover_color"]: button.add_theme_color_override(state_name,color)
		if selected_button!=null and indicator!=null and content.visible:
			var point:=selected_button.global_position+Vector2(-10,14)*content.scale
			indicator.position=indicator.position.lerp(point,1-exp(-delta*18))
			indicator.size=Vector2(3,24)*content.scale
			indicator.modulate.a=content.modulate.a
	if music!=null: music.volume_db=linear_to_db(maxf(.0001,.28*float(settings.music)*music_fade))
	if confirmation_left>0:
		confirmation_left=maxf(0,confirmation_left-delta)
		display_note.text="%d 秒内确认，否则恢复原设置 · Esc 撤销"%ceili(confirmation_left)
		if confirmation_left==0: revert_display()
	if changing or loading.is_empty(): return
	var state:=ResourceLoader.load_threaded_get_status(loading)
	if state==ResourceLoader.THREAD_LOAD_LOADED:
		var scene: PackedScene=ResourceLoader.load_threaded_get(loading);changing=true
		overlay.mouse_filter=Control.MOUSE_FILTER_STOP
		var fade:=create_tween().set_parallel(true)
		fade.tween_property(overlay,"modulate:a",1.0,.25);fade.tween_property(self,"music_fade",0.0,.25)
		await fade.finished
		get_tree().change_scene_to_packed(scene);loading=""
	elif state==ResourceLoader.THREAD_LOAD_FAILED: load_failed()

func _exit_tree() -> void:
	if not previous_display.is_empty(): DISPLAY.restore(get_window(),previous_display)
	if is_instance_valid(music): music.stop();music.stream=null
