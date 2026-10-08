#!/usr/bin/env bash
#
# Cross-distro development environment setup.
# Supports:
#   - Debian / Ubuntu            (apt)
#   - RHEL family incl. Oracle Linux, Rocky, Alma, CentOS, Fedora (dnf/yum)
#
# Adapted from https://github.com/LawrenceHe/fast-setup/blob/main/run.sh
set -Eeuo pipefail

MAVEN_VERSION="3.9.9"
export DEBIAN_FRONTEND=noninteractive

log(){ printf '\n==> %s\n' "$*"; }
ok(){ printf '✓ %s\n' "$*"; }
warn(){ printf '⚠ %s\n' "$*" >&2; }
die(){ printf '✗ %s\n' "$*" >&2; exit 1; }
trap 'printf "✗ Failed at line %s\n" "$LINENO" >&2' ERR

[[ $EUID -ne 0 ]] || die "Run as a normal user with sudo privileges."

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
fi

# ---------------------------------------------------------------------------
# Package manager detection
# ---------------------------------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  PM=apt
elif command -v dnf >/dev/null 2>&1; then
  PM=dnf
elif command -v yum >/dev/null 2>&1; then
  PM=yum
else
  die "Unsupported distribution: no apt-get/dnf/yum found. This script targets Debian/Ubuntu and RHEL-family systems."
fi

# ---------------------------------------------------------------------------
# Architecture
# ---------------------------------------------------------------------------
case "$(uname -m)" in
  x86_64) ARCH=amd64; LG_ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64; LG_ARCH=arm64 ;;
  *) die "Unsupported architecture: $(uname -m)" ;;
esac

# sudo -v under sudo-rs may demand a password when any non-NOPASSWD rule matches;
# try non-interactive first, then fall back to interactive.
sudo -n true 2>/dev/null || sudo -v || die "sudo is not usable for $(id -un)."
log "Distro: ${PRETTY_NAME:-${ID:-unknown}} (PM: ${PM}); architecture: ${ARCH}"

# ---------------------------------------------------------------------------
# Package helpers
# ---------------------------------------------------------------------------
# Install a package if it is missing, upgrade it if it is present, and leave it
# untouched if it is already the latest available version.
pm_install() {
  local rc=0 p
  case "$PM" in
    apt)
      for p in "$@"; do
        sudo apt-get install -y "$p" || rc=1
      done
      ;;
    dnf|yum)
      for p in "$@"; do
        case "$p" in
          http://*|https://*|ftp://*|*.rpm)
            # A file/URL (e.g. the EPEL release rpm): install it directly.
            sudo "$PM" -y install "$p" || rc=1
            ;;
          *)
            if rpm -q "$p" >/dev/null 2>&1; then
              # Present: upgrade to latest (no-op when already latest).
              sudo "$PM" -y upgrade "$p" || rc=1
            else
              # Missing: install the latest available version.
              sudo "$PM" -y install "$p" || rc=1
            fi
            ;;
        esac
      done
      ;;
  esac
  return $rc
}

pm_try() {
  pm_install "$@"
}

pm_try_each() {
  local rc=0 p
  for p in "$@"; do
    if ! pm_install "$p" >/dev/null 2>&1; then
      warn "could not install ${p}"
      rc=1
    fi
  done
  return $rc
}

repo_add() {
  local url="$1"
  case "$PM" in
    dnf)
      if command -v dnf5 >/dev/null 2>&1; then
        sudo dnf5 config-manager addrepo --overwrite --save-filename=docker-ce.repo --from-repofile="$url"
      else
        pm_try dnf-plugins-core >/dev/null 2>&1 || true
        sudo dnf config-manager --add-repo "$url"
      fi
      ;;
    yum)
      pm_try yum-utils >/dev/null 2>&1 || true
      sudo yum-config-manager --add-repo "$url"
      ;;
  esac
  sudo "$PM" -y makecache || true
}

