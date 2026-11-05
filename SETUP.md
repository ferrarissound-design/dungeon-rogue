# SETUP — 開発環境の復元手順

## 動作確認済みバージョン

| ツール | バージョン |
|---|---|
| OS | Debian 13 (trixie) x86_64、GPUなし（Mesa llvmpipe） |
| Godot | 4.7.2.stable.official（`/usr/local/bin/godot`） |
| エクスポートテンプレート | 4.7.2.stable（`~/.local/share/godot/export_templates/4.7.2.stable/`） |
| レンダラー | gl_compatibility（Web/GPUなし環境向け） |
| fonttools (pyftsubset) | 4.65.0 |
| ffmpeg | Debian パッケージ版（動画撮影用） |
| Playwright (Python) + Chromium headless shell | 1.64.1 / Chromium 156（Web版の自動テスト用、任意） |
| gh (GitHub CLI) | リポジトリ作成・Pages 設定用 |

## 一発セットアップ

```bash
git clone https://github.com/ferrarissound-design/dungeon-rogue.git
cd dungeon-rogue
bash tools/setup_env.sh
```

`tools/setup_env.sh` は以下を行います（何度実行しても安全）:
1. apt ミラーを `cdn-fastly.deb.debian.org` に変更（`deb.debian.org` がプロキシ経由で失敗する環境向け）
2. unzip / curl / git / ffmpeg / Noto CJK フォント / Mesa などをインストール
3. fonttools（pyftsubset）をインストール
4. Godot 4.7.2 をダウンロード（SHA-512 検証）して `/usr/local/bin/godot` に配置
5. エクスポートテンプレートを配置
6. ヘッドレス起動で動作確認

## よく使うコマンド

```bash
# エディタ起動（画面 :4）
DISPLAY=:4 godot --editor --rendering-driver opengl3 --path .

# ゲーム起動
DISPLAY=:4 godot --path . --rendering-driver opengl3

# 自動テスト（起動・マップ生成1500件・自動プレイでクリア/ゲームオーバー・タッチ操作）
bash tools/test_all.sh

# Web / Windows / Linux 書き出し → docs/ にコピー（Web版のみなら WEB_ONLY=1）
bash tools/build_all.sh

# 日本語フォントのサブセット再生成（scripts/*.gd に新しい文字を追加したら実行）
bash tools/make_font.sh

# アイコン再生成
godot --headless --path . -s tools/make_icon.gd

# ローカルで Web 版を確認
python3 -m http.server 8000 -d docs

# Web 版のブラウザ自動テスト（Playwright + Chromium、PC/スマホ横/スマホ縦のタッチ操作を確認）
python3 -m venv /tmp/pwenv && /tmp/pwenv/bin/pip install playwright && /tmp/pwenv/bin/playwright install --with-deps chromium
/tmp/pwenv/bin/python tools/web_test.py http://localhost:8000/ out
/tmp/pwenv/bin/python tools/web_test.py https://ferrarissound-design.github.io/dungeon-rogue/ out/live

# ゲームプレイ動画 out/gameplay.mp4 の撮影（DISPLAY=:4）
bash tools/record_video.sh
```

## テスト用起動オプション（`--` の後ろに付ける）

| オプション | 内容 |
|---|---|
| `--autoplay` | ボットが自動でプレイ |
| `--god` | 無敵 |
| `--weak` | 最大HP1（ゲームオーバー確認用） |
| `--seed=N` | ダンジョンのシード固定 |
| `--timescale=N` | ゲーム速度倍率 |
| `--autoquit` | 終了時に自動終了（終了コード 0=クリア, 2=ゲームオーバー, 3=時間切れ） |
| `--maxtime=秒` | 制限時間（超えたら終了コード3） |
| `--start-floor=N` | N階から開始 |
| `--gentest=N` | Nシード×5階のマップ生成検証 |
| `--touchtest` | タッチ操作の自動テスト（ウィンドウ表示が必要） |
| `--shots` / `--shot-dir=パス` | 各場面のスクリーンショットを保存（既定 out/） |
| `--touchui` | PCでもタッチ操作ボタンを表示（撮影用） |

例: `DISPLAY=:4 godot --path . --rendering-driver opengl3 -- --autoplay --god --shots --autoquit --seed=5 --timescale=2`

## 公開（GitHub Pages）

- `main` ブランチの `/docs` を公開（`docs/.nojekyll` あり）
- 設定コマンド（初回のみ）:
  `gh api -X POST repos/ferrarissound-design/dungeon-rogue/pages -f "source[branch]=main" -f "source[path]=/docs"`
- Web 版はスレッド無効（`variant/thread_support=false`）なので、GitHub Pages のような COOP/COEP ヘッダーなしのホスティングで動作します。
