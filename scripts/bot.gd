extends RefCounted
## 自動テスト用のオートプレイBOT（-- --autoplay）。
## 敵と戦い、宝箱を開け、階段へ向かい、ボスと戦う。

var path: PackedVector2Array = PackedVector2Array()
var path_t := 0.0
var goal := Vector2.INF
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var jiggle_t := 0.0
var jiggle := Vector2.ZERO
var mode := ""

func think(g, dt: float) -> void:
	g.in_move = Vector2.ZERO
	g.in_attack = false
	g.in_attack_pressed = false
	g.in_dodge = false
	g.in_potion = false
	if not g.alive or g.trans_t > 0.0:
		return
	var p: Vector2 = g.ppos
	# 回復
	if g.php < g.st["maxhp"] * 0.35 and g.potions > 0:
		g.in_potion = true
	# 危険回避
	var danger := Vector2.ZERO
	for b in g.bullets:
		var d: Vector2 = p - b["pos"]
		if d.length() < 42.0 and b["vel"].normalized().dot(d.normalized()) > 0.75:
			danger += Vector2(-b["vel"].y, b["vel"].x).normalized() * signf(Vector2(-b["vel"].y, b["vel"].x).dot(d) + 0.01)
	for e in g.enemies:
		if e.dead:
			continue
		var d2: Vector2 = p - e.pos
		if e.type == "charger" and e.state == "charge" and d2.length() < 70.0:
			danger += Vector2(-e.aim.y, e.aim.x) * signf(Vector2(-e.aim.y, e.aim.x).dot(d2) + 0.01)
		if e.type == "boss":
			if e.state == "charge" and d2.length() < 90.0:
				danger += Vector2(-e.aim.y, e.aim.x) * signf(Vector2(-e.aim.y, e.aim.x).dot(d2) + 0.01)
			if e.state == "slam_down" and p.distance_to(e.target) < 45.0:
				danger += (p - e.target).normalized()
	if danger != Vector2.ZERO and g.roll_cd <= 0.0:
		g.in_move = danger.normalized()
		g.in_dodge = true
		return
	# 目標を決める
	var tgt = null
	var td := INF
	for e in g.enemies:
		if e.dead or e.spawn_t > 0.0 or e.airborne():
			continue
		if e.type == "boss" and not g.boss_active:
			continue
		var d3: float = p.distance_to(e.pos)
		var near: bool = (e.aggro and d3 < 160.0) or d3 < 90.0
		if near and d3 < td and g.los(p, e.pos):
			td = d3
			tgt = e
	if tgt != null:
		mode = "fight"
		var rr: float = g.reach() * 0.8 + tgt.r
		if td > rr:
			g.in_move = (tgt.pos - p).normalized()
		else:
			g.in_attack = true
			g.in_attack_pressed = true
			# 遠距離の敵には貼り付き、ボスには少し動きながら
			if tgt.type == "boss":
				g.in_move = Vector2(-(tgt.pos - p).y, (tgt.pos - p).x).normalized() * 0.4
		_unstick(g, dt)
		return
	var dest := Vector2.INF
	for c in g.chests:
		if not c["opened"]:
			var dc: float = p.distance_to(c["pos"])
			if dest == Vector2.INF or dc < p.distance_to(dest):
				dest = c["pos"]
	if dest != Vector2.INF:
		mode = "chest"
	if dest == Vector2.INF and g.floor_num < g.FLOORS and g.floor_time < 75.0:
		for e in g.enemies:
			if not e.dead and (dest == Vector2.INF or p.distance_to(e.pos) < p.distance_to(dest)):
				dest = e.pos
				mode = "hunt"
	if dest == Vector2.INF:
		for pk in g.pickups:
			if pk["kind"] == "potion" and g.potions < g.MAX_POTIONS:
				dest = pk["pos"]
				mode = "pickup"
				break
	if dest == Vector2.INF:
		if g.floor_num < g.FLOORS:
			dest = g.cell_center(g.dun.stairs_cell)
			mode = "stairs"
		elif g.boss and not g.boss.dead:
			dest = g.boss.pos
			mode = "boss"
	if dest == Vector2.INF:
		return
	path_t -= dt
	if path_t <= 0.0 or goal.distance_to(dest) > 16.0:
		path_t = 0.3
		goal = dest
		path = g.astar.get_point_path(g.to_cell(p), g.to_cell(dest))
	while path.size() > 1 and (path[0] + Vector2(8, 8)).distance_to(p) < 6.0:
		path.remove_at(0)
	if path.size() > 1:
		var wp: Vector2 = path[1] + Vector2(8, 8) if (path[0] + Vector2(8, 8)).distance_to(p) < 12.0 else path[0] + Vector2(8, 8)
		g.in_move = (wp - p).normalized()
	else:
		g.in_move = (dest - p).normalized()
	_unstick(g, dt)

func _unstick(g, dt: float) -> void:
	if jiggle_t > 0.0:
		jiggle_t -= dt
		g.in_move = jiggle
		return
	stuck_t += dt
	if stuck_t > 0.8:
		if g.ppos.distance_to(last_pos) < 3.0 and g.in_move != Vector2.ZERO and not g.in_attack:
			jiggle = Vector2.from_angle(randf() * TAU)
			jiggle_t = 0.3
			path_t = 0.0
		stuck_t = 0.0
		last_pos = g.ppos
