extends CanvasLayer
## 画面UI: タイトル / HUD / タッチ操作 / レベルアップ / 宝箱 / 一時停止 / リザルト

signal start_requested
signal perk_chosen(idx: int)
signal item_decided(take: bool)
signal retry_requested
signal title_requested
signal pause_requested
signal resume_requested

const FONT := preload("res://fonts/NotoSansJP-Bold-subset.otf")
const Art := preload("res://scripts/art.gd")
const Items := preload("res://scripts/items.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch.gd")

var root: Control
var hud
var touch
var pause_button: Button
var title_layer: Control
var start_button: Button
var best_label: Label
var levelup_layer: Control
var levelup_title: Label
var cards_holder: Control
var cards: Array = []
var item_layer: Control
var item_name: Label
var item_info: Label
var item_stats: Label
var item_cur: Label
var item_icon: TextureRect
var take_button: Button
var leave_button: Button
var pause_layer: Control
var pause_info: Label
var resume_button: Button
var end_layer: Control
var end_title: Label
var end_stats: Label
var retry_button: Button
var end_title_button: Button
var hint_label: Label

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud = HudScript.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch = TouchScript.new()
	root.add_child(touch)
	touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.add_theme_font_size_override("font_size", 24)
	root.add_child(pause_button)
	pause_button.pressed.connect(func(): pause_requested.emit())
	touch.block_controls = [pause_button]
	_build_title()
	_build_levelup()
	_build_item()
	_build_pause()
	_build_end()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize.call_deferred()

func _on_resize() -> void:
	var vs := root.size
	var mm: Rect2 = hud.minimap_rect()
	var w := 60.0
	if mm.size.x > 0:
		pause_button.position = Vector2(mm.position.x - w - 12.0, 12.0)
	else:
		pause_button.position = Vector2(vs.x - w - 210.0, 12.0)
	pause_button.size = Vector2(w, w)

