#!/bin/zsh
set -e
cd "${0:A:h}"
godot_binary="${GODOT_BIN:-/Users/bytedance/Downloads/Godot_mono.app/Contents/MacOS/Godot}"
if [[ ! -x "$godot_binary" ]]; then
  echo '找不到 Godot，请修改 GODOT_BIN 或脚本中的路径。'
  read -r '?按回车关闭。'
  exit 1
fi
echo '即时竞技场：风火轰鸣对照九套配置，交换出生侧，共18场。'
"$godot_binary" --headless --path "$PWD" -- --arena-test
echo '完成。汇总：reports/arena-validation.json（每次覆盖）。'
read -r '?按回车关闭。'
