#!/usr/bin/env bash
#
# Install / update fast-setup's own scripts, independently of run.sh.
# Works on Linux and macOS; needs no root or sudo.
#
#   curl -fsSL https://raw.githubusercontent.com/lawrencehe/fast-setup/main/install.sh | bash -s -- statusline
#   ./install.sh mosh-sessions statusline
#   ./install.sh all
#
# Run from a clone, it installs the files in that clone; otherwise it downloads
# them from GitHub (override with FAST_SETUP_RAW).
set -Eeuo pipefail

FAST_SETUP_RAW="${FAST_SETUP_RAW:-https://raw.githubusercontent.com/lawrencehe/fast-setup/main}"

# Registry — one line per script: name | path in the repo | install path.
# To add a script: put the file in the repo, then add a line here.
SCRIPTS=(
  "mosh-sessions|bin/mosh-sessions|${HOME}/.local/bin/mosh-sessions"
  "statusline|claude/statusline.sh|${HOME}/.claude/statusline.sh"
)

ok(){ printf '✓ %s\n' "$*"; }
warn(){ printf '⚠ %s\n' "$*" >&2; }
die(){ printf '✗ %s\n' "$*" >&2; exit 1; }

usage() {
  local entry
  printf 'Usage: install.sh <name>... | all\n\nAvailable:\n'
  for entry in "${SCRIPTS[@]}"; do
    IFS='|' read -r name src dest <<<"$entry"
    printf '  %-16s %s -> %s\n' "$name" "$src" "${dest/#$HOME/\~}"
  done
}

# Local clone? (empty when piped through curl | bash)
SRC_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Fetch repo file $1 into $2, from the local clone or GitHub.
fetch() {
  local src="$1" out="$2"
  if [[ -n "$SRC_DIR" && -f "${SRC_DIR}/${src}" ]]; then
    cp "${SRC_DIR}/${src}" "$out"
  else
    curl -fsSL "${FAST_SETUP_RAW}/${src}" -o "$out"
  fi
}

# Install / update one script: skip when the installed copy is identical.
install_one() {
  local name="$1" src="$2" dest="$3" tmp
  tmp="${TMP_DIR}/${name}"
  fetch "$src" "$tmp" || { warn "${name}: could not fetch ${src}"; return 1; }
  [[ -s "$tmp" ]] || { warn "${name}: ${src} is empty"; return 1; }
  if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
    ok "${name} already latest (${dest/#$HOME/\~})"
  else
    local verb=installed
    [[ -f "$dest" ]] && verb=updated
    mkdir -p "$(dirname "$dest")"
    cp "$tmp" "$dest"
    chmod 0755 "$dest"
    ok "${name} ${verb} (${dest/#$HOME/\~})"
  fi
  if declare -F "post_${name//-/_}" >/dev/null; then
    "post_${name//-/_}" "$dest"
  fi
}

# --- Per-script post-install hooks: post_<name> <dest> ----------------------

post_mosh_sessions() {
  case ":${PATH}:" in
    *":$(dirname "$1"):"*) ;;
    *) warn "$(dirname "$1") is not in PATH; add it to run mosh-sessions by name" ;;
  esac
}

# Point Claude Code at the status line, unless another statusLine is configured.
# refreshInterval re-runs it every 10 minutes so the reset countdowns keep moving
# while the session is idle (runs the local script only; no API calls or tokens).
# A refreshInterval the user already set is left alone.
post_statusline() {
  local settings="${HOME}/.claude/settings.json" cmd="~/.claude/statusline.sh" current refresh=600
  command -v jq >/dev/null 2>&1 || { warn "statusline: jq is missing; install jq (the status line needs it too), then re-run"; return 0; }
  [[ -s "$settings" ]] || echo '{}' >"$settings"
  if ! current="$(jq -r '.statusLine.command // empty' "$settings" 2>/dev/null)"; then
    warn "statusline: ${settings} is not valid JSON; left unchanged"
    return 0
  fi
  if [[ -z "$current" ]]; then
    jq --arg c "$cmd" --argjson r "$refresh" '.statusLine = {type: "command", command: $c, refreshInterval: $r}' \
      "$settings" >"${settings}.tmp" && mv "${settings}.tmp" "$settings"
    ok "statusline configured in ${settings/#$HOME/\~} (takes effect in new sessions)"
  elif [[ "$current" == "$cmd" || "$current" == "${HOME}/.claude/statusline.sh" ]]; then
    if [[ "$(jq '.statusLine | has("refreshInterval")' "$settings")" == false ]]; then
      jq --argjson r "$refresh" '.statusLine.refreshInterval = $r' "$settings" >"${settings}.tmp" \
        && mv "${settings}.tmp" "$settings"
      ok "statusline refreshInterval set to ${refresh}s in ${settings/#$HOME/\~} (takes effect in new sessions)"
    else
      ok "statusline already configured in ${settings/#$HOME/\~}"
    fi
  else
    warn "statusline: settings.json already uses another status line (${current}); left unchanged"
  fi
}

# --- Main -------------------------------------------------------------------

[[ $# -gt 0 ]] || { usage; exit 1; }
case "$1" in -h|--help) usage; exit 0 ;; esac

names=()
if [[ "$1" == all ]]; then
  for entry in "${SCRIPTS[@]}"; do names+=("${entry%%|*}"); done
else
  names=("$@")
fi

rc=0
for want in "${names[@]}"; do
  found=0
  for entry in "${SCRIPTS[@]}"; do
    IFS='|' read -r name src dest <<<"$entry"
    if [[ "$name" == "$want" ]]; then
      found=1
      install_one "$name" "$src" "$dest" || rc=1
    fi
  done
  if [[ $found == 0 ]]; then
    warn "unknown script: ${want}"
    usage >&2
    rc=1
  fi
done
exit "$rc"
