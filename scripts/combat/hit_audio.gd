extends AudioStreamPlayer

const SAMPLE_RATE := 44100
var clips: Array[AudioStreamWAV] = []
var enabled := true
var level := 45.0
var played_events := 0


func _ready() -> void:
	max_polyphony = 2
	for style in 3:
		clips.append(make_clip(style))


static func make_clip(style: int) -> AudioStreamWAV:
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = SAMPLE_RATE
	clip.stereo = false
	var samples := int(SAMPLE_RATE * 0.036)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for index in samples:
		var t := float(index) / SAMPLE_RATE
		var envelope := minf(t / 0.0015, 1.0) * exp(-t * 130.0) * (1.0 - float(index) / samples)
		var wave := sin(TAU * 920.0 * t)
		if style == 1:
			wave = (sin(TAU * 1450.0 * t) + 0.45 * sin(TAU * 2317.0 * t)) / 1.45
		elif style == 2:
			wave = sin(TAU * (1800.0 * t - 12000.0 * t * t))
		pcm.encode_s16(index * 2, roundi(wave * envelope * 0.6 * 32767.0))
	clip.data = pcm
	return clip


func configure(values: Dictionary) -> void:
	stop()
	enabled = values.hit_sound
	level = values.hit_volume
	stream = clips[int(values.hit_sound_style)]
	volume_db = linear_to_db(maxf(0.00001, level / 100.0))


func confirmed_hit(damage: int) -> void:
	if damage <= 0 or not enabled or level <= 0.0:
		return
	played_events += 1
	play()
