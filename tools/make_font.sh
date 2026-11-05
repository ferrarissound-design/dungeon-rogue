#!/bin/sh
# スクリプト内の文字 + かな/英数字 で Noto Sans CJK JP Bold をサブセット化 (Debian fonts-noto-cjk, SIL OFL 1.1)
set -e
cd "$(dirname "$0")/.."
cat scripts/*.gd | python3 -c "
import sys
s=set(sys.stdin.read())
s|=set(chr(c) for c in range(0x20,0x7f))
s|=set(chr(c) for c in range(0x3000,0x3100))
s|=set(chr(c) for c in range(0xff01,0xff5f))
s|=set('★☆♥♪→←↑↓・…ー〜！？「」')
open('/tmp/chars.txt','w').write(''.join(sorted(c for c in s if c>=' ')))
"
pyftsubset /usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc --font-number=0 --text-file=/tmp/chars.txt \
  --output-file=fonts/NotoSansJP-Bold-subset.otf --layout-features='*' --name-IDs='*' --notdef-outline
ls -la fonts/
