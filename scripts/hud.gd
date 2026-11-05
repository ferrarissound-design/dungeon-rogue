extends Control
## HUD: HP/経験値/階層/装備/ミニマップ/ボスHP/ダメージ数字/画面効果

const FONT := preload("res://fonts/NotoSansJP-Bold-subset.otf")
const Art := preload("res://scripts/art.gd")
const Items := preload("res://scripts/items.gd")
var game
var banner := ""
var banner_col := Color.WHITE
var banner_t := 0.0
var sub_banner := ""
var show_hud := false
var mm_scale := 3.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func show_banner(text: String, col := Color.WHITE, dur := 2.2, sub := "") -> void:
	banner = text
	banner_col = col
	banner_t = dur
	sub_banner = sub

func _process(dt: float) -> void:
	banner_t = maxf(0.0, banner_t - dt)
	queue_redraw()

func _txt(p: Vector2, s: String, fs: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, outline := 6) -> void:
	draw_string_outline(FONT, p, s, align, w, fs, outline, Color(0, 0, 0, 0.85 * col.a))
	draw_string(FONT, p, s, align, w, fs, col)

func minimap_rect() -> Rect2:
	if game == null or game.dun == null:
		return Rect2()
	var vs := size
	mm_scale = 3.0 if vs.x >= 800.0 else 2.4
	var w: float = game.dun.w * mm_scale
	var h: float = game.dun.h * mm_scale
	return Rect2(vs.x - w - 12.0, 12.0, w, h)

