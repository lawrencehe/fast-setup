# fast-setup

One-command development environment setup for Linux VPS. It works on both
**Debian-family** and **RHEL-family** distributions, on **amd64** and **arm64**.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/lawrencehe/fast-setup/main/run.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/lawrencehe/fast-setup.git
cd fast-setup
./run.sh
```

Run it as a **normal user with sudo**. The script refuses to run as root.

## Requirements

- A Linux VPS with internet access
- A normal user that can use `sudo`
- A supported distribution/architecture (see below)

## Supported platforms

| Family   | Distributions                                             | Package manager |
| -------- | --------------------------------------------------------- | --------------- |
| Debian   | Debian 12+, Ubuntu 22.04+                                 | `apt`           |
| RHEL     | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux, Fedora | `dnf` (`yum` on EL7) |

Architectures: **x86_64 / amd64** and **aarch64 / arm64**.

On RHEL-family systems the script automatically enables **EPEL** (and
**CodeReady Builder** on Enterprise Linux) so that packages such as `mosh`,
`neovim` and `btop` are available.

## What gets installed

- **Base packages** — `curl`, `wget`, `tar`, `gzip`, `ca-certificates`, `gnupg`,
  `jq`, `ncurses`, `git`, `tmux`, `mosh`, `rsync`, `lsof`, `unzip`/`zip`, `xz`,
  and a build toolchain (`build-essential` or `gcc`/`gcc-c++`/`make`)
- **zsh** — installed if missing, upgraded when an update is available, otherwise left as-is
- **Database clients** — MySQL/MariaDB client and PostgreSQL client
- **OpenJDK 21** — pinned to the 21 line (latest 21.x); no other major version is installed if 21 is unavailable
- **Apache Maven 3.9.9** — installed under `/opt`, symlinked to `/usr/local/bin/mvn`
- **uv** and the latest stable Python (managed by uv)
- **nvm** and the latest Node.js LTS
- **[pi](https://pi.dev)** coding agent (native managed installer via `pi.dev/install.sh`)
- **[T3 Code](https://t3.codes)** (`t3`, native standalone installer via `t3.codes/install.sh`)
- **[Paseo](https://paseo.sh)** (`paseo`, official CLI `@getpaseo/cli` via nvm-managed Node.js)
- **[Codex CLI](https://github.com/openai/codex)** (`codex`, native standalone installer via `chatgpt.com/codex/install.sh`)
- **[Claude Code](https://claude.ai)** (`claude`, native standalone installer via `claude.ai/install.sh`)
- **[Antigravity CLI](https://antigravity.google)** (`agy`, native standalone installer via `antigravity.google/cli/install.sh`)
- **[herdr](https://herdr.dev)**
- **[Tailscale](https://tailscale.com)** (`tailscale` + `tailscaled` from the official stable
  repository, enabled at boot)
- **Docker CE** with Buildx and Compose plugins
- **kubectl** (latest stable)
- **Alibaba Cloud CLI**
- **lazygit** (latest)
- **Ghostty terminfo** (installed globally)
- **Daily auto-update (Linux system cron)** — installs `cron`/`cronie`, configures `/etc/cron.d/fast-setup-auto-update` to run daily at `03:00` Singapore time (`Asia/Singapore`, UTC+8; automatically converted to the server's local timezone) to update `t3`, `paseo`, `codex`, `claude`, `agy`, `pi`, `mosh`, and `tailscale`

## Notes

- **Docker group** — after the first install, log out and back in (or run
  `newgrp docker`) so you can use `docker ps` without `sudo`.
- **mosh / Tailscale firewall** — the script opens UDP `60000-61000` (mosh) and
  UDP `41641` (Tailscale direct connections) on `firewalld` or `ufw` when one of
  them is active. If your provider uses a cloud firewall, open the same ports
  there.
- **Tailscale** — installed from Tailscale's official stable repository. For
  Debian/Ubuntu derivatives whose codename is not published there, the nearest
  LTS suite is used; on RHEL-family systems the matching `centos/<major>` tree
  is used, falling back to EL9. Logging in is interactive: after the script
  finishes, run `tailscale up` (the invoking user is made the Tailscale operator,
  so no sudo is needed). For unattended installs, export
  `TAILSCALE_AUTH_KEY=tskey-auth-…` before running the script.
- **Best-effort optional packages** — tools such as `mosh`, `neovim`, `btop`,
  `tmux`, the database clients and the build toolchain are installed
  best-effort. If one of them is unavailable on an older release, the rest of
  the setup still completes.
- **Auto-update via cron** — `/etc/cron.d/fast-setup-auto-update` runs daily at
  `03:00` Singapore time (`Asia/Singapore`, UTC+8), automatically converted to
  the host's local timezone for compatibility with both Debian `cron` and RHEL
  `cronie`:
  - User tools (`t3`, `paseo`, `codex`, `claude`, `agy`, `pi`) are updated by
    `~/.local/bin/fast-setup-update` (logs in `~/.local/state/fast-setup/auto-update.log`).
    You can also run `fast-setup-update` manually at any time.
  - `mosh` and `tailscale` are updated by `/usr/local/sbin/fast-setup-pkg-update`
    via `apt`/`dnf`/`yum` (logs in `/var/log/fast-setup-pkg-update.log`).
- **Idempotent** — the script can be re-run safely: missing tools are installed,
  outdated tools are upgraded to the latest available version, and already-latest
  tools are skipped. Maven is pinned to 3.9.9.

## Claude Code status line

[`claude-statusline.sh`](claude-statusline.sh) is a standalone status line for
[Claude Code](https://claude.ai). It is not installed by `run.sh`; install it
separately on any Linux or macOS machine that has `bash`, `jq` and `git`:

```bash
mkdir -p ~/.claude
curl -fsSL https://raw.githubusercontent.com/lawrencehe/fast-setup/main/claude-statusline.sh -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
[ -f ~/.claude/settings.json ] || echo '{}' > ~/.claude/settings.json
jq '.statusLine = {type: "command", command: "~/.claude/statusline.sh"}' ~/.claude/settings.json > ~/.claude/settings.json.tmp \
  && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

Start a new Claude Code session and it shows one line:

```
Fable 5.2 · my-project · main* · ctx ▓░░░░░░░░░ 12% · 5h ▓░░░░░░░░░ 3% · 7d ▓▓░░░░░░░░ 19% · you@example.com
```

- **Model**, **directory**, **git branch** (`*` when there are uncommitted changes)
- **ctx** — context window usage of the current session
- **5h / 7d** — subscription rate-limit usage. Claude Code only reports these
  after the first response of a session, so the last values are cached in
  `~/.claude/cache/statusline-ratelimits` and shown in new sessions right away;
  a value whose reset time has passed shows as 0%.
- When a value is unavailable (before the first response of a session, on a
  fresh install with no cache yet, or for API-key users who have no rate
  limits), its bar is empty and shows `?%` — ctx, 5h and 7d are always shown.
- **⚡Code Mode** — only when `CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1` is set
- **Account** — the logged-in email, read locally from `~/.claude.json`
- A bar turns red at 85% or more.

## Repository layout

- [`run.sh`](run.sh) — the setup script
- [`claude-statusline.sh`](claude-statusline.sh) — Claude Code status line (see [above](#claude-code-status-line))
- [`mosh-sessions.sh`](mosh-sessions.sh) — mosh 会话巡检脚本：查看运行中的 mosh-server 进程及其 UDP socket