repo_enable() {
  local repo="$1"
  case "$PM" in
    dnf)
      sudo dnf repolist --all 2>/dev/null | grep -qE "^[[:space:]]*${repo}[[:space:]]" || return 0
      if command -v dnf5 >/dev/null 2>&1; then
        sudo dnf5 config-manager setopt "${repo}.enabled=1" || warn "could not enable ${repo} (best effort)"
      else
        pm_try dnf-plugins-core >/dev/null 2>&1 || true
        sudo dnf config-manager --set-enabled "$repo" || warn "could not enable ${repo} (best effort)"
      fi
      sudo dnf -y makecache || true
      ;;
    yum)
      sudo yum repolist all 2>/dev/null | grep -qE "^[[:space:]]*${repo}[[:space:]]" || return 0
      pm_try yum-utils >/dev/null 2>&1 || true
      sudo yum-config-manager --set-enabled "$repo" || warn "could not enable ${repo} (best effort)"
      sudo yum -y makecache || true
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Repositories (EPEL + CodeReady Builder for RHEL-family)
# ---------------------------------------------------------------------------
enable_crb() {
  local major="${VERSION_ID:-0}"
  major="${major%%.*}"
  [[ "$major" =~ ^[0-9]+$ ]] || major=0
  local repo=""
  case "${ID:-}" in
    ol) repo="ol${major}_codeready_builder" ;;
    rhel) repo="codeready-builder-for-rhel-${major}-$(uname -m)-rpms" ;;
    rocky|almalinux|cloudlinux|eurolinux|virtuozzo)
      if (( major >= 9 )); then repo="crb"; else repo="powertools"; fi ;;
    centos)
      if (( major >= 9 )); then repo="crb"; else repo="powertools"; fi ;;
  esac
  [[ -n "$repo" ]] && repo_enable "$repo"
}

enable_epel() {
  local major="${VERSION_ID:-0}"
  major="${major%%.*}"
  [[ "$major" =~ ^[0-9]+$ ]] || major=0
  case "${ID:-}" in
    fedora|amzn) return 0 ;;  # Fedora ships these natively; Amazon Linux has its own repos
    ol)
      pm_install "oracle-epel-release-el${major}"
      repo_enable "ol${major}_developer_EPEL"
      ;;
    rhel|centos|rocky|almalinux|cloudlinux|eurolinux|virtuozzo)
      pm_install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major}.noarch.rpm"
      ;;
    *)
      warn "EPEL: unknown RHEL-family ID '${ID:-}'; trying Fedora EPEL ${major} best-effort."
      pm_try "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major}.noarch.rpm" || true
      ;;
  esac
  sudo "$PM" -y makecache || true
}

setup_repos() {
  case "$PM" in
    apt)
      sudo apt-get update -y
      ;;
    dnf|yum)
      sudo "$PM" -y makecache || true
      case "${ID:-}" in
        fedora) : ;;
        *) enable_crb; enable_epel ;;
      esac
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Base packages: required (fatal) vs optional (best-effort)
# ---------------------------------------------------------------------------
case "$PM" in
  apt)
    REQUIRED_PKGS=(ca-certificates curl tar gzip gnupg jq ncurses-bin)
    OPTIONAL_PKGS=(wget unzip zip xz-utils rsync lsof build-essential git tmux mosh \
      postgresql-client neovim btop)
    ;;
  dnf)
    REQUIRED_PKGS=(ca-certificates curl tar gzip gnupg2 jq ncurses)
    OPTIONAL_PKGS=(wget unzip zip xz rsync lsof gcc gcc-c++ make git tmux mosh \
      postgresql neovim btop)
    ;;
  yum)
    # EL7: no btop
    REQUIRED_PKGS=(ca-certificates curl tar gzip gnupg2 jq ncurses)
    OPTIONAL_PKGS=(wget unzip zip xz rsync lsof gcc gcc-c++ make git tmux mosh \
      postgresql neovim)
    ;;
esac

log "Package repositories"
setup_repos

log "Required base packages"
pm_install "${REQUIRED_PKGS[@]}"

log "Optional developer packages"
if ! pm_try "${OPTIONAL_PKGS[@]}" >/dev/null 2>&1; then
  warn "Some optional packages are unavailable as a group; installing individually."
  pm_try_each "${OPTIONAL_PKGS[@]}" || warn "Some optional packages could not be installed."
fi

# ---------------------------------------------------------------------------
# zsh
# ---------------------------------------------------------------------------
log "zsh"
pm_install zsh || warn "zsh could not be installed (continuing)"

# MySQL/MariaDB client (package name varies by distro)
log "MySQL/MariaDB client"
case "$PM" in
  apt)
    pm_try mysql-client || pm_try default-mysql-client || warn "no MySQL client package found"
    ;;
  dnf)
    if [[ "${ID:-}" == fedora ]]; then
      pm_try community-mysql || warn "no MySQL client package found"
    else
      pm_try mysql || warn "no MySQL client package found"
    fi
    ;;
  yum)
    pm_try mysql || warn "no MySQL client package found"
    ;;
