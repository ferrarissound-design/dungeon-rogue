extends RefCounted
## 装備品とレベルアップ強化のデータ

const RARITY_NAME := ["ノーマル", "レア", "伝説"]
const RARITY_COL := [Color("e8e8e8"), Color("62b6ff"), Color("ffb13b")]
const SLOT_NAME := {"weapon": "武器", "armor": "防具", "accessory": "装飾品"}
const STAT_NAME := {
	"atk": "攻撃力", "def": "防御力", "maxhp": "最大HP", "spd": "移動速度", "crit": "会心率",
	"aspd": "攻撃速度", "reach": "リーチ", "regen": "HP再生", "vamp": "吸血",
}
const WEAPONS := ["銅の剣", "鉄の剣", "鋼の剣", "ミスリルの剣", "竜殺しの剣"]
const ARMORS := ["布の服", "革の鎧", "鎖かたびら", "鋼の鎧", "騎士の鎧"]
const ACCS := [
	["力の指輪", "atk"], ["疾風のブーツ", "spd"], ["見切りのお守り", "crit"],
	["命の首飾り", "maxhp"], ["再生の腕輪", "regen"], ["吸血の牙", "vamp"], ["迅雷の小手", "aspd"],
]
const PREFIX := ["", "上質な", "伝説の"]

static func stat_text(k: String, v: float) -> String:
	match k:
		"spd", "crit", "aspd", "reach":
			return "%s +%d%%" % [STAT_NAME[k], roundi(v * 100.0)]
		"regen":
			return "%s +%.1f/秒" % [STAT_NAME[k], v]
		_:
			return "%s +%d" % [STAT_NAME[k], roundi(v)]

static func _secondary(rng: RandomNumberGenerator, p: float) -> Array:
	var opts := [["crit", 0.05 + p * 0.01], ["aspd", 0.08 + p * 0.01], ["reach", 0.12], ["maxhp", 4.0 + p * 2.0], ["spd", 0.05 + p * 0.01]]
	return opts[rng.randi_range(0, opts.size() - 1)]

static func make_item(rng: RandomNumberGenerator, floor_num: int, slot := "") -> Dictionary:
	if slot == "":
		var r := rng.randf()
		slot = "weapon" if r < 0.4 else ("armor" if r < 0.75 else "accessory")
	var rr := rng.randf()
	var rarity := 0
	if rr < 0.08 + floor_num * 0.04:
		rarity = 2
	elif rr < 0.35 + floor_num * 0.06:
		rarity = 1
	var p := float(floor_num) + rarity * 1.5 + rng.randf_range(-0.5, 0.5)
	var tier := clampi(int(p / 1.6), 0, 4)
	var st := {}
	var name := ""
	match slot:
		"weapon":
			name = WEAPONS[tier]
			st["atk"] = roundf(2.0 + p * 1.7)
		"armor":
			name = ARMORS[tier]
			st["def"] = roundf(1.0 + p * 1.3)
			st["maxhp"] = roundf(p * 2.5)
		_:
			var a: Array = ACCS[rng.randi_range(0, ACCS.size() - 1)]
			name = a[0]
			var m := 1.0 + 0.5 * rarity
			match String(a[1]):
				"atk": st["atk"] = roundf((1.0 + p * 0.6) * m)
				"spd": st["spd"] = (0.06 + p * 0.015) * m
				"crit": st["crit"] = (0.06 + p * 0.015) * m
				"maxhp": st["maxhp"] = roundf((6.0 + p * 3.0) * m)
				"regen": st["regen"] = snappedf((0.3 + p * 0.12) * m, 0.1)
				"vamp": st["vamp"] = roundf((1.0 + p * 0.4) * m)
				"aspd": st["aspd"] = (0.08 + p * 0.015) * m
	if rarity >= 1 and slot != "accessory":
		var s: Array = _secondary(rng, p)
		st[s[0]] = st.get(s[0], 0.0) + s[1]
	if rarity >= 2:
		var s2: Array = _secondary(rng, p)
		st[s2[0]] = st.get(s2[0], 0.0) + s2[1]
	return {"slot": slot, "name": PREFIX[rarity] + name, "rarity": rarity, "stats": st, "score": _score(st)}

static func _score(st: Dictionary) -> float:
	var w := {"atk": 1.0, "def": 1.0, "maxhp": 0.25, "spd": 20.0, "crit": 25.0, "aspd": 22.0, "reach": 15.0, "regen": 4.0, "vamp": 1.5}
	var s := 0.0
	for k in st:
		s += float(st[k]) * float(w.get(k, 1.0))
	return s

static func describe(item: Dictionary) -> String:
	if item.is_empty():
		return "なし"
	var parts := []
	for k in item["stats"]:
		parts.append(stat_text(k, item["stats"][k]))
	return "  ".join(parts)

# ---------- レベルアップ強化 ----------
const PERKS := [
	{"id": "maxhp", "name": "頑丈な体", "desc": "最大HP +10", "icon": "heart"},
	{"id": "atk", "name": "剣の修練", "desc": "攻撃力 +2", "icon": "weapon"},
	{"id": "def", "name": "鉄壁", "desc": "防御力 +2", "icon": "armor"},
	{"id": "spd", "name": "俊足", "desc": "移動速度 +10%", "icon": "accessory"},
	{"id": "crit", "name": "見切り", "desc": "会心率 +8%", "icon": "accessory"},
	{"id": "aspd", "name": "連撃", "desc": "攻撃速度 +12%", "icon": "weapon"},
	{"id": "reach", "name": "大振り", "desc": "剣のリーチ +15%", "icon": "weapon"},
	{"id": "roll", "name": "身軽", "desc": "回避の再使用 -20%", "icon": "accessory"},
	{"id": "regen", "name": "自然治癒", "desc": "毎秒HP +0.4 回復", "icon": "heart"},
	{"id": "vamp", "name": "吸血", "desc": "敵を倒すとHP +2", "icon": "heart"},
	{"id": "potion", "name": "薬草学", "desc": "回復薬 +1 & HP全回復", "icon": "potion"},
]

static func roll_perks(rng: RandomNumberGenerator, n: int) -> Array:
	var pool := PERKS.duplicate()
	var out := []
	for i in n:
		var j := rng.randi_range(0, pool.size() - 1)
		out.append(pool[j])
		pool.remove_at(j)
	return out
