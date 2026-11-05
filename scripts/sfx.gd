extends Node
## 効果音とBGMをコードで生成（外部音声アセット不要）。

const RATE := 22050
var streams := {}
var players: Array = []
var last := {}
var enabled := true
var bgm: AudioStreamPlayer
var bgm_streams := {}
var bgm_name := ""

func _ready() -> void:
	streams["swing"] = _sweep(2400.0, 700.0, 0.09, 0.10, 2)
	streams["swing_fin"] = _sweep(1800.0, 300.0, 0.16, 0.14, 2)
	streams["hit"] = _tone(320.0, 120.0, 0.07, 0.16, 3)
	streams["hit_crit"] = _tone(520.0, 140.0, 0.10, 0.18, 3)
	streams["kill"] = _tone(300.0, 60.0, 0.16, 0.16, 2)
	streams["hurt"] = _tone(220.0, 70.0, 0.2, 0.2, 3)
	streams["die"] = _tone(300.0, 40.0, 0.7, 0.22, 3)
	streams["roll"] = _sweep(500.0, 1400.0, 0.12, 0.07, 2)
	streams["chest"] = _arp([523.0, 659.0, 784.0, 1046.0, 1318.0], 0.05, 0.12)
	streams["pickup"] = _tone(1050.0, 1700.0, 0.08, 0.10, 1)
	streams["potion"] = _arp([392.0, 523.0, 659.0, 784.0], 0.05, 0.11)
	streams["levelup"] = _arp([523.0, 659.0, 784.0, 1046.0], 0.07, 0.14)
	streams["stairs"] = _arp([784.0, 659.0, 523.0, 392.0], 0.07, 0.12)
	streams["roar"] = _tone(140.0, 55.0, 0.9, 0.24, 3)
	streams["slam"] = _tone(120.0, 30.0, 0.35, 0.26, 2)
	streams["jump"] = _tone(200.0, 600.0, 0.25, 0.12, 0)
	streams["charge"] = _tone(180.0, 90.0, 0.25, 0.14, 3)
	streams["shoot"] = _tone(900.0, 500.0, 0.07, 0.08, 0)
	streams["magic"] = _tone(700.0, 1300.0, 0.15, 0.08, 1)
	streams["teleport"] = _tone(400.0, 1600.0, 0.2, 0.08, 1)
	streams["parry"] = _tone(2200.0, 1800.0, 0.06, 0.10, 0)
	streams["bump"] = _tone(150.0, 60.0, 0.15, 0.2, 2)
	streams["boss_die"] = _tone(200.0, 30.0, 1.4, 0.26, 2)
	streams["click"] = _tone(700.0, 900.0, 0.04, 0.10, 1)
	streams["start"] = _arp([392.0, 523.0, 784.0], 0.08, 0.14)
	streams["clear"] = _arp([523.0, 659.0, 784.0, 1046.0, 784.0, 1046.0, 1318.0], 0.11, 0.14)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	bgm = AudioStreamPlayer.new()
	bgm.volume_db = -9.0
	add_child(bgm)

func play(name: String, gap := 0.04) -> void:
	if not enabled or not streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last.get(name, -10.0)) < gap:
		return
	last[name] = now
	for p in players:
		if not p.playing:
			p.stream = streams[name]
			p.play()
			return

func _wave(kind: int, ph: float) -> float:
	match kind:
		0: return 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
		1: return sin(ph * TAU)
		2: return randf_range(-1.0, 1.0)
		_: return absf(fmod(ph, 1.0) * 4.0 - 2.0) - 1.0

