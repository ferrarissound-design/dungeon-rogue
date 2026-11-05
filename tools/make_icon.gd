extends SceneTree
## アイコン画像 (icon.png) を生成: godot --headless --path . -s tools/make_icon.gd
const Art := preload("res://scripts/art.gd")
func _init() -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color("1a1324"))
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(Vector2(64, 70)) / 64.0
			img.set_pixel(x, y, Color("1a1324").lerp(Color("4a2f6a"), clampf(1.0 - d, 0.0, 1.0)))
	var spr: Image = Art._img_from(Art.SPR["player"])
	spr.resize(96, 96, Image.INTERPOLATE_NEAREST)
	img.blend_rect(spr, Rect2i(0, 0, 96, 96), Vector2i(16, 18))
	var sw: Image = Art._img_from(Art.SPR["weapon"])
	sw.resize(64, 64, Image.INTERPOLATE_NEAREST)
	img.blend_rect(sw, Rect2i(0, 0, 64, 64), Vector2i(62, 4))
	img.save_png("res://icon.png")
	print("icon saved")
	quit()
