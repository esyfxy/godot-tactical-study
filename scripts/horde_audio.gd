extends Node

# Original HordeMode scene: prep=5. HordeModeWeather overrides 4/6/8 at
# waves 1/3/5. Loop offsets come from GameParametersDatabase.MusicTracks.
const LOOP_OFFSETS = {"m05": 179.142, "m04": 105.75, "m06": 140.571, "m08": 289.756}
const ROOT = "res://assets/horde/audio/"
var music: Array[AudioStreamPlayer] = []
var voice: AudioStreamPlayer
var current_track := ""
var active := 0
var fade := 1.0
var crossfade: Tween
var duck := 1.0
var enabled := true
var rng := RandomNumberGenerator.new()
var last_clip := {}
var cache := {}
var voice_count := 0
var music_changes := 0
var effects: AudioStreamPlayer
var music_gain := 1.0

func _exit_tree() -> void:
	if crossfade != null and crossfade.is_valid(): crossfade.kill()
	for player in music+[voice,effects]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	cache.clear()

func _ready() -> void:
	rng.randomize() # Audio selection never consumes the tactical simulation RNG.
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.volume_db = -80
		add_child(player)
		music.append(player)
	voice = AudioStreamPlayer.new()
	voice.volume_db = -3
	add_child(voice)
	effects = AudioStreamPlayer.new()
	effects.volume_db = -10
	add_child(effects)

func shot(gun: String) -> void:
	var filename: String = {"Glock":"TacticsGlockShot.ogg","Rifle":"TacticsRifleShot.wav","Shotgun":"TacticsShotgunShot.wav"}.get(gun,"TacticsGunshot.wav")
	var path := ROOT+"combat/"+filename
	if not cache.has(path):
		cache[path] = load(path) if ResourceLoader.exists(path) else AudioStreamWAV.load_from_file(path) if path.ends_with("wav") else AudioStreamOggVorbis.load_from_file(path)
	effects.stream = cache[path]
	effects.play()

func stream(path: String) -> AudioStreamOggVorbis:
	if not cache.has(path):
		# Imported resources work in exported builds; raw fallback also allows
		# first launch before the editor has imported newly copied source audio.
		cache[path] = load(path).duplicate() if ResourceLoader.exists(path) else AudioStreamOggVorbis.load_from_file(path)
	return cache[path]

func sync(wave: int, phase: String) -> void:
	enabled = phase != "defeat"
	if not enabled:
		voice.stop()
		return
	var track := "m05" if wave == 0 else "m04" if wave < 3 else "m06" if wave < 5 else "m08"
	if current_track == track: return
	current_track = track
	music_changes += 1
	if crossfade != null and crossfade.is_valid(): crossfade.kill()
	active = 1-active
	var audio := stream(ROOT + "music/" + track + ".ogg")
	if audio == null: return
	audio.loop = true
	audio.loop_offset = float(LOOP_OFFSETS[track])
	music[active].stream = audio
	music[active].volume_db = -80
	music[active].play()
	fade = 0
	crossfade = create_tween()
	crossfade.tween_property(self, "fade", 1.0, 1.5)
	crossfade.tween_callback(func(): music[1-active].stop())

static func voice_group(cop: Dictionary) -> String:
	var female := int(cop.get("gender", 0)) == 1
	var age := int(cop.get("age", 1))
	return ("Female" if female else "Male") + ("Old" if age == 2 else "Young" if age == 0 and not female else "")

func confirm_move(cop: Dictionary) -> bool:
	if not enabled or voice.playing or cop.get("dead", false) or cop.get("captured", false): return false
	if not str(cop.get("wound", "")).is_empty() or int(cop.get("stun", 0)) > 0: return false
	var group := voice_group(cop)
	var count := 11 if group == "FemaleOld" else 10
	var previous := int(last_clip.get(group, 0))
	var index := rng.randi_range(1, count-1) if previous > 0 else rng.randi_range(1, count)
	if previous > 0 and index >= previous: index += 1
	var audio := stream(ROOT + "confirmation/Confirmation %s %d.ogg" % [group, index])
	if audio == null: return false
	last_clip[group] = index
	voice.stream = audio
	voice.play()
	voice_count += 1
	return true

func _process(delta: float) -> void:
	duck = move_toward(duck, (0.4 if voice.playing else 1.0) if enabled else 0.0, delta*2.5)
	for i in range(music.size()):
		var gain := (fade if i == active else 1.0-fade)*duck*0.28*music_gain
		music[i].volume_db = linear_to_db(maxf(gain, 0.0001))
		if not enabled and duck <= 0.0: music[i].stop()
