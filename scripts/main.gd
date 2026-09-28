extends Control

const LIBRARY_NAME := "Rebel.Cops.GodotAssetLibrary"

const CATEGORIES := [
	{
		"id": "characters",
		"title": "角色 / Character",
		"count": "155 张角色相关贴图",
		"preview": "res://assets/samples/character.png",
		"description": "角色头像、警员/敌人相关贴图。完整素材库在项目旁边。"
	},
	{
		"id": "maps",
		"title": "地图 / Map",
		"count": "446 张地图与环境贴图",
		"preview": "res://assets/samples/map.png",
		"description": "地面、墙体、场景、建筑和关卡环境贴图。"
	},
	{
		"id": "ui",
		"title": "界面 / UI",
		"count": "92 张 UI 贴图",
		"preview": "res://assets/samples/ui.png",
		"description": "按钮、图标、菜单、窗口、提示框和教程界面素材。"
	},
	{
		"id": "audio",
		"title": "音效 / Audio",
		"count": "799 个 OGG/WAV 文件",
		"preview": "",
		"description": "Godot 可直接导入的音效和音乐文件。"
	}
]

func _ready() -> void:
	_build_interface()

func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("10151d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_bottom", 34)
	background.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Rebel Cops · Godot 素材学习项目"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "个人学习用途｜项目只导入 4 个示例素材｜点击按钮可查看完整分类目录"
	subtitle.modulate = Color("a9b6c8")
	column.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	column.add_child(grid)

	for category in CATEGORIES:
		grid.add_child(_make_category_card(category))

	var footer := Label.new()
	footer.text = "模型/骨骼/动画的 Unity 原始参考：项目外的 Rebel.Cops.UnityReference；使用前需转换为 glTF/GLB 或重新绑定。"
	footer.modulate = Color("8492a6")
	column.add_child(footer)

func _make_category_card(category: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 230)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := Label.new()
	header.text = category["title"]
	header.add_theme_font_size_override("font_size", 22)
	box.add_child(header)

	var count := Label.new()
	count.text = category["count"]
	count.modulate = Color("7ed6a5")
	box.add_child(count)

	var preview := _find_preview(category["preview"])
	if preview != null:
		var image := TextureRect.new()
		image.texture = preview
		image.custom_minimum_size = Vector2(0, 108)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(image)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 108)
		box.add_child(spacer)

	var description := Label.new()
	description.text = category["description"]
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(description)

	var open_button := Button.new()
	open_button.text = "打开资源目录"
	open_button.pressed.connect(_open_folder.bind(category["id"]))
	box.add_child(open_button)
	return panel

func _find_preview(preview_path: String) -> Texture2D:
	if preview_path.is_empty():
		return null
	var resource := load(preview_path)
	if resource is Texture2D:
		return resource
	return null

func _open_folder(category_id: String) -> void:
	var project_dir := ProjectSettings.globalize_path("res://project.godot").get_base_dir()
	var library_dir := project_dir.get_base_dir().path_join(LIBRARY_NAME)
	OS.shell_open(library_dir.path_join(category_id))
