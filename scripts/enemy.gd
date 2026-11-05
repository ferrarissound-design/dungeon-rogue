extends RefCounted
## 敵1体ぶんのデータとAI。g = game.gd

const DEF := {
	"slime": {"name": "スライム", "hp": 14.0, "dmg": 5.0, "spd": 36.0, "r": 5.0, "xp": 3, "tex": "slime"},
	"bat": {"name": "コウモリ", "hp": 8.0, "dmg": 4.0, "spd": 58.0, "r": 4.0, "xp": 3, "tex": "bat"},
	"archer": {"name": "骸骨弓兵", "hp": 12.0, "dmg": 6.0, "spd": 40.0, "r": 5.0, "xp": 5, "tex": "archer"},
	"charger": {"name": "突撃オーク", "hp": 28.0, "dmg": 9.0, "spd": 30.0, "r": 6.0, "xp": 7, "tex": "charger"},
	"mage": {"name": "闇の魔術師", "hp": 18.0, "dmg": 6.0, "spd": 30.0, "r": 5.0, "xp": 8, "tex": "mage"},
	"boss": {"name": "深淵の魔王", "hp": 1300.0, "dmg": 15.0, "spd": 42.0, "r": 11.0, "xp": 0, "tex": "boss"},
}

var type := "slime"
var tex := "slime"
var pos := Vector2.ZERO
var vel := Vector2.ZERO      # ノックバック
var mv := Vector2.ZERO       # 自発的な移動
var hp := 10.0
var maxhp := 10.0
var dmg := 5.0
var spd := 40.0
var r := 5.0
var xp := 3
var state := "idle"
var t := 0.0
var cd := 0.0
var flash := 0.0
var aggro := false
var face := 1.0
var anim := 0.0
var dead := false
var aim := Vector2.RIGHT
var phase := 1
var spawn_t := 0.0
var invuln := 0.0
var touch_cd := 0.0
var counter := 0
var minion := false
var target := Vector2.ZERO
var stagger := 0.0
var last_pattern := ""

func setup(kind: String, p: Vector2, floor_num: int) -> void:
	type = kind
	var d: Dictionary = DEF[kind]
	tex = d["tex"]
	pos = p
	var hs := 1.0 + 0.38 * (floor_num - 1)
	var ds := 1.0 + 0.30 * (floor_num - 1)
	if kind == "boss":
		hs = 1.0
		ds = 1.0
	maxhp = d["hp"] * hs
	hp = maxhp
	dmg = d["dmg"] * ds
	spd = d["spd"]
	r = d["r"]
	xp = int(d["xp"] * (1.0 + 0.25 * (floor_num - 1)))
	cd = randf_range(0.5, 1.5)
	anim = randf() * 10.0
	if kind == "boss":
		state = "sleep"

func contact_damage() -> float:
	if type == "charger" and state == "charge":
		return dmg * 1.3
	if type == "boss":
		return dmg * 0.8
	if type == "archer" or type == "mage":
		return dmg * 0.5
	return dmg

func update(g, dt: float) -> void:
	anim += dt
	flash = maxf(0.0, flash - dt)
	touch_cd = maxf(0.0, touch_cd - dt)
	invuln = maxf(0.0, invuln - dt)
	stagger = maxf(0.0, stagger - dt)
	if spawn_t > 0.0:
		spawn_t -= dt
		return
	cd -= dt
	t += dt
	mv = Vector2.ZERO
	var to_p: Vector2 = g.ppos - pos
	var dist := to_p.length()
	if not aggro and type != "boss":
		var sight := 150.0 if type == "bat" else 125.0
		if dist < sight and g.los(pos, g.ppos):
			aggro = true
			g.on_enemy_alert(self)
		elif dist < 40.0:
			aggro = true
	if aggro and g.alive:
		match type:
			"slime": _ai_slime(g, dt, to_p, dist)
			"bat": _ai_bat(g, dt, to_p, dist)
			"archer": _ai_ranged(g, dt, to_p, dist, false)
			"mage": _ai_ranged(g, dt, to_p, dist, true)
			"charger": _ai_charger(g, dt, to_p, dist)
			"boss": _ai_boss(g, dt, to_p, dist)
	elif type == "boss" and state != "sleep":
		mv = Vector2.ZERO
	if absf(mv.x) > 1.0:
		face = signf(mv.x)
	elif absf(to_p.x) > 2.0 and aggro and state != "charge":
		face = signf(to_p.x)
	if stagger > 0.0:
		mv *= 0.2
	var res: Array = g.move_body(pos, (mv + vel) * dt, r)
	pos = res[0]
	if res[1] and type == "charger" and state == "charge":
		state = "stun"
		t = 0.0
		g.add_shake(3.0)
		g.burst(pos + aim * r, Color(0.8, 0.75, 0.6), 10, 60.0)
		g.play("bump")
	vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * dt))