# ---------- テーマ ----------
func _sb(bg: Color, border: Color, bw := 3, radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = FONT
	th.default_font_size = 24
	th.set_stylebox("normal", "Button", _sb(Color("2a2238"), Color("a07cd8")))
	th.set_stylebox("hover", "Button", _sb(Color("3a2f50"), Color("d0b4ff")))
	th.set_stylebox("pressed", "Button", _sb(Color("1a1424"), Color("ffd166")))
	th.set_stylebox("disabled", "Button", _sb(Color("2a2238"), Color("5a4a78")))
	var focus := _sb(Color(0, 0, 0, 0), Color("ffd166"), 4)
	focus.draw_center = false
	focus.shadow_size = 0
	th.set_stylebox("focus", "Button", focus)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		th.set_color(c, "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.6))
	var panel := _sb(Color(0.07, 0.05, 0.1, 0.95), Color("7c5cc4"), 3, 14)
	panel.content_margin_left = 26
	panel.content_margin_right = 26
	panel.content_margin_top = 20
	panel.content_margin_bottom = 22
	th.set_stylebox("panel", "PanelContainer", panel)
	return th

func _label(text: String, fs: int, col := Color.WHITE, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.04))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(text: String, fs := 28, w := 300.0, h := 72.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", fs)
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b

func _overlay(dim: float, with_panel := true) -> Array:
	var layer_c := Control.new()
	layer_c.mouse_filter = Control.MOUSE_FILTER_STOP
	layer_c.visible = false
	root.add_child(layer_c)
	layer_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.0, 0.03, dim)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_c.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_c.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	if with_panel:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(panel)
		panel.add_child(vb)
	else:
		cc.add_child(vb)
	return [layer_c, vb]

## 誤タップ防止: 表示直後は少しだけボタンを無効化
func _guard(buttons: Array, focus: Button) -> void:
	for b in buttons:
		b.disabled = true
	get_tree().create_timer(0.35, true, false, true).timeout.connect(func():
		for b in buttons:
			b.disabled = false
		if focus and focus.is_visible_in_tree():
			focus.grab_focus())

# ---------- 画面構築 ----------
func _build_title() -> void:
	var o := _overlay(0.62, false)
	title_layer = o[0]
	var vb: VBoxContainer = o[1]
	vb.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.texture = Art.tex("player")
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(80, 80)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vb.add_child(icon)
	vb.add_child(_label("深淵の剣士", 76, Color("ffd166"), 16))
	vb.add_child(_label("〜 五層の迷宮 〜", 28, Color("d8c8ff"), 8))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	vb.add_child(sp)
	start_button = _button("冒険を始める", 34, 340, 84)
	start_button.pressed.connect(func(): start_requested.emit())
	vb.add_child(start_button)
	best_label = _label("", 22, Color("bfa8ff"), 6)
	vb.add_child(best_label)
	hint_label = _label("", 19, Color("c8c0dc"), 6)
	vb.add_child(hint_label)

func set_controls_hint(touch_mode: bool) -> void:
	if touch_mode:
		hint_label.text = "左側をドラッグ: 移動　右下ボタン: 攻撃・回避・回復薬"
	else:
		hint_label.text = "移動: WASD/矢印　攻撃: J/Z/スペース　回避: K/X/Shift\n回復薬: Q/C　一時停止: Esc　（ゲームパッド・タッチ対応）"

func _build_levelup() -> void:
	var o := _overlay(0.6)
	levelup_layer = o[0]
	var vb: VBoxContainer = o[1]
	levelup_title = _label("レベルアップ！", 42, Color("ffd166"), 10)
	vb.add_child(levelup_title)
	vb.add_child(_label("強化を1つ選んでください", 22, Color("d0c8e8")))
	cards_holder = VBoxContainer.new()
	vb.add_child(cards_holder)

func _build_item() -> void:
	var o := _overlay(0.55)
	item_layer = o[0]
	var vb: VBoxContainer = o[1]
	vb.add_child(_label("宝箱を開けた！", 34, Color("ffd166"), 8))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	item_icon = TextureRect.new()
	item_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item_icon.custom_minimum_size = Vector2(64, 64)
	item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(item_icon)
	var vb2 := VBoxContainer.new()
	hb.add_child(vb2)
	item_name = _label("", 32, Color.WHITE, 6)
	item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb2.add_child(item_name)
	item_info = _label("", 20, Color("bbbbcc"))
	item_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb2.add_child(item_info)
	item_stats = _label("", 24, Color("9fffb0"))
	vb.add_child(item_stats)
	item_cur = _label("", 19, Color("a8a0c0"))
	vb.add_child(item_cur)
	var hb2 := HBoxContainer.new()
	hb2.alignment = BoxContainer.ALIGNMENT_CENTER
	hb2.add_theme_constant_override("separation", 18)
	vb.add_child(hb2)
	take_button = _button("装備する", 28, 220, 72)
	take_button.pressed.connect(func(): item_decided.emit(true))
	hb2.add_child(take_button)
	leave_button = _button("置いていく", 24, 200, 72)
	leave_button.pressed.connect(func(): item_decided.emit(false))
	hb2.add_child(leave_button)

func _build_pause() -> void:
	var o := _overlay(0.65)
	pause_layer = o[0]
	var vb: VBoxContainer = o[1]
	vb.add_child(_label("一時停止", 44, Color("ffd166"), 10))
	pause_info = _label("", 19, Color("d8d0f0"))
	pause_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(pause_info)
	resume_button = _button("再開")
	resume_button.pressed.connect(func(): resume_requested.emit())
	vb.add_child(resume_button)
	var tb := _button("タイトルへ", 24, 300, 64)
	tb.pressed.connect(func(): title_requested.emit())
	vb.add_child(tb)

func _build_end() -> void:
	var o := _overlay(0.7)
	end_layer = o[0]
	var vb: VBoxContainer = o[1]
	end_title = _label("", 56, Color.WHITE, 12)
	vb.add_child(end_title)
	end_stats = _label("", 22, Color("e0d8f0"))
	vb.add_child(end_stats)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	retry_button = _button("もう一度", 30, 240, 76)
	retry_button.pressed.connect(func(): retry_requested.emit())
	hb.add_child(retry_button)
	end_title_button = _button("タイトルへ", 24, 200, 76)
	end_title_button.pressed.connect(func(): title_requested.emit())
	hb.add_child(end_title_button)

# ---------- 表示切替 ----------
func _hide_all() -> void:
	for l in [title_layer, levelup_layer, item_layer, pause_layer, end_layer]:
		l.visible = false

func show_title(best_text: String) -> void:
	_hide_all()
	title_layer.visible = true
	best_label.text = best_text
	hud.show_hud = false
	pause_button.visible = false
	touch.set_enabled(false)
	_guard([start_button], start_button)

func show_playing() -> void:
	_hide_all()
	hud.show_hud = true
	pause_button.visible = true
	touch.set_enabled(true)
	_on_resize()

func show_levelup(level: int, perks: Array) -> void:
	_hide_all()
	levelup_layer.visible = true
	levelup_title.text = "レベルアップ！  Lv %d" % level
	touch.set_enabled(false)
	for c in cards_holder.get_children():
		c.queue_free()
	cards.clear()
	var vs := root.size
	var box: BoxContainer = HBoxContainer.new() if vs.x > vs.y * 1.2 else VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_holder.add_child(box)
	for i in perks.size():
		var p: Dictionary = perks[i]
		var b := Button.new()
		var wide := vs.x > vs.y * 1.2
		b.text = ("\n%s\n%s" if wide else "%s\n%s") % [p["name"], p["desc"]]
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(230, 170) if wide else Vector2(420, 96)
		var ic := TextureRect.new()
		ic.texture = Art.tex(p["icon"])
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.size = Vector2(48, 48)
		ic.position = Vector2(91, 10) if wide else Vector2(14, 24)
		b.add_child(ic)
		var idx := i
		b.pressed.connect(func(): perk_chosen.emit(idx))
		box.add_child(b)
		cards.append(b)
	_guard(cards, cards[0] if cards.size() > 0 else null)

func show_item(item: Dictionary, current: Dictionary) -> void:
	_hide_all()
	item_layer.visible = true
	touch.set_enabled(false)
	item_icon.texture = Art.tex(item["slot"])
	item_name.text = item["name"]
	item_name.add_theme_color_override("font_color", Items.RARITY_COL[item["rarity"]])
	item_info.text = "%s ・ %s" % [Items.RARITY_NAME[item["rarity"]], Items.SLOT_NAME[item["slot"]]]
	item_stats.text = Items.describe(item)
	if current.is_empty():
		item_cur.text = "現在の%s: なし" % Items.SLOT_NAME[item["slot"]]
	else:
		item_cur.text = "現在: %s（%s）" % [current["name"], Items.describe(current)]
	var better: bool = current.is_empty() or item["score"] >= current["score"]
	take_button.text = "装備する" + ("▲" if better else "")
	_guard([take_button, leave_button], take_button if better else leave_button)

func show_pause(info: String) -> void:
	_hide_all()
	pause_layer.visible = true
	pause_info.text = info
	touch.set_enabled(false)
	_guard([resume_button], resume_button)

func show_end(won: bool, stats_text: String) -> void:
	_hide_all()
	end_layer.visible = true
	touch.set_enabled(false)
	pause_button.visible = false
	end_title.text = "ダンジョン制覇！" if won else "ゲームオーバー"
	end_title.add_theme_color_override("font_color", Color("ffd166") if won else Color("ff5a5a"))
	end_stats.text = stats_text
	_guard([retry_button, end_title_button], retry_button)
