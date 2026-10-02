extends Node

# Visual-only whole-canopy fade; no local reveal holes or tactical changes.
const LIMIT:=8
var camera: Camera3D
var campus
var enabled:=true
var targets: Array[Vector3]=[]

func initialize(map_node,view: Camera3D) -> void:
	campus=map_node
	camera=view

func _update_canopies(blend: float) -> void:
	# Transform the orthographic view ray into campus-local coordinates so
	# camera panning / zoom and the combat map's 1.4 scale stay consistent.
	var direction: Vector3=campus.global_basis.inverse()*camera.global_basis.z
	for group: Dictionary in campus.canopies:
		var covered:=false
		if enabled and direction.y>.001:
			for point: Vector3 in targets:
				var local: Vector3=campus.to_local(point)
				if local.y>=float(group.height)-.15: continue
				var hit:=local+direction*((float(group.height)-local.y)/direction.y)
				if (group.rect as Rect2).has_point(Vector2(hit.x,-hit.z)):
					covered=true
					break
		group.opacity=lerpf(float(group.opacity),.22 if covered else 1.0,blend)
		for material: ShaderMaterial in group.materials:
			material.set_shader_parameter("object_opacity",group.opacity)

func set_targets(points: Array[Vector3]) -> void:
	targets=points.slice(0,LIMIT)

func _process(delta: float) -> void:
	if camera==null: return
	var blend:=1.0-exp(-delta*14.0)
	_update_canopies(blend)
