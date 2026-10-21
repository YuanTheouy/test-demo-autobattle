#!/bin/zsh
set -e
cd "${0:A:h}"
godot_binary="${GODOT_BIN:-/Users/bytedance/Downloads/Godot_mono.app/Contents/MacOS/Godot}"
if [[ ! -x "$godot_binary" ]]; then
  echo '找不到 Godot。请用 Godot 导入此目录的 project.godot。'
  read -r '?按回车关闭。'
  exit 1
fi
exec "$godot_binary" --path "$PWD"