func _chase(g, to_p: Vector2, dist: float) -> Vector2:
	if dist < 1.0:
		return Vector2.ZERO
	if g.los_wide(pos, g.ppos, r):
		return to_p / dist
	return g.flow_dir(pos)

# ---- スライム: 跳ねながら追いかける ----
func _ai_slime(g, _dt: float, to_p: Vector2, dist: float) -> void:
	var cyc := fmod(anim, 0.9)
	if cyc < 0.45:
		mv = _chase(g, to_p, dist) * spd * 1.9
	else:
		mv = Vector2.ZERO

# ---- コウモリ: ふらふら飛び回り、時々急降下 ----
func _ai_bat(g, _dt: float, to_p: Vector2, dist: float) -> void:
	var dir := _chase(g, to_p, dist)
	var side := Vector2(-dir.y, dir.x) * sin(anim * 5.0) * 0.9
	if state == "dart":
		mv = aim * spd * 2.6
		if t > 0.32:
			state = "idle"
			t = 0.0
			cd = randf_range(1.6, 2.6)
		return
	mv = (dir + side).normalized() * spd
	if dist < 22.0:
		mv = (-dir + side * 2.0).normalized() * spd * 0.8
	if cd <= 0.0 and dist < 90.0 and g.los(pos, g.ppos):
		state = "dart"
		t = 0.0
		aim = to_p / maxf(dist, 1.0)

# ---- 弓兵/魔術師: 距離をとって撃つ ----
func _ai_ranged(g, _dt: float, to_p: Vector2, dist: float, is_mage: bool) -> void:
	var see: bool = g.los(pos, g.ppos)
	if state == "aim":
		mv = Vector2.ZERO
		if not is_mage:
			aim = to_p / maxf(dist, 1.0)
		if t >= (0.7 if is_mage else 0.55):
			if is_mage:
				var base := aim.angle()
				for i in 3:
					var a := base + (i - 1) * 0.38
					g.spawn_bullet(pos, Vector2.from_angle(a) * 85.0, dmg, Color(0.75, 0.4, 1.0), 4.0, 0.9)
				g.play("magic")
			else:
				g.spawn_bullet(pos, aim * 155.0, dmg, Color(0.95, 0.9, 0.7), 3.0, 0.0, "arrow")
				g.play("shoot")
			state = "idle"
			t = 0.0
			cd = randf_range(2.0, 2.8) if is_mage else randf_range(1.6, 2.3)
		return
	if state == "teleport":
		mv = Vector2.ZERO
		if t > 0.35:
			var np: Vector2 = g.random_floor_near(g.ppos, 60.0, 110.0)
			if np != Vector2.INF:
				g.burst(pos, Color(0.6, 0.3, 0.9), 12, 50.0)
				pos = np
				g.burst(pos, Color(0.6, 0.3, 0.9), 12, 50.0)
			state = "idle"
			t = 0.0
			cd = maxf(cd, 0.8)
		return
	var want_min := 55.0
	var want_max := 115.0
	if is_mage and dist < 42.0 and counter < 6 and cd < 1.2:
		state = "teleport"
		t = 0.0
		counter += 1
		g.play("teleport")
		return
	if dist > want_max or not see:
		mv = _chase(g, to_p, dist) * spd
	elif dist < want_min:
		mv = -to_p / maxf(dist, 1.0) * spd * 1.1
	else:
		var side := Vector2(-to_p.y, to_p.x).normalized()
		mv = side * spd * 0.5 * (1.0 if fmod(anim, 4.0) < 2.0 else -1.0)
	if cd <= 0.0 and see and dist < 175.0:
		state = "aim"
		t = 0.0
		aim = to_p / maxf(dist, 1.0)

# ---- 突撃オーク: 溜めてから一直線に突進 ----
func _ai_charger(g, _dt: float, to_p: Vector2, dist: float) -> void:
	match state:
		"windup":
			mv = Vector2.ZERO
			if t < 0.45:
				aim = to_p / maxf(dist, 1.0)
			if t >= 0.65:
				state = "charge"
				t = 0.0
				g.play("charge")
		"charge":
			mv = aim * 205.0
			if t > 0.75:
				state = "idle"
				t = 0.0
				cd = randf_range(1.4, 2.0)
		"stun":
			mv = Vector2.ZERO
			if t > 1.1:
				state = "idle"
				t = 0.0
				cd = 0.8
		_:
			mv = _chase(g, to_p, dist) * spd
			if cd <= 0.0 and dist < 135.0 and dist > 20.0 and g.los_wide(pos, g.ppos, r):
				state = "windup"
				t = 0.0
				aim = to_p / maxf(dist, 1.0)

