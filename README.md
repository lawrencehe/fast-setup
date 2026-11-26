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
- **[rclone](https://rclone.org)** (latest stable, official installer via `rclone.org/install.sh`)
- **lazygit** (latest)
- **Ghostty terminfo** (installed globally)
- **fast-setup scripts** — `mosh-sessions` and the Claude Code status line, via
  [`install.sh`](install.sh) (see [below](#fast-setup-scripts))
- **Daily auto-update (Linux system cron)** — installs `cron`/`cronie`, configures `/etc/cron.d/fast-setup-auto-update` to run daily at `03:00` Singapore time (`Asia/Singapore`, UTC+8; automatically converted to the server's local timezone) to update `t3`, `paseo`, `codex`, `claude`, `agy`, `pi`, `mosh`, and `tailscale`

## Install policy

Rules every step in `run.sh` follows (see `CLAUDE.md` for details):

- **Both distro families** — every step works on Debian/Ubuntu (`apt`) and
  the RHEL family (`dnf`/`yum`).
- **Install / update / skip** — missing tools are installed, installed tools
  are updated, and tools already at the latest version are skipped (pinned
  versions such as Maven and the OpenJDK 21 line stay on their pin).
- **Official installer first** — when a tool ships an official install script,
  use it rather than distro packages or hand-rolled downloads.
- **Native installer first** — when a tool ships a native/standalone installer,
  use it rather than npm/pip; fall back to the package manager or npm only when
  neither exists or works.

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

## fast-setup scripts

Besides third-party tools, this repo ships a few scripts of its own. `run.sh`
installs all of them, and [`install.sh`](install.sh) installs any of them on
its own — no `run.sh`, no root or sudo, on Linux or macOS:

```bash
# one script
curl -fsSL https://raw.githubusercontent.com/lawrencehe/fast-setup/main/install.sh | bash -s -- mosh-sessions
# several, or all
curl -fsSL https://raw.githubusercontent.com/lawrencehe/fast-setup/main/install.sh | bash -s -- mosh-sessions statusline
curl -fsSL https://raw.githubusercontent.com/lawrencehe/fast-setup/main/install.sh | bash -s -- all
```

Re-running it updates a script whose contents changed and skips one that is
already the latest. Run from a clone (`./install.sh …`), it installs the files
in that clone.

| Name            | Source                                       | Installed to                   |
| --------------- | -------------------------------------------- | ------------------------------ |
| `mosh-sessions` | [`bin/mosh-sessions`](bin/mosh-sessions)     | `~/.local/bin/mosh-sessions`   |
| `statusline`    | [`claude/statusline.sh`](claude/statusline.sh) | `~/.claude/statusline.sh`      |

Every script is a single self-contained file, so it can also be run once
without installing:

```bash
curl -fsSL https://raw.githubusercontent.com/lawrencehe/fast-setup/main/bin/mosh-sessions | bash
```

### mosh-sessions

mosh 会话巡检：列出运行中的 `mosh-server` 进程、其 UDP socket，并标出当前会话；
装了 `tcpdump` 时会短暂抓包探测客户端来源 IP。需要 `lsof`，部分信息需要 `sudo`。

### Claude Code status line

`statusline` is a status line for [Claude Code](https://claude.ai). It needs
`bash`, `jq` and `git`. The installer also sets `statusLine` in
`~/.claude/settings.json`, unless another status line is already configured
there (then it leaves the setting alone and warns).

Start a new Claude Code session and it shows one line:

```
Fable 5.2 · my-project · main* · ctx █▌          12% · 5h ▍           3% ↻2h13m · 7d ██▎         19% ↻3d4h · you@example.com
```

- **Model**, **directory**, **git branch** (`*` when there are uncommitted changes)
- **ctx** — context window usage of the current session
- **5h / 7d** — subscription rate-limit usage. Claude Code only reports these
  after the first response of a session, so the last values are cached in
  `~/.claude/cache/statusline-ratelimits` and shown in new sessions right away;
  a value whose reset time has passed shows as 0%.
- **↻** — time until that limit resets (`↻42m`, `↻2h13m`, `↻3d4h`); left out
  when the reset time is unknown or has already passed
- When a value is unavailable (before the first response of a session, on a
  fresh install with no cache yet, or for API-key users who have no rate
  limits), its bar is empty and shows `?%` — ctx, 5h and 7d are always shown.
- **Account** — the logged-in email, read locally from `~/.claude.json`
- **⚡** — Code Mode, shown last and only when `CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1` is set
- Each bar is 12 characters wide on a dark track; the last cell uses ⅛-block
  characters (`▏▎▍▌▋▊▉`), so a bar has 96 steps of about 1%. Any non-zero usage
  shows at least one step. A bar turns red at 85% or more.

## Repository layout

- [`run.sh`](run.sh) — the server setup script (third-party tools)
- [`install.sh`](install.sh) — installs fast-setup's own scripts (see [above](#fast-setup-scripts))
- [`bin/`](bin) — command-line scripts, installed to `~/.local/bin`
- [`claude/`](claude) — Claude Code add-ons, installed to `~/.claude`
