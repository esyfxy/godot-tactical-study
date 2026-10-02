extends Node3D

# Original campus, in metres. Rect2.y is distance north; Godot Z is negative.
const WIDTH := 108
const DEPTH := 110
const CLASSROOM := Rect2(6,65,40,14)
const WEST_WING := Rect2(6,38,18,23)
const LIBRARY := Rect2(44,50,24,13)
const CAFETERIA := Rect2(78,29,23,22)
var nav := AStarGrid2D.new()
var roof_root: Node3D
var facade_root: Node3D
var batches: Dictionary = {}
var mats: Dictionary = {}
var canopies: Array[Dictionary] = []
var shapes: Dictionary = {}
var blocked_rects: Array[Rect2] = []
var low_cover_rects: Array[Rect2] = []
var tactical := false
var indoor_rects: Array[Rect2] = []
var rain_sites: Array[Vector3] = []
var roofs_visible := true
var rng := RandomNumberGenerator.new()
var mesh_count := 0

func _ready() -> void:
	rng.seed = 41001
	roof_root = Node3D.new()
	roof_root.name = "RoofsAndUpperStoreys"
	add_child(roof_root)
	facade_root = Node3D.new()
	facade_root.name = "CutawayFacades"
	add_child(facade_root)
	_materials()
	_ground()
	_perimeter()
	_building(CLASSROOM,"教学楼",2)
	_building(WEST_WING,"教学楼西翼",2)
	_building(LIBRARY,"图书馆",1)
	_building(CAFETERIA,"食堂",1)
	_interiors()
	_courtyard()
	_sports()
	_services()
	_landscape()
	if tactical: _tactical_props()
	_flush_batches()
	_navigation()

