extends Control
## スマホ用タッチ操作: 左側=フローティング仮想スティック、右側=攻撃/回避/回復薬ボタン。
## マルチタッチ対応（指ごとに index を追跡）。

const FONT := preload("res://fonts/NotoSansJP-Bold-subset.otf")
const STICK_R := 70.0
const KNOB_R := 30.0

var enabled := false
var visible_controls := false
var stick_idx := -1
var stick_origin := Vector2.ZERO
var stick_knob := Vector2.ZERO
var buttons := {}            # name -> {c: Vector2, r: float, idx: int, label: String, col: Color}
var attack_held := false
var dodge_pressed := false
var potion_pressed := false
var attack_pressed := false
var potion_count := 0
var roll_ready := 1.0
var block_controls: Array = []
var sim_vec := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons = {
		"attack": {"c": Vector2.ZERO, "r": 64.0, "idx": -1, "label": "攻撃", "col": Color(1.0, 0.45, 0.35)},
		"dodge": {"c": Vector2.ZERO, "r": 46.0, "idx": -1, "label": "回避", "col": Color(0.45, 0.75, 1.0)},
		"potion": {"c": Vector2.ZERO, "r": 34.0, "idx": -1, "label": "薬", "col": Color(0.5, 1.0, 0.55)},
	}
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var s := size
	var m := 1.0 if s.x >= s.y else 0.95
	buttons["attack"]["c"] = Vector2(s.x - 100.0 * m, s.y - 105.0 * m)
	buttons["dodge"]["c"] = Vector2(s.x - 225.0 * m, s.y - 70.0 * m)
	buttons["potion"]["c"] = Vector2(s.x - 80.0 * m, s.y - 235.0 * m)

func stick_rest() -> Vector2:
	return Vector2(clampf(size.x * 0.16, 110.0, 200.0), size.y - 120.0)

func get_vector() -> Vector2:
	if sim_vec != Vector2.ZERO:
		return sim_vec
	if stick_idx == -1:
		return Vector2.ZERO
	var v := (stick_knob - stick_origin) / STICK_R
	if v.length() < 0.18:
		return Vector2.ZERO
	return v.limit_length(1.0)

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		release_all()
	queue_redraw()

func release_all() -> void:
	stick_idx = -1
	for k in buttons:
		buttons[k]["idx"] = -1
	attack_held = false
	queue_redraw()

## 1フレーム分の押下イベントを取り出す
func consume() -> Dictionary:
	var d := {"attack": attack_pressed, "dodge": dodge_pressed, "potion": potion_pressed}
	attack_pressed = false
	dodge_pressed = false
	potion_pressed = false
	return d

func _blocked(pos: Vector2) -> bool:
	for c in block_controls:
		if c.is_visible_in_tree() and c.get_global_rect().grow(8.0).has_point(pos):
			return true
	return false

func _button_at(pos: Vector2) -> String:
	var best := ""
	var bd := INF
	for k in buttons:
		var b: Dictionary = buttons[k]
		var d: float = pos.distance_to(b["c"])
		if d < b["r"] * 1.3 and d < bd:
			bd = d
			best = k
	return best

func _press(k: String, idx: int) -> void:
	buttons[k]["idx"] = idx
	match k:
		"attack":
			attack_held = true
			attack_pressed = true
		"dodge":
			dodge_pressed = true
		"potion":
			potion_pressed = true

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not visible_controls and event.pressed:
			visible_controls = true
		if not enabled:
			return
		if event.pressed:
			if _blocked(event.position):
				return
			var k := _button_at(event.position)
			if k != "":
				_press(k, event.index)
			elif stick_idx == -1 and event.position.x < size.x * 0.6:
				stick_idx = event.index
				stick_origin = event.position
				stick_knob = event.position
		else:
			if event.index == stick_idx:
				stick_idx = -1
			for kk in buttons:
				if buttons[kk]["idx"] == event.index:
					buttons[kk]["idx"] = -1
					if kk == "attack":
						attack_held = false
		queue_redraw()
	elif event is InputEventScreenDrag and enabled:
		if event.index == stick_idx:
			var d: Vector2 = event.position - stick_origin
			if d.length() > STICK_R:
				stick_origin = event.position - d.normalized() * STICK_R
			stick_knob = event.position
			queue_redraw()

func _process(_dt: float) -> void:
	if visible_controls:
		queue_redraw()

func _draw() -> void:
	if not visible_controls or not enabled:
		return
	# スティック
	var o := stick_origin if stick_idx != -1 else stick_rest()
	var k := (stick_knob if stick_idx != -1 else o)
	if sim_vec != Vector2.ZERO:
		k = o + sim_vec * STICK_R
	k = o + (k - o).limit_length(STICK_R)
	var act := stick_idx != -1 or sim_vec != Vector2.ZERO
	draw_circle(o, STICK_R, Color(1, 1, 1, 0.10 if act else 0.05))
	draw_arc(o, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.45 if act else 0.2), 3.0, true)
	draw_circle(k, KNOB_R, Color(0.8, 0.85, 1.0, 0.5 if act else 0.22))
	# ボタン
	for name in buttons:
		var b: Dictionary = buttons[name]
		var pressed: bool = b["idx"] != -1
		var col: Color = b["col"]
		var c: Vector2 = b["c"]
		var r: float = b["r"] * (0.93 if pressed else 1.0)
		var dim := 1.0
		if name == "potion" and potion_count <= 0:
			dim = 0.4
		draw_circle(c, r, Color(col.darkened(0.55), (0.55 if pressed else 0.38) * dim))
		draw_arc(c, r, 0, TAU, 48, Color(col, 0.85 * dim), 3.0, true)
		if name == "dodge" and roll_ready < 1.0:
			draw_arc(c, r - 6.0, -PI * 0.5, -PI * 0.5 + TAU * roll_ready, 40, Color(1, 1, 1, 0.6), 4.0, true)
		var fs := int(r * 0.48)
		var txt: String = b["label"]
		if name == "potion":
			txt = "薬×%d" % potion_count
			fs = int(r * 0.42)
		draw_string_outline(FONT, Vector2(c.x - r, c.y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, 6, Color(0, 0, 0, 0.7 * dim))
		draw_string(FONT, Vector2(c.x - r, c.y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, 0.95 * dim))