esac

# ---------------------------------------------------------------------------
# Java (OpenJDK 21 — stay on the 21 line, latest 21.x only)
# ---------------------------------------------------------------------------
log "Java (OpenJDK 21)"
case "$PM" in
  apt)
    pm_install openjdk-21-jdk || warn "openjdk-21-jdk unavailable; skipping Java (no other major version installed)."
    ;;
  dnf|yum)
    pm_install java-21-openjdk-devel || warn "java-21-openjdk-devel unavailable; skipping Java (no other major version installed)."
    ;;
esac

# ---------------------------------------------------------------------------
# Maven
# ---------------------------------------------------------------------------
log "Maven ${MAVEN_VERSION}"
CURRENT_MAVEN="$(mvn -version 2>/dev/null | head -1 | awk '{print $3}' || true)"
if [[ "$CURRENT_MAVEN" != "$MAVEN_VERSION" ]]; then
  tmp="$(mktemp -d)"
  curl -fL "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -o "$tmp/maven.tgz"
  sudo rm -rf "/opt/apache-maven-${MAVEN_VERSION}"
  sudo tar -xzf "$tmp/maven.tgz" -C /opt
  sudo ln -sfn "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven
  sudo ln -sfn /opt/maven/bin/mvn /usr/local/bin/mvn
  rm -rf "$tmp"
else
  ok "Maven already ${MAVEN_VERSION}"
fi

# ---------------------------------------------------------------------------
# uv + latest stable Python
# ---------------------------------------------------------------------------
log "uv + latest stable Python"
export PATH="$HOME/.local/bin:$PATH"
if command -v uv >/dev/null 2>&1; then
  uv self update || true
else
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
uv python install --default

# ---------------------------------------------------------------------------
# nvm + latest Node.js LTS
# ---------------------------------------------------------------------------
log "nvm + latest Node.js LTS"
export NVM_DIR="$HOME/.nvm"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  NVM_VERSION="$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -r '.tag_name')"
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi
# shellcheck disable=SC1090
. "$NVM_DIR/nvm.sh"
# nvm conflicts with prefix/globalconfig in ~/.npmrc (nvm use returns 11)
if [[ -f "$HOME/.npmrc" ]] && grep -qE '^[[:space:]]*(prefix|globalconfig)[[:space:]]*=' "$HOME/.npmrc"; then
  cp "$HOME/.npmrc" "$HOME/.npmrc.bak.$(date +%s)"
  sed -i -E '/^[[:space:]]*(prefix|globalconfig)[[:space:]]*=/d' "$HOME/.npmrc"
  ok "Removed prefix/globalconfig from ~/.npmrc (backup kept)"
fi
nvm install --lts
nvm alias default 'lts/*'
nvm use default

# ---------------------------------------------------------------------------
# pi coding agent
# ---------------------------------------------------------------------------
log "pi coding agent"
# https://github.com/earendil-works/pi — installs into the nvm-managed Node
npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# ---------------------------------------------------------------------------
# herdr
# ---------------------------------------------------------------------------
log "herdr"
# https://github.com/herdrdev/herdr — official installer, puts the binary in ~/.local/bin
curl -fsSL https://herdr.dev/install.sh | sh

# ---------------------------------------------------------------------------
# mosh firewall
# ---------------------------------------------------------------------------
log "mosh firewall"
if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state 2>/dev/null | grep -q running; then
  sudo firewall-cmd --permanent --add-port=60000-61000/udp
  sudo firewall-cmd --reload
elif command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q '^Status: active'; then
  sudo ufw allow 60000:61000/udp
else
  ok "no local firewall active; if the provider has a cloud firewall, open UDP 60000-61000 for mosh"
fi

# ---------------------------------------------------------------------------
# Docker CE
# ---------------------------------------------------------------------------
log "Docker CE"
case "$PM" in
  apt)
    curl -fsSL https://get.docker.com | sudo sh
    ;;
  dnf|yum)
    case "${ID:-}" in
      fedora) repo_url="https://download.docker.com/linux/fedora/docker-ce.repo" ;;
      *) repo_url="https://download.docker.com/linux/centos/docker-ce.repo" ;;
    esac
    repo_add "$repo_url"
    pm_install docker-ce docker-ce-cli containerd.io
    pm_try docker-buildx-plugin || true
    pm_try docker-compose-plugin || true
    ;;
