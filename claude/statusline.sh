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
# 每次运行最多启动 2 个外部进程（jq、git 各一次，不在 git 仓库里时只有 jq）；其余都用 bash 内建功能，不开子 shell。

LC_NUMERIC=C
command -v jq >/dev/null 2>&1 || { printf 'statusline: jq missing'; exit 0; }

# 一次 jq 读出全部字段：stdin 的会话 JSON + ~/.claude.json 里的登录账号
# （oauthAccount 是非公开接口，以后可能变）。字段用 \x1f 分隔，空字段也能保留。
src=(-); [ -r "$HOME/.claude.json" ] && src+=("$HOME/.claude.json")
IFS=$'\x1f' read -r m mid d p f fr w wr acct < <(jq -nr '
  input as $s | (try input catch {}) as $c
  | [$s.model.display_name, $s.model.id, $s.workspace.current_dir,
     # 新会话在第一次 API 回复前 used_percentage 是 null，但 context_window 已经有了：算 0%；
     # 整个 context_window 都没有（旧版本、数据异常）才留空，显示 ?%
     ($s.context_window | if . == null then null else (.used_percentage // 0) end),
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
# 不在 git 仓库里（或 git 读不了这个仓库）显示当前目录名。
# 仓库顶层由 bash 自己向上找 .git（目录或文件，后者是 worktree / submodule），不用另起 git 进程；
# 找到了才运行一次 git status，不在仓库里则一次 git 都不调用。
d=${d:-$PWD}
top=$d
while [ -n "$top" ] && [ ! -e "$top/.git" ]; do top=${top%/*}; done
[ -z "$top" ] && [ -e /.git ] && top=/
head=''
if [ -n "$top" ]; then
  ab='' dirty=''
  # porcelain v2 先输出 "# branch.*" 头部，再输出改动；看到第一行改动就够了
  while IFS= read -r line; do
    case $line in
      '# branch.head '*) head=${line#'# branch.head '} ;;
      '# branch.ab '*)   ab=${line#'# branch.ab '} ;;
      '#'*) ;;
      *) dirty='*'; break ;;
    esac
  done < <(git -C "$top" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
fi
if [ -n "$head" ]; then
  name=${top%/}; name=${name##*/}
  col 67 "${name:-/}"; loc=$R
  if [ "$head" != '(detached)' ]; then
    b=$head$dirty
    if [ -n "$ab" ]; then   # "+2 -1"
      ahead=${ab%% *}; ahead=${ahead#+}; behind=${ab##*-}
      [ "${ahead:-0}" -gt 0 ] 2>/dev/null && b+="↑$ahead"
      [ "${behind:-0}" -gt 0 ] 2>/dev/null && b+="↓$behind"
    fi
    col 144 "$b"; loc+=$'\033[2m:\033[0m'$R
  fi
  add "$loc"
else
  name=${d%/}; name=${name##*/}
  col 67 "${name:-/}"; add "$R"
fi

# 当前时间：bash 5 用 $EPOCHSECONDS，bash 4.2+ 用 printf %(...)T，都不行（macOS 自带的 bash 3.2）才调 date
now=${EPOCHSECONDS:-}
[ -z "$now" ] && printf -v now '%(%s)T' -1 2>/dev/null
case "$now" in ''|*[!0-9]*) now=$(date +%s) ;; esac

# 用量：ctx 青、5h 黄、7d 蓝
# 5h/7d 只在会话收到 API 回复时才随 JSON 更新，闲着的会话手里是旧值。额度是账号级的，
# 所以所有会话共用一份缓存，每次把 JSON 里的值和缓存里的值比一比，取较新的那份：
#   - 重置时间相同（同一个额度窗口，相差 10 分钟内都算）：用量只增不减，取较大的；
#   - 重置时间不同：中间重置过，取重置时间较晚的那份；
#   - 只有一边有值：用那一边。
# 这样闲着的会话也能显示别的会话刚拿到的用量。新会话在第一次 API 响应之前 JSON 里没有这些字段，
# 直接用缓存。重置时间已过的当 0%。都拿不到时（首次安装、API key 用户）显示空条和 ?%。
RL_CACHE="$HOME/.claude/cache/statusline-ratelimits"
cf='' cfr='' cw='' cwr=''
[ -r "$RL_CACHE" ] && read -r cf cfr cw cwr <"$RL_CACHE"
[ "$cf" = - ] && cf=''; [ "$cfr" = - ] && cfr=''
[ "$cw" = - ] && cw=''; [ "$cwr" = - ] && cwr=''

# gt a b：非负小数 a > b 时返回 0（bash 只会整数比较，这里按整数部分 + 补齐的小数部分比）
gt() {
  local ai=${1%%.*} bi=${2%%.*} af bf
  af=${1#"$ai"}; af=${af#.}; bf=${2#"$bi"}; bf=${bf#.}
  [ "$ai" != "$bi" ] && { [ "$((10#${ai:-0}))" -gt "$((10#${bi:-0}))" ]; return; }
  while [ ${#af} -lt ${#bf} ]; do af+=0; done
  while [ ${#bf} -lt ${#af} ]; do bf+=0; done
  [[ $af > $bf ]]
}
isnum() { case "$1" in ''|.*|*.|*[!0-9.]*|*.*.*) return 1 ;; esac; }
# pick JSON值 JSON重置 缓存值 缓存重置 → PV PR（取较新的一份）
pick() {
  PV=$1 PR=$2
  isnum "$3" || return           # 缓存里没有可用的值
  if ! isnum "$1"; then PV=$3 PR=$4; return; fi
  isnum "$2" && isnum "$4" || return
  local diff=$(( $4 - $2 ))
  if [ "$diff" -gt 600 ]; then PV=$3 PR=$4                  # 缓存的窗口更晚
  elif [ "$diff" -ge -600 ] && gt "$3" "$1"; then PV=$3 PR=$4  # 同一窗口，缓存用量更大
  fi
}
pick "$f" "$fr" "$cf" "$cfr"; f=$PV fr=$PR
pick "$w" "$wr" "$cw" "$cwr"; w=$PV wr=$PR
# 结果和缓存不同才写回（先写临时文件再改名，多个会话同时写也不会读到半截）
new="${f:--} ${fr:--} ${w:--} ${wr:--}"
if [ -n "$f$w" ] && [ "$new" != "${cf:--} ${cfr:--} ${cw:--} ${cwr:--}" ]; then
  [ -d "${RL_CACHE%/*}" ] || mkdir -p "${RL_CACHE%/*}" 2>/dev/null
  printf '%s\n' "$new" >"$RL_CACHE.$$" 2>/dev/null && mv -f "$RL_CACHE.$$" "$RL_CACHE" 2>/dev/null
fi
# 重置时间已过的，用量归零
case "$fr" in ''|*[!0-9]*) ;; *) [ -n "$f" ] && [ "$fr" -le "$now" ] && f=0 ;; esac
case "$wr" in ''|*[!0-9]*) ;; *) [ -n "$w" ] && [ "$wr" -le "$now" ] && w=0 ;; esac

# 重置倒计时：until 时间戳 → R=" ↻42m" / " ↻08m" / " ↻2h05m" / " ↻3d4h"；没有时间或已过期时 R 为空
# 分钟固定两位（08m、1h00m），每分钟跳动时长度不变；5h 倒计时只在 1h00m → 59m 时变短一次
until_reset() {
  local t=$1 d
  R=''
  case "$t" in ''|*[!0-9]*) return ;; esac
  d=$(( t - now ))
  [ "$d" -le 0 ] && return
  # 不到一天：按分钟向上取整（剩 30 秒也显示 01m），再拆成小时和分钟
  local m=$(( (d + 59) / 60 ))
  if   [ "$m" -lt 60 ];    then printf -v d '%02dm' "$m"
  elif [ "$m" -lt 1440 ];  then printf -v d '%dh%02dm' "$(( m / 60 ))" "$(( m % 60 ))"
  else                          d="$(( m / 1440 ))d$(( m % 1440 / 60 ))h"; fi
  col 245 "↻$d"; R=" $R"
}

bar ctx "$p" 73; add "$R"
bar 5h "$f" 179; x=$R; until_reset "$fr"; add "$x$R"
bar 7d "$w" 111; x=$R; until_reset "$wr"; add "$x$R"

[ -n "$acct" ] && { col 245 "$acct"; add "$R"; }

# Code Mode 只显示一个图标，放在最后
[ "$CLAUDE_CODE_EXPERIMENTAL_CODE_MODE" = 1 ] && { col 140 '⚡' b; add "$R"; }

printf '%s' "$s"
