extends Node2D
## ゲーム世界: ダンジョン、プレイヤー、敵、弾、宝箱、エフェクト、描画。

signal died
signal won
signal floor_started(n: int)
signal message(text: String, col: Color)

const Art := preload("res://scripts/art.gd")
const Dungeon := preload("res://scripts/dungeon.gd")
const Items := preload("res://scripts/items.gd")
const Enemy := preload("res://scripts/enemy.gd")
const T := 16
const FLOORS := 5
const BASE := {"atk": 6.0, "def": 0.0, "maxhp": 40.0, "spd": 0.0, "crit": 0.05, "aspd": 0.0, "reach": 0.0, "regen": 0.0, "vamp": 0.0, "roll": 0.0}
const PLAYER_R := 5.0
const MOVE_SPEED := 84.0
const ROLL_SPEED := 240.0
const MAX_POTIONS := 5
const TRAP_CYCLE := 2.6

var sfx
var rng := RandomNumberGenerator.new()
var run_seed := 0
var floor_num := 1
var dun
var map_tex: ImageTexture
var astar: AStarGrid2D
var explored := PackedByteArray()
var minimap_img: Image
var minimap_tex: ImageTexture
var minimap_dirty := true
var god := false
var weak := false
var hide_player := false

# 入力（main.gd が毎フレーム設定）
var in_move := Vector2.ZERO
var in_attack := false
var in_attack_pressed := false
var in_dodge := false
var in_potion := false

# プレイヤー
var ppos := Vector2.ZERO
var pface := Vector2.RIGHT
var pvel_vis := Vector2.ZERO
var pknock := Vector2.ZERO
var php := 40.0
var level := 1
var xp := 0
var pending_levelups := 0
var pending_item := {}
var potions := 1
var perks := {}
var equip := {"weapon": {}, "armor": {}, "accessory": {}}
var st := {}
var roll_t := 0.0
var roll_cd := 0.0
var roll_dir := Vector2.RIGHT
var iframes := 0.0
var swing_t := 0.0
var atk_cd := 0.0
var atk_buffer := 0.0
var combo := 0
var combo_t := 0.0
var pflash := 0.0
var alive := true
var dead_t := 0.0
var died_emitted := false
var walk_anim := 0.0
var regen_acc := 0.0
var after_t := 0.0

var enemies: Array = []
var traps: Array = []        # トゲ罠 {cell, pos, ph}
var bullets: Array = []
var chests: Array = []
var pickups: Array = []
var particles: Array = []
var texts: Array = []
var slashes: Array = []
var afterimages: Array = []
var waves: Array = []
var boss = null
var boss_active := false
var boss_dead_t := -1.0
var won_emitted := false
var trans_t := 0.0
var fade := 0.0
var shake := 0.0
var hitstop := 0.0
var flow := PackedInt32Array()
var flow_t := 0.0
var reveal_t := 0.0
var kills := 0
var time := 0.0
var floor_time := 0.0
var camera: Camera2D
var cam_pos := Vector2.ZERO
var light_r := 175.0
var stats_log := {"dmg_taken": 0.0, "chests": 0, "potions_used": 0}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

func play(name: String, gap := 0.04) -> void:
	if sfx:
		sfx.play(name, gap)

# ================= ラン / フロア =================
func new_run(seed: int) -> void:
	run_seed = seed
	rng.seed = seed
	hide_player = false
	level = 1
	xp = 0
	pending_levelups = 0
	pending_item = {}
	potions = 1
	perks = {}
	equip = {"weapon": {"slot": "weapon", "name": "古びた剣", "rarity": 0, "stats": {"atk": 1.0}, "score": 1.0}, "armor": {}, "accessory": {}}
	recalc()
	php = st["maxhp"]
	if weak:
		php = 1.0
	alive = true
	dead_t = 0.0
	died_emitted = false
	won_emitted = false
	kills = 0
	time = 0.0
	stats_log = {"dmg_taken": 0.0, "chests": 0, "potions_used": 0}
	start_floor(1)

func start_floor(n: int) -> void:
	floor_num = n
	floor_time = 0.0
	enemies.clear()
	bullets.clear()
	chests.clear()
	pickups.clear()
	traps.clear()
	particles.clear()
	texts.clear()
	slashes.clear()
	afterimages.clear()
	waves.clear()
	boss = null
	boss_active = false
	boss_dead_t = -1.0
	roll_t = 0.0
	swing_t = 0.0
	iframes = 0.0
	pknock = Vector2.ZERO
	dun = Dungeon.new()
	var s := run_seed * 7919 + n * 104729
	for attempt in 20:
		dun.generate(s + attempt, n, n == FLOORS)
		if dun.validate() == "":
			break
		push_warning("floor regen: " + dun.validate())
	var img: Image = Art.build_map_image(dun.grid, dun.w, dun.h, n - 1, s)
	map_tex = ImageTexture.create_from_image(img)
	_build_astar()
	explored = PackedByteArray()
	explored.resize(dun.w * dun.h)
	explored.fill(0)
	minimap_img = Image.create(dun.w, dun.h, false, Image.FORMAT_RGBA8)
	minimap_tex = ImageTexture.create_from_image(minimap_img)
	minimap_dirty = true
	ppos = cell_center(dun.start_cell)
	cam_pos = ppos
	camera.position = ppos
	camera.limit_left = -T * 4
	camera.limit_top = -T * 4
	camera.limit_right = dun.w * T + T * 4
	camera.limit_bottom = dun.h * T + T * 4
	camera.reset_smoothing()
	light_r = 175.0
	flow = PackedInt32Array()
	_populate()
	_reveal()
	fade = 1.0
	floor_started.emit(n)

func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, dun.w, dun.h)
	astar.cell_size = Vector2(T, T)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in dun.h:
		for x in dun.w:
			if dun.grid[y * dun.w + x] == 0:
				astar.set_point_solid(Vector2i(x, y), true)