esac
if getent group docker >/dev/null 2>&1 && ! id -nG | tr ' ' '\n' | grep -qx docker; then
  sudo usermod -aG docker "$(id -un)"
  DOCKER_RELOGIN=1
fi

# ---------------------------------------------------------------------------
# kubectl latest stable
# ---------------------------------------------------------------------------
log "kubectl latest stable"
KUBE_LATEST="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
KUBE_CURRENT="$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion // empty' || true)"
if [[ "$KUBE_CURRENT" != "$KUBE_LATEST" ]]; then
  tmp="$(mktemp -d)"
  curl -fL "https://dl.k8s.io/release/${KUBE_LATEST}/bin/linux/${ARCH}/kubectl" -o "$tmp/kubectl"
  curl -fL "https://dl.k8s.io/release/${KUBE_LATEST}/bin/linux/${ARCH}/kubectl.sha256" -o "$tmp/kubectl.sha256"
  echo "$(cat "$tmp/kubectl.sha256")  $tmp/kubectl" | sha256sum --check
  sudo install -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl
  rm -rf "$tmp"
else
  ok "kubectl already ${KUBE_LATEST}"
fi

# ---------------------------------------------------------------------------
# Alibaba Cloud CLI
# ---------------------------------------------------------------------------
log "Alibaba Cloud CLI"
# Official installer installs/updates the CLI and detects Linux architecture.
curl -fsSL https://aliyuncli.alicdn.com/install.sh | sudo bash

# ---------------------------------------------------------------------------
# lazygit latest
# ---------------------------------------------------------------------------
log "lazygit latest"
LG_LATEST="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
LG_CURRENT="$(lazygit --version 2>/dev/null | grep -oE ', version=[^,]+' | cut -d= -f2 || true)"
if [[ "$LG_CURRENT" != "$LG_LATEST" ]]; then
  tmp="$(mktemp -d)"
  curl -fL "https://github.com/jesseduffield/lazygit/releases/download/v${LG_LATEST}/lazygit_${LG_LATEST}_linux_${LG_ARCH}.tar.gz" -o "$tmp/lazygit.tgz"
  tar -xzf "$tmp/lazygit.tgz" -C "$tmp" lazygit
  sudo install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
  rm -rf "$tmp"
else
  ok "lazygit already ${LG_LATEST}"
fi

