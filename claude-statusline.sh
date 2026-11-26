#!/usr/bin/env bash
# Claude Code 状态栏：模型 · 目录 · git 分支 · 上下文 · 5h/7d 额度 · Code Mode · 登录账号
# stdin 是 Claude Code 传来的会话 JSON，输出一行文字。颜色用 256 色里偏柔和的色号。
# 依赖：bash、jq、git。Linux 和 macOS 都能用。
# 安装：放到 ~/.claude/statusline.sh 并 chmod +x，在 ~/.claude/settings.json 里加
#   "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }

input=$(cat)
command -v jq >/dev/null 2>&1 || { printf 'statusline: jq missing'; exit 0; }
g() { printf '%s' "$input" | jq -r "$1 // empty"; }

SEP=$' \033[2m·\033[0m '
s=''
add() { s="${s:+$s$SEP}$1"; }
# 上色：col 色号(0-255) 文字 [bold]
col() { local b=''; [ -n "$3" ] && b='1;'; printf '\033[%s38;5;%sm%s\033[0m' "$b" "$1" "$2"; }

# 进度条：bar 名称 百分比 色号 → "名称 ▓▓▓░░░░░ 38%"
# 每项固定一个颜色；≥85% 时进度条和数字整项变红
bar() {
  local label=$1 pct w=8 n i out=''
  pct=$(printf '%.0f' "$2")
  [ "$pct" -gt 100 ] && pct=100
  n=$(( (pct * w + 50) / 100 ))
  # 一格是 12.5%，四舍五入会让 1%~6% 显示成空条；只要不是 0 就至少亮一格
  [ "$pct" -gt 0 ] && [ "$n" -lt 1 ] && n=1
  for ((i = 0; i < w; i++)); do
    if [ "$i" -lt "$n" ]; then out+='▓'; else out+='░'; fi
  done
  if [ "$pct" -ge 85 ]; then
    printf '%s' "$(col 167 "$label $out $pct%")"
  else
    printf '%s %s %s' "$label" "$(col "$3" "$out")" "$pct%"
  fi
}

# 模型：Opus 绿、Fable 橙、Sonnet 蓝、Haiku 淡紫红，其它灰
m=$(g .model.display_name)
mid=$(g .model.id)
if [ -n "$m" ]; then
  case "$(printf '%s %s' "$m" "$mid" | tr '[:upper:]' '[:lower:]')" in
    *opus*)   mc=108 ;;
    *fable*)  mc=173 ;;
    *sonnet*) mc=110 ;;
    *haiku*)  mc=182 ;;
    *)        mc=250 ;;
  esac
  add "$(col "$mc" "$m" b)"
fi

d=$(g .workspace.current_dir); [ -n "$d" ] && add "$(col 67 "$(basename "$d")")"

b=$(git -C "${d:-.}" --no-optional-locks branch --show-current 2>/dev/null)
if [ -n "$b" ]; then
  [ -n "$(git -C "${d:-.}" --no-optional-locks status --porcelain 2>/dev/null)" ] && b="$b*"
  add "$(col 144 "$b")"
fi

# 用量：ctx 青、5h 黄、7d 蓝
# 新会话在第一次 API 响应之前，这三个字段都是空的：ctx 当 0%，5h/7d 用上次缓存的值
# （额度是账号级的，跨会话、跨项目通用）。缓存里记了重置时间，过了重置点就当 0%。
p=$(g .context_window.used_percentage); add "$(bar ctx "${p:-0}" 73)"

RL_CACHE="$HOME/.claude/cache/statusline-ratelimits"
f=$(g .rate_limits.five_hour.used_percentage); fr=$(g .rate_limits.five_hour.resets_at)
w=$(g .rate_limits.seven_day.used_percentage); wr=$(g .rate_limits.seven_day.resets_at)
if [ -n "$f" ] || [ -n "$w" ]; then
  # 有新数据：缺的那一项沿用缓存，再整体写回（先写临时文件再改名，多个会话同时写也不会读到半截）
  if [ -z "$f" ] || [ -z "$w" ]; then
    read -r cf cfr cw cwr 2>/dev/null <"$RL_CACHE"
    [ -z "$f" ] && { f=$cf; fr=$cfr; }
    [ -z "$w" ] && { w=$cw; wr=$cwr; }
  fi
  mkdir -p "${RL_CACHE%/*}" 2>/dev/null
  printf '%s %s %s %s\n' "${f:--}" "${fr:--}" "${w:--}" "${wr:--}" >"$RL_CACHE.$$" 2>/dev/null \
    && mv -f "$RL_CACHE.$$" "$RL_CACHE" 2>/dev/null
else
  read -r f fr w wr 2>/dev/null <"$RL_CACHE"
fi
now=$(date +%s)
# 把 "-"（没有值）还原成空；重置时间已过的，用量归零
[ "$f" = - ] && f=''; [ "$w" = - ] && w=''
case "$fr" in ''|*[!0-9]*) ;; *) [ -n "$f" ] && [ "$fr" -le "$now" ] && f=0 ;; esac
case "$wr" in ''|*[!0-9]*) ;; *) [ -n "$w" ] && [ "$wr" -le "$now" ] && w=0 ;; esac
[ -n "$f" ] && add "$(bar 5h "$f" 179)"
[ -n "$w" ] && add "$(bar 7d "$w" 111)"

[ "$CLAUDE_CODE_EXPERIMENTAL_CODE_MODE" = 1 ] && add "$(col 140 '⚡Code Mode' b)"

# 登录账号：取自 ~/.claude.json 的 oauthAccount（非公开接口，以后可能变）
acct=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
[ -n "$acct" ] && add "$(col 245 "$acct")"

printf '%s' "$s"