# ---- ボス: 複数の攻撃パターン + 2段階のフェーズ ----
func _ai_boss(g, dt: float, to_p: Vector2, dist: float) -> void:
	var dir := to_p / maxf(dist, 1.0)
	if phase == 1 and hp < maxhp * 0.5:
		phase = 2
		state = "enrage"
		t = 0.0
		invuln = 1.4
		g.on_boss_phase2(self)
		return
	match state:
		"sleep":
			return
		"intro":
			if t > 1.6:
				state = "idle"
				t = 0.0
		"enrage":
			if t > 1.4:
				state = "idle"
				t = 0.0
		"idle":
			mv = _chase(g, to_p, dist) * spd * (1.25 if phase == 2 else 1.0)
			if dist < 30.0:
				mv *= 0.3
			if t > (0.55 if phase == 2 else 0.95):
				_pick_pattern(g, dist)
		"ring":
			if t > 0.6 and counter == 0 or t > 1.1 and counter == 1 or (phase == 2 and t > 1.6 and counter == 2):
				var n := 14 if phase == 1 else 18
				var off := 0.0 if counter % 2 == 0 else PI / n
				for i in n:
					g.spawn_bullet(pos, Vector2.from_angle(TAU * i / n + off) * (78.0 if phase == 1 else 90.0), dmg, Color(1.0, 0.35, 0.3), 4.0)
				g.play("magic")
				counter += 1
			if t > (1.5 if phase == 1 else 2.0):
				_to_idle()
		"fan":
			if t > 0.45 + counter * 0.35 and counter < 3:
				var base := dir.angle()
				var n2 := 5 if phase == 1 else 7
				for i in n2:
					var a := base + (i - (n2 - 1) * 0.5) * 0.17
					g.spawn_bullet(pos, Vector2.from_angle(a) * 125.0, dmg, Color(1.0, 0.6, 0.2), 3.5)
				g.play("shoot")
				counter += 1
			if t > 1.7:
				_to_idle()
		"charge_wind":
			if t < 0.5:
				aim = dir
			if t > 0.8:
				state = "charge"
				t = 0.0
				g.play("charge")
		"charge":
			mv = aim * (250.0 if phase == 2 else 220.0)
			var res: Array = g.move_body(pos, mv * dt, r)
			if res[1] or t > 0.8:
				if res[1]:
					g.add_shake(6.0)
					g.play("slam")
					g.burst(pos + aim * r, Color(0.8, 0.7, 0.6), 18, 90.0)
					if phase == 2:
						for i in 10:
							g.spawn_bullet(pos, Vector2.from_angle(TAU * i / 10.0) * 85.0, dmg, Color(1.0, 0.35, 0.3), 4.0)
				state = "stun"
				t = 0.0
			mv = Vector2.ZERO
			pos = res[0]
		"stun":
			if t > 0.9:
				_to_idle()
		"summon":
			if t > 0.8 and counter == 0:
				counter = 1
				var n3 := 2 if phase == 1 else 3
				for i in n3:
					if g.minion_count() < 5:
						var kind := "bat" if randf() < 0.5 else ("slime" if phase == 1 else "charger")
						g.spawn_minion(kind, pos + Vector2.from_angle(randf() * TAU) * 28.0)
				g.play("teleport")
			if t > 1.3:
				_to_idle()
		"spiral":
			if fmod(t, 0.085) < dt and t > 0.4:
				var a2 := t * 2.6
				for k in 3:
					g.spawn_bullet(pos, Vector2.from_angle(a2 + TAU * k / 3.0) * 72.0, dmg, Color(0.85, 0.35, 1.0), 3.5)
			if t > 3.0:
				_to_idle()
		"slam_up":
			target = target.lerp(g.ppos, 1.0 - exp(-6.0 * dt))
			if t > 0.9:
				state = "slam_down"
				t = 0.0
		"slam_down":
			if t > 0.45:
				pos = g.clamp_to_floor(target, r)
				g.add_shake(8.0)
				g.play("slam")
				g.burst(pos, Color(0.9, 0.5, 0.4), 24, 110.0)
				g.shockwave(pos, 38.0, dmg * 1.4)
				for i in 12:
					g.spawn_bullet(pos, Vector2.from_angle(TAU * i / 12.0 + 0.2) * 95.0, dmg, Color(1.0, 0.35, 0.3), 4.0)
				state = "stun"
				t = 0.2
	# 被ダメージで怯まない
	vel *= 0.3

func _to_idle() -> void:
	state = "idle"
	t = 0.0
	counter = 0

func _pick_pattern(g, dist: float) -> void:
	var opts := ["ring", "fan", "charge_wind", "summon"]
	if phase == 2:
		opts += ["spiral", "slam_up", "slam_up"]
	if g.minion_count() >= 3:
		opts.erase("summon")
	opts.erase(last_pattern)
	if dist > 120.0 and opts.has("summon") and randf() < 0.3:
		opts.erase("summon")
	var p: String = opts[randi() % opts.size()]
	last_pattern = p
	state = p
	t = 0.0
	counter = 0
	if p == "slam_up":
		target = g.ppos
		g.play("jump")
	elif p == "charge_wind":
		aim = (g.ppos - pos).normalized()

func airborne() -> bool:
	return type == "boss" and (state == "slam_up" or state == "slam_down")
