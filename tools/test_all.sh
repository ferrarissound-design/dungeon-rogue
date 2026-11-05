#!/usr/bin/env bash
# 自動テスト一式: スクリプトエラー確認 / マップ生成検証 / オートプレイ（クリア・ゲームオーバー） / タッチ入力
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
run() { echo "== $1"; shift; out=$("$@" 2>&1); code=$?; echo "$out" | grep -E "SCRIPT ERROR|ERROR:|GENTEST|GAME END|TOUCHTEST|FLOOR" ; if echo "$out" | grep -q "SCRIPT ERROR"; then echo "!! script error"; fail=1; fi; echo "exit=$code"; return $code; }
run "起動チェック" godot --headless --path . --quit-after 120 || fail=1
run "マップ生成 300シード×5階" godot --headless --path . -- --gentest=300 || fail=1
run "オートプレイ（無敵）でクリアまで" godot --headless --path . -- --autoplay --god --autoquit --seed=11 --timescale=4 --maxtime=240 || fail=1
run "オートプレイ（HP1）でゲームオーバー" godot --headless --path . -- --autoplay --weak --autoquit --seed=12 --timescale=4 --maxtime=120; [ $? -eq 2 ] || fail=1
DISPLAY=${DISPLAY:-:4} run "タッチ入力テスト" godot --path . --rendering-driver opengl3 -- --touchtest || fail=1
echo "RESULT: $([ $fail -eq 0 ] && echo ALL PASS || echo FAILED)"
exit $fail
