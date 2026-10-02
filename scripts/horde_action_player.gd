extends Node

var world
var audio
var played := 0
var enemy_speed := 1.0
signal impact(event: Dictionary)

func recover_shooter(motion,clip: String,prefix: String,speed: float,completion: Dictionary) -> void:
	await get_tree().create_timer(maxf(.01,motion.duration(clip)-motion.event_time(clip))/speed).timeout
	if not motion.dead:
		var end_clip := prefix+"end"
		motion.start_clip(end_clip,true)
		await get_tree().create_timer(motion.duration(end_clip)/speed).timeout
		motion.release_action()
	motion.playback_speed = 1.0
	completion.done = true

func interact(unit: Dictionary, at: Vector2i, commit: Callable, time_limit := 0.0) -> void:
	var actor: Node3D = world.actors.get(unit.id)
	if actor == null:
		commit.call()
		return
	var motion = actor.get_node("Motion")
	var speed := maxf(1.0,float(motion.duration("interact"))/time_limit) if time_limit>0 else 1.0
	motion.face(world.grid(at))
	motion.playback_speed = speed
	motion.start_clip("interact",true)
	await get_tree().create_timer(maxf(.01,motion.event_time("interact"))/speed).timeout
	commit.call()
	await get_tree().create_timer(maxf(.01,motion.duration("interact")-motion.event_time("interact"))/speed).timeout
	motion.release_action()
	motion.playback_speed = 1.0

func play_grenade(event: Dictionary, actor: Node3D) -> void:
	var motion = actor.get_node("Motion")
	motion.face(world.grid(event.to))
	var clip := "grenade_idle"
	if motion.cover_tier > 0:
		var direction: Vector3 = world.grid(event.to)-world.grid(event.from)
		var side := "right" if direction.x+direction.z>=0 else "left"
		clip = "grenade_hide_attack_%d_%s" % [100 if motion.cover_tier>=2 else 50,side]
	motion.start_clip(clip,true)
	# The source OnAction marks release, not the moment the enemy is stunned.
	await get_tree().create_timer(motion.event_time(clip)).timeout
	await world.grenade_flight(event.from,event.to)
	var affected: Array = world.state.grenade_impact(event.to)
	world.grenade_blast(event.to)
	audio.grenade()
	for id in affected:
		var victim: Node3D = world.actors.get(id)
		if victim == null or not victim.visible: continue
		world.combat_text(victim,"眩晕")
		victim.get_node("Motion").start_clip("idle_body_damage")
	impact.emit(event)
	played += 1
	var remaining: float = float(motion.duration(clip))-float(motion.event_time(clip))-world.GRENADE_FLIGHT_TIME
	if remaining>0: await get_tree().create_timer(remaining).timeout
	motion.release_action()
	motion.playback_speed=1.0

