extends Node
## ゲーム全体の状態管理 + テスト用の各種モード
## ユーザー引数（godot ... -- の後ろ）:
##   --autoplay        BOTが自動でプレイ
##   --god             無敵（BOTで最後まで通すため）
##   --weak            HP1で開始（ゲームオーバー画面の確認用）
##   --seed=N          ランのシード
##   --timescale=X     ゲーム速度
##   --autoquit        リザルト画面が出たら終了（終了コード 0=クリア 2=ゲームオーバー）
##   --gentest=N       N個のシード×全階層のマップ生成を検証して終了
##   --touchtest       タッチ入力の自己テスト
##   --shots           スクリーンショットを out/ に保存
##   --start-floor=N   N階から開始
##   --maxtime=SEC     実時間の上限（超えたら終了コード 3）

enum State { TITLE, PLAYING, LEVELUP, ITEM, PAUSED, GAMEOVER, CLEAR }

const GameScript := preload("res://scripts/game.gd")
const UIScript := preload("res://scripts/ui.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const BotScript := preload("res://scripts/bot.gd")
const Items := preload("res://scripts/items.gd")
const Dungeon := preload("res://scripts/dungeon.gd")
const SAVE_PATH := "user://save.cfg"

var state := State.TITLE
var game
var ui
var sfx
var bot
var perk_choices: Array = []
var best_time := -1.0
var clears := 0
var touch_mode := false

var autoplay := false
var god := false
var weak := false
var seed_arg := -1
var timescale := 1.0
var autoquit := false
var gentest := 0
var touchtest := false
var take_shots := false
var start_floor := 1
var maxtime := 0.0
var shot_dir := ""
var shots_done := {}
var real_t := 0.0
var state_t := 0.0
var last_floor_logged := 0

func _ready() -> void:
	_parse_args()
	if gentest > 0:
		_run_gentest()
		return
	_setup_input()
	_load_save()
	Engine.time_scale = timescale
	sfx = SfxScript.new()
	add_child(sfx)
	game = GameScript.new()
	game.sfx = sfx
	game.god = god
	game.weak = weak
	add_child(game)
	game.died.connect(func(): _end(false))
	game.won.connect(func(): _end(true))
	game.floor_started.connect(_on_floor_started)
	game.message.connect(func(t, c): ui.hud.show_banner(t, c, 2.4))
	ui = UIScript.new()
	add_child(ui)
	ui.hud.game = game
	ui.start_requested.connect(start_game)
	ui.retry_requested.connect(start_game)
	ui.title_requested.connect(go_title)
	ui.perk_chosen.connect(_on_perk)
	ui.item_decided.connect(_on_item)
	ui.pause_requested.connect(toggle_pause)
	ui.resume_requested.connect(toggle_pause)
	bot = BotScript.new()
	touch_mode = _detect_touch() or touchtest or OS.get_cmdline_user_args().has("--touchui")
	ui.touch.visible_controls = touch_mode
	get_window().size_changed.connect(_update_scale)
	_update_scale()
	go_title()
	if touchtest:
		_run_touchtest()

func _parse_args() -> void:
	shot_dir = ProjectSettings.globalize_path("res://out")
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a == "--autoplay": autoplay = true
		elif a == "--god": god = true
		elif a == "--weak": weak = true
		elif a == "--autoquit": autoquit = true
		elif a == "--touchtest": touchtest = true
		elif a == "--shots": take_shots = true
		elif a.begins_with("--seed="): seed_arg = v.to_int()
		elif a.begins_with("--timescale="): timescale = v.to_float()
		elif a.begins_with("--gentest="): gentest = v.to_int()
		elif a.begins_with("--start-floor="): start_floor = v.to_int()
		elif a.begins_with("--maxtime="): maxtime = v.to_float()
		elif a.begins_with("--shot-dir="): shot_dir = v

func _add_action(act: String, keys: Array, joy: Array) -> void:
	if not InputMap.has_action(act):
		InputMap.add_action(act, 0.3)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(act, ev)
	for j in joy:
		var jb := InputEventJoypadButton.new()
		jb.button_index = j
		InputMap.action_add_event(act, jb)

func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN])
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0], "move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	for act in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axes[act][0]
		jm.axis_value = axes[act][1]
		InputMap.action_add_event(act, jm)
	_add_action("attack", [KEY_J, KEY_Z, KEY_SPACE], [JOY_BUTTON_A, JOY_BUTTON_X])
	_add_action("dodge", [KEY_K, KEY_X, KEY_SHIFT], [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("potion", [KEY_Q, KEY_C], [JOY_BUTTON_Y])

func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_time = float(cf.get_value("record", "best_time", -1.0))
		clears = int(cf.get_value("record", "clears", 0))

func _save() -> void:
	if autoplay or touchtest:
		return
	var cf := ConfigFile.new()
	cf.set_value("record", "best_time", best_time)
	cf.set_value("record", "clears", clears)
	cf.save(SAVE_PATH)

func _set_state(s: State) -> void:
	state = s
	state_t = 0.0

## 縦画面では基準解像度を小さくしてUIを大きく見せる。カメラのズームも画面に合わせる
func _update_scale() -> void:
	var ws := get_window().size
	var portrait := ws.y > ws.x
	var base := 540 if not portrait else 500
	get_window().content_scale_size = Vector2i(base, base)
	await get_tree().process_frame
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var z := clampf(minf(vs.x, vs.y) / 200.0, 2.0, 4.0)
	game.camera.zoom = Vector2(z, z)

func _fmt_time(t: float) -> String:
	return "%d分%02d秒" % [int(t) / 60, int(t) % 60]

# ---------- 状態遷移 ----------
func go_title() -> void:
	_set_state(State.TITLE)
	game.new_run(randi())
	game.fade = 0.0
	game.hide_player = true
	game.queue_redraw()
	var best := "最速クリア: %s（クリア %d回）" % [_fmt_time(best_time), clears] if best_time > 0.0 else "地下5階に潜む魔王を倒せ！"
	ui.show_title(best)
	ui.set_controls_hint(touch_mode)
	sfx.play_bgm("dungeon")

func start_game() -> void:
	var s := seed_arg if seed_arg >= 0 else randi()
	print("RUN START seed=", s)
	game.new_run(s)
	if start_floor > 1:
		for i in range(1, start_floor):
			game.gain_xp(25 * i)
			game.equip_item(Items.make_item(game.rng, i, "weapon"))
			game.equip_item(Items.make_item(game.rng, i, "armor"))
		for i in game.pending_levelups:
			game.apply_perk(Items.PERKS[i % 3]["id"])
		game.pending_levelups = 0
		game.php = game.st["maxhp"]
		game.start_floor(start_floor)
	_set_state(State.PLAYING)
	ui.show_playing()
	sfx.play("start", 0.0)

func _on_floor_started(n: int) -> void:
	print("FLOOR ", n, " rooms=", game.dun.rooms.size(), " enemies=", game.enemies.size(), " chests=", game.chests.size(), " t=", snappedf(game.time, 0.1))
	if ui == null:
		return
	if n < game.FLOORS:
		ui.hud.show_banner("地下%d階" % n, Color(1.0, 0.88, 0.5), 2.2, "階段を探して下へ進め")
		sfx.play_bgm("dungeon")
	else:
		ui.hud.show_banner("最下層", Color(1.0, 0.4, 0.35), 2.6, "魔王の気配がする…")
		sfx.play_bgm("boss")

func toggle_pause() -> void:
	if state == State.PLAYING:
		_set_state(State.PAUSED)
		ui.show_pause(_status_text())
	elif state == State.PAUSED:
		_set_state(State.PLAYING)
		ui.show_playing()

func _status_text() -> String:
	var s: Dictionary = game.st
	var lines := []
	lines.append("Lv %d　HP %d/%d　攻撃 %d　防御 %d" % [game.level, ceili(game.php), roundi(s["maxhp"]), roundi(s["atk"]), roundi(s["def"])])
	lines.append("会心 %d%%　攻速 +%d%%　移動 +%d%%" % [roundi(s["crit"] * 100), roundi(s["aspd"] * 100), roundi(s["spd"] * 100)])
	for slot in ["weapon", "armor", "accessory"]:
		var it: Dictionary = game.equip[slot]
		lines.append("%s: %s" % [Items.SLOT_NAME[slot], "なし" if it.is_empty() else "%s（%s）" % [it["name"], Items.describe(it)]])
	return "\n".join(lines)

func _open_levelup() -> void:
	_set_state(State.LEVELUP)
	perk_choices = Items.roll_perks(game.rng, 3)
	ui.show_levelup(game.level - game.pending_levelups + 1, perk_choices)
	sfx.play("levelup", 0.0)

func _on_perk(i: int) -> void:
	if state != State.LEVELUP or i >= perk_choices.size():
		return
	game.apply_perk(perk_choices[i]["id"])
	print("PERK ", perk_choices[i]["id"], " lv=", game.level)
	game.pending_levelups -= 1
	sfx.play("click", 0.0)
	if game.pending_levelups > 0:
		_open_levelup()
	else:
		_set_state(State.PLAYING)
		ui.show_playing()

func _open_item() -> void:
	_set_state(State.ITEM)
	var it: Dictionary = game.pending_item
	ui.show_item(it, game.equip[it["slot"]])

func _on_item(take: bool) -> void:
	if state != State.ITEM:
		return
	var it: Dictionary = game.pending_item
	if take:
		game.equip_item(it)
		sfx.play("pickup", 0.0)
	print("ITEM ", it["name"], " ", Items.describe(it), " take=", take)
	game.pending_item = {}
	_set_state(State.PLAYING)
	ui.show_playing()

func _end(won: bool) -> void:
	var t: float = game.time
	var new_best := false
	if won:
		clears += 1
		if best_time < 0.0 or t < best_time:
			best_time = t
			new_best = true
		_save()
	print("GAME END won=", won, " time=", snappedf(t, 0.1), " floor=", game.floor_num, " level=", game.level, " kills=", game.kills, " dmg_taken=", game.stats_log["dmg_taken"])
	_set_state(State.CLEAR if won else State.GAMEOVER)
	var lines := []
	if won:
		lines.append("深淵の魔王は倒れ、迷宮に光が戻った。")
	else:
		lines.append("%s で力尽きた…" % ("地下%d階" % game.floor_num if game.floor_num < game.FLOORS else "最下層"))
	lines.append("")
	lines.append("プレイ時間　%s%s" % [_fmt_time(t), "　★最速記録！" if new_best else ""])
	lines.append("レベル　%d　　撃破数　%d　　宝箱　%d" % [game.level, game.kills, game.stats_log["chests"]])
	lines.append("武器: %s" % (game.equip["weapon"].get("name", "なし")))
	ui.show_end(won, "\n".join(lines))
	sfx.stop_bgm()
	sfx.play("clear" if won else "die", 0.0)

func _unhandled_input(event: InputEvent) -> void:
	var pause_key: bool = (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_P)) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START)
	if pause_key and (state == State.PLAYING or state == State.PAUSED):
		toggle_pause()
		get_viewport().set_input_as_handled()

