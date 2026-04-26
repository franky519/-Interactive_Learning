#!/usr/bin/env bash
# sync-agents.sh — 将 AGENTS.md 作为 single source of truth，
# 自动为所有 AI 编码工具创建/修复对应的 symlink。
#
# 用法：
#   ./sync-agents.sh          # 扫描当前目录树，创建/修复 symlink
#   ./sync-agents.sh --check  # 仅检查，不修改（适合 CI / git hook）
#   ./sync-agents.sh --clean  # 删除所有自动生成的 symlink
#
# 映射关系（在此处添加新工具）：
#   AGENTS.md  →  CLAUDE.md      (Claude Code)
#   AGENTS.md  →  COPILOT.md     (GitHub Copilot, 预留)
#
# 如果将来 Gemini / Codex 用了不同文件名，在 TARGETS 数组里加一行即可。

set -euo pipefail

# ─── 配置 ──────────────────────────────────────────────
SOURCE="AGENTS.md"
TARGETS=("CLAUDE.md")   # 需要 symlink 的目标文件名
# ───────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-sync}"
ISSUES=0

color_green="\033[32m"
color_yellow="\033[33m"
color_red="\033[31m"
color_reset="\033[0m"

log_ok()   { printf "${color_green}  ✓${color_reset} %s\n" "$1"; }
log_warn() { printf "${color_yellow}  ⚠${color_reset} %s\n" "$1"; }
log_err()  { printf "${color_red}  ✗${color_reset} %s\n" "$1"; ISSUES=$((ISSUES + 1)); }
log_info() { printf "  ℹ %s\n" "$1"; }

# 找到所有 AGENTS.md
find_sources() {
  find "$ROOT_DIR" -name "$SOURCE" -not -path '*/\.*' | sort
}

do_sync() {
  echo "🔄 Syncing symlinks (source: $SOURCE)..."
  echo ""

  while IFS= read -r src; do
    dir="$(dirname "$src")"
    rel_dir="${dir#"$ROOT_DIR"}"
    [ -z "$rel_dir" ] && rel_dir="/"

    for target in "${TARGETS[@]}"; do
      target_path="$dir/$target"

      if [ -L "$target_path" ]; then
        # 已经是 symlink，检查是否指向正确
        link_target="$(readlink "$target_path")"
        if [ "$link_target" = "$SOURCE" ]; then
          log_ok "$rel_dir/$target → $SOURCE"
        else
          # 指向错误，修复
          rm "$target_path"
          ln -s "$SOURCE" "$target_path"
          log_warn "$rel_dir/$target: 修复（旧指向: $link_target）"
        fi
      elif [ -f "$target_path" ]; then
        # 是普通文件（可能是 symlink 被打断了）
        if diff -q "$src" "$target_path" > /dev/null 2>&1; then
          # 内容一致，安全替换为 symlink
          rm "$target_path"
          ln -s "$SOURCE" "$target_path"
          log_warn "$rel_dir/$target: 普通文件→symlink（内容一致，已替换）"
        else
          # 内容不一致，不敢动，报警
          log_err "$rel_dir/$target: 普通文件且内容不同于 $SOURCE！请手动处理"
        fi
      else
        # 不存在，创建
        ln -s "$SOURCE" "$target_path"
        log_ok "$rel_dir/$target → $SOURCE（新建）"
      fi
    done
  done < <(find_sources)

  echo ""
  if [ $ISSUES -gt 0 ]; then
    echo "⚠️  有 $ISSUES 个问题需要手动处理"
    exit 1
  else
    echo "✅ 全部同步完成"
  fi
}

do_check() {
  echo "🔍 检查 symlink 状态..."
  echo ""

  while IFS= read -r src; do
    dir="$(dirname "$src")"
    rel_dir="${dir#"$ROOT_DIR"}"
    [ -z "$rel_dir" ] && rel_dir="/"

    for target in "${TARGETS[@]}"; do
      target_path="$dir/$target"

      if [ -L "$target_path" ]; then
        link_target="$(readlink "$target_path")"
        if [ "$link_target" = "$SOURCE" ]; then
          log_ok "$rel_dir/$target → $SOURCE"
        else
          log_err "$rel_dir/$target: 指向 $link_target（应为 $SOURCE）"
        fi
      elif [ -f "$target_path" ]; then
        log_err "$rel_dir/$target: 是普通文件，不是 symlink"
      else
        log_err "$rel_dir/$target: 不存在"
      fi
    done
  done < <(find_sources)

  echo ""
  if [ $ISSUES -gt 0 ]; then
    echo "❌ 有 $ISSUES 个问题"
    exit 1
  else
    echo "✅ 全部正常"
  fi
}

do_clean() {
  echo "🧹 清理自动生成的 symlink..."
  echo ""

  while IFS= read -r src; do
    dir="$(dirname "$src")"
    rel_dir="${dir#"$ROOT_DIR"}"
    [ -z "$rel_dir" ] && rel_dir="/"

    for target in "${TARGETS[@]}"; do
      target_path="$dir/$target"

      if [ -L "$target_path" ]; then
        rm "$target_path"
        log_ok "$rel_dir/$target: 已删除"
      elif [ -f "$target_path" ]; then
        log_warn "$rel_dir/$target: 是普通文件，跳过"
      fi
    done
  done < <(find_sources)

  echo ""
  echo "✅ 清理完成"
}

case "$MODE" in
  sync|--sync|-s)   do_sync ;;
  check|--check|-c) do_check ;;
  clean|--clean)    do_clean ;;
  *)
    echo "用法: $0 [sync|check|clean]"
    echo "  sync   创建/修复 symlink（默认）"
    echo "  check  仅检查，不修改"
    echo "  clean  删除所有自动生成的 symlink"
    exit 1
    ;;
esac
