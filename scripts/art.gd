extends RefCounted
## ドット絵スプライトとタイルをコードで生成する（外部画像アセット不要）。

static var _cache := {}

const PAL := {
	"k": Color(0.07, 0.06, 0.09), "s": Color(0.80, 0.84, 0.92), "S": Color(0.46, 0.51, 0.62),
	"b": Color(0.27, 0.48, 0.88), "B": Color(0.15, 0.25, 0.52), "f": Color(0.96, 0.76, 0.60),
	"y": Color(1.0, 0.83, 0.30), "Y": Color(0.74, 0.50, 0.16), "w": Color(1, 1, 1),
	"g": Color(0.38, 0.82, 0.38), "G": Color(0.16, 0.50, 0.26), "r": Color(0.92, 0.22, 0.22),
	"R": Color(0.55, 0.10, 0.16), "p": Color(0.62, 0.38, 0.88), "P": Color(0.36, 0.17, 0.52),
	"n": Color(0.62, 0.41, 0.23), "N": Color(0.38, 0.24, 0.13), "e": Color(0.92, 0.90, 0.80),
	"E": Color(0.64, 0.61, 0.54), "o": Color(1.0, 0.56, 0.16), "c": Color(0.42, 0.92, 1.0),
	"x": Color(0.02, 0.02, 0.03), "h": Color(1.0, 0.35, 0.60), "C": Color(0.20, 0.55, 0.75),
}