func _draw() -> void:
	if game == null or game.dun == null:
		return
	var vs := size
	var xf: Transform2D = game.get_viewport().get_canvas_transform()
	# ダメージ数字
	for t in game.texts:
		var sp: Vector2 = xf * t["pos"]
		var a: float = clampf(t["life"] / 0.3, 0.0, 1.0)
		var fs := int(22 * t["scale"])
		var pop: float = 1.0 + maxf(0.0, (t["life"] - 0.65) / 0.15) * 0.4
		fs = int(fs * pop)
		_txt(sp - Vector2(100, 0), t["text"], fs, Color(t["col"], a), HORIZONTAL_ALIGNMENT_CENTER, 200.0, 7)
	if not show_hud:
		_draw_fade(vs)
		return
	# 低HP時の赤いビネット
	var hpr: float = game.php / game.st["maxhp"]
	if hpr < 0.3 and game.alive:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
		var a2 := (0.3 - hpr) / 0.3 * 0.35 + pulse * 0.1
		for i in 6:
			var g := float(i) * 10.0
			draw_rect(Rect2(g, g, vs.x - g * 2, vs.y - g * 2), Color(0.9, 0.05, 0.05, a2 * (1.0 - i / 6.0)), false, 10.0)
	# HPバー
	var x0 := 16.0
	var y0 := 14.0
	var bw := 250.0
	draw_rect(Rect2(x0 - 4, y0 - 4, bw + 8, 30), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x0, y0, bw, 22), Color(0.25, 0.05, 0.08))
	draw_rect(Rect2(x0, y0, bw * clampf(hpr, 0.0, 1.0), 22), Color(0.88, 0.2, 0.25) if hpr > 0.3 else Color(1.0, 0.35, 0.2))
	draw_rect(Rect2(x0, y0, bw * clampf(hpr, 0.0, 1.0), 7), Color(1, 1, 1, 0.18))
	_txt(Vector2(x0 + 8, y0 + 18), "HP %d / %d" % [ceili(game.php), roundi(game.st["maxhp"])], 18)
	# 経験値
	var xr: float = float(game.xp) / game.xp_need()
	draw_rect(Rect2(x0 - 4, y0 + 28, bw + 8, 12), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x0, y0 + 30, bw * xr, 8), Color(0.35, 0.75, 1.0))
	_txt(Vector2(x0, y0 + 64), "Lv %d" % game.level, 22, Color(0.75, 0.9, 1.0))
	var fl := "地下%d階" % game.floor_num if game.floor_num < game.FLOORS else "最下層"
	_txt(Vector2(x0 + 80, y0 + 64), fl, 22, Color(1.0, 0.85, 0.45))
	# 装備と回復薬
	var ix := x0
	var iy := y0 + 74
	for slot in ["weapon", "armor", "accessory"]:
		var it: Dictionary = game.equip[slot]
		var col: Color = Items.RARITY_COL[it["rarity"]] if not it.is_empty() else Color(0.4, 0.4, 0.45)
		draw_rect(Rect2(ix, iy, 36, 36), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(ix, iy, 36, 36), Color(col, 0.9), false, 2.0)
		draw_texture_rect(Art.tex(slot), Rect2(ix + 2, iy + 2, 32, 32), false, Color(1, 1, 1, 1.0 if not it.is_empty() else 0.3))
		ix += 42
	draw_rect(Rect2(ix, iy, 36, 36), Color(0, 0, 0, 0.55))
	draw_texture_rect(Art.tex("potion"), Rect2(ix + 2, iy + 2, 32, 32), false)
	_txt(Vector2(ix + 38, iy + 28), "×%d" % game.potions, 20)
	# ミニマップ
	var mr := minimap_rect()
	draw_rect(mr.grow(3), Color(0, 0, 0, 0.5))
	draw_texture_rect(game.get_minimap(), mr, false)
	var ms := mm_scale
	if game.floor_num < game.FLOORS and game.is_explored(game.dun.stairs_cell):
		var sc: Vector2 = mr.position + (Vector2(game.dun.stairs_cell) + Vector2(0.5, 0.5)) * ms
		draw_rect(Rect2(sc - Vector2(4, 4), Vector2(8, 8)), Color(0.35, 1.0, 0.55))
	for c in game.chests:
		if not c["opened"] and game.is_explored(c["cell"]):
			var cp: Vector2 = mr.position + (Vector2(c["cell"]) + Vector2(0.5, 0.5)) * ms
			draw_rect(Rect2(cp - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.82, 0.3))
	if game.boss and not game.boss.dead:
		var bp: Vector2 = mr.position + game.boss.pos / game.T * ms
		draw_circle(bp, 5.0, Color(1.0, 0.25, 0.25))
	var pp: Vector2 = mr.position + game.ppos / game.T * ms
	draw_circle(pp, 4.0, Color(1, 1, 1))
	draw_circle(pp, 2.5, Color(0.3, 0.6, 1.0))
	_txt(Vector2(mr.position.x, mr.end.y + 24), "%d:%02d" % [int(game.time) / 60, int(game.time) % 60], 18, Color(0.8, 0.8, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, mr.size.x)
	# 階段への矢印（探索に時間がかかった時のヒント）
	if game.floor_num < game.FLOORS and game.floor_time > 70.0 and game.alive:
		var sw: Vector2 = xf * game.cell_center(game.dun.stairs_cell)
		var ctr := vs * 0.5
		var d := sw - ctr
		if d.length() > 160.0:
			var dir := d.normalized()
			var ap := ctr + dir * minf(d.length() - 30.0, minf(vs.x, vs.y) * 0.38)
			var nrm := Vector2(-dir.y, dir.x)
			var pts := PackedVector2Array([ap + dir * 18.0, ap - dir * 8.0 + nrm * 12.0, ap - dir * 8.0 - nrm * 12.0])
			var pa := 0.6 + 0.3 * sin(Time.get_ticks_msec() / 200.0)
			draw_colored_polygon(pts, Color(0.35, 1.0, 0.55, pa))
			_txt(ap - dir * 30.0 + Vector2(-40, 8), "階段", 18, Color(0.6, 1.0, 0.7, pa), HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	# ボスHP
	if game.boss and game.boss_active and not game.boss.dead:
		var b = game.boss
		var bw2 := minf(vs.x * 0.6, 560.0)
		var bx := (vs.x - bw2) * 0.5
		var by := vs.y - 46.0 if vs.x < vs.y else 150.0
		if vs.x >= vs.y:
			by = 22.0 + (0.0 if vs.x - mr.size.x - 30.0 > bx + bw2 else mr.end.y + 30.0)
		_txt(Vector2(bx, by - 6), "深淵の魔王", 20, Color(1.0, 0.5, 0.45))
		draw_rect(Rect2(bx - 3, by - 1, bw2 + 6, 18), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bx, by + 2, bw2 * clampf(b.hp / b.maxhp, 0.0, 1.0), 12), Color(0.85, 0.15, 0.2) if b.phase == 1 else Color(1.0, 0.4, 0.1))
		draw_line(Vector2(bx + bw2 * 0.5, by), Vector2(bx + bw2 * 0.5, by + 16), Color(1, 1, 1, 0.5), 2.0)
	# バナー
	if banner_t > 0.0:
		var a3 := clampf(banner_t / 0.5, 0.0, 1.0)
		var sc2 := 1.0 + maxf(0.0, banner_t - 1.9) * 1.0
		var fs2 := int(46 * sc2)
		_txt(Vector2(0, vs.y * 0.36), banner, fs2, Color(banner_col, a3), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 10)
		if sub_banner != "":
			_txt(Vector2(0, vs.y * 0.36 + 40), sub_banner, 22, Color(0.9, 0.9, 1.0, a3), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
	_draw_fade(vs)

func _draw_fade(vs: Vector2) -> void:
	var f: float = maxf(game.fade, clampf(game.trans_t / 0.5, 0.0, 1.0))
	if f > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, f))
