extends RefCounted

const GOLD = Color("#ffe126")
const INK = Color("#111110")
static var sprites: Dictionary = {}
static var cache: Dictionary = {}

static func ammo_icon(gun: String) -> String:
	return {"Glock":"GlockClip","Revolver":"RevolverClip","Rifle":"RifleBullet","Shotgun":"ShotgunBullet"}.get(gun,"PassAmmo")

static func texture(key: String) -> Texture2D:
	if sprites.is_empty(): sprites = JSON.parse_string(FileAccess.get_file_as_string("res://assets/horde/ui/sprites.json"))
	if not sprites.has(key): return null
	if not cache.has(key):
		var data: Dictionary = sprites[key]
		var crop := AtlasTexture.new()
		crop.atlas = load(data.atlas)
		crop.region = Rect2(data.rect[0], data.rect[1], data.rect[2], data.rect[3])
		cache[key] = crop
	return cache[key]

static func text(parent: Node, value: String, rect: Rect2, font_size := 24, color := Color.WHITE, centered := false) -> Label:
	var n := Label.new()
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.text = value
	n.position = rect.position
	n.size = rect.size
	n.add_theme_font_size_override("font_size", font_size)
	n.add_theme_color_override("font_color", color)
	n.size = rect.size
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered: n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(n)
	return n

static func icon(parent: Node, key: String, rect: Rect2, tint := Color.WHITE) -> TextureRect:
	var n := TextureRect.new()
	# Set expansion before assigning a small size, or the texture's native
	# minimum (e.g. 256px) clamps the requested 50px control on creation.
	n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	n.texture = texture(key)
	n.position = rect.position
	n.size = rect.size
	n.stretch_mode = TextureRect.STRETCH_SCALE
	n.modulate = tint
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(n)
	return n

static func flat(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style

static func heading_paper(parent: Node, rect: Rect2) -> NinePatchRect:
	# Unity's source sprite has 191px left/right slicing borders. Preserve the
	# torn edges instead of stretching them across the whole title banner.
	var n := NinePatchRect.new()
	n.texture = texture("pause_header")
	n.patch_margin_left = 191
	n.patch_margin_right = 191
	n.position = rect.position
	n.size = rect.size*2
	n.scale = Vector2(0.5, 0.5)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(n)
	return n

static func button(parent: Node, value: String, rect: Rect2, callback: Callable, font_size := 25) -> Button:
	var b := Button.new()
	b.text = value
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", flat(Color.TRANSPARENT))
	b.add_theme_stylebox_override("hover", flat(Color(1, 1, 1, 0.13)))
	b.add_theme_stylebox_override("pressed", flat(Color(1, 0.87, 0.1, 0.2)))
	b.add_theme_color_override("font_hover_color", GOLD)
	b.pressed.connect(callback)
	parent.add_child(b)
	preload("res://scripts/horde_ui_motion.gd").bind_button(b)
	return b
