extends SceneTree
const STATE = preload("res://scripts/horde_state.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var s = STATE.new()
	var nav = s.nav
	nav.width = 10
	nav.height = 10
	nav.edges.resize(200)
	nav.edges.fill(0)
	for x in range(10):
		for y in range(10): nav.cells[Vector2i(x,y)] = {"Height":0,"IsPassable":1}
	var a := Vector2i(2,2)
	var b := Vector2i(3,3)
	var wall: int = nav.edge(Vector2i(3,2),b)
	nav.edges[wall] = 1
	check(not s.can_collect_at(a,b),"diagonal loot cannot cross the box-side wall")
	nav.edges[wall] = 11
	check(not s.can_collect_at(a,b),"closed door prevents diagonal pickup")
	nav.open_edge(wall)
	check(s.can_collect_at(a,b),"opened door allows pickup")
	nav.opened.clear()
	nav.edges.fill(0)
	nav.edges[wall] = 2
	check(s.can_collect_at(a,b),"low cabinet loot remains accessible")
	check(nav.clear_shot(a,b),"a lone corner obstacle must not stop a diagonal shot")
	nav.cells[Vector2i(3,2)].IsPassable = 0
	check(nav.clear_shot(a,Vector2i(4,2)),"unwalkable ground alone cannot block a bullet")
	nav.cells[Vector2i(3,2)].IsPassable = 1
	nav.edges.fill(0)
	wall = nav.edge(a,Vector2i(3,2))
	nav.edges[wall] = 1
	check(not nav.clear_shot(a,Vector2i(5,2)),"direct ray stops at full wall")
	check(nav.targeting(a,Vector2i(5,2),9).clear,"free side opening permits leaning around isolated cover")
	for y in range(10): nav.edges[nav.edge(Vector2i(2,y),Vector2i(3,y))] = 1
	check(not nav.targeting(a,Vector2i(5,2),9).clear,"continuous wall cannot be bypassed by leaning")
	check(not nav.can_see(a,Vector2i(5,2)),"continuous wall blocks observation")
	nav.edges.fill(0)
	nav.edges[nav.edge(Vector2i(4,2),Vector2i(5,2))] = 2
	var low: Dictionary = nav.targeting(a,Vector2i(5,2),9)
	check(low.clear and low.cover==1,"target low cover allows shot with half-cover protection")
	nav.edges[nav.edge(Vector2i(4,2),Vector2i(5,2))] = 1
	var high: Dictionary = nav.targeting(a,Vector2i(5,2),9)
	check(high.clear and high.to != Vector2i(5,2) and high.cover==2,"target full-cover opening keeps full-cover penalty")
	check(not nav.targeting(a,Vector2i(5,2),9,true,false).clear,"incapacitated target cannot expose an opening")
	nav.edges.fill(0)
	nav.edges[wall] = 1
	var blocked_openings := {Vector2i(2,1):true,Vector2i(2,3):true}
	check(not nav.targeting(a,Vector2i(5,2),9,true,true,blocked_openings).clear,"occupied shooter openings cannot be used")
	nav.edges.fill(0)
	check(nav.targeting(a,Vector2i(5,2),3).clear,"shot at exact range allowed")
	check(not nav.targeting(a,Vector2i(5,2),2.99).clear,"beyond exact range rejected")
	nav.edges.fill(0)
	var cop: Dictionary = s.unit("观察者",a,"cop")
	s.cops.append(cop)
	s.viewing_positions[cop.id] = Vector2i(8,2)
	for y in range(10): nav.edges[nav.edge(Vector2i(4,y),Vector2i(5,y))] = 1
	check(s.tile_visible(Vector2i(7,2)),"sight follows moving rendered cop rather than committed position")
	s.viewing_positions.clear()
	check(not s.tile_visible(Vector2i(7,2)),"same target hidden from old side of wall")
	nav.edges.fill(0)
	var enemy: Dictionary = s.unit("射手",Vector2i(5,2),"enemy")
	enemy.gun = "Rifle"
	enemy.weapons = {"Rifle":1}
	cop.gun = "Rifle"
	cop.weapons = {"Rifle":1}
	s.enemies.append(enemy)
	check(s.current_shot_range(enemy)==11 and s.current_shot_range(cop)==16,"source vision caps current rifle range")
	check(s.action_reason(cop,enemy,"shoot").is_empty() and s.shot_details(cop,enemy).trace.clear,"UI and probability use same targeting")
	for y in range(10): nav.edges[nav.edge(Vector2i(4,y),Vector2i(5,y))] = 1
	check(s.shot_details(cop,enemy).chance == 0 and not s.shot_trace(cop,enemy).clear,"blocked preview cannot retain positive shot probability")
	print("HORDE VISIBILITY failures=",failures)
	quit(failures)
