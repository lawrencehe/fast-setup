# fast-setup 项目规则

## run.sh 的基本要求

- **兼容两个系列**：每个安装步骤都必须同时支持 Debian 系（Debian / Ubuntu，
  `apt`）和 RHEL 系（RHEL / Oracle Linux / Rocky / Alma / CentOS / Fedora，
  `dnf` / `yum`）。官方脚本本身跨发行版的可以直接用；否则按 `$PM`
  分支处理（包名、软件源不同的要分别写）。
- **没安装的，安装；已经安装的，更新；已是最新版本的，跳过**：`run.sh`
  可以反复运行，每次运行后每个工具都应是最新版（固定版本的除外，如
  Maven、OpenJDK 21 主版本）。
  - 不能出现“检测到已安装就跳过”而不检查更新的写法。
  - 已是最新版时不要重复下载、重装，输出 `ok "<工具> already <版本>"` 即可
    （参考 kubectl、lazygit、nvm 的写法：先取最新版本号，与当前版本比较）。
    官方脚本或工具自带的 update 命令本身会判断“已是最新”的（如
    `rclone.org/install.sh` 退出码 3、`claude update`），直接交给它们处理。

## run.sh 安装方式的选择

给 `run.sh` 新增或修改某个工具的安装方式时，按以下优先级选择：

1. **有官方安装脚本的，优先用官方安装脚本**（例如 `rclone.org/install.sh`、
   `astral.sh/uv/install.sh`、`aliyuncli.alicdn.com/install.sh`），
   而不是发行版仓库里的包或自己拼下载/解压逻辑。
2. **有原生（native / standalone）安装器的，优先用原生安装器**，
   而不是 npm、pip 等语言包管理器分发的版本（例如 Claude Code 用
   `claude.ai/install.sh`、Codex 用 `chatgpt.com/codex/install.sh`、
   pi 用 `pi.dev/install.sh`，不用 `npm install -g`）。
3. 只有在官方脚本 / 原生安装器都没有或不可用时，才退回到系统包管理器
   （`pm_install` / `pm_try`）、官方软件源，或 npm 等。原生安装器失败时
   可以把 npm 作为兜底（参考 pi 的写法）。

配套要求：

- 已安装时优先用工具自带的更新命令（如 `claude update`、`t3 update`），
  失败再重跑官方安装脚本。
- 非关键工具安装失败只 `warn` 并继续，不要让整个脚本退出（脚本开启了
  `set -Eeuo pipefail`，注意处理安装脚本的非 0 退出码）。
- 新增工具时同步更新 `README.md` 的 “What gets installed” 列表和
  `run.sh` 末尾的 `run_ver` 版本输出。
- **下载的文件一律放在 `/tmp`**：用 `mktemp -d /tmp/fast-setup.XXXXXX`
  建临时目录（不用裸 `mktemp`，避免受 `$TMPDIR` 影响），用完删掉。
  会把文件下载到当前目录的官方脚本（如阿里云 CLI 的 `install.sh`），
  要先 `cd` 到这个临时目录再运行，不能在用户家目录或仓库目录里留下文件。

## 仓库自带脚本（bin/、claude/ 与 install.sh）

仓库里自己写的常用脚本，既能随 `run.sh` 安装，也能脱离 `run.sh` 单独安装、运行。

- **自包含**：每个脚本是单个文件，不 source 仓库里的其它文件，
  `curl -fsSL <raw URL> | bash` 也能直接跑。
- **放哪里**：命令行工具放 `bin/<名字>`（不带 `.sh`，装到 `~/.local/bin`）；
  某个软件的配套脚本放对应目录（如 `claude/`）。
- **新增脚本只改两处**：
  1. 把文件放进上面的目录；
  2. 在 `install.sh` 的 `SCRIPTS` 里登记一行 `名字|仓库内路径|安装路径`。
     需要额外配置的（如改 `settings.json`），写一个 `post_<名字>` 函数
     （名字里的 `-` 换成 `_`）。
  `run.sh` 调用 `install.sh all`，不用改。
- **install.sh 的要求**：不需要 root / sudo，Linux 和 macOS 都能用，
  不依赖 `apt` / `dnf`；内容相同的跳过（`ok "<名字> already latest"`），
  不同的才覆盖；修改用户已有配置前先检查，不覆盖用户自己的设置。
- **同步更新 `README.md`** 的 “fast-setup scripts” 表格和说明。
- 只收服务器上常用的脚本；与服务器无关的脚本不放进本仓库。
