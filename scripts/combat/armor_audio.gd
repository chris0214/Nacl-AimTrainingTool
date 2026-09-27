extends Node

const RATE := 44100
var voices: Array[AudioStreamPlayer] = []
var enabled := true
var level := 55.0
var played_events := [0, 0]


func _ready() -> void:
	for side in 2:
		var voice := AudioStreamPlayer.new()
		voice.stream = make_clip(side)
		add_child(voice)
		voices.append(voice)


static func make_clip(side: int) -> AudioStreamWAV:
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = RATE
	var duration := 0.18 if side == 0 else 0.26
	var count := int(RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 7843 + side
	for index in count:
		var t := float(index) / RATE
		var envelope := minf(t / 0.002, 1) * exp(-t * 22) * pow(1 - t / duration, 2)
		var frequency := 1700.0 if side == 0 else 650.0
		var phase := TAU * (frequency * t - frequency * t * t * 1.4)
		var shards := sin(phase) * 0.38 + sin(phase * 1.73) * 0.22
		var noise := random.randf_range(-1, 1) * exp(-t * 45) * 0.22
		var body := sin(TAU * 140 * t) * 0.12 if side == 1 else 0.0
		pcm.encode_s16(index * 2, roundi((shards + noise + body) * envelope * 26000))
	clip.data = pcm
	return clip


func configure(values: Dictionary) -> void:
	stop()
	enabled = values.armor_sound
	level = values.armor_volume
	for voice in voices:
		voice.volume_db = linear_to_db(maxf(0.00001, level / 100.0))


func broken(own: bool) -> void:
	if not enabled or level <= 0:
		return
	var side := int(own)
	played_events[side] += 1
	voices[side].play()


func stop() -> void:
	for voice in voices:
		voice.stop()
