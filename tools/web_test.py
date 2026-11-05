"""Web版の自動ブラウザテスト（Playwright + Chromium）
使い方: python3 tools/web_test.py [URL] [出力ディレクトリ]
  - デスクトップ: 読み込み → タイトル → クリックで開始 → キー操作で移動・攻撃 → スクリーンショット
  - スマホ（タッチエミュレーション, 横持ち）: タップで開始 → スティックをドラッグ → 攻撃/回避ボタンをタップ
  - コンソールの致命的エラーを確認
"""
import sys, time, json
from playwright.sync_api import sync_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000/"
OUT = sys.argv[2] if len(sys.argv) > 2 else "out"
results = []

def check(name, ok, info=""):
    results.append((name, ok))
    print(("PASS " if ok else "FAIL ") + name + (f"  ({info})" if info else ""), flush=True)

def state(page):
    return page.evaluate("window.__dr || null")

def wait_state(page, pred, timeout=60):
    t0 = time.time()
    while time.time() - t0 < timeout:
        s = state(page)
        if s and pred(s):
            return s
        time.sleep(0.25)
    return state(page)

FATAL = ("Aborted", "RuntimeError", "SCRIPT ERROR", "Uncaught", "unreachable", "Failed to load", "out of memory")

def run(p, label, ctx_args, touch):
    browser = p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--autoplay-policy=no-user-gesture-required"])
    ctx = browser.new_context(**ctx_args)
    page = ctx.new_page()
    logs = []
    page.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
    page.on("pageerror", lambda e: logs.append(f"[pageerror] {e}"))
    page.goto(URL, wait_until="load", timeout=120000)
    s = wait_state(page, lambda s: s["state"] == "TITLE", 120)
    check(f"{label}: エンジン起動・タイトル表示", bool(s and s["state"] == "TITLE"), json.dumps(s, ensure_ascii=False))
    time.sleep(1.0)
    vw, vh = ctx_args["viewport"]["width"], ctx_args["viewport"]["height"]
    page.screenshot(path=f"{OUT}/web_{label}_title.png")
    if touch:
        cdp = ctx.new_cdp_session(page)
        def tp(typ, pts):
            cdp.send("Input.dispatchTouchEvent", {"type": typ, "touchPoints": [{"x": x, "y": y, "id": i} for (i, x, y) in pts]})
        # 開始ボタン付近（画面中央やや下）をタップ
        page.touchscreen.tap(vw / 2, vh * 0.62)
    else:
        page.mouse.click(vw / 2, vh * 0.62)
    s = wait_state(page, lambda s: s["state"] == "PLAYING", 15)
    check(f"{label}: 開始ボタンでゲーム開始", bool(s and s["state"] == "PLAYING"), json.dumps(s, ensure_ascii=False))
    time.sleep(1.5)
    s0 = state(page)
    if touch:
        # 左側でスティックを右へドラッグ（指を保持したまま攻撃ボタンもタップ = マルチタッチ）
        sx, sy = vw * 0.18, vh * 0.7
        tp("touchStart", [(0, sx, sy)])
        for k in range(1, 8):
            tp("touchMove", [(0, sx + k * 8, sy)])
            time.sleep(0.03)
        time.sleep(1.2)
        s1 = state(page)
        check(f"{label}: スティックで移動", s1 and abs(s1["x"] - s0["x"]) + abs(s1["y"] - s0["y"]) > 5, f"{s0['x']},{s0['y']} -> {s1['x']},{s1['y']}")
        portrait = vh > vw
        ax, ay = (vw * 0.805, vh * 0.898) if portrait else (vw * 0.895, vh * 0.80)   # 攻撃ボタン
        tp("touchMove", [(0, sx + 56, sy), (1, ax, ay)])
        time.sleep(0.15)
        tp("touchMove", [(0, sx + 56, sy)])  # 指1を離す
        time.sleep(0.5)
        s2 = state(page)
        check(f"{label}: 移動しながら攻撃ボタン（マルチタッチ）", s2["swings"] > s1["swings"], f"swings {s1['swings']} -> {s2['swings']}")
        tp("touchEnd", [])
        time.sleep(0.3)
        page.screenshot(path=f"{OUT}/web_{label}_play.png")
        # 回避ボタン（攻撃ボタンの左下）
        rx, ry = (vw * 0.57, vh * 0.933) if portrait else (vw * 0.765, vh * 0.868)
        page.touchscreen.tap(rx, ry)
        time.sleep(0.5)
        s3 = state(page)
        check(f"{label}: 回避ボタン", s3["rolls"] > s2["rolls"], f"rolls {s2['rolls']} -> {s3['rolls']}")
        check(f"{label}: タッチ操作ボタン表示", bool(s3["touch"]))
    else:
        check(f"{label}: PCではタッチボタン非表示", not s0["touch"])
        page.keyboard.down("d"); time.sleep(1.0); page.keyboard.up("d")
        s1 = state(page)
        check(f"{label}: キーボードで移動", abs(s1["x"] - s0["x"]) + abs(s1["y"] - s0["y"]) > 5, f"{s0['x']},{s0['y']} -> {s1['x']},{s1['y']}")
        page.keyboard.press("j"); time.sleep(0.4)
        page.keyboard.press("k"); time.sleep(0.4)
        s2 = state(page)
        check(f"{label}: 攻撃・回避キー", s2["swings"] > s1["swings"] and s2["rolls"] > s1["rolls"], json.dumps(s2))
        time.sleep(0.5)
        page.screenshot(path=f"{OUT}/web_{label}_play.png")
    fatal = [l for l in logs if any(f in l for f in FATAL) or l.startswith("[pageerror]")]
    errs = [l for l in logs if l.startswith("[error]")]
    check(f"{label}: 致命的なコンソールエラーなし", not fatal, "; ".join(fatal[:3]))
    with open(f"{OUT}/web_{label}_console.txt", "w") as f:
        f.write("\n".join(logs))
    print(f"  console lines={len(logs)} errors={len(errs)}: " + " | ".join(errs[:5]))
    browser.close()

with sync_playwright() as p:
    run(p, "desktop", {"viewport": {"width": 1280, "height": 720}}, False)
    iphone = dict(p.devices["iPhone 13 landscape"])
    iphone.pop("default_browser_type", None)
    run(p, "mobile", iphone, True)
    pix = dict(p.devices["Pixel 7"])  # 縦持ち
    pix.pop("default_browser_type", None)
    run(p, "portrait", pix, True)

ok = all(r[1] for r in results)
print("WEBTEST RESULT:", "ALL PASS" if ok else "FAILED")
sys.exit(0 if ok else 1)