func _populate() -> void:
	var weights := {
		1: {"slime": 5, "bat": 3, "archer": 2},
		2: {"slime": 3, "bat": 3, "archer": 3, "charger": 2},
		3: {"slime": 2, "bat": 2, "archer": 3, "charger": 3, "mage": 2},
		4: {"slime": 2, "bat": 3, "archer": 3, "charger": 3, "mage": 3},
	}
	var used := [dun.start_cell, dun.stairs_cell]
	if floor_num < FLOORS:
		var wt: Dictionary = weights[floor_num]
		for i in dun.rooms.size():
			if i == dun.start_room:
				continue
			var r: Rect2i = dun.rooms[i]
			var area := r.size.x * r.size.y
			var cnt := clampi(1 + area / 30 + int(floor_num * 0.3) + rng.randi_range(-1, 1), 1, 5)
			for k in cnt:
				var c: Vector2i = dun.random_cell_in(r, used)
				used.append(c)
				var e = Enemy.new()
				e.setup(_pick_weighted(wt), cell_center(c), floor_num)
				if floor_num >= 2 and e.type != "bat" and rng.randf() < 0.05 + 0.02 * floor_num:
					e.make_elite()
				enemies.append(e)
		# 宝箱
		var rooms_idx := []
		for i in dun.rooms.size():
			if i != dun.start_room:
				rooms_idx.append(i)
		rooms_idx.shuffle()
		var nchest := 2 + (1 if rng.randf() < 0.5 else 0)
		for i in mini(nchest, rooms_idx.size()):
			var c2: Vector2i = dun.random_cell_in(dun.rooms[rooms_idx[i]], used)
			used.append(c2)
			chests.append({"cell": c2, "pos": cell_center(c2), "opened": false, "good": false, "bounce": 0.0})
		# 回復薬
		var pr: Rect2i = dun.rooms[rooms_idx[rooms_idx.size() - 1]]
		var c3: Vector2i = dun.random_cell_in(pr, used)
		used.append(c3)
		pickups.append({"kind": "potion", "pos": cell_center(c3), "t": 0.0})
		# トゲ罠（地下2階から）: 床から周期的にトゲが出る。回避（ローリング）中は無敵で通り抜けられる
		if floor_num >= 2:
			rooms_idx.shuffle()
			var ngroups := mini(1 + floor_num, rooms_idx.size())
			for gi in ngroups:
				var rr: Rect2i = dun.rooms[rooms_idx[gi]]
				var base: Vector2i = dun.random_cell_in(rr, used)
				var horiz := rng.randf() < 0.5
				var ph := rng.randf() * TRAP_CYCLE
				for k in rng.randi_range(2, 4):
					var tc := base + (Vector2i(k, 0) if horiz else Vector2i(0, k))
					if not dun.is_floor(tc) or used.has(tc) or not rr.has_point(tc):
						break
					used.append(tc)
					traps.append({"cell": tc, "pos": cell_center(tc), "ph": ph + k * 0.12})
					if astar != null:
						astar.set_point_weight_scale(tc, 6.0)
	else:
		# ボス階: スタート部屋に良い宝箱と回復薬、ボス部屋にボス
		var sr: Rect2i = dun.rooms[0]
		var cc := Vector2i(sr.get_center().x - 3, sr.position.y + 2)
		chests.append({"cell": cc, "pos": cell_center(cc), "opened": false, "good": true, "bounce": 0.0})
		pickups.append({"kind": "potion", "pos": cell_center(Vector2i(sr.get_center().x + 3, sr.position.y + 2)), "t": 0.0})
		var b = Enemy.new()
		b.setup("boss", cell_center(Vector2i(dun.boss_room.get_center().x, dun.boss_room.position.y + 7)), floor_num)
		enemies.append(b)
		boss = b

func _pick_weighted(wt: Dictionary) -> String:
	var total := 0
	for k in wt:
		total += int(wt[k])
	var r := rng.randi_range(1, total)
	for k in wt:
		r -= int(wt[k])
		if r <= 0:
			return k
	return wt.keys()[0]

# ================= ステータス =================
func recalc() -> void:
	st = BASE.duplicate()
	var p := perks
	st["maxhp"] += 10.0 * p.get("maxhp", 0)
	st["atk"] += 2.0 * p.get("atk", 0)
	st["def"] += 2.0 * p.get("def", 0)
	st["spd"] += 0.10 * p.get("spd", 0)
	st["crit"] += 0.08 * p.get("crit", 0)
	st["aspd"] += 0.12 * p.get("aspd", 0)
	st["reach"] += 0.15 * p.get("reach", 0)
	st["regen"] += 0.4 * p.get("regen", 0)
	st["vamp"] += 2.0 * p.get("vamp", 0)
	st["roll"] += 1.0 * p.get("roll", 0)
	for slot in equip:
		var it: Dictionary = equip[slot]
		if it.is_empty():
			continue
		for k in it["stats"]:
			st[k] = st.get(k, 0.0) + float(it["stats"][k])
	if weak:
		st["maxhp"] = 1.0
		st["regen"] = 0.0
		st["vamp"] = 0.0
	php = minf(php, st["maxhp"])

func xp_need() -> int:
	return 8 + 9 * (level - 1)

func gain_xp(n: int) -> void:
	xp += n
	while xp >= xp_need():
		xp -= xp_need()
		level += 1
		pending_levelups += 1

func apply_perk(id: String) -> void:
	perks[id] = perks.get(id, 0) + 1
	recalc()
	match id:
		"maxhp":
			php = minf(php + 10.0, st["maxhp"])
		"potion":
			potions = mini(potions + 1, MAX_POTIONS)
			php = st["maxhp"]
	php = minf(php + st["maxhp"] * 0.2, st["maxhp"])

func equip_item(it: Dictionary) -> void:
	var old_max: float = st["maxhp"]
	equip[it["slot"]] = it
	recalc()
	if st["maxhp"] > old_max:
		php += st["maxhp"] - old_max

func reach() -> float:
	return 25.0 * (1.0 + st["reach"])

# ================= 地形ユーティリティ =================
func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * T + T * 0.5, c.y * T + T * 0.5)

func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T), floori(p.y / T))

func solid_cell(c: Vector2i) -> bool:
	return not dun.is_floor(c)

func solid_at(p: Vector2) -> bool:
	return solid_cell(to_cell(p))

func _box_solid(p: Vector2, r: float) -> bool:
	var n := int(ceil(r * 2.0 / 8.0))
	for iy in n + 1:
		for ix in n + 1:
			var q := Vector2(p.x - r + 2.0 * r * ix / n, p.y - r + 2.0 * r * iy / n)
			if solid_at(q):
				return true
	return false

## 軸ごとに移動して壁で止める。戻り値 [新しい位置, 壁に当たったか]
func move_body(pos: Vector2, d: Vector2, r: float) -> Array:
	var hit := false
	var steps := maxi(1, int(ceil(d.length() / 3.0)))
	var sd := d / steps
	for i in steps:
		var nx := pos + Vector2(sd.x, 0)
		if _box_solid(nx, r):
			hit = true
		else:
			pos = nx
		var ny := pos + Vector2(0, sd.y)
		if _box_solid(ny, r):
			hit = true
		else:
			pos = ny
	return [pos, hit]

func los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := int(d.length() / 5.0) + 1
	for i in range(1, n):
		if solid_at(a + d * (float(i) / n)):
			return false
	return true

## 体の幅を考慮した視線（突進が角に引っかからないように）
func los_wide(a: Vector2, b: Vector2, r: float) -> bool:
	var d := (b - a)
	if d.length() < 1.0:
		return true
	var nrm := Vector2(-d.y, d.x).normalized() * r * 0.8
	return los(a + nrm, b + nrm) and los(a - nrm, b - nrm)

func _update_flow() -> void:
	flow = dun.bfs(to_cell(ppos), 40)

