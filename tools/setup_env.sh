#!/usr/bin/env bash
# 深淵の剣士（dungeon-rogue）開発環境セットアップ（Debian 13 trixie / x86_64 / GPUなし のクラウドPC向け）
# 使い方: bash tools/setup_env.sh
# 何度実行しても安全（入っているものはスキップ）
set -euo pipefail
ROOT="$(cd "$ROOT" && pwd)"

GODOT_VER="4.7.2"
GODOT_TAG="${GODOT_VER}-stable"
GODOT_ZIP="Godot_v${GODOT_TAG}_linux.x86_64.zip"
TPL_FILE="Godot_v${GODOT_TAG}_export_templates.tpz"
GODOT_SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
TPL_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
BASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}"
TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VER}.stable"

echo "== 1. apt ミラー修正（deb.debian.org がプロキシ経由で失敗するため）"
SRC=/etc/apt/sources.list.d/debian.sources
if [ -f "$SRC" ] && grep -q "deb.debian.org" "$SRC"; then
  sudo cp -n "$SRC" /root/debian.sources.bak || true
  sudo sed -i 's#http://deb.debian.org#https://cdn-fastly.deb.debian.org#g; s#https://deb.debian.org#https://cdn-fastly.deb.debian.org#g' "$SRC"
fi

echo "== 2. apt パッケージ"
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  unzip curl git ffmpeg p7zip-full fonts-noto-cjk python3-pip \
  libgl1-mesa-dri libvulkan1 mesa-vulkan-drivers libasound2t64

echo "== 3. fonttools（日本語フォントのサブセット化用 pyftsubset）"
if ! command -v pyftsubset >/dev/null; then
  sudo pip install --break-system-packages "fonttools==4.65.0" || sudo apt-get install -y -q fonttools
fi

echo "== 4. Godot ${GODOT_VER}"
if ! command -v godot >/dev/null || ! godot --version 2>/dev/null | grep -q "^${GODOT_VER}.stable"; then
  cd /tmp
  curl -fL -o "$GODOT_ZIP" "$BASE_URL/$GODOT_ZIP"
  echo "$GODOT_SHA512  $GODOT_ZIP" | sha512sum -c -
  sudo mkdir -p /opt/godot
  sudo unzip -o -q "$GODOT_ZIP" -d /opt/godot
  sudo chmod +x "/opt/godot/Godot_v${GODOT_TAG}_linux.x86_64"
  sudo ln -sf "/opt/godot/Godot_v${GODOT_TAG}_linux.x86_64" /usr/local/bin/godot
  rm -f "$GODOT_ZIP"
fi
godot --version

echo "== 5. エクスポートテンプレート"
if [ ! -f "$TPL_DIR/web_nothreads_release.zip" ]; then
  cd /tmp
  curl -fL -o "$TPL_FILE" "$BASE_URL/$TPL_FILE"
  echo "$TPL_SHA512  $TPL_FILE" | sha512sum -c -
  rm -rf /tmp/godot_tpl && mkdir -p /tmp/godot_tpl "$TPL_DIR"
  unzip -q "$TPL_FILE" -d /tmp/godot_tpl
  cp -r /tmp/godot_tpl/templates/* "$TPL_DIR/"
  rm -rf /tmp/godot_tpl "$TPL_FILE"
fi
ls "$TPL_DIR" | head

echo "== 6. 動作確認（ヘッドレス起動）"
cd "$ROOT"
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --quit-after 120 2>&1 | tail -3

echo "完了。エディタ起動: DISPLAY=:4 godot --editor --rendering-driver opengl3 --path $(pwd)"
