extends AudioStreamPlayer

# Synthesized shot and bolt sounds: no third-party recordings.
var shot_clip: AudioStreamWAV
var bolt_clip: AudioStreamWAV


func _ready() -> void:
	max_polyphony = 4
	shot_clip = _clip(false)
	bolt_clip = _clip(true)


func trigger(is_bolt: bool, level: float, enemy: bool = false) -> void:
	if level <= 0:
		return
	stream = bolt_clip if is_bolt else shot_clip
	volume_db = linear_to_db(level / 100.0) - (5.0 if enemy else 0.0)
	pitch_scale = 0.88 if enemy else 1.0
	play()


func _clip(is_bolt: bool) -> AudioStreamWAV:
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = 44100
	var duration := 0.085 if is_bolt else 0.19
	var count := int(duration * 44100)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 8842 if is_bolt else 7312
	for index in count:
		var t := index / 44100.0
		var envelope := minf(t / 0.001, 1) * exp(-t * (65 if is_bolt else 28))
		var wave := random.randf_range(-1, 1) * (0.65 if is_bolt else 0.45)
		wave += sin(TAU * (1700 if is_bolt else 95) * t) * 0.3
		bytes.encode_s16(index * 2, int(wave * envelope * 20000))
	clip.data = bytes
	return clip
