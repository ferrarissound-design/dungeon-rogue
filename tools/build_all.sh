#!/usr/bin/env bash
# Web / Windows / Linux を書き出し、Web版を docs/（GitHub Pages）にコピーする
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web build/windows build/linux out && touch build/.gdignore out/.gdignore
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --export-release "Web" build/web/index.html
if [ "${WEB_ONLY:-0}" != "1" ]; then
  godot --headless --path . --export-release "Windows" build/windows/dungeon-rogue.exe
  godot --headless --path . --export-release "Linux" build/linux/dungeon-rogue.x86_64
fi
rm -rf docs && cp -r build/web docs && rm -f docs/*.import && touch docs/.nojekyll docs/.gdignore
echo "書き出し完了。公開するには: git add -A && git commit -m 'update build' && git push"
