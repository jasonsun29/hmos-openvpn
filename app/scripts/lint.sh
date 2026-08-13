#!/usr/bin/env bash
#
# P2-15 hvigor lint 入口脚本
#
# 用途：
#   1) 被 scripts/install-hooks.sh 安装为 .git/hooks/pre-commit，提交前自动跑
#   2) 开发者手动调用：./scripts/lint.sh（CI 也用得上）
#
# 实现：
#   - 优先调用 hvigorw（项目根目录的 wrapper），保证 toolchain 一致
#   - 失败退出码非 0，pre-commit 会拒绝提交
#   - 加 set -e + set -o pipefail 防止 lint 失败被吞
#
# 注意：hvigor lint 在 HarmonyOS NEXT 工程中会扫描 entry + proxy_core 两个模块
#       的 .ets 源文件，按 code-linter.json5 规则执行（已包含 ets 检查/ArkTS 检查 等）

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

echo "[lint] running hvigor lint ..."
# hvigorw 是 HarmonyOS 标准的 hvigor wrapper（nodejs 实现）
# 若 hvigorw 不存在则尝试 hvigor（全局安装）
if [ -x "$ROOT_DIR/hvigorw" ]; then
  "$ROOT_DIR/hvigorw" lint --no-daemon
elif command -v hvigor >/dev/null 2>&1; then
  hvigor lint --no-daemon
else
  echo "[lint] WARN: hvigorw / hvigor not found, skip lint"
  echo "[lint] 在 DevEco Studio 工程里会自动跑 lint"
  exit 0
fi

echo "[lint] OK"