func _make(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s

func _tone(f0: float, f1: float, dur: float, vol: float, kind: int) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += lerpf(f0, f1, k) / RATE
		var env := minf(1.0, i / (0.004 * RATE)) * pow(1.0 - k, 2.0)
		var v := _wave(kind, ph)
		if kind == 3:
			v = v * 0.6 + randf_range(-1.0, 1.0) * 0.4
		out[i] = v * vol * env
	return _make(out)

## ノイズをローパスで掃引（剣の風切り音など）
func _sweep(f0: float, f1: float, dur: float, vol: float, _kind: int) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var k := float(i) / n
		var fc := lerpf(f0, f1, k)
		var a := clampf(TAU * fc / RATE, 0.0, 1.0)
		y += (randf_range(-1.0, 1.0) - y) * a
		var env := minf(1.0, i / (0.01 * RATE)) * pow(1.0 - k, 1.5)
		out[i] = y * vol * 3.0 * env
	return _make(out)

func _arp(freqs: Array, note: float, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var per := int(note * RATE)
	out.resize(per * freqs.size() + per * 2)
	var ph := 0.0
	for j in freqs.size():
		var len := per * (3 if j == freqs.size() - 1 else 1)
		for i in len:
			var idx := j * per + i
			if idx >= out.size():
				break
			ph += float(freqs[j]) / RATE
			var k := float(i) / len
			out[idx] = (sin(ph * TAU) * 0.6 + (1.0 if fmod(ph, 1.0) < 0.5 else -1.0) * 0.25) * vol * (1.0 - k)
	return _make(out)

# ---------- BGM（簡易チップチューン、ループ） ----------
func _midi(n: int) -> float:
	return 440.0 * pow(2.0, (n - 69) / 12.0)

func _gen_bgm(kind: String) -> AudioStreamWAV:
	var bpm := 112.0 if kind == "dungeon" else 150.0
	var step := 60.0 / bpm / 2.0  # 8分音符
	var bass: Array
	var lead: Array
	if kind == "dungeon":
		# Am - F - G - Em
		bass = [45, 45, 57, 45, 41, 41, 53, 41, 43, 43, 55, 43, 40, 40, 52, 40]
		lead = [69, -1, 72, 76, 74, -1, 72, 71, 72, -1, 69, -1, 67, 69, 71, -1,
				69, -1, 72, 76, 77, -1, 76, 74, 76, -1, 74, 72, 71, -1, -1, -1]
	else:
		# Dm - Bb - C - A
		bass = [38, 50, 38, 50, 34, 46, 34, 46, 36, 48, 36, 48, 33, 45, 33, 45]
		lead = [62, 65, 69, 74, 72, 69, 65, 69, 70, 69, 67, 65, 67, -1, 64, -1,
				62, 65, 69, 74, 76, 74, 72, 74, 72, 70, 69, 67, 69, -1, 61, 64]
	var steps := 32
	var spn := int(step * RATE)
	var n := spn * steps
	var out := PackedFloat32Array()
	out.resize(n)
	var phb := 0.0
	var phl := 0.0
	for s in steps:
		var bn: int = bass[(s / 2) % bass.size()] if kind == "dungeon" else bass[s % bass.size()]
		var ln: int = lead[s % lead.size()]
		var fb := _midi(bn)
		var fl := _midi(ln) if ln >= 0 else 0.0
		for i in spn:
			var k := float(i) / spn
			phb += fb / RATE
			var b := (absf(fmod(phb, 1.0) * 4.0 - 2.0) - 1.0) * 0.28 * (1.0 - k * 0.5)
			var l := 0.0
			if fl > 0.0:
				phl += fl / RATE
				var duty := 0.25
				l = (1.0 if fmod(phl, 1.0) < duty else -1.0) * 0.07 * minf(1.0, (1.0 - k) * 3.0)
			var dr := 0.0
			if kind == "boss" or s % 2 == 0:
				if i < spn * 0.25 and (s % 4 == 0):
					dr = sin(TAU * (90.0 - k * 200.0) * i / RATE) * 0.3 * (1.0 - float(i) / (spn * 0.25))
				elif i < spn * 0.08 and s % 4 == 2:
					dr = randf_range(-1.0, 1.0) * 0.1 * (1.0 - float(i) / (spn * 0.08))
			out[s * spn + i] = b + l + dr
	return _make(out, true)

func play_bgm(kind: String) -> void:
	if not enabled:
		return
	if bgm_name == kind and bgm.playing:
		return
	bgm_name = kind
	if kind == "":
		bgm.stop()
		return
	if not bgm_streams.has(kind):
		bgm_streams[kind] = _gen_bgm(kind)
	bgm.stream = bgm_streams[kind]
	bgm.play()

func stop_bgm() -> void:
	bgm_name = ""
	bgm.stop()
