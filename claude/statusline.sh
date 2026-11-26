#!/usr/bin/env bash
# Claude Code 状态栏：模型 · 仓库名:分支↑↓（非 git 仓库为目录名） · 上下文 · 5h/7d 额度（带重置倒计时） · 登录账号 · ⚡（Code Mode）
# stdin 是 Claude Code 传来的会话 JSON，输出一行文字。颜色用 256 色里偏柔和的色号。
# 依赖：bash、jq、git。Linux 和 macOS 都能用。
# 安装：curl -fsSL https://raw.githubusercontent.com/lawrencehe/fast-setup/main/install.sh | bash -s -- statusline
#   （或手动放到 ~/.claude/statusline.sh 并 chmod +x，在 ~/.claude/settings.json 里加
#    "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "refreshInterval": 60 }）
#
# 只做本地读取，不联网、不调用 API：会话信息来自 stdin，账号来自 ~/.claude.json，
# git 状态来自本地仓库（↑↓ 对比的是本地记录的远程分支，即上次 fetch/pull/push 时的状态）。
# 每次运行只启动 3 个外部进程（jq 一次、git 两次）；其余都用 bash 内建功能，不开子 shell。

LC_NUMERIC=C
command -v jq >/dev/null 2>&1 || { printf 'statusline: jq missing'; exit 0; }

# 一次 jq 读出全部字段：stdin 的会话 JSON + ~/.claude.json 里的登录账号
# （oauthAccount 是非公开接口，以后可能变）。字段用 \x1f 分隔，空字段也能保留。
src=(-); [ -r "$HOME/.claude.json" ] && src+=("$HOME/.claude.json")
IFS=$'\x1f' read -r m mid d p f fr w wr acct < <(jq -nr '
  input as $s | (try input catch {}) as $c
  | [$s.model.display_name, $s.model.id, $s.workspace.current_dir,
     $s.context_window.used_percentage,
     $s.rate_limits.five_hour.used_percentage, $s.rate_limits.five_hour.resets_at,
     $s.rate_limits.seven_day.used_percentage, $s.rate_limits.seven_day.resets_at,
     ($c.oauthAccount.emailAddress? // null)]
  | map(if . == null then "" else tostring end) | join("\u001f")' "${src[@]}" 2>/dev/null)

SEP=$' \033[2m·\033[0m '
s=''
add() { s="${s:+$s$SEP}$1"; }
# 下面的函数都把结果放进变量 R（不用 $(...)，省掉子 shell）
# 上色：col 色号(0-255) 文字 [bold]
col() { local b=''; [ -n "$3" ] && b='1;'; printf -v R '\033[%s38;5;%sm%s\033[0m' "$b" "$1" "$2"; }

# 进度条：bar 名称 百分比 色号 → "名称 ████▌       38%"
# 12 格宽，暗色背景当槽，前景色填充；最后一格用八分之一块（▏▎▍▌▋▊▉），共 96 级、每级约 1.04%
# 每项固定一个颜色；≥85% 时进度条和数字整项变红
# 百分比为空（拿不到数据）时显示空槽和 "?%"
BAR_TRACK=237   # 槽的背景色（256 色色号）
BAR_PART=('' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
bar() {
  local label=$1 fg=$3 pct w=12 lv full rem i out='' l n
  if [ -z "$2" ]; then
    for ((i = 0; i < w; i++)); do out+=' '; done
    printf -v R '%s \033[48;5;%sm%s\033[0m %s' "$label" "$BAR_TRACK" "$out" '?%'
    return
  fi
  printf -v pct '%.0f' "$2" 2>/dev/null || pct=0
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
  l=$label n="$pct%"
  if [ "$pct" -ge 85 ]; then
    fg=167
    col 167 "$label"; l=$R
    col 167 "$pct%"; n=$R
  fi
  printf -v R '%s \033[38;5;%s;48;5;%sm%s\033[0m %s' "$l" "$fg" "$BAR_TRACK" "$out" "$n"
}

# 模型：Opus 绿、Fable 橙、Sonnet 蓝、Haiku 淡紫红，其它灰
if [ -n "$m" ]; then
  shopt -s nocasematch
  case "$m $mid" in
    *opus*)   mc=108 ;;
    *fable*)  mc=173 ;;
    *sonnet*) mc=110 ;;
    *haiku*)  mc=182 ;;
    *)        mc=250 ;;
  esac
  shopt -u nocasematch
  col "$mc" "$m" b; add "$R"
fi

