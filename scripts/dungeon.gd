extends RefCounted
## ダンジョン自動生成: 部屋 + 通路（最小全域木 + ループ）。最終階はボス部屋。

const W := 60
const H := 46

var w := W
var h := H
var grid := PackedByteArray()   # 0=壁 1=床
var rooms: Array = []           # Array[Rect2i]
var start_room := 0
var stairs_room := -1
var start_cell := Vector2i.ZERO
var stairs_cell := Vector2i(-1, -1)
var boss_room := Rect2i()
var gate_cells: Array = []
var is_boss := false
var rng := RandomNumberGenerator.new()

func idx(c: Vector2i) -> int:
	return c.y * w + c.x

func is_floor(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and grid[c.y * w + c.x] == 1

func _carve(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x > 0 and y > 0 and x < w - 1 and y < h - 1:
				grid[y * w + x] = 1

func _corridor(a: Vector2i, b: Vector2i) -> void:
	# 幅2のL字通路
	var horiz_first := rng.randf() < 0.5
	var corner := Vector2i(b.x, a.y) if horiz_first else Vector2i(a.x, b.y)
	_seg(a, corner)
	_seg(corner, b)

func _seg(a: Vector2i, b: Vector2i) -> void:
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	_carve(Rect2i(x0, y0, x1 - x0 + 2, y1 - y0 + 2))

func generate(seed: int, floor_num: int, boss: bool) -> void:
	rng.seed = seed
	is_boss = boss
	grid = PackedByteArray()
	grid.resize(w * h)
	grid.fill(0)
	rooms.clear()
	gate_cells.clear()
	if boss:
		_gen_boss()
	else:
		_gen_rooms(floor_num)

func _gen_rooms(floor_num: int) -> void:
	var target := mini(7 + floor_num, 12)
	var tries := 0
	while rooms.size() < target and tries < 600:
		tries += 1
		var rw := rng.randi_range(6, 11)
		var rh := rng.randi_range(5, 8)
		var r := Rect2i(rng.randi_range(2, w - rw - 2), rng.randi_range(2, h - rh - 2), rw, rh)
		var ok := true
		for o in rooms:
			if (o as Rect2i).grow(2).intersects(r):
				ok = false
				break
		if ok:
			rooms.append(r)
	for r in rooms:
		_carve(r)
	# 最小全域木（Prim）で全部屋を接続
	var centers := []
	for r in rooms:
		centers.append((r as Rect2i).get_center())
	var in_tree := {0: true}
	var edges := []
	while in_tree.size() < rooms.size():
		var best := INF
		var ba := -1
		var bb := -1
		for a in in_tree.keys():
			for b in rooms.size():
				if in_tree.has(b):
					continue
				var d: float = Vector2(centers[a]).distance_to(Vector2(centers[b]))
				if d < best:
					best = d
					ba = a
					bb = b
		in_tree[bb] = true
		edges.append([ba, bb])
	# ループ用の追加通路
	var extra := 0
	for a in rooms.size():
		for b in range(a + 1, rooms.size()):
			if extra >= 3:
				break
			var d2: float = Vector2(centers[a]).distance_to(Vector2(centers[b]))
			if d2 < 22.0 and rng.randf() < 0.25 and not edges.has([a, b]) and not edges.has([b, a]):
				edges.append([a, b])
				extra += 1
	for e in edges:
		_corridor(centers[e[0]], centers[e[1]])
	# スタート部屋とゴール（階段）部屋: スタートから最も遠い部屋
	start_room = rng.randi_range(0, rooms.size() - 1)
	start_cell = (rooms[start_room] as Rect2i).get_center()
	var dist := bfs(start_cell)
	var far := -1
	var far_d := -1
	for i in rooms.size():
		var c: Vector2i = (rooms[i] as Rect2i).get_center()
		var d3: int = dist[idx(c)]
		if i != start_room and d3 > far_d:
			far_d = d3
			far = i
	stairs_room = far
	stairs_cell = (rooms[far] as Rect2i).get_center()

func _gen_boss() -> void:
	boss_room = Rect2i(w / 2 - 12, 5, 24, 17)
	_carve(boss_room)
	var sr := Rect2i(w / 2 - 5, 31, 10, 8)
	_carve(sr)
	rooms = [sr, boss_room]
	_carve(Rect2i(w / 2 - 1, boss_room.end.y, 2, sr.position.y - boss_room.end.y))
	# 柱
	for p in [Vector2i(-7, 4), Vector2i(5, 4), Vector2i(-7, 11), Vector2i(5, 11)]:
		var c := Vector2i(boss_room.position.x + 12 + p.x, boss_room.position.y + p.y)
		for y in 2:
			for x in 2:
				grid[idx(c + Vector2i(x, y))] = 0
	gate_cells = [Vector2i(w / 2 - 1, boss_room.end.y), Vector2i(w / 2, boss_room.end.y)]
	start_room = 0
	start_cell = Vector2i(w / 2, sr.position.y + 5)
	stairs_room = -1
	stairs_cell = Vector2i(-1, -1)

## 4近傍BFSの距離（到達不可 = -1）
func bfs(from: Vector2i, max_d := 100000) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	if not is_floor(from):
		return dist
	var q := [from]
	dist[idx(from)] = 0
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		var dc := dist[idx(c)]
		if dc >= max_d:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if is_floor(n) and dist[idx(n)] == -1:
				dist[idx(n)] = dc + 1
				q.append(n)
	return dist

## 検証: 全床が連結 / 階段到達可能 / スタートが床
func validate() -> String:
	if not is_floor(start_cell):
		return "start not floor"
	var dist := bfs(start_cell)
	var floors := 0
	var reach := 0
	for i in w * h:
		if grid[i] == 1:
			floors += 1
			if dist[i] >= 0:
				reach += 1
	if floors != reach:
		return "disconnected %d/%d" % [reach, floors]
	if not is_boss:
		if not is_floor(stairs_cell) or dist[idx(stairs_cell)] < 0:
			return "stairs unreachable"
		if rooms.size() < 5:
			return "too few rooms %d" % rooms.size()
	return ""

## 部屋内のランダムな床セル（壁際1マスは避ける）
func random_cell_in(r: Rect2i, avoid: Array = []) -> Vector2i:
	for i in 40:
		var c := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - 2), rng.randi_range(r.position.y + 1, r.end.y - 2))
		if is_floor(c) and not avoid.has(c):
			return c
	return r.get_center()