func play(events: Array) -> void:
	for event: Dictionary in events:
		var speed := enemy_speed if world.state.phase == "enemy" else 1.0
		var actor: Node3D = world.actors.get(event.actor)
		var target: Node3D = world.actors.get(event.target)
		if actor == null: continue
		var actor_visible := actor.visible
		var target_visible := target != null and target.visible
		if not actor_visible and not target_visible: continue
		var motion = actor.get_node("Motion")
		motion.playback_speed = speed
		if event.kind == "grenade":
			await play_grenade(event,actor)
			continue
		if event.kind == "capture":
			world.state.remember_event(event,actor_visible,target_visible)
			motion.start_clip("surrender",true)
			world.combat_text(actor,"已逮捕")
			await get_tree().create_timer(motion.duration("surrender")/speed).timeout
			actor.hide()
			continue
		var shoot_prefix := "shooting_straight_" if event.gun in ["Rifle","Shotgun"] else "gun_shooting_standing_"
		var shoot_clip := shoot_prefix+("shot" if event.gun in ["Rifle","Shotgun"] else "shoot")
		if event.kind == "shoot" and event.get("shot_from",event.from) != event.from:
			var direction: Vector3 = (world.grid(event.to)-world.grid(event.from)).normalized()
			var opening: Vector3 = world.grid(event.shot_from)-world.grid(event.from)
			var side := "right" if direction.cross(Vector3.UP).dot(opening)>0 else "left"
			shoot_prefix = "hide_shoot_"+side+("_rifle_" if event.gun in ["Rifle","Shotgun"] else "_")
			shoot_clip = shoot_prefix+"shot"
		if actor_visible:
			if world.follow_actions: world.center_on(event.from)
			motion.face(world.grid(event.to))
		if event.kind == "shoot" and actor_visible:
			motion.aim_at(world.grid(event.get("shot_to",event.to)),shoot_clip)
			motion.start_clip(shoot_prefix+"start",true)
			await get_tree().create_timer(motion.duration(shoot_prefix+"start")/speed).timeout
		var clip := "knife_attack" if event.kind == "knife" else "rifle_reloading_3parts" if event.kind == "reload" and event.gun in ["Rifle","Shotgun"] else "idle_reload" if event.kind == "reload" else shoot_clip
		if event.kind=="knife" and motion.melee=="Ax": clip="ax_attack"
		if event.kind == "reload" and motion.cover_tier > 0 and event.gun not in ["Rifle","Shotgun"]: clip = "hide_reload"
		if event.kind != "death" and actor_visible:
			motion.start_clip(clip,event.kind=="shoot")
			await get_tree().create_timer(maxf(.01,motion.event_time(clip))/speed).timeout
		played += 1
		world.state.remember_event(event,actor_visible,target_visible)
		impact.emit(event)
		if event.kind == "shoot":
			audio.shot(event.gun)
			if actor_visible: world.shot_flash(actor)
		var reaction_wait := 0.0
		if target_visible and event.kind != "reload":
			world.combat_text(target,event.result)
			var reaction = target.get_node("Motion")
			reaction.playback_speed = speed
			if event.dead:
				# Cop.controller Death From Idle/Cover references idle_body_damage.
				var death_clip := "damage_head" if event.get("body_part", "") == "头" else "idle_body_damage"
				reaction_wait = reaction.start_death(death_clip,speed)
				world.rings[event.target].hide()
				world.actor_labels[event.target].hide()
			elif event.result != "未命中":
				if str(event.result).begins_with("腿"): reaction.wounded="腿"
				elif str(event.result).begins_with("手臂"): reaction.wounded="手臂"
				elif str(event.result).begins_with("躯干"): reaction.wounded="躯干"
				if str(event.result).begins_with("躯干"):
					reaction_wait=reaction.start_fall(speed)
				else:
					reaction.start_clip("idle_body_damage_armor" if event.result == "防具抵挡" else "idle_damage_leg" if str(event.result).begins_with("腿") else "damage_hand_hide" if reaction.cover_tier > 0 else "damage_hand_idle")
					reaction_wait = reaction.duration(reaction.action_clip)/speed
		# Shooter and victim animate concurrently. Wait for both, not the sum.
		var recovery := maxf(.01,motion.duration(clip)-motion.event_time(clip))/speed if actor_visible and event.kind != "death" else 0.0
		var recovery_done := {"done":true}
		if actor_visible and event.kind=="shoot":
			# Lower the gun as soon as recoil ends, while the victim is still
			# reacting. Holding phase endpoints prevents idle between clips.
			recovery_done.done=false
			recover_shooter(motion,clip,shoot_prefix,speed,recovery_done)
			recovery += motion.duration(shoot_prefix+"end")/speed
		if maxf(recovery,reaction_wait) > 0:
			await get_tree().create_timer(maxf(recovery,reaction_wait)).timeout
		while not recovery_done.done: await get_tree().process_frame
		if target_visible and event.kind != "reload":
			target.get_node("Motion").playback_speed = 1.0
		# Shooter recovery and target reaction have both completed here.
		motion.playback_speed = 1.0