# 位置：在 git 仓库里显示 "仓库名:分支"，仓库名取当前目录所属仓库的顶层目录名。
#   分支后：* 有未提交的改动；↑N 本地有 N 个提交没 push；↓N 远程有 N 个提交没 pull
#   （按本地记录的远程分支算，不联网）。没有上游分支时不显示箭头；detached HEAD 时只显示仓库名。
# 不在 git 仓库里显示当前目录名。
top=$(git -C "${d:-.}" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
if [ -n "$top" ]; then
  name=${top%/}; name=${name##*/}
  col 67 "${name:-/}"; loc=$R
  head='' ab='' dirty=''
  # porcelain v2 先输出 "# branch.*" 头部，再输出改动；看到第一行改动就够了
  while IFS= read -r line; do
    case $line in
      '# branch.head '*) head=${line#'# branch.head '} ;;
      '# branch.ab '*)   ab=${line#'# branch.ab '} ;;
      '#'*) ;;
      *) dirty='*'; break ;;
    esac
  done < <(git -C "$top" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
  if [ -n "$head" ] && [ "$head" != '(detached)' ]; then
    b=$head$dirty
    if [ -n "$ab" ]; then   # "+2 -1"
      ahead=${ab%% *}; ahead=${ahead#+}; behind=${ab##*-}
      [ "${ahead:-0}" -gt 0 ] 2>/dev/null && b+="↑$ahead"
      [ "${behind:-0}" -gt 0 ] 2>/dev/null && b+="↓$behind"
    fi
    col 144 "$b"; loc+=$'\033[2m:\033[0m'$R
  fi
  add "$loc"
elif [ -n "$d" ]; then
  name=${d%/}; name=${name##*/}
  col 67 "${name:-/}"; add "$R"
fi

# 当前时间：bash 5 用 $EPOCHSECONDS，bash 4.2+ 用 printf %(...)T，都不行（macOS 自带的 bash 3.2）才调 date
now=${EPOCHSECONDS:-}
[ -z "$now" ] && printf -v now '%(%s)T' -1 2>/dev/null
case "$now" in ''|*[!0-9]*) now=$(date +%s) ;; esac

# 用量：ctx 青、5h 黄、7d 蓝
# 新会话在第一次 API 响应之前，这三个字段都是空的：ctx 显示 ?%，5h/7d 用上次缓存的值
# （额度是账号级的，跨会话、跨项目通用）。缓存里记了重置时间，过了重置点就当 0%。
# 没有缓存也拿不到数据时（首次安装、API key 用户），同样显示空条和 ?%，三项始终都在。
RL_CACHE="$HOME/.claude/cache/statusline-ratelimits"
cf='' cfr='' cw='' cwr=''
[ -r "$RL_CACHE" ] && read -r cf cfr cw cwr <"$RL_CACHE"
if [ -n "$f" ] || [ -n "$w" ]; then
  # 有新数据：缺的那一项沿用缓存；内容有变化才写回（先写临时文件再改名，多个会话同时写也不会读到半截）
  [ -z "$f" ] && { f=$cf; fr=$cfr; }
  [ -z "$w" ] && { w=$cw; wr=$cwr; }
  new="${f:--} ${fr:--} ${w:--} ${wr:--}"
  if [ "$new" != "$cf $cfr $cw $cwr" ]; then
    [ -d "${RL_CACHE%/*}" ] || mkdir -p "${RL_CACHE%/*}" 2>/dev/null
    printf '%s\n' "$new" >"$RL_CACHE.$$" 2>/dev/null && mv -f "$RL_CACHE.$$" "$RL_CACHE" 2>/dev/null
  fi
else
  f=$cf fr=$cfr w=$cw wr=$cwr
fi
# 把 "-"（没有值）还原成空；重置时间已过的，用量归零
[ "$f" = - ] && f=''; [ "$w" = - ] && w=''
case "$fr" in ''|*[!0-9]*) ;; *) [ -n "$f" ] && [ "$fr" -le "$now" ] && f=0 ;; esac
case "$wr" in ''|*[!0-9]*) ;; *) [ -n "$w" ] && [ "$wr" -le "$now" ] && w=0 ;; esac

# 重置倒计时：until 时间戳 → R=" ↻42m" / " ↻2h13m" / " ↻3d4h"；没有时间或已过期时 R 为空
until_reset() {
  local t=$1 d
  R=''
  case "$t" in ''|*[!0-9]*) return ;; esac
  d=$(( t - now ))
  [ "$d" -le 0 ] && return
  if   [ "$d" -lt 3600 ];  then d="$(( (d + 59) / 60 ))m"
  elif [ "$d" -lt 86400 ]; then d="$(( d / 3600 ))h$(( d % 3600 / 60 ))m"
  else                          d="$(( d / 86400 ))d$(( d % 86400 / 3600 ))h"; fi
  col 245 "↻$d"; R=" $R"
}

bar ctx "$p" 73; add "$R"
bar 5h "$f" 179; x=$R; until_reset "$fr"; add "$x$R"
bar 7d "$w" 111; x=$R; until_reset "$wr"; add "$x$R"

[ -n "$acct" ] && { col 245 "$acct"; add "$R"; }

# Code Mode 只显示一个图标，放在最后
[ "$CLAUDE_CODE_EXPERIMENTAL_CODE_MODE" = 1 ] && { col 140 '⚡' b; add "$R"; }

printf '%s' "$s"