func flow_dir(p: Vector2) -> Vector2:
	if flow.is_empty():
		return Vector2.ZERO
	var c := to_cell(p)
	var best := 1 << 30
	var cur: int = flow[dun.idx(c)] if dun.is_floor(c) else -1
	if cur < 0:
		return (ppos - p).normalized() * 0.3
	var bc := c
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var n: Vector2i = c + d
		if not dun.is_floor(n):
			continue
		if d.x != 0 and d.y != 0 and (not dun.is_floor(Vector2i(c.x + d.x, c.y)) or not dun.is_floor(Vector2i(c.x, c.y + d.y))):
			continue
		var v: int = flow[dun.idx(n)]
		if v >= 0 and v < best:
			best = v
			bc = n
	if bc == c:
		return (ppos - p).normalized()
	return (cell_center(bc) - p).normalized()

func random_floor_near(center: Vector2, rmin: float, rmax: float) -> Vector2:
	for i in 30:
		var p := center + Vector2.from_angle(randf() * TAU) * randf_range(rmin, rmax)
		if not _box_solid(p, 6.0) and los(p, center):
			return p
	return Vector2.INF

func clamp_to_floor(p: Vector2, r: float) -> Vector2:
	if not _box_solid(p, r):
		return p
	for k in range(1, 6):
		for i in 12:
			var q := p + Vector2.from_angle(TAU * i / 12.0) * k * 6.0
			if not _box_solid(q, r):
				return q
	return boss.pos if boss else p

# ================= メインループ =================
func step(dt: float) -> void:
	if dun == null:
		return
	_update_fx(dt)
	if hitstop > 0.0:
		hitstop -= dt
		return
	time += dt
	floor_time += dt
	fade = maxf(0.0, fade - dt * 2.0)
	if trans_t > 0.0:
		trans_t += dt
		if trans_t > 0.6:
			trans_t = 0.0
			start_floor(floor_num + 1)
		return
	_update_player(dt)
	_update_traps()
	flow_t -= dt
	if flow_t <= 0.0:
		flow_t = 0.25
		_update_flow()
	for e in enemies:
		if not e.dead:
			e.update(self, dt)
	_separate()
	_update_bullets(dt)
	_contact()
	_update_pickups(dt)
	_update_chests()
	_update_boss(dt)
	reveal_t -= dt
	if reveal_t <= 0.0:
		reveal_t = 0.12
		_reveal()
	if floor_num < FLOORS and dun.is_floor(dun.stairs_cell) and alive and ppos.distance_to(cell_center(dun.stairs_cell)) < 9.0 and trans_t == 0.0:
		trans_t = 0.001
		play("stairs", 0.0)
	enemies = enemies.filter(func(e): return not e.dead)

func _update_player(dt: float) -> void:
	roll_cd -= dt
	atk_cd -= dt
	iframes -= dt
	combo_t -= dt
	swing_t -= dt
	pflash -= dt
	atk_buffer -= dt
	if not alive:
		dead_t += dt
		if dead_t > 1.6 and not died_emitted:
			died_emitted = true
			died.emit()
		return
	if st["regen"] > 0.0 and php < st["maxhp"]:
		php = minf(st["maxhp"], php + st["regen"] * dt)
	if in_attack_pressed:
		atk_buffer = 0.25
	if in_potion:
		use_potion()
	var mvin := in_move.limit_length(1.0)
	if mvin.length() > 0.2 and swing_t <= 0.0 and roll_t <= 0.0:
		pface = mvin.normalized()
	if in_dodge and roll_cd <= 0.0 and roll_t <= 0.0:
		roll_dir = mvin.normalized() if mvin.length() > 0.2 else pface
		pface = roll_dir
		roll_t = 0.24
		stats_log["rolls"] = stats_log.get("rolls", 0) + 1
		roll_cd = maxf(0.25, 0.62 * pow(0.8, st["roll"]))
		iframes = maxf(iframes, 0.32)
		swing_t = 0.0
		play("roll")
		burst(ppos + Vector2(0, 4), Color(0.7, 0.65, 0.55, 0.8), 6, 40.0)
	var v := Vector2.ZERO
	if roll_t > 0.0:
		roll_t -= dt
		v = roll_dir * ROLL_SPEED
		after_t -= dt
		if after_t <= 0.0:
			after_t = 0.035
			afterimages.append({"pos": ppos, "life": 0.18, "flip": pface.x < 0})
	else:
		v = mvin * MOVE_SPEED * (1.0 + st["spd"])
		if swing_t > 0.0:
			v *= 0.45
		if (in_attack or atk_buffer > 0.0) and atk_cd <= 0.0:
			atk_buffer = 0.0
			_swing()
	var res: Array = move_body(ppos, (v + pknock) * dt, PLAYER_R)
	ppos = res[0]
	pknock = pknock.lerp(Vector2.ZERO, 1.0 - exp(-12.0 * dt))
	pvel_vis = v
	walk_anim += dt * v.length() / 14.0

func use_potion() -> void:
	if potions <= 0 or php >= st["maxhp"] or not alive:
		return
	potions -= 1
	stats_log["potions_used"] += 1
	var heal: float = st["maxhp"] * 0.5
	php = minf(st["maxhp"], php + heal)
	add_text(ppos + Vector2(0, -14), "+%d" % roundi(heal), Color(0.4, 1.0, 0.5), 1.2)
	burst(ppos, Color(0.4, 1.0, 0.5), 14, 50.0)
	play("potion", 0.0)

func _nearest_target(maxd: float):
	var best = null
	var bd := maxd
	for e in enemies:
		if e.dead or e.spawn_t > 0.0 or e.airborne():
			continue
		var d: float = ppos.distance_to(e.pos) - e.r
		if d < bd and los(ppos, e.pos):
			bd = d
			best = e
	return best

