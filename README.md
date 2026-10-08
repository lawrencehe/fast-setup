# fast-setup

One-command development environment setup for Linux VPS. It works on both
**Debian-family** and **RHEL-family** distributions, on **amd64** and **arm64**.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/LawrenceHe/fast-setup/main/run.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/LawrenceHe/fast-setup.git
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
- **[pi](https://github.com/earendil-works/pi)** coding agent
- **[herdr](https://herdr.dev)**
- **Docker CE** with Buildx and Compose plugins
- **kubectl** (latest stable)
- **Alibaba Cloud CLI**
- **lazygit** (latest)
- **Ghostty terminfo** (installed globally)

## Notes

- **Docker group** — after the first install, log out and back in (or run
  `newgrp docker`) so you can use `docker ps` without `sudo`.
- **mosh** — the script opens UDP `60000-61000` on `firewalld` or `ufw` when one
  of them is active. If your provider uses a cloud firewall, open the same range
  there.
- **Best-effort optional packages** — tools such as `mosh`, `neovim`, `btop`,
  `tmux`, the database clients and the build toolchain are installed
  best-effort. If one of them is unavailable on an older release, the rest of
  the setup still completes.
- **Idempotent** — the script can be re-run safely: missing tools are installed,
  outdated tools are upgraded to the latest available version, and already-latest
  tools are skipped. Maven is pinned to 3.9.9.

## Repository layout

- [`run.sh`](run.sh) — the setup script