func material(key: String, color: String, roughness := 0.8, grain := 0.0) -> Material:
	var mat: Material
	var occluder:=key in ["cream","terracotta","stone","dark","glass","roof","roof_tile","white","wood","desk","blackboard","metal","trunk","leaf0","leaf1","leaf2","leaf3","flowers","red","gold"]
	if occluder:
		var custom:=ShaderMaterial.new()
		custom.shader=preload("res://shaders/school_occlusion.gdshader")
		custom.set_shader_parameter("base",Color(color))
		custom.set_shader_parameter("rough",roughness)
		custom.set_shader_parameter("grain_scale",grain)
		mat=custom
	elif grain > 0.0:
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 base : source_color;
uniform float rough = 0.8;
uniform float grain_scale = 8.0;
uniform bool paving = false;
varying vec3 wp;
void vertex(){wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;}
float noise(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
void fragment(){
 float n=noise(floor(wp*grain_scale));
 vec3 c=base.rgb*(0.98+0.04*n);
 if(paving){vec2 q=fract(wp.xz*1.25);float joint=1.0-step(0.025,min(q.x,q.y));c*=1.0-joint*0.15;}
 ALBEDO=c;ROUGHNESS=rough;METALLIC=0.035;
}"""
		var custom := ShaderMaterial.new()
		custom.shader = shader
		custom.set_shader_parameter("base",Color(color))
		custom.set_shader_parameter("rough",roughness)
		custom.set_shader_parameter("grain_scale",grain)
		custom.set_shader_parameter("paving",key=="paving")
		mat = custom
	else:
		var basic := StandardMaterial3D.new()
		basic.albedo_color = Color(color)
		basic.roughness = roughness
		mat = basic
	mats[key] = mat
	return mat

func _materials() -> void:
	material("ground","#777b68",.94,5)
	material("grass","#658352",.94,14)
	material("paving","#8e958f",.72,14)
	material("road","#505958",.54,18)
	material("cream","#e4dfcc",.84,6)
	material("terracotta","#b78162",.86,8)
	material("stone","#939791",.75,12)
	material("dark","#334e4c",.45)
	material("glass","#709b9c",.18)
	material("roof","#687775",.7,10)
	material("roof_tile","#bf8160",.75,13)
	material("white","#e7e6d6",.72)
	material("indoor_floor","#b4ac96",.82,14)
	material("wood","#a67c4e",.85,10)
	material("desk","#c7a065",.8)
	material("blackboard","#355c50",.82)
	material("track","#ae6659",.88,22)
	material("court","#457f82",.76,18)
	material("court_inner","#587e64",.8)
	material("metal","#536262",.52)
	material("trunk","#716349",.92)
	for i in range(4): material("leaf%d"%i,["#68824f","#7d9655","#4e7050","#8a9b5b"][i],.95)
	material("flowers","#cc916d",.9)
	material("red","#b34838",.74)
	material("gold","#ad925f",.45)
	material("water","#829598",.16)

func _transform(at: Vector3, dimensions: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,yaw)*Basis.from_scale(dimensions),at)

func _batch(shape: String, mat: String, transform: Transform3D, layer := 0) -> void:
	var key := "%s/%s/%d"%[shape,mat,layer]
	if not batches.has(key): batches[key] = {"shape":shape,"mat":mat,"layer":layer,"transforms":[]}
	batches[key].transforms.append(transform)

func box(at: Vector3, dimensions: Vector3, mat: String, yaw := 0.0, layer := 0) -> void:
	_batch("box",mat,_transform(at,dimensions,yaw),layer)

func cylinder(at: Vector3, radius: float, height: float, mat: String, layer := 0) -> void:
	_batch("cylinder",mat,_transform(at,Vector3(radius,height,radius)),layer)

func sphere(at: Vector3, scale_value: Vector3, mat: String) -> void:
	_batch("sphere",mat,_transform(at,scale_value))

func plate(rect: Rect2, mat: String, elevation := 0.015) -> void:
	box(Vector3(rect.get_center().x,elevation,-rect.get_center().y),Vector3(rect.size.x,.055,rect.size.y),mat)

func _flush_batches() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	shapes.box = cube
	var cyl := CylinderMesh.new()
	cyl.top_radius=1.0
	cyl.bottom_radius=1.0
	cyl.height=1.0
	cyl.radial_segments=10
	shapes.cylinder=cyl
	var ball := SphereMesh.new()
	ball.radius=1.0
	ball.height=2.0
	ball.radial_segments=10
	ball.rings=5
	shapes.sphere=ball
	for key: String in batches:
		var record: Dictionary = batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = shapes[record.shape]
		multi.instance_count = record.transforms.size()
		for i in range(multi.instance_count): multi.set_instance_transform(i,record.transforms[i])
		var node := MultiMeshInstance3D.new()
		node.name = key.replace("/","_")
		node.multimesh = multi
		node.material_override = mats[record.mat]
		var parent: Node3D = roof_root if record.layer==1 else facade_root if record.layer==2 else self
		parent.add_child(node)
		mesh_count += multi.instance_count
	batches.clear()

func text3d(value: String, at: Vector3, font_size := 64, pixel_size := .012, color := Color("#3f5650"), layer := 0) -> void:
	var label := Label3D.new()
	label.text=value
	label.font_size=font_size
	label.pixel_size=pixel_size
	label.modulate=color
	label.outline_size=0
	label.position=at
	(roof_root if layer==1 else facade_root if layer==2 else self).add_child(label)

func _ground() -> void:
	plate(Rect2(-14,-18,138,144),"ground",-.10)
	plate(Rect2(3,4,102,103),"paving")
	plate(Rect2(-14,-14,138,11),"road",.025)
	plate(Rect2(-14,-3,138,6),"paving",.04)
	for x in range(-10,119,8): box(Vector3(x,.065,8.5),Vector3(3,.025,.12),"white")
	for x in range(42,55,2): box(Vector3(x,.075,1.0),Vector3(.8,.02,7),"white")
	for x in range(-10,122,4):
		box(Vector3(x,.19,-1.8),Vector3(3.6,.34,.35),"stone")
	for i in range(28):
		var p := Vector2(rng.randf_range(27,76),rng.randf_range(8,51))
		cylinder(Vector3(p.x,.075,-p.y),rng.randf_range(.3,.85),.007,"water")

func _perimeter() -> void:
	_wall_line(Vector2(3,4),Vector2(40,4))
	_wall_line(Vector2(56,4),Vector2(105,4))
	_wall_line(Vector2(3,4),Vector2(3,107))
	_wall_line(Vector2(105,4),Vector2(105,107))
	_wall_line(Vector2(3,107),Vector2(105,107))
	for x in [39.8,56.2]:
		box(Vector3(x,2.75,-4),Vector3(1.3,5.5,1.6),"stone")
		box(Vector3(x,5.52,-4),Vector3(1.6,.25,1.9),"cream")
		sphere(Vector3(x,5.94,-4),Vector3(.38,.38,.38),"white")
	box(Vector3(48,4.75,-4),Vector3(15.9,1.25,1.15),"cream")
	box(Vector3(48,5.48,-4),Vector3(17.2,.24,1.5),"stone")
	text3d("平南县中学",Vector3(48,4.76,-3.40),98,.014,Color("#7e6641"))
	# Gate is retracted so the visible entrance and navigation agree.
	for x in range(56,60):
		box(Vector3(x,1.03,-4),Vector3(.09,2,.10),"metal")
		box(Vector3(x,1.0,-4),Vector3(1.3,.07,.10),"metal",PI/4)
	box(Vector3(64,1.7,-5.5),Vector3(7.5,3.4,6.5),"cream")
	box(Vector3(64,3.5,-5.5),Vector3(8.2,.25,7.2),"roof")
	for x in [61.5,64,66.5]: box(Vector3(x,1.85,-2.2),Vector3(1.9,1.7,.08),"glass")
	box(Vector3(60.2,1.55,-5.2),Vector3(.12,2.4,2.1),"dark")
	blocked_rects.append(Rect2(60,2,8,7))

func _wall_line(a: Vector2,b: Vector2) -> void:
	var middle := (a+b)*.5
	var length := a.distance_to(b)
	var yaw := -atan2(b.y-a.y,b.x-a.x)
	box(Vector3(middle.x,.65,-middle.y),Vector3(length,1.3,.42),"cream",yaw)
	box(Vector3(middle.x,1.32,-middle.y),Vector3(length,.15,.52),"stone",yaw)
	for i in range(int(length/2)+1):
		var p := a.lerp(b,float(i)/maxf(1,floorf(length/2)))
		box(Vector3(p.x,1.7,-p.y),Vector3(.3,1,.3),"stone")
		box(Vector3(p.x,1.65,-p.y),Vector3(.075,.5,.075),"metal")
		for j in range(3): box(Vector3(p.x+(j-1)*.48,1.65,-p.y),Vector3(.06,.55,.06),"metal")

func _building(rect: Rect2, title: String, floors: int) -> void:
	indoor_rects.append(rect)
	var center := rect.get_center()
	var wall_height := 3.25
	plate(rect.grow(.38),"stone",.11)
	plate(rect,"indoor_floor",.22)
	# Permanent low front/left walls keep cutaway proportions readable.
	box(Vector3(rect.position.x,.72,-center.y),Vector3(.28,1.0,rect.size.y),"cream")
	# Door is always an actual opening; leave 2.8 metres in the centre.
	var door_x := center.x
	var side_width := (rect.size.x-2.8)*.5
	for side in [-1,1]:
		box(Vector3(center.x+side*(side_width+2.8)*.5,1.9,-rect.position.y),Vector3(side_width,2.35,.26),"cream",0,2)
		box(Vector3(center.x+side*(side_width+2.8)*.5,.75,-rect.position.y),Vector3(side_width,1.0,.30),"terracotta")
	box(Vector3(door_x,3.05,-rect.position.y),Vector3(2.9,.65,.40),"cream",0,2)
	box(Vector3(door_x,.18,-rect.position.y+.70),Vector3(3.3,.32,1.6),"stone")
	box(Vector3(door_x,1.3,-rect.position.y-.25),Vector3(.12,2.35,1.35),"dark",.2)
	# Left facade lifts with roofs; rear and right walls retain spatial context.
	box(Vector3(rect.position.x,2,-center.y),Vector3(.28,2.6,rect.size.y),"cream",0,2)
	box(Vector3(center.x,1.95,-rect.end.y),Vector3(rect.size.x,3.45,.28),"cream")
	box(Vector3(rect.end.x,1.95,-center.y),Vector3(.28,3.45,rect.size.y),"cream")
	box(Vector3(center.x,3.45,-rect.position.y-.4),Vector3(rect.size.x+.7,.30,.95),"terracotta",0,2)
	for storey in range(floors):
		var y := 1.95+storey*3.8
		var layer := 2 if storey==0 else 1
		if storey>0:
			box(Vector3(center.x,5.7,-center.y),Vector3(rect.size.x,3.6,rect.size.y),"cream",0,1)
		for i in range(int(rect.size.x/3.3)):
			var x := rect.position.x+1.65+i*3.3
			if storey==0 and absf(x-door_x)<2: continue
			_window(Vector3(x,y,-rect.position.y+.18),false,layer)
			_window(Vector3(x,y,-rect.end.y-.18),false,layer)
		for i in range(int(rect.size.y/3.2)):
			_window(Vector3(rect.position.x-.18,y,-rect.position.y-1.6-i*3.2),true,layer)
			_window(Vector3(rect.end.x+.18,y,-rect.position.y-1.6-i*3.2),true,layer)
		box(Vector3(center.x,3.55+storey*3.8,-center.y),Vector3(rect.size.x+.5,.16,rect.size.y+.5),"terracotta",0,layer)
	var roof_y := floors*3.8+.18
	if title=="食堂":
		var run:=rect.size.y*.5+.6
		var slope:=atan2(1.8,run)
		for side in [-1,1]:
			var basis:=Basis(Vector3.RIGHT,side*slope)*Basis.from_scale(Vector3(rect.size.x+1,.26,sqrt(run*run+3.24)))
			_batch("box","roof_tile",Transform3D(basis,Vector3(center.x,roof_y+.9,-center.y+side*run*.5)),1)
		box(Vector3(center.x,roof_y+1.85,-center.y),Vector3(rect.size.x+1.1,.18,.18),"terracotta",0,1)
	else:
		box(Vector3(center.x,roof_y,-center.y),Vector3(rect.size.x+.95,.26,rect.size.y+.95),"roof",0,1)
		for dx in [-1,1]: box(Vector3(center.x+dx*rect.size.x*.5,roof_y+.22,-center.y),Vector3(.2,.55,rect.size.y+.9),"cream",0,1)
		for dy in [-1,1]: box(Vector3(center.x,roof_y+.22,-center.y+dy*rect.size.y*.5),Vector3(rect.size.x+.7,.55,.2),"cream",0,1)
		box(Vector3(rect.end.x-2,roof_y+.62,-rect.end.y+2),Vector3(1.4,1,1.4),"stone",0,1)
	text3d(title,Vector3(center.x,3.17,-rect.position.y+.38),60,.014,Color("#61564a"),2)
	# Continuous wall strips, with one front doorway.
	blocked_rects.append(Rect2(rect.position,Vector2(1,rect.size.y)))
	blocked_rects.append(Rect2(rect.end.x-1,rect.position.y,1,rect.size.y))
	blocked_rects.append(Rect2(rect.position.x,rect.end.y-1,rect.size.x,1))
	blocked_rects.append(Rect2(rect.position.x,rect.position.y,side_width,1))
	blocked_rects.append(Rect2(door_x+1.4,rect.position.y,side_width,1))

func _window(at: Vector3, side: bool, layer: int) -> void:
	var yaw := PI/2 if side else 0.0
	box(at,Vector3(2.35,1.85,.16),"dark",yaw,layer)
	box(at+Vector3(-.10 if side else 0,0,0 if side else .10),Vector3(2.08,1.61,.075),"glass",yaw,layer)
	box(at,Vector3(.07,1.85,.21),"cream",yaw,layer)
	box(at+Vector3(0,-.23,0),Vector3(2.35,.07,.21),"cream",yaw,layer)

func _interiors() -> void:
	for room in [Rect2(8,67,16,10),Rect2(28,67,16,10),Rect2(8,40,14,9),Rect2(8,51,14,8)]:
		for row in range(3):
			for col in range(4):
				var p := Vector3(room.position.x+2+col*3,.86,-room.position.y-2-row*2.3)
				box(p,Vector3(1.32,.12,.7),"desk")
				for side in [-1,1]: box(p+Vector3(side*.5,-.4,0),Vector3(.09,.73,.5),"metal")
				box(p+Vector3(0,-.18,.82),Vector3(.58,.10,.58),"wood")
				box(p+Vector3(0,.15,1.03),Vector3(.6,.59,.1),"wood")
				blocked_rects.append(Rect2(p.x-.75,-p.z-.40,1.5,1.3))
				low_cover_rects.append(blocked_rects.back())
		box(Vector3(room.get_center().x,2,-room.end.y+.2),Vector3(4,1.25,.12),"blackboard")
		box(Vector3(room.get_center().x,.92,-room.end.y+1.1),Vector3(2.1,.17,.9),"desk")
	for x in [47,51,64]:
		for y in [54,58]:
			_bookshelf(Vector3(x,0,-y))
			blocked_rects.append(Rect2(x-.7,y-1.5,1.4,3))
	for y in [53,58]:
		box(Vector3(57,1,-y),Vector3(3.0,.15,1.4),"wood")
		box(Vector3(57,.53,-y),Vector3(.55,1.0,.65),"dark")
		blocked_rects.append(Rect2(55,y-.9,4,1.8))
		low_cover_rects.append(blocked_rects.back())
	for x in [82,87,93,98]:
		for y in [33,39,45]:
			box(Vector3(x,.94,-y),Vector3(2.6,.15,1.25),"desk")
			for side in [-1,1]: box(Vector3(x,.55,-y+side*1.02),Vector3(2.6,.14,.42),"wood")
			blocked_rects.append(Rect2(x-1.5,y-1.35,3,2.7))
			low_cover_rects.append(blocked_rects.back())
	box(Vector3(89.5,1,-49.2),Vector3(18,1.8,.75),"white")
	blocked_rects.append(Rect2(80.5,48.8,18,.8))
	low_cover_rects.append(blocked_rects.back())

func _bookshelf(at: Vector3) -> void:
	box(at+Vector3(0,1.25,0),Vector3(1.15,2.5,2.8),"wood")
	for shelf in range(4):
		for book in range(7):
			box(at+Vector3(-.61,.38+shelf*.57,-1.10+book*.34),Vector3(.12,.40,.23),["cream","terracotta","dark","white"][book%4])

func _courtyard() -> void:
	plate(Rect2(43,8,10,47),"paving",.09)
	for x in [28,68]:
		_planter(Rect2(x,15,7,13))
		_planter(Rect2(x,33,7,12))
		for y in [18,24,36,42]: _tree(Vector2(x+3.5,y),1.0)
	_planter(Rect2(43,30,10,5))
	box(Vector3(48,.40,-32.5),Vector3(3.8,.7,2.5),"stone")
	cylinder(Vector3(48,4.15,-32.5),.065,7.8,"metal")
	box(Vector3(49.08,7.12,-32.5),Vector3(2.0,1.22,.04),"red",.18)
	for p in [Vector2(35,20),Vector2(64,20),Vector2(35,39),Vector2(64,39),Vector2(38,52),Vector2(73,54)]: _bench(p)
	for p in [Vector2(39,12),Vector2(60,12),Vector2(38,44),Vector2(71,45),Vector2(73,75),Vector2(51,81)]: _lamp(p)
	_canopy(Rect2(24,60,33,3))
	_canopy(Rect2(69,48,18,3))
	_canopy(Rect2(6,32,18,3))
	for p in [Vector2(30,10),Vector2(73,28)]:
		box(Vector3(p.x,1.6,-p.y),Vector3(2.8,1.45,.15),"dark")
		box(Vector3(p.x,1.6,-p.y+.10),Vector3(2.5,1.18,.05),"white")
		for x in [-1,1]: cylinder(Vector3(p.x+x,.77,-p.y),.07,1.5,"metal")

func _canopy(rect: Rect2) -> void:
	var p := rect.get_center()
	# Each canopy is a fade group, not part of the campus-wide roof batch.
	var keys: Dictionary={}
	var group_materials: Array[ShaderMaterial]=[]
	for source: String in ["roof_tile","terracotta","cream"]:
		var key: String="canopy_%d_%s"%[canopies.size(),source]
		var custom:=mats[source].duplicate() as ShaderMaterial
		custom.set_shader_parameter("whole_object",true)
		custom.set_shader_parameter("object_opacity",1.0)
		mats[key]=custom
		keys[source]=key
		group_materials.append(custom)
	canopies.append({"rect":rect.grow(.23),"height":3.35,"materials":group_materials,"opacity":1.0})
	box(Vector3(p.x,3.35,-p.y),Vector3(rect.size.x+.35,.20,rect.size.y+.45),keys.roof_tile)
	for x in range(int(rect.position.x),int(rect.end.x)+1,4):
		for y in [rect.position.y,rect.end.y]: cylinder(Vector3(x,1.67,-y),.11,3.3,keys.cream)
	for x in range(int(rect.position.x),int(rect.end.x),1): box(Vector3(x,3.5,-p.y),Vector3(.07,.11,rect.size.y+.4),keys.terracotta)

func _planter(rect: Rect2) -> void:
	plate(rect,"grass",.19)
	var c := rect.get_center()
	for side in [-1,1]:
		box(Vector3(c.x,.24,-c.y+side*rect.size.y/2),Vector3(rect.size.x+.3,.4,.25),"stone")
		box(Vector3(c.x+side*rect.size.x/2,.24,-c.y),Vector3(.25,.4,rect.size.y+.3),"stone")
	blocked_rects.append(rect.grow(.25))
	low_cover_rects.append(blocked_rects.back())
	for i in range(int(rect.size.x*rect.size.y/8)):
		var p := Vector3(rng.randf_range(rect.position.x+.35,rect.end.x-.35),.6,-rng.randf_range(rect.position.y+.35,rect.end.y-.35))
		sphere(p,Vector3(.5,.4,.5),"leaf%d"%(i%4))
		if i%3==0: sphere(p+Vector3(.1,.3,0),Vector3(.17,.12,.17),"flowers")

func _tree(p: Vector2, factor := 1.0) -> void:
	cylinder(Vector3(p.x,2.1*factor,-p.y),.14*factor,4.2*factor,"trunk")
	for i in range(6):
		var angle := i*TAU/6
		sphere(Vector3(p.x+cos(angle)*.93*factor,(4.2+float(i%2)*.42)*factor,-p.y+sin(angle)*.93*factor),Vector3(1.48,1.1,1.38)*factor,"leaf%d"%(i%4))
	sphere(Vector3(p.x,5.1*factor,-p.y),Vector3(1.65,1.35,1.6)*factor,"leaf1")
	blocked_rects.append(Rect2(p-Vector2(.55,.55),Vector2(1.1,1.1)))

func _bench(p: Vector2) -> void:
	for i in range(4): box(Vector3(p.x,.60,-p.y+(i-1.5)*.16),Vector3(2.6,.075,.12),"wood")
	for i in range(3): box(Vector3(p.x,1.0+i*.17,-p.y-.38),Vector3(2.6,.11,.065),"wood")
	for x in [-1,1]: box(Vector3(p.x+x,.31,-p.y),Vector3(.13,.58,.69),"metal")
	blocked_rects.append(Rect2(p.x-1.45,p.y-.60,2.9,1.2))
	low_cover_rects.append(blocked_rects.back())

func _tactical_props() -> void:
	# Integer footprints keep visible cover and the combat grid aligned.
	for rect in [Rect2(44,19,3,1),Rect2(53,26,3,1),Rect2(37,44,3,1),Rect2(61,64,3,1),Rect2(76,58,3,1)]:
		box(Vector3(rect.get_center().x,.62,-rect.get_center().y),Vector3(rect.size.x,1.0,rect.size.y),"stone")
		box(Vector3(rect.get_center().x,1.15,-rect.get_center().y),Vector3(rect.size.x+.1,.12,rect.size.y+.1),"wood")
		blocked_rects.append(rect)
		low_cover_rects.append(rect)
	for rect in [Rect2(58,21,2,2),Rect2(41,48,2,2),Rect2(69,69,2,2)]:
		box(Vector3(rect.get_center().x,1.3,-rect.get_center().y),Vector3(rect.size.x,2.4,rect.size.y),"dark")
		for side in [-1,1]: box(Vector3(rect.get_center().x+side*.7,1.3,-rect.get_center().y+1.02),Vector3(.06,2.4,.08),"metal")
		blocked_rects.append(rect)

func combat_cover_at(tile: Vector2i) -> int:
	if not nav.is_point_solid(tile): return 0
	var p:=Vector2(tile)+Vector2(.5,.5)
	# Walls take precedence where low furniture touches a permanent wall.
	for rect in blocked_rects:
		if rect.has_point(p) and rect not in low_cover_rects: return 2
	for rect in low_cover_rects:
		if rect.grow(.49).has_point(p): return 1
	return 2

func _lamp(p: Vector2) -> void:
	cylinder(Vector3(p.x,2.3,-p.y),.085,4.6,"metal")
	sphere(Vector3(p.x,4.75,-p.y),Vector3(.24,.30,.24),"white")
	cylinder(Vector3(p.x,.14,-p.y),.25,.25,"stone")

func _stadium_points(center: Vector2,radius: float,straight: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(49):
		var a := -PI/2+PI*i/48
		points.append(center+Vector2(straight+cos(a)*radius,sin(a)*radius))
	for i in range(49):
		var a := PI/2+PI*i/48
		points.append(center+Vector2(-straight+cos(a)*radius,sin(a)*radius))
	return points

func _flat_polygon(points: PackedVector2Array,mat: String,y := .085) -> void:
	var node := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(points)
	for index in indices:
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_add_vertex(Vector3(points[index].x,y,-points[index].y))
	mesh.surface_end()
	node.mesh=mesh
	var m: Material = mats[mat].duplicate()
	if m is StandardMaterial3D: m.cull_mode=BaseMaterial3D.CULL_DISABLED
	node.material_override=m
	add_child(node)

func _stadium_band(center: Vector2,inner: float,outer: float,straight: float,mat: String,y := .10) -> void:
	var a := _stadium_points(center,inner,straight)
	var b := _stadium_points(center,outer,straight)
	var node := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(a.size()):
		var j := (i+1)%a.size()
		for p in [a[i],a[j],b[i],b[i],a[j],b[j]]:
			mesh.surface_set_normal(Vector3.UP)
			mesh.surface_add_vertex(Vector3(p.x,y,-p.y))
	mesh.surface_end()
	node.mesh=mesh
	var m: Material=mats[mat].duplicate()
	if m is StandardMaterial3D: m.cull_mode=BaseMaterial3D.CULL_DISABLED
	node.material_override=m
	add_child(node)

func _sports() -> void:
	var center := Vector2(78,91)
	_flat_polygon(_stadium_points(center,12,12),"track")
	_flat_polygon(_stadium_points(center,8.1,12),"grass",.105)
	for i in range(7): _stadium_band(center,8.12+i*.62,8.17+i*.62,12,"white",.117)
	_field_lines(Rect2(60,84,36,14))
	for x in [60,96]:
		box(Vector3(x,1.15,-91),Vector3(.07,2.25,.07),"white")
		for y in [89.5,92.5]: box(Vector3(x,1.15,-y),Vector3(.075,2.25,.075),"white")
		box(Vector3(x,2.26,-91),Vector3(.075,.075,3),"white")
		for i in range(9): box(Vector3(x-.6,.75,-89.5-i*.375),Vector3(1.1,.045,.028),"white")
	for rect in [Rect2(72,64,13,9),Rect2(88,64,13,9)]:
		plate(rect.grow(.45),"terracotta",.10)
		plate(rect,"court",.14)
		_field_lines(rect)
		for side in [-1,1]:
			var p := Vector2(rect.get_center().x+side*(rect.size.x*.5-1),rect.get_center().y)
			box(Vector3(p.x,1.6,-p.y),Vector3(.09,3.2,.09),"metal")
			box(Vector3(p.x-side*.34,2.8,-p.y),Vector3(.13,.9,1.3),"white")
			cylinder(Vector3(p.x-side*.85,2.52,-p.y),.25,.06,"terracotta")
			plate(Rect2(p.x-(2.2 if side==1 else 0),p.y-1.6,2.2,3.2),"court_inner",.16)
	for x in range(55,102,8): _lamp(Vector2(x,77))
	for y in [85,90,95]: _bench(Vector2(51,y))

func _field_lines(rect: Rect2) -> void:
	var c := rect.get_center()
	for side in [-1,1]:
		box(Vector3(c.x,.185,-c.y+side*rect.size.y*.5),Vector3(rect.size.x,.018,.065),"white")
		box(Vector3(c.x+side*rect.size.x*.5,.185,-c.y),Vector3(.065,.018,rect.size.y),"white")
	box(Vector3(c.x,.185,-c.y),Vector3(.055,.018,rect.size.y),"white")
	_stadium_band(c,1.6,1.66,0,"white",.185)

func _services() -> void:
	_canopy(Rect2(9,97,33,5))
	for x in range(11,41,2):
		for y in [98,101]:
			for side in [-1,1]:
				var wheel := TorusMesh.new()
				wheel.inner_radius=.30
				wheel.outer_radius=.36
				wheel.rings=12
				wheel.ring_segments=4
				var node := MeshInstance3D.new()
				node.mesh=wheel
				node.material_override=mats.metal
				node.rotation.x=PI/2
				node.position=Vector3(x+side*.54,.43,-y)
				add_child(node)
			box(Vector3(x,.75,-y),Vector3(1.1,.055,.08),"metal",.5)
			box(Vector3(x+.36,.94,-y),Vector3(.05,.7,.05),"metal")
	blocked_rects.append(Rect2(9,97,33,5))
	box(Vector3(17,1.55,-105),Vector3(15,3.1,4),"cream")
	box(Vector3(17,3.22,-105),Vector3(15.6,.25,4.6),"roof")
	for x in [12,17,22]: box(Vector3(x,1.35,-102.95),Vector3(2.2,2.45,.13),"dark")
	blocked_rects.append(Rect2(9,103,16,4))

func _landscape() -> void:
	for x in [9,14,20,26,32,77,83,89,96]:
		var y := 13.0 if x<40 else 17.0
		_tree(Vector2(x,y),.9 if x%2 else 1.05)
	for y in range(20,106,11):
		_tree(Vector2(103,y),.82)
		if y<32 or y>82: _tree(Vector2(5,y),.9)
	for x in range(34,101,9): _tree(Vector2(x,105),.90)
	_planter(Rect2(10,16,26,10))
	_planter(Rect2(78,12,22,10))
	for p in [Vector2(25,57),Vector2(38,81),Vector2(69,58),Vector2(100,57)]:
		_tree(p,.8)
		_bench(p+Vector2(2.5,0))
	for x in [14,30,70,92]: _lamp(Vector2(x,-1))

func _navigation() -> void:
	nav.region=Rect2i(0,0,WIDTH,DEPTH)
	nav.cell_size=Vector2.ONE
	nav.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	nav.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	nav.update()
	for x in range(WIDTH):
		for y in range(DEPTH):
			if x<4 or x>103 or y<5 or y>105: nav.set_point_solid(Vector2i(x,y))
	for rect in blocked_rects:
		for x in range(maxi(0,floori(rect.position.x)),mini(WIDTH,ceili(rect.end.x))):
			for y in range(maxi(0,floori(rect.position.y)),mini(DEPTH,ceili(rect.end.y))): nav.set_point_solid(Vector2i(x,y))
	for y in range(5,106,3):
		for x in range(5,104,3):
			var tile:=Vector2i(x,y)
			if not nav.is_point_solid(tile) and not indoor(Vector3(x+.5,0,-y-.5)): rain_sites.append(Vector3(x+.5,.10,-y-.5))

func indoor(at: Vector3) -> bool:
	for rect in indoor_rects:
		if rect.has_point(Vector2(at.x,-at.z)): return true
	return false

func set_roofs(value: bool) -> void:
	roofs_visible=value
	roof_root.visible=value
	facade_root.visible=value

func tile_at(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x),floori(-at.z))

func world_at(tile: Vector2i) -> Vector3:
	return Vector3(tile.x+.5,.29 if indoor(Vector3(tile.x,0,-tile.y)) else .12,-tile.y-.5)

func path(from: Vector3,to: Vector3) -> PackedVector3Array:
	var start:=tile_at(from)
	var finish:=tile_at(to)
	var route:=PackedVector3Array()
	if not nav.is_in_boundsv(start) or not nav.is_in_boundsv(finish) or nav.is_point_solid(finish): return route
	for tile in nav.get_id_path(start,finish): route.append(world_at(tile))
	return route
