extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error("AWARENESS CACHE: "+message)
func slow_visible(s,e: Dictionary,tile: Vector2i) -> bool:
	if s.tile_visible(tile): return true
	if e.dead or e.captured or str(e.gun).is_empty(): return false
	for c: Dictionary in s.living_cops():
		if not s.conscious(c): continue
		var at: Vector2i=s.viewing_positions.get(c.id,c.pos)
		if s.nav.targeting(tile,at,s.current_shot_range(e),s.cover_enabled(e),s.cover_enabled(c),s.occupied(e.id)).clear: return true
	return false
func verify(s,label: String) -> void:
	var visible: Dictionary={}
	var kinds: Dictionary={}
	for e: Dictionary in s.active_enemies():
		kinds[e.id]=s.ENEMY_AI.awareness(s,e)
		if s.conscious(e) and not e.surrender: visible[e.id]=slow_visible(s,e,e.pos)
	var expected: Dictionary={}
	for c: Dictionary in s.living_cops(): expected[c.id]=s._cop_awareness(c,visible,kinds)
	var snapshot: Dictionary=s.awareness_snapshot()
	check(snapshot.cops==expected and snapshot.enemies==kinds,label+" cached statuses match raw queries")
	check(snapshot.summary==s._awareness_summary(expected),label+" summary matches raw queries")
func run() -> void:
	var s=preload("res://scripts/horde_state.gd").new()
	s.data={"guard_patrol":true}
	s.nav.width=36;s.nav.height=36;s.nav.edges.resize(2592);s.nav.edges.fill(0)
	for x in range(36):
		for y in range(36): s.nav.cells[Vector2i(x,y)]={"Height":0,"IsPassable":1}
	s.nav.rebuild()
	var c: Dictionary=s.unit("警员",Vector2i(12,12),"cop")
	var e: Dictionary=s.unit("守卫",Vector2i(12,20),"enemy")
	e.gun="Glock";e.alerted=false;e.facing=Vector2i.UP
	s.cops=[c];s.enemies=[e]
	verify(s,"initial")
	var builds: int=s.awareness_cache_builds
	for i in range(30): s.awareness_summary();s.cop_awareness(c)
	check(builds==s.awareness_cache_builds,"unchanged UI calls do not rebuild")
	s.ENEMY_AI.observe(s,e);verify(s,"same-frame suspicion")
	s.turn+=1;s.ENEMY_AI.observe(s,e);verify(s,"confirmation")
	s.viewing_positions[c.id]=Vector2i(1,1);verify(s,"rendered moving position")
	s.viewing_positions.clear();c.pos=Vector2i(1,1);s.ENEMY_AI.observe(s,e);verify(s,"lost sight")
	s.turn+=5;verify(s,"memory expiry")
	e.heard={"turn":s.turn,"pos":c.pos,"kind":"shot"};verify(s,"hearing")
	e.wound="躯干";verify(s,"incapacitation")
	e.wound="";e.captured=true;verify(s,"capture")
	e.captured=false;e.dead=true;verify(s,"death")
	e.dead=false;e.gun="Rifle";verify(s,"weapon swap")
	c.pos=Vector2i(12,12)
	for y in range(36): s.nav.edges[s.nav.edge(Vector2i(12,y),Vector2i(13,y))]=1
	s.nav.rebuild();verify(s,"wall change")
	s.nav.open_edge(s.nav.edge(Vector2i(12,12),Vector2i(13,12)));verify(s,"opening change")
	for x in [0,1,11,12,13,23,24,25,35]:
		for y in [0,1,11,12,13,23,24,25,35]:
			var tile:=Vector2i(x,y)
			check(s.enemy_visible_at(e,tile)==slow_visible(s,e,tile),"range broad phase preserves visibility "+str(tile))
	print("AWARENESS CACHE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
