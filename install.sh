#!/bin/bash
# 一键安装：部署运行文件到 ~/.display-switcher，下载 displayplacer，编译并安装 App
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.display-switcher"

mkdir -p "$DEST/bin" "$DEST/layouts"
cp "$REPO_DIR/layout.sh" "$REPO_DIR/preset.py" "$DEST/"
cp -R "$REPO_DIR/menubar" "$DEST/"
chmod +x "$DEST/layout.sh" "$DEST/menubar/build.sh"

if [ ! -x "$DEST/bin/displayplacer" ]; then
  if [ "$(uname -m)" = "arm64" ]; then
    ASSET=displayplacer-apple-v140
  else
    ASSET=displayplacer-intel-v140
  fi
  URL="https://github.com/jakehilborn/displayplacer/releases/download/v1.4.0/$ASSET"
  echo "下载 displayplacer…"
  curl -fL --connect-timeout 15 -o "$DEST/bin/displayplacer" "$URL" \
    || curl -fL -o "$DEST/bin/displayplacer" "https://gh-proxy.com/$URL"
  chmod +x "$DEST/bin/displayplacer"
fi

"$DEST/menubar/build.sh"
cp -R "$DEST/menubar/DisplaySwitcher.app" /Applications/
echo "安装完成。启动: open /Applications/DisplaySwitcher.app"