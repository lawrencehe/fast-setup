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