func _swing() -> void:
	stats_log["swings"] = stats_log.get("swings", 0) + 1
	var tgt = _nearest_target(reach() + 45.0)
	if tgt != null:
		pface = (tgt.pos - ppos).normalized()
	combo = combo + 1 if combo_t > 0.0 else 1
	if combo > 3:
		combo = 1
	combo_t = 0.8
	var fin := combo == 3
	var rr := reach() * (1.2 if fin else 1.0)
	var arc := deg_to_rad(160.0 if fin else 120.0)
	var ang := pface.angle()
	swing_t = 0.2
	atk_cd = 0.34 / (1.0 + st["aspd"]) * (1.3 if fin else 1.0)
	var lunge: Array = move_body(ppos, pface * (5.0 if fin else 2.5), PLAYER_R)
	ppos = lunge[0]
	slashes.append({"pos": ppos, "ang": ang, "arc": arc, "r": rr, "life": 0.17, "max": 0.17, "side": 1 if combo % 2 == 1 else -1, "fin": fin})
	play("swing_fin" if fin else "swing", 0.0)
	var hit_any := false
	for e in enemies:
		if e.dead or e.spawn_t > 0.0 or e.airborne():
			continue
		var d: Vector2 = e.pos - ppos
		var dl := d.length()
		if dl > rr + e.r:
			continue
		if dl > 9.0 and absf(angle_difference(ang, d.angle())) > arc * 0.5 + atan2(e.r, dl):
			continue
		var dmg: float = st["atk"] * randf_range(0.85, 1.15) * (1.6 if fin else 1.0)
		var crit: bool = randf() < st["crit"]
		if crit:
			dmg *= 1.8
		hit_enemy(e, dmg, d.normalized() if dl > 0.1 else pface, crit, 150.0 if fin else 90.0)
		hit_any = true
	# 弾を斬り落とす
	for b in bullets:
		var d2: Vector2 = b["pos"] - ppos
		if d2.length() < rr + 4.0 and absf(angle_difference(ang, d2.angle())) < arc * 0.5 + 0.2:
			b["life"] = 0.0
			burst(b["pos"], Color(1, 1, 0.7), 5, 60.0)
			play("parry")
	# 宝箱を叩いて開ける
	for c in chests:
		if not c["opened"] and ppos.distance_to(c["pos"]) < rr + 8.0:
			open_chest(c)
	if hit_any:
		hitstop = maxf(hitstop, 0.05 if fin else 0.035)

func hit_enemy(e, dmg: float, dir: Vector2, crit: bool, kb: float) -> void:
	if e.invuln > 0.0:
		add_text(e.pos + Vector2(0, -12), "無効", Color(0.7, 0.7, 0.8), 0.6)
		play("parry")
		return
	if e.type == "boss" and e.state == "sleep":
		return
	e.hp -= dmg
	e.flash = 0.12
	e.aggro = true
	var kbm := 0.15 if e.type == "boss" else (0.5 if e.type == "charger" and e.state == "charge" else 1.0)
	e.vel += dir * kb * kbm
	if e.type != "boss":
		e.stagger = 0.18
	add_text(e.pos + Vector2(randf_range(-4, 4), -10), str(roundi(dmg)) + ("!" if crit else ""), Color(1.0, 0.85, 0.2) if crit else Color(1, 1, 1), 1.3 if crit else 1.0)
	burst(e.pos, Color(1.0, 0.95, 0.8) if e.type in ["archer"] else (Color(0.4, 0.9, 0.4) if e.type == "slime" else Color(0.9, 0.25, 0.3)), 6, 70.0)
	add_shake(2.5 if crit else 1.5)
	play("hit_crit" if crit else "hit")
	if e.hp <= 0.0:
		_kill(e)

func _kill(e) -> void:
	e.dead = true
	kills += 1
	burst(e.pos, Color(0.9, 0.9, 0.95), 14, 90.0)
	burst(e.pos, Color(0.35, 0.3, 0.4), 10, 50.0)
	play("kill")
	if st["vamp"] > 0.0:
		php = minf(st["maxhp"], php + st["vamp"])
	if e.type == "boss":
		boss_dead_t = 0.0
		add_shake(10.0)
		hitstop = 0.25
		play("boss_die", 0.0)
		message.emit("深淵の魔王を倒した！", Color(1.0, 0.85, 0.3))
		for o in enemies:
			if o != e and not o.dead:
				o.dead = true
				burst(o.pos, Color(0.9, 0.9, 0.95), 10, 80.0)
		bullets.clear()
		return
	if e.elite:
		burst(e.pos, Color(1.0, 0.8, 0.3), 18, 110.0)
		pickups.append({"kind": "potion", "pos": e.pos, "t": 0.0})
		message.emit("強敵を倒した！", Color(1.0, 0.85, 0.3))
	if not e.minion:
		gain_xp(e.xp)
		var r := randf()
		if r < 0.06:
			pickups.append({"kind": "potion", "pos": e.pos, "t": 0.0})
		elif r < 0.22:
			pickups.append({"kind": "heart", "pos": e.pos, "t": 0.0})

## 罠の状態: 0=引っ込み 1=予兆 2=トゲが出ている
func trap_state(tr: Dictionary) -> int:
	var c := fmod(time + tr["ph"], TRAP_CYCLE)
	if c > 1.9:
		return 2
	if c > 1.45:
		return 1
	return 0

func _update_traps() -> void:
	if traps.is_empty() or not alive:
		return
	for tr in traps:
		if trap_state(tr) != 2:
			continue
		var d: Vector2 = (ppos - tr["pos"]).abs()
		if d.x < T * 0.5 - 2.0 and d.y < T * 0.5 - 2.0:
			hurt_player(5.0 * (1.0 + 0.3 * (floor_num - 1)), tr["pos"])
			break

func hurt_player(amount: float, src: Vector2) -> void:
	if not alive or iframes > 0.0 or trans_t > 0.0:
		return
	var red: float = st["def"] / (st["def"] + 15.0)
	var d := maxf(1.0, roundf(amount * (1.0 - red)))
	if god:
		d = 0.0
	php -= d
	stats_log["dmg_taken"] += d
	iframes = 0.75
	pflash = 0.15
	var dir := (ppos - src).normalized() if ppos.distance_to(src) > 0.1 else Vector2.DOWN
	pknock = dir * 160.0
	add_shake(5.0)
	hitstop = maxf(hitstop, 0.06)
	if d > 0.0:
		add_text(ppos + Vector2(0, -14), "-%d" % roundi(d), Color(1.0, 0.35, 0.35), 1.2)
	burst(ppos, Color(0.9, 0.2, 0.25), 8, 70.0)
	play("hurt", 0.0)
	if php <= 0.0:
		php = 0.0
		alive = false
		dead_t = 0.0
		add_shake(8.0)
		burst(ppos, Color(0.9, 0.2, 0.25), 24, 100.0)
		play("die", 0.0)

func on_enemy_alert(e) -> void:
	add_text(e.pos + Vector2(0, -14), "!", Color(1.0, 0.8, 0.3), 0.9)
	# 近くの仲間も気づく
	for o in enemies:
		if not o.aggro and o.pos.distance_to(e.pos) < 60.0:
			o.aggro = true

func on_boss_phase2(_b) -> void:
	add_shake(9.0)
	play("roar", 0.0)
	message.emit("魔王が怒り狂った！", Color(1.0, 0.35, 0.3))
	bullets.clear()

func minion_count() -> int:
	var n := 0
	for e in enemies:
		if e.minion and not e.dead:
			n += 1
	return n

func spawn_minion(kind: String, p: Vector2) -> void:
	var e = Enemy.new()
	e.setup(kind, clamp_to_floor(p, 6.0), 3)
	e.minion = true
	e.aggro = true
	e.spawn_t = 0.5
	enemies.append(e)
	burst(e.pos, Color(0.6, 0.3, 0.9), 10, 50.0)

