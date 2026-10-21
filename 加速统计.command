#!/bin/zsh
set -e
cd "${0:A:h}"
godot_binary="${GODOT_BIN:-/Users/bytedance/Downloads/Godot_mono.app/Contents/MacOS/Godot}"
if [[ ! -x "$godot_binary" ]]; then
  echo '找不到 Godot，请修改 GODOT_BIN 或脚本中的路径。'
  read -r '?按回车关闭。'
  exit 1
fi
echo '格子版：炮击压制对照七套配置，交换出生侧，共14场。'
"$godot_binary" --headless --path "$PWD" -- --batch-test
echo '完成。汇总：reports/grid-validation.json（每次覆盖）。'
read -r '?按回车关闭。'
