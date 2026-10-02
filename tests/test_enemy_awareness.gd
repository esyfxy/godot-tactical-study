extends SceneTree
const STATE=preload("res://scripts/horde_state.gd")
const AI=preload("res://scripts/horde_enemy_ai.gd")
const SAVE=preload("res://scripts/horde_save.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error("AWARENESS: "+message)
func fixture():
	var s=STATE.new()
	s.data={"guard_patrol":true,"doors":[],"windows":[]}
	s.nav.width=60;s.nav.height=60;s.nav.edges.resize(7200);s.nav.edges.fill(0)
	for x in range(60):
		for y in range(60): s.nav.cells[Vector2i(x,y)]={"Height":0,"IsPassable":1}
	s.nav.rebuild()
	var c: Dictionary=s.unit("测试警员",Vector2i(20,12),"cop")
	var e: Dictionary=s.unit("测试守卫",Vector2i(12,12),"enemy")
	e.alerted=false;e.facing=Vector2i.RIGHT;e.guard_origin=e.pos
	s.cops=[c];s.enemies=[e]
	return s
func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("AWARENESS test timeout"); quit(1))
	var s=fixture()
	var e: Dictionary=s.enemies[0]
	var c: Dictionary=s.cops[0]
	check(AI.vision_area(s,e,Vector2i(22,12))==3,"forward far cone reaches 10 cells")
	check(AI.vision_area(s,e,Vector2i(22,19))==0,"far peripheral target outside 60 degree cone")
	check(AI.vision_area(s,e,Vector2i(4,12))==0,"unalerted sentry cannot see behind at range")
	check(AI.vision_area(s,e,Vector2i(24,12))==0,"11 cell maximum retained")
	check(AI.vision_area(s,e,Vector2i(13,14))==1,"stationary near cone is 135 degrees")
	e.ai_moving=true
	check(AI.vision_area(s,e,Vector2i(13,14))==0,"moving near cone narrows to 95 degrees")
	e.ai_moving=false
	check(AI.vision_area(s,e,Vector2i(11,12))==1,"adjacent uncovered unit noticed from rear")
	s.nav.edges[s.nav.edge(e.pos,Vector2i(13,12))]=2;s.nav.rebuild()
	check(AI.vision_area(s,e,Vector2i(13,12))==0,"target-side cover prevents adjacent automatic notice")
	s.nav.edges.fill(0)
	for y in range(60): s.nav.edges[s.nav.edge(Vector2i(15,y),Vector2i(16,y))]=1
	s.nav.rebuild()
	check(AI.vision_area(s,e,c.pos)==0,"continuous wall blocks forward vision")
	s=fixture();e=s.enemies[0];c=s.cops[0]
	check(AI.observe(s,e).is_empty() and AI.awareness(s,e)=="suspicious","medium sight creates suspicion not attack target")
	check(e.known.is_empty() and s.cop_awareness(c)=="suspicious","suspicion is not confirmed tracking knowledge")
	var log_count: int=s.log.size()
	for i in range(20): AI.observe(s,e)
	check(not e.alerted and s.log.size()==log_count,"repeated same-frame observation cannot advance caution timer or spam warning")
	check(AI.goal(s,e)==c.pos and e.behavior=="suspicious","suspected position becomes investigation goal")
	s.turn+=1
	check(AI.observe(s,e).size()==1 and e.alerted and AI.awareness(s,e)=="combat","sustained visual contact confirms identity next turn")
	check(AI.goal(s,e)==c.pos and e.behavior=="combat","goal selection no longer overwrites live combat with track")
	check(s.awareness_summary().kind=="combat" and s.awareness_summary().text.contains("已被发现"),"persistent squad status reports confirmed exposure")
	check(s.observed_events.back().text.contains("已发现"),"confirmed discovery is retained in journal")
	c.pos=Vector2i(55,55);AI.observe(s,e)
	check(AI.goal(s,e)==Vector2i(20,12) and e.behavior=="track","lost target uses fixed last-seen tile not live hidden position")
	check(s.awareness_summary().kind=="track","loss of sight does not falsely claim safety")
	var before_known: Dictionary=e.known.duplicate(true)
	var before_rng: int=s.rng.state
	for i in range(30):
		s.awareness_summary();AI.awareness(s,e);AI.vision_area(s,e,Vector2i(21,12))
	check(e.known==before_known and s.rng.state==before_rng,"status and cone queries are read-only, no AI observations or combat RNG")
	s.turn+=5;AI.observe(s,e);AI.goal(s,e)
	check(not e.alerted and e.behavior=="patrol" and e.known.is_empty(),"expired evidence returns local guard to unaware patrol")
	s=fixture();e=s.enemies[0];c=s.cops[0]
	var second: Dictionary=s.unit("第二警员",Vector2i(20,14),"cop")
	s.cops.append(second)
	for i in range(10): AI.observe(s,e)
	check(e.suspected.cop==c.id,"multiple distant officers do not reset first suspect")
	s.turn+=1
	check(AI.observe(s,e).size()==2 and e.alerted,"continued multi-officer contact confirms next turn")
	s=fixture();e=s.enemies[0];c=s.cops[0];c.pos=Vector2i(14,12)
	check(AI.observe(s,e).size()==1 and e.alerted,"close sight confirms immediately")
	var ally: Dictionary=s.unit("附近守卫",Vector2i(13,14),"enemy")
	var remote: Dictionary=s.unit("远处守卫",Vector2i(50,50),"enemy")
	ally.alerted=false;remote.alerted=false;s.enemies.append_array([ally,remote])
	e.known.clear();AI.observe(s,e)
	check(ally.get("known",{}).has(c.id) and ally.known[c.id].source=="report" and ally.alerted,"nearby witness shares confirmed report")
	check(not remote.get("known",{}).has(c.id) and not remote.alerted,"no map-wide alarm location sharing")
	e.surrender=true;AI.observe(s,e)
	check(e.visible_ids.is_empty(),"surrendered enemy no longer observes police")
	s=fixture();e=s.enemies[0];c=s.cops[0];c.pos=Vector2i(55,55)
	AI.noise(s,Vector2i(14,12),"shot")
	check(AI.awareness(s,e)=="investigate" and not e.alerted and e.get("known",{}).is_empty(),"sound investigation is not confirmed police detection")
	check(AI.goal(s,e)==Vector2i(14,12),"sound investigation uses event position")
	e.pos=Vector2i(45,12);e.erase("heard");e.erase("search_origin")
	var start: Vector2i=e.pos
	var result: Dictionary=AI.move(s,e,[])
	check(not result.route.is_empty() and Vector2(e.pos-e.guard_origin).length()<Vector2(start-e.guard_origin).length(),"guard outside local search radius can return to distant post")
	for i in range(9): AI.move(s,e,[])
	check(Vector2(e.pos-e.guard_origin).length()<=4,"distant guard actually returns without orbiting or standing")
	s=fixture();e=s.enemies[0];c=s.cops[0]
	e.alerted=true
	check(AI.vision_area(s,e,Vector2i(4,12))>0,"already alerted combat does not retain unaware blind rear cone")
	e.alerted=false;c.pos=Vector2i(14,12)
	var edge: int=s.nav.edge(e.pos,Vector2i(13,12))
	for y in range(60): s.nav.edges[s.nav.edge(Vector2i(12,y),Vector2i(13,y))]=1
	s.nav.edges[edge]=11;s.nav.rebuild();c.pos=Vector2i(13,12);c.ap=2
	check(AI.observe(s,e).is_empty(),"closed doorway conceals police")
	check(s.open(c,edge) and e.alerted and e.visible_ids.has(c.id),"opening door refreshes discovery immediately without waiting enemy turn")
	# Dictionary fields must survive existing continue format without version bump.
	s.phase="player"
	var snapshot: Dictionary=SAVE.snapshot(s)
	check(snapshot.enemies[0].facing==e.facing and snapshot.enemies[0].alerted==e.alerted,"facing and awareness survive snapshot")
	print("AWARENESS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