func spawn_bullet(p: Vector2, v: Vector2, dmg: float, col: Color, r := 3.5, homing := 0.0, kind := "orb") -> void:
	bullets.append({"pos": p, "vel": v, "dmg": dmg, "col": col, "r": r, "homing": homing, "life": 4.0, "kind": kind})

func shockwave(p: Vector2, radius: float, dmg: float) -> void:
	waves.append({"pos": p, "r": 0.0, "max": radius * 1.6, "life": 0.35})
	if ppos.distance_to(p) < radius:
		hurt_player(dmg, p)

func _update_bullets(dt: float) -> void:
	for b in bullets:
		if b["homing"] > 0.0:
			var want: Vector2 = (ppos - b["pos"]).normalized() * b["vel"].length()
			b["vel"] = b["vel"].lerp(want, b["homing"] * dt)
		b["pos"] += b["vel"] * dt
		b["life"] -= dt
		if solid_at(b["pos"]):
			b["life"] = 0.0
			burst(b["pos"], b["col"], 4, 40.0)
		elif alive and b["pos"].distance_to(ppos) < b["r"] + PLAYER_R - 1.0:
			if iframes <= 0.0:
				hurt_player(b["dmg"], b["pos"] - b["vel"].normalized() * 4.0)
				b["life"] = 0.0
	bullets = bullets.filter(func(b): return b["life"] > 0.0)

func _separate() -> void:
	var n := enemies.size()
	for i in n:
		var a = enemies[i]
		if a.dead:
			continue
		for j in range(i + 1, n):
			var b = enemies[j]
			if b.dead:
				continue
			var d: Vector2 = b.pos - a.pos
			var md: float = a.r + b.r
			var dl := d.length()
			if dl < md and dl > 0.01:
				var push := d / dl * (md - dl) * 0.5
				var wa := 0.1 if a.type == "boss" else 1.0
				var wb := 0.1 if b.type == "boss" else 1.0
				a.pos = move_body(a.pos, -push * wa, a.r)[0]
				b.pos = move_body(b.pos, push * wb, b.r)[0]

func _contact() -> void:
	if not alive:
		return
	for e in enemies:
		if e.dead or e.spawn_t > 0.0 or e.airborne() or (e.type == "boss" and e.state == "sleep"):
			continue
		if e.pos.distance_to(ppos) < e.r + PLAYER_R - 1.0:
			if e.type == "charger" and e.state == "stun":
				continue
			hurt_player(e.contact_damage(), e.pos)
			if e.type == "bat":
				e.vel -= (ppos - e.pos).normalized() * 120.0

func _update_pickups(dt: float) -> void:
	for p in pickups:
		p["t"] += dt
		var d: float = p["pos"].distance_to(ppos)
		if d < 30.0 and p["t"] > 0.4:
			p["pos"] = p["pos"].move_toward(ppos, 120.0 * dt)
		if d < 8.0 and p["t"] > 0.4:
			match p["kind"]:
				"potion":
					if potions < MAX_POTIONS:
						potions += 1
						p["taken"] = true
						add_text(ppos + Vector2(0, -14), "回復薬 +1", Color(1.0, 0.5, 0.5), 1.0)
						play("pickup")
				"heart":
					var heal: float = 4.0 + st["maxhp"] * 0.08
					php = minf(st["maxhp"], php + heal)
					p["taken"] = true
					add_text(ppos + Vector2(0, -14), "+%d" % roundi(heal), Color(0.4, 1.0, 0.5), 1.0)
					play("pickup")
	pickups = pickups.filter(func(p): return not p.get("taken", false))

func _update_chests() -> void:
	for c in chests:
		if not c["opened"] and ppos.distance_to(c["pos"]) < 13.0:
			open_chest(c)

func open_chest(c: Dictionary) -> void:
	if c["opened"]:
		return
	c["opened"] = true
	c["bounce"] = 0.3
	stats_log["chests"] += 1
	play("chest", 0.0)
	burst(c["pos"], Color(1.0, 0.85, 0.3), 16, 70.0)
	add_shake(2.0)
	if c["good"] or rng.randf() < 0.75:
		var it: Dictionary = Items.make_item(rng, floor_num)
		if c["good"]:
			for i in 10:
				if it["rarity"] >= 1:
					break
				it = Items.make_item(rng, floor_num)
		pending_item = it
	else:
		for i in 2:
			pickups.append({"kind": "potion" if i == 0 else "heart", "pos": c["pos"] + Vector2(i * 8 - 4, 10), "t": 0.0})
		add_text(c["pos"] + Vector2(0, -14), "回復アイテム！", Color(1.0, 0.6, 0.6), 1.2)

func _update_boss(dt: float) -> void:
	if boss == null:
		return
	if not boss_active and dun.boss_room.grow(-1).has_point(to_cell(ppos)) and ppos.y < (dun.boss_room.end.y - 2) * T:
		boss_active = true
		boss.aggro = true
		boss.state = "intro"
		boss.t = 0.0
		boss.invuln = 1.6
		light_r = 260.0
		# 退路を塞ぐ
		for gc in dun.gate_cells:
			dun.grid[dun.idx(gc)] = 0
			astar.set_point_solid(gc, true)
		map_tex = ImageTexture.create_from_image(Art.build_map_image(dun.grid, dun.w, dun.h, floor_num - 1, run_seed * 7919 + floor_num * 104729))
		add_shake(6.0)
		play("roar", 0.0)
		message.emit("深淵の魔王が現れた！", Color(1.0, 0.35, 0.3))
	if boss_dead_t >= 0.0:
		boss_dead_t += dt
		if fmod(boss_dead_t, 0.15) < dt and boss_dead_t < 1.5:
			burst(boss.pos + Vector2(randf_range(-14, 14), randf_range(-14, 14)), Color(1.0, 0.6, 0.3), 10, 90.0)
			play("kill")
		if boss_dead_t > 2.6 and not won_emitted:
			won_emitted = true
			won.emit()

func _reveal() -> void:
	var pc := to_cell(ppos)
	var rad := 6
	var changed := false
	for y in range(pc.y - rad, pc.y + rad + 1):
		for x in range(pc.x - rad, pc.x + rad + 1):
			if x < 0 or y < 0 or x >= dun.w or y >= dun.h:
				continue
			if (x - pc.x) * (x - pc.x) + (y - pc.y) * (y - pc.y) > rad * rad:
				continue
			var i: int = y * dun.w + x
			if explored[i] == 0:
				explored[i] = 1
				changed = true
	for r in dun.rooms:
		var rr: Rect2i = (r as Rect2i).grow(1)
		if rr.has_point(pc):
			for y in range(rr.position.y, rr.end.y):
				for x in range(rr.position.x, rr.end.x):
					var i2: int = y * dun.w + x
					if explored[i2] == 0:
						explored[i2] = 1
						changed = true
	if changed:
		minimap_dirty = true

