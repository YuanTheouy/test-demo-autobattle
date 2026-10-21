#!/bin/zsh
set -e
cd "${0:A:h}"
godot_binary="${GODOT_BIN:-/Users/bytedance/Downloads/Godot_mono.app/Contents/MacOS/Godot}"
if [[ ! -x "$godot_binary" ]]; then
  echo '找不到 Godot，请修改 GODOT_BIN 或脚本中的路径。'
  read -r '?按回车关闭。'
  exit 1
fi
sample_count="${1:-10}"
echo "示范两队生成 ${sample_count} 个部署样本，各交换出生侧再打一局。"
echo '使用原来的 1/60 秒模拟步长，跳过画面和真实等待；不改变战斗规则。'
"$godot_binary" --headless --path "$PWD" -- --batch-test "--samples=$sample_count"
echo '完成。汇总：reports/rules-batch.json（每次覆盖）。'
read -r '?按回车关闭。'