# ---------------------------------------------------------------------------
# Ghostty terminfo
# ---------------------------------------------------------------------------
log "Ghostty terminfo"
tmp="$(mktemp)"
cat >"$tmp" <<'TERMINFO'
# Reconstructed via infocmp from file: /Applications/Ghostty.app/Contents/Resources/terminfo/78/xterm-ghostty
xterm-ghostty|ghostty|Ghostty,
        am, bce, ccc, hs, km, mc5i, mir, msgr, npc, xenl, AX, Su, Tc, XT, fullkbd,
        colors#256, cols#80, it#8, lines#24, pairs#32767,
        acsc=++\,\,--..00``aaffgghhiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~,
        bel=^G, blink=\E[5m, bold=\E[1m, cbt=\E[Z, civis=\E[?25l,
        clear=\E[H\E[2J, cnorm=\E[?12l\E[?25h, cr=^M,
        csr=\E[%i%p1%d;%p2%dr, cub=\E[%p1%dD, cub1=^H,
        cud=\E[%p1%dB, cud1=^J, cuf=\E[%p1%dC, cuf1=\E[C,
        cup=\E[%i%p1%d;%p2%dH, cuu=\E[%p1%dA, cuu1=\E[A,
        cvvis=\E[?12;25h, dch=\E[%p1%dP, dch1=\E[P, dim=\E[2m,
        dl=\E[%p1%dM, dl1=\E[M, dsl=\E]2;\007, ech=\E[%p1%dX,
        ed=\E[J, el=\E[K, el1=\E[1K, flash=\E[?5h$<100/>\E[?5l,
        fsl=^G, home=\E[H, hpa=\E[%i%p1%dG, ht=^I, hts=\EH,
        ich=\E[%p1%d@, ich1=\E[@, il=\E[%p1%dL, il1=\E[L, ind=^J,
        indn=\E[%p1%dS,
        initc=\E]4;%p1%d;rgb\:%p2%{255}%*%{1000}%/%2.2X/%p3%{255}%*%{1000}%/%2.2X/%p4%{255}%*%{1000}%/%2.2X\E\\,
        invis=\E[8m, kDC=\E[3;2~, kEND=\E[1;2F, kHOM=\E[1;2H,
        kIC=\E[2;2~, kLFT=\E[1;2D, kNXT=\E[6;2~, kPRV=\E[5;2~,
        kRIT=\E[1;2C, kbs=\177, kcbt=\E[Z, kcub1=\EOD, kcud1=\EOB,
        kcuf1=\EOC, kcuu1=\EOA, kdch1=\E[3~, kend=\EOF, kent=\EOM,
        kf1=\EOP, kf10=\E[21~, kf11=\E[23~, kf12=\E[24~,
        kf13=\E[1;2P, kf14=\E[1;2Q, kf15=\E[1;2R, kf16=\E[1;2S,
        kf17=\E[15;2~, kf18=\E[17;2~, kf19=\E[18;2~, kf2=\EOQ,
        kf20=\E[19;2~, kf21=\E[20;2~, kf22=\E[21;2~,
        kf23=\E[23;2~, kf24=\E[24;2~, kf25=\E[1;5P, kf26=\E[1;5Q,
        kf27=\E[1;5R, kf28=\E[1;5S, kf29=\E[15;5~, kf3=\EOR,
        kf30=\E[17;5~, kf31=\E[18;5~, kf32=\E[19;5~,
        kf33=\E[20;5~, kf34=\E[21;5~, kf35=\E[23;5~,
        kf36=\E[24;5~, kf37=\E[1;6P, kf38=\E[1;6Q, kf39=\E[1;6R,
        kf4=\EOS, kf40=\E[1;6S, kf41=\E[15;6~, kf42=\E[17;6~,
        kf43=\E[18;6~, kf44=\E[19;6~, kf45=\E[20;6~,
        kf46=\E[21;6~, kf47=\E[23;6~, kf48=\E[24;6~,
        kf49=\E[1;3P, kf5=\E[15~, kf50=\E[1;3Q, kf51=\E[1;3R,
        kf52=\E[1;3S, kf53=\E[15;3~, kf54=\E[17;3~,
        kf55=\E[18;3~, kf56=\E[19;3~, kf57=\E[20;3~,
        kf58=\E[21;3~, kf59=\E[23;3~, kf6=\E[17~, kf60=\E[24;3~,
        kf61=\E[1;4P, kf62=\E[1;4Q, kf63=\E[1;4R, kf7=\E[18~,
        kf8=\E[19~, kf9=\E[20~, khome=\EOH, kich1=\E[2~,
        kind=\E[1;2B, kmous=\E[<, knp=\E[6~, kpp=\E[5~,
        kri=\E[1;2A, oc=\E]104\007, op=\E[39;49m, rc=\E8,
        rep=%p1%c\E[%p2%{1}%-%db, rev=\E[7m, ri=\EM,
        rin=\E[%p1%dT, ritm=\E[23m, rmacs=\E(B, rmam=\E[?7l,
        rmcup=\E[?1049l, rmir=\E[4l, rmkx=\E[?1l\E>, rmso=\E[27m,
        rmul=\E[24m, rs1=\E]\E\\\Ec, sc=\E7,
        setab=\E[%?%p1%{8}%<%t4%p1%d%e%p1%{16}%<%t10%p1%{8}%-%d%e48;5;%p1%d%;m,
        setaf=\E[%?%p1%{8}%<%t3%p1%d%e%p1%{16}%<%t9%p1%{8}%-%d%e38;5;%p1%d%;m,
        sgr=%?%p9%t\E(0%e\E(B%;\E[0%?%p6%t;1%;%?%p5%t;2%;%?%p2%t;4%;%?%p1%p3%|%t;7%;%?%p4%t;5%;%?%p7%t;8%;m,
        sgr0=\E(B\E[m, sitm=\E[3m, smacs=\E(0, smam=\E[?7h,
        smcup=\E[?1049h, smir=\E[4h, smkx=\E[?1h\E=, smso=\E[7m,
        smul=\E[4m, tbc=\E[3g, tsl=\E]2;, u6=\E[%i%d;%dR, u7=\E[6n,
        u8=\E[?%[;0123456789]c, u9=\E[c, vpa=\E[%i%p1%dd,
        BD=\E[?2004l, BE=\E[?2004h, Clmg=\E[s,
        Cmg=\E[%i%p1%d;%p2%ds, Dsmg=\E[?69l, E3=\E[3J,
        Enmg=\E[?69h, Ms=\E]52;%p1%s;%p2%s\007, PE=\E[201~,
        PS=\E[200~, RV=\E[>c, Se=\E[2 q,
        Setulc=\E[58\:2\:\:%p1%{65536}%/%d\:%p1%{256}%/%{255}%&%d\:%p1%{255}%&%d%;m,
        Smulx=\E[4\:%p1%dm, Ss=\E[%p1%d q,
        Sync=\E[?2026%?%p1%{1}%-%tl%eh%;,
        XM=\E[?1006;1000%?%p1%{1}%=%th%el%;, XR=\E[>0q,
        fd=\E[?1004l, fe=\E[?1004h, kDC3=\E[3;3~, kDC4=\E[3;4~,
        kDC5=\E[3;5~, kDC6=\E[3;6~, kDC7=\E[3;7~, kDN=\E[1;2B,
        kDN3=\E[1;3B, kDN4=\E[1;4B, kDN5=\E[1;5B, kDN6=\E[1;6B,
        kDN7=\E[1;7B, kEND3=\E[1;3F, kEND4=\E[1;4F,
        kEND5=\E[1;5F, kEND6=\E[1;6F, kEND7=\E[1;7F,
        kHOM3=\E[1;3H, kHOM4=\E[1;4H, kHOM5=\E[1;5H,
        kHOM6=\E[1;6H, kHOM7=\E[1;7H, kIC3=\E[2;3~, kIC4=\E[2;4~,
        kIC5=\E[2;5~, kIC6=\E[2;6~, kIC7=\E[2;7~, kLFT3=\E[1;3D,
        kLFT4=\E[1;4D, kLFT5=\E[1;5D, kLFT6=\E[1;6D,
        kLFT7=\E[1;7D, kNXT3=\E[6;3~, kNXT4=\E[6;4~,
        kNXT5=\E[6;5~, kNXT6=\E[6;6~, kNXT7=\E[6;7~,
        kPRV3=\E[5;3~, kPRV4=\E[5;4~, kPRV5=\E[5;5~,
        kPRV6=\E[5;6~, kPRV7=\E[5;7~, kRIT3=\E[1;3C,
        kRIT4=\E[1;4C, kRIT5=\E[1;5C, kRIT6=\E[1;6C,
        kRIT7=\E[1;7C, kUP=\E[1;2A, kUP3=\E[1;3A, kUP4=\E[1;4A,
        kUP5=\E[1;5A, kUP6=\E[1;6A, kUP7=\E[1;7A, kxIN=\E[I,
        kxOUT=\E[O, rmxx=\E[29m, rv=\E\\[[0-9]+;[0-9]+;[0-9]+c,
        setrgbb=\E[48\:2\:%p1%d\:%p2%d\:%p3%dm,
        setrgbf=\E[38\:2\:%p1%d\:%p2%d\:%p3%dm, smxx=\E[9m,
        xm=\E[<%i%p3%d;%p1%d;%p2%d;%?%p4%tM%em%;,
        xr=\EP>\\|[ -~]+a\E\\,
TERMINFO
sudo tic -x -o /usr/share/terminfo "$tmp"
rm -f "$tmp"
infocmp -x xterm-ghostty >/dev/null
ok "xterm-ghostty installed globally"

# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------
run_ver() {
  local desc="$1"; shift
  if command -v "$1" >/dev/null 2>&1; then
    "$@" 2>&1 | head -1 || true
  else
    warn "${desc}: not installed"
  fi
}

log "Versions"
run_ver git git --version
run_ver java java -version
run_ver maven mvn -version
run_ver uv uv --version
run_ver python3 python3 --version
run_ver node node --version
run_ver npm npm --version
run_ver docker docker --version
run_ver kubectl kubectl version --client
run_ver aliyun aliyun version
run_ver mysql mysql --version
run_ver psql psql --version
run_ver nvim nvim --version
run_ver lazygit lazygit --version
run_ver btop btop --version
run_ver tmux tmux -V
run_ver mosh mosh --version
run_ver pi pi --version
run_ver herdr herdr --version

printf '\n✓ VPS setup complete.\n'
if [[ "${DOCKER_RELOGIN:-0}" == 1 ]]; then
  printf 'NOTE: Log out and SSH back in once so Docker group membership takes effect.\n'
fi
