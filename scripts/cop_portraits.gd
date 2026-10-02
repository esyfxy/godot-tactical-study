extends RefCounted

# User-provided 5x2 contact sheet, retained byte-for-byte as a single atlas.
# Regions are selected at runtime; the original extracted atlas stays on disk
# for recovery but is no longer loaded by either playable police HUD.
const ATLAS: Texture2D = preload("res://assets/bank/ui/police_portraits_custom_10.png")
const FEMALE := [0, 2, 5, 7, 9]
const MALE := [1, 3, 4, 6, 8]

static func texture(index: int) -> AtlasTexture:
	var slot := posmod(index,10)
	var column := slot%5
	var row := floori(float(slot)/5.0)
	var cell_width := float(ATLAS.get_width())/5.0
	var cell_height := float(ATLAS.get_height())/2.0
	var left := roundi(column*cell_width)+3
	var right := roundi((column+1)*cell_width)-3
	var crop := AtlasTexture.new()
	crop.atlas = ATLAS
	# Preserve hat insignia, eyes and chin at the 100px in-game size.
	crop.region = Rect2(left,row*cell_height+36,right-left,350)
	return crop

static func choose(gender: int, employee: Variant, used: Array) -> int:
	var candidates: Array = FEMALE if gender == 1 else MALE
	# The source IDs end in four digits (COP0001..COP0027); modulo five
	# distributes both genders across all ten supplied faces over the roster.
	var source_id := str(employee)
	var start := source_id.right(4).to_int()%candidates.size()
	for offset in range(candidates.size()):
		var index: int = candidates[(start+offset)%candidates.size()]
		if index not in used: return index
	# Only five variants per gender exist; repeat after those five are used.
	return candidates[start]
