#!/usr/bin/env bash
# Claude Code 状态栏，两行（一行放不下时窄终端会截断）：
#   第 1 行：模型 · 目录 · git 分支 · Code Mode · 登录账号
#   第 2 行：上下文 · 5h/7d 额度（带重置倒计时）
# stdin 是 Claude Code 传来的会话 JSON。颜色用 256 色里偏柔和的色号。
# 依赖：bash、jq、git。Linux 和 macOS 都能用。
# 安装：curl -fsSL https://raw.githubusercontent.com/lawrencehe/fast-setup/main/install.sh | bash -s -- statusline
#   （或手动放到 ~/.claude/statusline.sh 并 chmod +x，在 ~/.claude/settings.json 里加
#    "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }）

input=$(cat)
command -v jq >/dev/null 2>&1 || { printf 'statusline: jq missing'; exit 0; }
g() { printf '%s' "$input" | jq -r "$1 // empty"; }

SEP=$' \033[2m·\033[0m '
s=''
add() { s="${s:+$s$SEP}$1"; }
# 上色：col 色号(0-255) 文字 [bold]
col() { local b=''; [ -n "$3" ] && b='1;'; printf '\033[%s38;5;%sm%s\033[0m' "$b" "$1" "$2"; }

# 进度条：bar 名称 百分比 色号 → "名称 ████▌       38%"
# 12 格宽，暗色背景当槽，前景色填充；最后一格用八分之一块（▏▎▍▌▋▊▉），共 96 级、每级约 1.04%
# 每项固定一个颜色；≥85% 时进度条和数字整项变红
# 百分比为空（拿不到数据）时显示空槽和 "?%"
BAR_TRACK=237   # 槽的背景色（256 色色号）
BAR_PART=('' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
bar() {
  local label=$1 fg=$3 pct w=12 lv full rem i out=''
  if [ -z "$2" ]; then
    for ((i = 0; i < w; i++)); do out+=' '; done
    printf '%s \033[48;5;%sm%s\033[0m %s' "$label" "$BAR_TRACK" "$out" '?%'
    return
  fi
  pct=$(printf '%.0f' "$2")
  [ "$pct" -gt 100 ] && pct=100
  lv=$(( (pct * w * 8 + 50) / 100 ))
  # 只要不是 0 就至少亮八分之一格
  [ "$pct" -gt 0 ] && [ "$lv" -lt 1 ] && lv=1
  full=$(( lv / 8 )); rem=$(( lv % 8 ))
  for ((i = 0; i < w; i++)); do
    if [ "$i" -lt "$full" ]; then out+='█'
    elif [ "$i" -eq "$full" ] && [ "$rem" -gt 0 ]; then out+=${BAR_PART[$rem]}
    else out+=' '; fi
  done
  [ "$pct" -ge 85 ] && fg=167
  out=$(printf '\033[38;5;%s;48;5;%sm%s\033[0m' "$fg" "$BAR_TRACK" "$out")
  if [ "$pct" -ge 85 ]; then
    printf '%s %s %s' "$(col 167 "$label")" "$out" "$(col 167 "$pct%")"
  else
    printf '%s %s %s' "$label" "$out" "$pct%"
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
# 新会话在第一次 API 响应之前，这三个字段都是空的：ctx 显示 ?%，5h/7d 用上次缓存的值
# （额度是账号级的，跨会话、跨项目通用）。缓存里记了重置时间，过了重置点就当 0%。
# 没有缓存也拿不到数据时（首次安装、API key 用户），同样显示空条和 ?%，三项始终都在。
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

# 重置倒计时：until 时间戳 → " ↻42m" / " ↻2h13m" / " ↻3d4h"；没有时间或已过期时不输出
until_reset() {
  local t=$1 d
  case "$t" in ''|*[!0-9]*) return ;; esac
  d=$(( t - now ))
  [ "$d" -le 0 ] && return
  if   [ "$d" -lt 3600 ];  then d="$(( (d + 59) / 60 ))m"
  elif [ "$d" -lt 86400 ]; then d="$(( d / 3600 ))h$(( d % 3600 / 60 ))m"
  else                          d="$(( d / 86400 ))d$(( d % 86400 / 3600 ))h"; fi
  printf ' %s' "$(col 245 "↻$d")"
}

[ "$CLAUDE_CODE_EXPERIMENTAL_CODE_MODE" = 1 ] && add "$(col 140 '⚡Code Mode' b)"

# 登录账号：取自 ~/.claude.json 的 oauthAccount（非公开接口，以后可能变）
acct=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
[ -n "$acct" ] && add "$(col 245 "$acct")"

line1=$s; s=''
p=$(g .context_window.used_percentage); add "$(bar ctx "$p" 73)"
add "$(bar 5h "$f" 179)$(until_reset "$fr")"
add "$(bar 7d "$w" 111)$(until_reset "$wr")"

printf '%s\n%s' "$line1" "$s"