# ---------- ループ ----------
var _web_t := 0.0

## タッチ端末かどうか（PCではタッチボタンを隠す。最初に画面に触れた時点でも表示される）
func _detect_touch() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("(navigator.maxTouchPoints > 0) && window.matchMedia('(pointer: coarse)').matches", true)
		return bool(r)
	return false

## Web版: 自動ブラウザテスト用に状態を window.__dr へ公開（読み取り専用の情報のみ）
func _web_report(delta: float) -> void:
	_web_t += delta
	if _web_t < 0.25:
		return
	_web_t = 0.0
	var d := {"state": State.keys()[state], "floor": game.floor_num, "x": snappedf(game.ppos.x, 0.1), "y": snappedf(game.ppos.y, 0.1),
		"hp": game.php, "level": game.level, "swings": game.stats_log.get("swings", 0), "rolls": game.stats_log.get("rolls", 0),
		"potions": game.potions, "touch": ui.touch.visible_controls}
	JavaScriptBridge.eval("window.__dr = " + JSON.stringify(d) + ";", true)

func _process(delta: float) -> void:
	real_t += delta / maxf(Engine.time_scale, 0.001)
	if OS.has_feature("web"):
		_web_report(delta)
	state_t += delta
	if maxtime > 0.0 and real_t > maxtime:
		print("MAXTIME exceeded state=", state, " floor=", game.floor_num)
		get_tree().quit(3)
		return
	match state:
		State.TITLE:
			if (autoplay or take_shots) and state_t > 1.2:
				if take_shots and not shots_done.has("title"):
					_shot("title")
				elif autoplay:
					start_game()
		State.PLAYING:
			_gather_input()
			if autoplay:
				bot.think(game, delta)
				ui.touch.sim_vec = game.in_move if touch_mode else Vector2.ZERO
			ui.touch.potion_count = game.potions
			ui.touch.roll_ready = clampf(1.0 - game.roll_cd / 0.62, 0.0, 1.0)
			game.step(delta)
			if state == State.PLAYING:
				if not game.pending_item.is_empty():
					_open_item()
				elif game.pending_levelups > 0 and game.alive:
					_open_levelup()
		State.LEVELUP:
			if autoplay and state_t > 0.5:
				_on_perk(randi() % perk_choices.size())
		State.ITEM:
			if autoplay and state_t > 0.5:
				_on_item(game.pending_item["score"] >= game.equip[game.pending_item["slot"]].get("score", -1.0))
		State.GAMEOVER, State.CLEAR:
			if autoquit and state_t > 1.5:
				if take_shots and not shots_done.has("end"):
					_shot("end_" + ("clear" if state == State.CLEAR else "gameover"))
					shots_done["end"] = true
				elif state_t > 2.0:
					get_tree().quit(0 if state == State.CLEAR else 2)
	if take_shots:
		_check_shots()