const SPR := {
	"player": [
		"......kkkk......",
		".....kssssk.....",
		"....kssssssk....",
		"....ksSSSSsk....",
		"....kSkccksk....",
		"....kskffksk....",
		".....kkkkkk.....",
		"....kbbyybbk....",
		"...kbbbyybbbk...",
		"...kfbbbbbbfk...",
		"...kfkbbbbkfk...",
		"....kBBBBBBk....",
		"....kBBkkBBk....",
		"....kSSkkSSk....",
		"....kkk..kkk....",
		"................"],
	"slime": [
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		".......kk.......",
		".....kkggkk.....",
		"....kggggggk....",
		"...kgwwggggGk...",
		"...kgwgggggGk...",
		"..kggkggkgggGk..",
		"..kgggggggggGk..",
		"..kGgggggggGGk..",
		"...kGGGGGGGGk...",
		"....kkkkkkkk...."],
	"bat": [
		"................",
		"................",
		"................",
		"................",
		"k..............k",
		"kk....k..k....kk",
		"kPk..kpkkpk..kPk",
		"kPPk.kppppk.kPPk",
		"kPPPkphpphpkPPPk",
		"kPPPPppppppPPPPk",
		".kPPkppwwppkPPk.",
		"..kk.kppppk.kk..",
		"......kppk......",
		".......kk.......",
		"................",
		"................"],
	"archer": [
		"................",
		".....kkkkk......",
		"....keeeeek.....",
		"....kerEerk.....",
		"....keeeeek.....",
		".....kEkEk...kk.",
		"......kkk...kNk.",
		"....kkeEkk.kNk..",
		"...keekeeeknk...",
		"...kekkekkeknk..",
		"...ke.keEk.kNk..",
		"....kkeEekk..kk.",
		".....kekek......",
		".....kek.kek....",
		"....kek...kek...",
		"....kk.....kk..."],
	"charger": [
		"................",
		"..kk........kk..",
		"..kek......kek..",
		"...kekkkkkkek...",
		"...kGggggggGk...",
		"..kGgrggggrgGk..",
		"..kGggggggggGk..",
		"..kGgeggggegGk..",
		"...kGggkkggGk...",
		"..kNNnnnnnnNNk..",
		".kgkNnnnnnnNkgk.",
		".kgkNnnyynnNkgk.",
		"..kkNnnnnnnNkk..",
		"...kNNNkkNNNk...",
		"...kGGk..kGGk...",
		"...kkkk..kkkk..."],
	"mage": [
		".......kk.......",
		"......kpPk......",
		".....kpppPk.....",
		"....kpppppPk....",
		"...kkkkkkkkkk...",
		"....kxhxxhxk....",
		"....kxxxxxxk....",
		"...kPpppppppPk..",
		"..kfkPppyppPkfk.",
		"..kfkPppyppPkfk.",
		"....kPppyppPk...",
		"...kPppppppppk..",
		"...kPPpppppPPk..",
		"..kPPPPPPPPPPPk.",
		"..kkkkkkkkkkkkk.",
		"................"],
	"boss": [
		"........................",
		"..kk................kk..",
		"..kRk..............kRk..",
		"...kRk....kkkk....kRk...",
		"...kRRk.kkRRRRkk.kRRk...",
		"....kRRkRRRRRRRRkRRk....",
		".....kRRRrrrrrrRRRk.....",
		"....kRRrrrrrrrrrrRRk....",
		"....kRrryyrrrryyrrRk....",
		"....kRrrkyrrrrykrrRk....",
		"....kRrrrrrrrrrrrrRk....",
		".....kRrrwkwwkwrrRk.....",
		"..kkkkRRrrrrrrrrRRkkkk..",
		".kPPPPkRRRRRRRRRRkPPPPk.",
		"kPPppPPkkkkyykkkkPPppPPk",
		"kPppppPPPPPyyPPPPPppppPk",
		"kPpkkpPPpppyyppPPPpkkpPk",
		"kPk.kpPPppppppppPPpk.kPk",
		".k..kRRpPPPPPPPPpRRk..k.",
		"...kRRkPPPPPPPPPPkRRk...",
		"...kRk.kPPPPPPPPk.kRk...",
		"...kRk.kPPPkkPPPk.kRk...",
		"...kkk.kRRRk.kRRRk.kkk..",
		"........kkkk..kkkk......"],
	"chest": [
		"................",
		"................",
		"................",
		"..kkkkkkkkkkkk..",
		".knnnnnnnnnnnnk.",
		".knNNNNNNNNNNnk.",
		".knnnnnnnnnnnnk.",
		".kYYYYYkkYYYYYk.",
		".kkkkkkyykkkkkk.",
		".knnnnnkykknnnk.",
		".knNNNNkkkNNNnk.",
		".knnnnnnnnnnnnk.",
		".knNNNNNNNNNNnk.",
		".kYnnnnnnnnnnYk.",
		".kkkkkkkkkkkkkk.",
		"................"],
	"chest_open": [
		"..kkkkkkkkkkkk..",
		".knnnnnnnnnnnnk.",
		".knNNNNNNNNNNnk.",
		".kYYYYYYYYYYYYk.",
		".kkkkkkkkkkkkkk.",
		".kxxxxxxxxxxxxk.",
		".kxxxxxxxxxxxxk.",
		".kYYYYYkkYYYYYk.",
		".kkkkkkkkkkkkkk.",
		".knnnnnnnnnnnnk.",
		".knNNNNNNNNNNnk.",
		".knnnnnnnnnnnnk.",
		".knNNNNNNNNNNnk.",
		".kYnnnnnnnnnnYk.",
		".kkkkkkkkkkkkkk.",
		"................"],
	"potion": [
		"................",
		"................",
		"......kkkk......",
		"......kNNk......",
		".......kk.......",
		"......kwwk......",
		".....kwrrrk.....",
		"....krrwrrrk....",
		"....krwrrrrk....",
		"....krrrrrRk....",
		"....kRrrrRRk....",
		".....kRRRRk.....",
		"......kkkk......",
		"................",
		"................",
		"................"],
	"heart": [
		"................",
		"................",
		"................",
		"....kkk..kkk....",
		"...krrrkkrrrk...",
		"..krwwrrrrrrRk..",
		"..krwrrrrrrrRk..",
		"..krrrrrrrrrRk..",
		"...krrrrrrrRk...",
		"....krrrrrRk....",
		".....krrrRk.....",
		"......krRk......",
		".......kk.......",
		"................",
		"................",
		"................"],
	"weapon": [
		"................",
		"............kk..",
		"...........kwk..",
		"..........kssk..",
		".........kssk...",
		"........kssk....",
		".......kssk.....",
		"..kk..kssk......",
		"..kyk.ksk.......",
		"...kykSk........",
		"....kyk.........",
		"...kNkyk........",
		"..kNk.kyk.......",
		".kNk...kk.......",
		".kk.............",
		"................"],
	"armor": [
		"................",
		"...kkkk..kkkk...",
		"..kssSkkkkSssk..",
		"..ksSSbbbbSSsk..",
		"..kSSbbbbbbSSk..",
		"..kkkbbyybbkkk..",
		"....kbbyybbk....",
		"....kbbbbbbk....",
		"....kbbbbbbk....",
		"....kBBBBBBk....",
		"....kyyyyyyk....",
		"....kBBBBBBk....",
		".....kkkkkk.....",
		"................",
		"................",
		"................"],
	"accessory": [
		"................",
		"................",
		"......kkkk......",
		".....kcwcck.....",
		"......kkkk......",
		".....kyyyyk.....",
		"....kyk..kyk....",
		"...kyk....kyk...",
		"...kyk....kyk...",
		"...kyk....kYk...",
		"....kYk..kYk....",
		".....kYYYYk.....",
		"......kkkk......",
		"................",
		"................",
		"................"],
	"sword": [
		"..kk.......",
		".kwsk......",
		".kssSk.....",
		"..kssSk....",
		"...kssSk...",
		"....kssSk..",
		".....kssSk.",
		"......kssk.",
		".......kk..",
	],
}