func get_minimap() -> Texture2D:
	if minimap_dirty and minimap_img:
		minimap_dirty = false
		for y in dun.h:
			for x in dun.w:
				var i: int = y * dun.w + x
				var c := Color(0, 0, 0, 0)
				if explored[i] == 1:
					c = Color(0.62, 0.62, 0.7, 0.85) if dun.grid[i] == 1 else Color(0.22, 0.22, 0.28, 0.85)
				minimap_img.set_pixel(x, y, c)
		minimap_tex.update(minimap_img)
	return minimap_tex

func is_explored(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < dun.w and c.y < dun.h and explored[c.y * dun.w + c.x] == 1

# ================= エフェクト =================
func add_shake(a: float) -> void:
	shake = maxf(shake, a)

func burst(p: Vector2, col: Color, n: int, spd: float) -> void:
	for i in n:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * spd
		particles.append({"pos": p, "vel": v, "life": randf_range(0.25, 0.55), "max": 0.55, "col": col, "size": randf_range(1.0, 2.5)})
	if particles.size() > 500:
		particles = particles.slice(particles.size() - 500)

func add_text(p: Vector2, s: String, col: Color, scale := 1.0) -> void:
	texts.append({"pos": p, "text": s, "col": col, "life": 0.8, "max": 0.8, "scale": scale})

func _update_fx(dt: float) -> void:
	for p in particles:
		p["pos"] += p["vel"] * dt
		p["vel"] *= exp(-5.0 * dt)
		p["life"] -= dt
	particles = particles.filter(func(p): return p["life"] > 0.0)
	for t in texts:
		t["pos"].y -= 22.0 * dt
		t["life"] -= dt
	texts = texts.filter(func(t): return t["life"] > 0.0)
	for s in slashes:
		s["life"] -= dt
	slashes = slashes.filter(func(s): return s["life"] > 0.0)
	for a in afterimages:
		a["life"] -= dt
	afterimages = afterimages.filter(func(a): return a["life"] > 0.0)
	for w in waves:
		w["life"] -= dt
		w["r"] = w["max"] * (1.0 - w["life"] / 0.35)
	waves = waves.filter(func(w): return w["life"] > 0.0)
	for c in chests:
		c["bounce"] = maxf(0.0, c["bounce"] - dt)
	shake = maxf(0.0, shake - dt * 18.0)

func _process(delta: float) -> void:
	if dun == null:
		return
	var look := pface * 10.0 if alive else Vector2.ZERO
	cam_pos = cam_pos.lerp(ppos + look, 1.0 - exp(-7.0 * delta))
	var so := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	camera.position = cam_pos + so
	queue_redraw()

# ================= 描画 =================
func _spr(name: String, p: Vector2, flip := false, flash := false, mod := Color.WHITE, scale := 1.0) -> void:
	var tx: Texture2D = Art.white(name) if flash else Art.tex(name)
	var sz := tx.get_size() * scale
	draw_set_transform(p, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	draw_texture_rect(tx, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false, mod)
	draw_set_transform(Vector2.ZERO)

func _shadow(p: Vector2, w: float) -> void:
	draw_set_transform(p, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, w, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)

func view_rect() -> Rect2:
	var vs := get_viewport_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - vs * 0.5, vs).grow(24.0)

func _draw() -> void:
	if dun == null or map_tex == null:
		return
	var vr := view_rect()
	draw_texture(map_tex, Vector2.ZERO)
	# 階段
	if floor_num < FLOORS:
		var sp := cell_center(dun.stairs_cell)
		var r := Rect2(sp - Vector2(8, 8), Vector2(16, 16))
		draw_rect(r.grow(1), Color(0.05, 0.04, 0.06))
		for i in 4:
			draw_rect(Rect2(r.position + Vector2(0, i * 4), Vector2(16, 4)), Color(0.55, 0.52, 0.5).darkened(i * 0.22))
			draw_rect(Rect2(r.position + Vector2(0, i * 4 + 3), Vector2(16, 1)), Color(0.1, 0.1, 0.12))
		var gl := 0.5 + 0.5 * sin(time * 3.0)
		draw_rect(r.grow(2 + gl * 2), Color(0.4, 1.0, 0.6, 0.25 + gl * 0.25), false, 1.0)
	# トゲ罠
	for tr in traps:
		if not vr.has_point(tr["pos"]):
			continue
		var tp: Vector2 = tr["pos"] - Vector2(7, 7)
		draw_rect(Rect2(tp, Vector2(14, 14)), Color(0.12, 0.1, 0.13))
		draw_rect(Rect2(tp, Vector2(14, 14)), Color(0.3, 0.27, 0.3), false, 1.0)
		var ts := trap_state(tr)
		for iy in 3:
			for ix in 3:
				var hp2: Vector2 = tp + Vector2(2.5 + ix * 4.5, 3.0 + iy * 4.5)
				if ts == 0:
					draw_rect(Rect2(hp2 - Vector2(1, 0), Vector2(2, 1.5)), Color(0.03, 0.03, 0.04))
				else:
					var hgt := 2.0 if ts == 1 else 5.0
					var col := Color(0.6, 0.6, 0.65) if ts == 1 else Color(0.9, 0.9, 0.95)
					draw_colored_polygon(PackedVector2Array([hp2 + Vector2(-1.5, 1.5), hp2 + Vector2(1.5, 1.5), hp2 + Vector2(0, 1.5 - hgt)]), col)
		if ts == 2:
			draw_rect(Rect2(tp, Vector2(14, 14)), Color(1.0, 0.3, 0.25, 0.18))
	# 予告線など
	for e in enemies:
		if e.dead or not vr.has_point(e.pos):
			continue
		if e.type == "archer" and e.state == "aim":
			var a := clampf(e.t / 0.55, 0.0, 1.0)
			draw_line(e.pos, e.pos + e.aim * 170.0, Color(1, 0.3, 0.2, 0.15 + 0.4 * a), 1.0)
		elif e.type == "charger" and e.state == "windup":
			var a2 := clampf(e.t / 0.65, 0.0, 1.0)
			draw_line(e.pos, e.pos + e.aim * 150.0, Color(1, 0.25, 0.2, 0.2 + 0.4 * a2), e.r * 2.0 * a2)
		elif e.type == "boss":
			if e.state == "charge_wind":
				var a3 := clampf(e.t / 0.8, 0.0, 1.0)
				draw_line(e.pos, e.pos + e.aim * 260.0, Color(1, 0.2, 0.2, 0.15 + 0.35 * a3), e.r * 2.0)
			elif e.airborne():
				var k := clampf(e.t / 0.9, 0.0, 1.0) if e.state == "slam_up" else 1.0
				draw_circle(e.target, 38.0 * k, Color(1, 0.15, 0.1, 0.18 + 0.15 * k))
				draw_arc(e.target, 38.0, 0, TAU, 40, Color(1, 0.3, 0.2, 0.6 * k), 1.5)
	# y順に描画するもの
	var items: Array = []
	for c in chests:
		items.append([c["pos"].y, 0, c])
	for p in pickups:
		items.append([p["pos"].y, 1, p])
	for e in enemies:
		if not e.dead and vr.has_point(e.pos):
			items.append([e.pos.y, 2, e])
	items.append([ppos.y, 3, null])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for a in afterimages:
		_spr("player", a["pos"] + Vector2(0, 6), a["flip"], false, Color(0.5, 0.7, 1.0, a["life"] / 0.18 * 0.5))
	for it in items:
		match it[1]:
			0: _draw_chest(it[2])
			1: _draw_pickup(it[2])
			2: _draw_enemy(it[2])
			3: _draw_player()
	# 斬撃
	for s in slashes:
		_draw_slash(s)
	for w in waves:
		draw_arc(w["pos"], w["r"], 0, TAU, 40, Color(1, 0.7, 0.5, w["life"] / 0.35), 3.0)
	# 弾
	for b in bullets:
		if b["kind"] == "arrow":
			var dn: Vector2 = b["vel"].normalized()
			draw_line(b["pos"] - dn * 6.0, b["pos"] + dn * 2.0, Color(0.6, 0.45, 0.3), 1.5)
			draw_line(b["pos"], b["pos"] + dn * 2.5, Color(0.95, 0.95, 0.95), 2.0)
		else:
			draw_circle(b["pos"], b["r"] + 1.5, Color(b["col"], 0.35))
			draw_circle(b["pos"], b["r"], b["col"])
			draw_circle(b["pos"], b["r"] * 0.45, Color(1, 1, 1, 0.9))
	for p in particles:
		var a4: float = clampf(p["life"] / 0.35, 0.0, 1.0)
		var sz: float = p["size"]
		draw_rect(Rect2(p["pos"] - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(p["col"], a4 * p["col"].a))
	# 暗闇（プレイヤー周りだけ明るい）
	var lt := Art.light_tex()
	var lr := light_r + sin(time * 2.0) * 3.0
	var lrect := Rect2(ppos - Vector2(lr, lr), Vector2(lr, lr) * 2.0)
	var dk := Color(1, 1, 1, 0.86)
	draw_texture_rect(lt, lrect, false, dk)
	var big := vr.grow(200.0)
	var dc := Color(0, 0, 0, 0.86)
	draw_rect(Rect2(big.position.x, big.position.y, big.size.x, lrect.position.y - big.position.y), dc)
	draw_rect(Rect2(big.position.x, lrect.end.y, big.size.x, big.end.y - lrect.end.y), dc)
	draw_rect(Rect2(big.position.x, lrect.position.y, lrect.position.x - big.position.x, lrect.size.y), dc)
	draw_rect(Rect2(lrect.end.x, lrect.position.y, big.end.x - lrect.end.x, lrect.size.y), dc)
	# 階段の位置はうっすら見える（探索済みなら）
	if floor_num < FLOORS and is_explored(dun.stairs_cell):
		var sp2 := cell_center(dun.stairs_cell)
		if sp2.distance_to(ppos) > lr * 0.7:
			draw_arc(sp2, 9.0 + sin(time * 3.0) * 1.5, 0, TAU, 24, Color(0.4, 1.0, 0.6, 0.6), 1.2)

func _draw_player() -> void:
	if hide_player:
		return
	if not alive:
		var k := clampf(dead_t / 0.8, 0.0, 1.0)
		_shadow(ppos + Vector2(0, 4), 5.0)
		draw_set_transform(ppos + Vector2(0, 4), k * PI * 0.5, Vector2.ONE)
		draw_texture(Art.tex("player"), Vector2(-8, -16), Color(1, 0.5, 0.5, 1.0 - k * 0.3))
		draw_set_transform(Vector2.ZERO)
		return
	_shadow(ppos + Vector2(0, 4), 5.5)
	var blink := iframes > 0.0 and roll_t <= 0.0 and fmod(time, 0.12) < 0.06
	var bob := absf(sin(walk_anim)) * 1.5 if pvel_vis.length() > 5.0 else 0.0
	var flip := pface.x < -0.1
	var p := ppos + Vector2(0, 6 - bob)
	if roll_t > 0.0:
		# 回転して転がる
		var k2 := 1.0 - roll_t / 0.24
		draw_set_transform(ppos + Vector2(0, 0), (k2 * TAU) * (-1.0 if flip else 1.0), Vector2(0.9, 0.9))
		draw_texture(Art.tex("player"), Vector2(-8, -8), Color(0.85, 0.95, 1.0))
		draw_set_transform(Vector2.ZERO)
		return
	# 剣（構え）
	if swing_t <= 0.0:
		var hand := ppos + Vector2(4.0 * (-1.0 if flip else 1.0), 1.0)
		_draw_sword(hand, pface.angle() * 0.3 + (PI * 0.75 if flip else PI * 0.25) - PI * 0.5, 0.8)
	if not blink:
		_spr("player", p, flip, pflash > 0.0)
	if swing_t > 0.0:
		var s: Dictionary = slashes[-1] if slashes.size() > 0 else {}
		if not s.is_empty():
			var k3: float = 1.0 - s["life"] / s["max"]
			var a: float = s["ang"] + s["side"] * (-s["arc"] * 0.5 + s["arc"] * k3)
			_draw_sword(ppos, a, 1.0)

func _draw_sword(base: Vector2, ang: float, scale: float) -> void:
	var tip := base + Vector2.from_angle(ang) * (14.0 + reach() * 0.15) * scale
	var nrm := Vector2.from_angle(ang + PI * 0.5)
	draw_line(base, tip, Color(0.07, 0.06, 0.09), 3.5)
	draw_line(base, tip, Color(0.85, 0.88, 0.95), 2.0)
	draw_line(base + nrm * 3.0, base - nrm * 3.0, Color(1.0, 0.8, 0.3), 2.0)

func _draw_slash(s: Dictionary) -> void:
	var k: float = 1.0 - s["life"] / s["max"]
	var a0: float = s["ang"] - s["arc"] * 0.5
	var a1: float = s["ang"] + s["arc"] * 0.5
	var n := 16
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var rr: float = s["r"]
	var inner := rr * 0.45
	var col := Color(1.0, 0.95, 0.7) if s["fin"] else Color(0.85, 0.95, 1.0)
	var alpha := (1.0 - k) * 0.85
	for i in n + 1:
		var t := float(i) / n
		if s["side"] < 0:
			t = 1.0 - t
		var a := lerpf(a0, a1, t)
		var vis := clampf((k * 1.8 - (1.0 - t) * 0.8), 0.0, 1.0)
		pts.append(s["pos"] + Vector2.from_angle(a) * rr)
		cols.append(Color(col, alpha * vis))
	for i in range(n, -1, -1):
		var t2 := float(i) / n
		if s["side"] < 0:
			t2 = 1.0 - t2
		var a2 := lerpf(a0, a1, t2)
		pts.append(s["pos"] + Vector2.from_angle(a2) * inner)
		cols.append(Color(col, 0.0))
	draw_polygon(pts, cols)
	var arc_pts := PackedVector2Array()
	for i in n + 1:
		arc_pts.append(s["pos"] + Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * rr)
	draw_polyline(arc_pts, Color(1, 1, 1, alpha * 0.9), 1.5)

func _draw_enemy(e) -> void:
	var p: Vector2 = e.pos
	var flip: bool = e.face < 0.0
	var mod := Color.WHITE
	var sc := 1.0
	if e.spawn_t > 0.0:
		mod.a = 1.0 - e.spawn_t / 0.5
	if e.elite:
		sc = 1.3
		var pr := 0.5 + 0.5 * sin(e.anim * 5.0)
		draw_set_transform(p + Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 11.0 + pr * 2.0, Color(1.0, 0.75, 0.2, 0.22 + 0.15 * pr))
		draw_arc(Vector2.ZERO, 11.0 + pr * 2.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.35, 0.7), 1.0)
		draw_set_transform(Vector2.ZERO)
		mod = mod * Color(1.0, 0.92, 0.75)
	match e.type:
		"slime":
			var cyc := fmod(e.anim, 0.9)
			var hop := sin(clampf(cyc / 0.45, 0.0, 1.0) * PI) * 4.0 if e.aggro else 0.0
			_shadow(p + Vector2(0, 4), 6.0)
			var sq := 1.0 + sin(e.anim * 6.0) * 0.06
			draw_set_transform(p + Vector2(0, 5 - hop), 0.0, Vector2((1.0 / sq) * (-1.0 if flip else 1.0), sq) * sc)
			draw_texture(Art.white("slime") if e.flash > 0.0 else Art.tex("slime"), Vector2(-8, -16), mod)
			draw_set_transform(Vector2.ZERO)
			return
		"bat":
			var fl := sin(e.anim * 18.0) * 2.0
			_shadow(p + Vector2(0, 8), 4.0)
			draw_set_transform(p + Vector2(0, 2 + fl), 0.0, Vector2(-1.0 if flip else 1.0, 1.0 - absf(fl) * 0.08))
			draw_texture(Art.white("bat") if e.flash > 0.0 else Art.tex("bat"), Vector2(-8, -12), mod)
			draw_set_transform(Vector2.ZERO)
			return
		"boss":
			_draw_boss(e)
			return
	_shadow(p + Vector2(0, 4), e.r + 1.0)
	var off := Vector2.ZERO
	if e.type == "charger" and e.state == "windup":
		off.x = sin(e.t * 60.0) * 1.2
		mod = Color(1.0, 0.7, 0.7)
	if e.type == "charger" and e.state == "stun":
		for i in 3:
			var a: float = e.anim * 5.0 + TAU * i / 3.0
			draw_circle(p + Vector2(cos(a) * 6.0, -14 + sin(a) * 2.0), 1.2, Color(1, 1, 0.5))
	if (e.type == "mage" and (e.state == "aim" or e.state == "teleport")):
		draw_circle(p + Vector2(0, -4), 8.0 + sin(e.t * 20.0) * 1.5, Color(0.7, 0.3, 1.0, 0.3))
	var bob: float = absf(sin(e.anim * 8.0)) * 1.0 if e.mv.length() > 5.0 else 0.0
	_spr(e.tex, p + Vector2(0, 5 - bob) + off, flip, e.flash > 0.0, mod, sc)
	if (e.hp < e.maxhp or e.elite) and e.type != "boss":
		var w := 18.0 if e.elite else 12.0
		var hy := -20.0 if e.elite else -15.0
		draw_rect(Rect2(p + Vector2(-w * 0.5, hy), Vector2(w, 2)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(p + Vector2(-w * 0.5, hy), Vector2(w * e.hp / e.maxhp, 2)), Color(1.0, 0.75, 0.2) if e.elite else Color(0.95, 0.3, 0.3))

func _draw_boss(e) -> void:
	var p: Vector2 = e.pos
	if e.state == "sleep":
		_shadow(p + Vector2(0, 8), 12.0)
		_spr("boss", p + Vector2(0, 10), false, false, Color(0.55, 0.5, 0.6), 1.0)
		return
	var lift := 0.0
	var dp := p
	if e.state == "slam_up":
		lift = clampf(e.t / 0.4, 0.0, 1.0) * 220.0
		_shadow(e.target + Vector2(0, 8), 12.0 * clampf(e.t / 0.9, 0.2, 1.0))
	elif e.state == "slam_down":
		dp = e.target
		lift = (1.0 - clampf(e.t / 0.45, 0.0, 1.0)) * 220.0
		_shadow(dp + Vector2(0, 8), 12.0)
	else:
		_shadow(p + Vector2(0, 8), 13.0)
	var mod := Color.WHITE
	if e.phase == 2:
		mod = Color(1.0, 0.8, 0.8)
		draw_circle(dp + Vector2(0, -6 - lift), 18.0 + sin(time * 8.0) * 2.0, Color(1.0, 0.2, 0.2, 0.15))
	if e.state in ["ring", "summon", "spiral"] and e.t < 0.7:
		draw_circle(dp + Vector2(0, -6), 20.0 * e.t / 0.7, Color(1.0, 0.4, 0.8, 0.25))
	var shake_x: float = sin(e.t * 50.0) * 1.5 if e.state in ["charge_wind", "enrage", "intro"] else 0.0
	var breathe := 1.0 + sin(e.anim * 3.0) * 0.03
	draw_set_transform(dp + Vector2(shake_x, 10 - lift), 0.0, Vector2(-breathe if e.face < 0 else breathe, 1.0 / breathe))
	var tx: Texture2D = Art.white("boss") if (e.flash > 0.0 or (e.invuln > 0.0 and fmod(time, 0.2) < 0.1 and e.state == "enrage")) else Art.tex("boss")
	draw_texture_rect(tx, Rect2(-12, -24, 24, 24), false, mod)
	draw_set_transform(Vector2.ZERO)

func _draw_chest(c: Dictionary) -> void:
	var p: Vector2 = c["pos"]
	_shadow(p + Vector2(0, 5), 7.0)
	var b: float = sin(c["bounce"] / 0.3 * PI) * 3.0
	if not c["opened"]:
		var gl := 0.5 + 0.5 * sin(time * 4.0 + p.x)
		draw_circle(p, 10.0, Color(1.0, 0.85, 0.3, 0.08 + gl * 0.08))
	_spr("chest_open" if c["opened"] else "chest", p + Vector2(0, 6 - b))

func _draw_pickup(pk: Dictionary) -> void:
	var p: Vector2 = pk["pos"]
	var f := sin(time * 4.0 + p.x) * 1.5
	_shadow(p + Vector2(0, 4), 3.5)
	_spr("potion" if pk["kind"] == "potion" else "heart", p + Vector2(0, 5 + f), false, false, Color.WHITE, 0.8)