func _gather_input() -> void:
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var tv: Vector2 = ui.touch.get_vector()
	if tv != Vector2.ZERO:
		mv = tv
	var tc: Dictionary = ui.touch.consume()
	game.in_move = mv
	game.in_attack = Input.is_action_pressed("attack") or ui.touch.attack_held
	game.in_attack_pressed = Input.is_action_just_pressed("attack") or tc["attack"]
	game.in_dodge = Input.is_action_just_pressed("dodge") or tc["dodge"]
	game.in_potion = Input.is_action_just_pressed("potion") or tc["potion"]

# ---------- スクリーンショット ----------
func _check_shots() -> void:
	if state == State.PLAYING:
		if game.floor_num != last_floor_logged and game.floor_time > 6.0:
			last_floor_logged = game.floor_num
			_shot("floor%d" % game.floor_num)
		if game.boss_active and game.boss and not shots_done.has("boss") and game.boss.state != "intro" and game.boss.t > 0.5:
			_shot("boss")
		if game.boss and game.boss.phase == 2 and not shots_done.has("boss2") and game.boss.state != "enrage" and game.bullets.size() > 8:
			_shot("boss2")
	if state == State.LEVELUP and state_t > 0.4 and not shots_done.has("levelup"):
		_shot("levelup")
	if state == State.ITEM and state_t > 0.4 and not shots_done.has("item"):
		_shot("item")

