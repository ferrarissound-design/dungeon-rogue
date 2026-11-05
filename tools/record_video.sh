#!/usr/bin/env bash
# ゲームプレイ動画 out/gameplay.mp4 を撮影（DISPLAY=:4、自動プレイ）
# 1) 地下1階の探索・戦闘・宝箱  2) 地下3階（強敵・トゲ罠）  3) 最下層のボス戦  を連結
set -euo pipefail
cd "$(dirname "$0")/.."
export DISPLAY=${DISPLAY:-:4}
mkdir -p out
rec() { # $1=出力 $2=秒数 $3...=ゲーム引数
  local outf=$1 dur=$2; shift 2
  godot --path . --rendering-driver opengl3 --position 40,40 --resolution 1280x720 -- --autoplay --touchui "$@" >/tmp/rec_game.log 2>&1 &
  local gp=$!
  local wid=""
  for i in $(seq 1 60); do wid=$(xdotool search --pid $gp 2>/dev/null | tail -1 || true); [ -n "$wid" ] && break; sleep 0.5; done
  sleep 2.5
  local info; info=$(xwininfo -id "$wid")
  X=$(echo "$info" | awk '/Absolute upper-left X/{print $4}'); Y=$(echo "$info" | awk '/Absolute upper-left Y/{print $4}')
  WIDTH=$(echo "$info" | awk '/Width:/{print $2}'); HEIGHT=$(echo "$info" | awk '/Height:/{print $2}')
  WIDTH=$((WIDTH/2*2)); HEIGHT=$((HEIGHT/2*2))
  ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size ${WIDTH}x${HEIGHT} -i "$DISPLAY+$X,$Y" -t "$dur" \
    -vf "scale=1280:-2" -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p "$outf"
  kill $gp 2>/dev/null || true; wait $gp 2>/dev/null || true
}
rec /tmp/seg1.mp4 32 --seed=7
rec /tmp/seg2.mp4 30 --seed=8 --start-floor=3
rec /tmp/seg3.mp4 42 --seed=7 --start-floor=5
printf "file '/tmp/seg1.mp4'\nfile '/tmp/seg2.mp4'\nfile '/tmp/seg3.mp4'\n" > /tmp/segs.txt
ffmpeg -y -loglevel error -f concat -safe 0 -i /tmp/segs.txt -c copy out/gameplay.mp4
ls -la out/gameplay.mp4