static func _img_from(rows: Array) -> Image:
	var h := rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, String(r).length())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if PAL.has(ch):
				img.set_pixel(x, y, PAL[ch])
	return img

static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var img := _img_from(SPR[name])
	var t := ImageTexture.create_from_image(img)
	_cache[name] = t
	return t

## 被弾フラッシュ用の白シルエット
static func white(name: String) -> Texture2D:
	var key := name + "#w"
	if _cache.has(key):
		return _cache[key]
	var img := _img_from(SPR[name])
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

## 光のグラデーション（暗闇オーバーレイ用）。中心は透明、外側ほど暗い
static func light_tex() -> Texture2D:
	if _cache.has("light"):
		return _cache["light"]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (n * 0.5)
			var a := clampf((d - 0.45) / 0.55, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	var t := ImageTexture.create_from_image(img)
	_cache["light"] = t
	return t

# ---------- タイル ----------
## 階層ごとの配色 [床, 床の暗部, 壁面, 壁上部, 目地]
const THEMES := [
	[Color("5a4a3c"), Color("46392e"), Color("7a5f48"), Color("2a211b"), Color("332820")],
	[Color("4b5058"), Color("3a3e45"), Color("676f7b"), Color("1f2227"), Color("2b2f35")],
	[Color("3f5243"), Color("314136"), Color("566e57"), Color("19231c"), Color("243128")],
	[Color("4a3f5c"), Color("3a3149"), Color("665683"), Color("1d1726"), Color("2a2238")],
	[Color("5a3434"), Color("462828"), Color("7d4545"), Color("251313"), Color("331a1a")],
]

static func _tile_floor(rng: RandomNumberGenerator, th: Array) -> Image:
	var T := 16
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var floor_c: Color = th[0]
	var floor_d: Color = th[1]
	var grout: Color = th[4]
	var base := floor_c.lerp(floor_d, rng.randf() * 0.4)
	for y in T:
		for x in T:
			var c := base
			if x % 8 == 0 or y % 8 == 0:
				c = grout
			elif rng.randf() < 0.07:
				c = base.darkened(0.15)
			elif rng.randf() < 0.03:
				c = base.lightened(0.08)
			img.set_pixel(x, y, c)
	var deco := rng.randf()
	if deco < 0.35:
		var px := rng.randi_range(3, 12)
		var py := rng.randi_range(2, 9)
		for i in 5:
			img.set_pixel(clampi(px, 0, T - 1), clampi(py, 0, T - 1), grout)
			px += rng.randi_range(-1, 1)
			py += 1
	elif deco < 0.5:
		var px2 := rng.randi_range(3, 11)
		var py2 := rng.randi_range(3, 11)
		var bc := Color(0.85, 0.82, 0.72) if rng.randf() < 0.5 else base.lightened(0.2)
		img.set_pixel(px2, py2, bc)
		img.set_pixel(px2 + 1, py2, bc)
		img.set_pixel(px2 + 2, py2 + 1, bc.darkened(0.3))
	return img

static func _tile_face(rng: RandomNumberGenerator, th: Array) -> Image:
	var T := 16
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var face_c: Color = (th[2] as Color).lerp(th[3], rng.randf() * 0.15)
	var top_c: Color = th[3]
	for y in T:
		for x in T:
			var row := y / 5
			var off := 4 if row % 2 == 1 else 0
			var c := face_c
			if y % 5 == 4 or (x + off) % 8 == 0:
				c = face_c.darkened(0.35)
			elif y % 5 == 0:
				c = face_c.lightened(0.10)
			if y < 2:
				c = top_c.lightened(0.25)
			img.set_pixel(x, y, c)
	if rng.randf() < 0.5:
		for i in 7:
			img.set_pixel(rng.randi_range(0, 15), rng.randi_range(8, 15), face_c.darkened(0.5))
	return img

static func _tile_top(rng: RandomNumberGenerator, th: Array) -> Image:
	var T := 16
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var top_c: Color = th[3]
	for y in T:
		for x in T:
			img.set_pixel(x, y, top_c.lightened(0.08) if rng.randf() < 0.05 else top_c)
	return img

static func build_map_image(grid: PackedByteArray, w: int, h: int, theme: int, seed: int) -> Image:
	const T := 16
	var th: Array = THEMES[clampi(theme, 0, THEMES.size() - 1)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var floors := []
	for i in 10:
		floors.append(_tile_floor(rng, th))
	var faces := []
	for i in 4:
		faces.append(_tile_face(rng, th))
	var tops := [_tile_top(rng, th), _tile_top(rng, th)]
	var shadow := Image.create(T, 5, false, Image.FORMAT_RGBA8)
	for y in 5:
		shadow.fill_rect(Rect2i(0, y, T, 1), Color(0, 0, 0, 0.5 - y * 0.1))
	var hl: Color = (th[3] as Color).lightened(0.3)
	var img := Image.create(w * T, h * T, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var full := Rect2i(0, 0, T, T)
	for cy in h:
		for cx in w:
			var v := grid[cy * w + cx]
			var o := Vector2i(cx * T, cy * T)
			if v == 1:
				var fi := rng.randi_range(0, 9) if rng.randf() < 0.5 else rng.randi_range(0, 3)
				img.blit_rect(floors[fi], full, o)
				if cy > 0 and grid[(cy - 1) * w + cx] == 0:
					img.blend_rect(shadow, Rect2i(0, 0, T, 5), o)
			else:
				var below_floor := cy + 1 < h and grid[(cy + 1) * w + cx] == 1
				if below_floor:
					img.blit_rect(faces[rng.randi_range(0, 3)], full, o)
				else:
					var near := false
					for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
						var nx: int = cx + d.x
						var ny: int = cy + d.y
						if nx >= 0 and ny >= 0 and nx < w and ny < h and grid[ny * w + nx] == 1:
							near = true
							break
					if near:
						img.blit_rect(tops[rng.randi_range(0, 1)], full, o)
						if cx > 0 and grid[cy * w + cx - 1] == 1:
							img.fill_rect(Rect2i(o.x, o.y, 1, T), hl)
						if cx + 1 < w and grid[cy * w + cx + 1] == 1:
							img.fill_rect(Rect2i(o.x + T - 1, o.y, 1, T), hl)
						if cy > 0 and grid[(cy - 1) * w + cx] == 1:
							img.fill_rect(Rect2i(o.x, o.y, T, 1), hl)
	return img