func _shot(name: String) -> void:
	shots_done[name] = true
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var path := shot_dir.path_join(name + ".png")
	img.save_png(path)
	print("SHOT saved ", path, " ", img.get_size())

# ---------- マップ生成テスト ----------
func _run_gentest() -> void:
	var fails := 0
	var total := 0
	var t0 := Time.get_ticks_msec()
	for s in gentest:
		for f in range(1, 6):
			var d = Dungeon.new()
			var ok := false
			var msg := ""
			for attempt in 20:
				d.generate(s * 7919 + f * 104729 + attempt, f, f == 5)
				msg = d.validate()
				if msg == "":
					ok = true
					break
			total += 1
			if not ok:
				fails += 1
				print("GENTEST FAIL seed=", s, " floor=", f, " ", msg)
			elif f < 5:
				var dist: PackedInt32Array = d.bfs(d.start_cell)
				if dist[d.idx(d.stairs_cell)] < 10:
					print("GENTEST WARN short stairs seed=", s, " floor=", f, " d=", dist[d.idx(d.stairs_cell)])
	print("GENTEST total=%d fails=%d ms=%d" % [total, fails, Time.get_ticks_msec() - t0])
	get_tree().quit(0 if fails == 0 else 1)

# ---------- タッチ自己テスト ----------
func _to_window(canvas_pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * canvas_pos

func _touch(idx: int, canvas_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = _to_window(canvas_pos)
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _drag(idx: int, canvas_pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = _to_window(canvas_pos)
	ev.relative = rel
	Input.parse_input_event(ev)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _tap(c: Vector2) -> void:
	_touch(0, c, true)
	await _frames(2)
	_touch(0, c, false)
	await _frames(4)

func _run_touchtest() -> void:
	var results := []
	await _frames(30)
	var vs := get_viewport().get_visible_rect().size
	print("TOUCHTEST viewport=", vs, " window=", DisplayServer.window_get_size())
	# 1) スタートボタンをタップ
	await _tap(ui.start_button.get_global_rect().get_center())
	results.append(["タップでスタート", state == State.PLAYING])
	game.god = true
	for e in game.enemies:
		e.aggro = false
		e.dead = true
	await _frames(5)
	# 2) 左側ドラッグで移動
	var p0: Vector2 = game.ppos
	var o := Vector2(vs.x * 0.2, vs.y * 0.7)
	_touch(0, o, true)
	await _frames(2)
	for i in 16:
		_drag(0, o + Vector2(0, -(i + 1) * 5.0), Vector2(0, -5))
		await _frames(1)
	await _frames(20)
	var moved: float = p0.distance_to(game.ppos)
	var sv: Vector2 = ui.touch.get_vector()
	results.append(["スティックで移動 (移動量=%.1f, stick=%s)" % [moved, str(sv)], moved > 15.0 and sv.y < -0.8])
	if take_shots:
		_shot("touch_stick")
		await _frames(3)
	# 3) マルチタッチ: スティックを押したまま攻撃ボタン
	var ac: Vector2 = ui.touch.buttons["attack"]["c"]
	var swings_before: int = game.combo
	_touch(1, ac, true)
	await _frames(3)
	var swung: bool = game.swing_t > 0.0 or game.atk_cd > 0.0
	var still_stick: bool = ui.touch.get_vector() != Vector2.ZERO
	_touch(1, ac, false)
	await _frames(3)
	results.append(["マルチタッチ: 移動しながら攻撃 (swing=%s stick=%s)" % [swung, still_stick], swung and still_stick])
	# 4) 回避ボタン
	await _frames(20)
	var dc: Vector2 = ui.touch.buttons["dodge"]["c"]
	_touch(2, dc, true)
	await _frames(2)
	var rolled: bool = game.roll_t > 0.0 or game.roll_cd > 0.0
	_touch(2, dc, false)
	results.append(["マルチタッチ: 移動しながら回避", rolled])
	# 5) 指を離すと停止
	_touch(0, o + Vector2(0, -80), false)
	await _frames(30)
	var p1: Vector2 = game.ppos
	await _frames(10)
	results.append(["指を離すと停止", game.ppos.distance_to(p1) < 0.5])
	# 6) 回復薬ボタン
	game.php = 5.0
	game.potions = 1
	var pc: Vector2 = ui.touch.buttons["potion"]["c"]
	await _tap(pc)
	results.append(["回復薬ボタン", game.potions == 0 and game.php > 5.0])
	# 7) 一時停止 → 再開
	await _tap(ui.pause_button.get_global_rect().get_center())
	var paused := state == State.PAUSED
	await _frames(30)
	await _tap(ui.resume_button.get_global_rect().get_center())
	results.append(["一時停止と再開ボタン", paused and state == State.PLAYING])
	# 8) レベルアップカードをタップ
	game.gain_xp(game.xp_need())
	await _frames(40)
	var ok8 := false
	if state == State.LEVELUP and ui.cards.size() == 3:
		if take_shots:
			_shot("touch_levelup")
			await _frames(3)
		await _tap(ui.cards[1].get_global_rect().get_center())
		ok8 = state == State.PLAYING
	results.append(["レベルアップカードをタップ", ok8])
	# 9) 宝箱の装備ボタン
	game.pending_item = Items.make_item(game.rng, 2, "weapon")
	await _frames(40)
	var ok9 := false
	if state == State.ITEM:
		await _tap(ui.take_button.get_global_rect().get_center())
		ok9 = state == State.PLAYING and game.equip["weapon"]["name"] != "古びた剣"
	results.append(["宝箱の『装備する』ボタン", ok9])
	var all_ok := true
	for r in results:
		print("TOUCHTEST ", "PASS" if r[1] else "FAIL", " - ", r[0])
		all_ok = all_ok and r[1]
	print("TOUCHTEST RESULT: ", "ALL PASS" if all_ok else "FAILED")
	get_tree().quit(0 if all_ok else 1)
