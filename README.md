# ss-go-onekey

在 Vultr 等 VPS 上，用**一条命令**完成 [ToyoDAdoubiBackup/doubi](https://github.com/ToyoDAdoubiBackup/doubi) `ss-go.sh` 的下载、安装与交互配置。

上游 `ss-go.sh` 是交互式菜单脚本，需要依次手动输入“安装 → 端口 → 密码 → 加密 → 日志模式”。本项目用 `expect` 按**提示文本**自动应答，并补齐了自检、参数化、错误提示、日志脱敏和安装校验。

> 请仅在你自己拥有或已获授权管理的服务器上使用，并遵守所在地及服务器所在地区的法律法规。

---

## 特性

| 能力 | 说明 |
|------|------|
| 一条命令完成 | 下载脚本 → 安装依赖 → 自动应答 → 启动 → 校验 |
| 参数化配置 | 端口、加密方式、日志模式、上游地址、工作目录、超时均可配 |
| 密码安全 | 仓库内无任何真实密码；运行时密文输入或环境变量传入；日志自动脱敏 |
| 按提示匹配 | 匹配上游脚本的提示文本而非固定行号，上游微调顺序时仍能定位 |
| 清晰错误提示 | 分阶段报错（菜单/端口/密码/加密/日志/安装），并指出日志位置 |
| 安装后校验 | 校验配置文件、可执行文件、进程状态与端口监听 |

---

## 前置条件

- 以 **root** 身份运行（非 root 会直接报错退出）
- 系统为 CentOS / Debian / Ubuntu，架构为 **x86_64**（上游脚本仅支持 64 位）
- 已安装 `curl` 或 `wget`
- 需要 `expect`：脚本会在缺失时尝试用 `apt-get` / `yum` / `dnf` 自动安装

---

## 快速使用

把下文中的 `<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>` 替换为你自己的 GitHub 仓库路径；若你的默认分支是 `master`，请把 URL 中的 `main` 一并改为 `master`。

### 方式 A：运行时输入密码（推荐，密码不落盘）

```bash
wget -N --no-check-certificate \
  https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>/main/install.sh \
  && chmod +x install.sh && bash install.sh
```

执行后会提示两次输入密码（输入内容不显示），随后全自动完成安装。

### 方式 B：环境变量传密码（适合脚本化调用）

```bash
SS_PASSWORD='替换为你的强密码' bash install.sh
```

> 注意：方式 B 的密码会出现在 shell 历史中。执行前可在命令前加一个空格（部分 shell 会因此不记录历史），或改用方式 A。

---

## 参数一览

所有参数均为环境变量，未设置时使用默认值。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SS_PASSWORD` | 无 | **必填**。8-64 位，不能含空格。未设置时交互式密文输入 |
| `SS_PORT` | `443` | 端口，1-65535 |
| `SS_CIPHER` | `12` | 加密方式编号 1-12，默认 `chacha20-ietf-poly1305` |
| `SS_VERBOSE` | `N` | 详细日志模式，`Y` / `N` |
| `SS_SCRIPT_URL` | 官方仓库地址 | 上游 `ss-go.sh` 下载地址，可换为自建镜像 |
| `SS_WORKDIR` | `/root/ss-go-onekey` | 工作目录（存放下载的脚本与日志） |
| `SS_LOG_FILE` | `${SS_WORKDIR}/install.log` | 安装日志路径（已脱敏，权限 600） |
| `SS_PROMPT_TIMEOUT` | `30` | 等待单个交互提示的超时秒数 |
| `SS_INSTALL_TIMEOUT` | `900` | 等待整个安装流程结束的超时秒数 |

组合示例：

```bash
SS_PASSWORD='<YOUR_STRONG_PASSWORD>' SS_PORT='8388' SS_CIPHER='11' SS_VERBOSE='N' bash install.sh
```

也可使用配置模板（真实密码写入本地文件，不提交）：

```bash
cp config.example.sh config.local.sh
# 编辑 config.local.sh 填入真实值
source ./config.local.sh && bash ./install.sh
```

---

## 目录结构

```
.
├── install.sh           # 主脚本：自检 + 生成 expect 脚本 + 调用 + 校验
├── config.example.sh    # 配置模板（仅占位符）
├── README.md            # 本文档
├── .gitignore           # 忽略 config.local.sh / 日志 / 上游脚本副本
└── LICENSE              # MIT
```

---

## 工作原理

1. **预检**：root、架构、发行版、是否已安装、参数合法性、密码强度。
2. **下载**：从 `SS_SCRIPT_URL` 下载 `ss-go.sh`，并校验内容特征，防止误指向其他文件。
3. **自动应答**（expect 按提示文本匹配）：
   - `请输入数字 [0-10]:` → 发送 `1`（安装）
   - `(默认: 443):` → 发送 `SS_PORT`
   - `(默认: 随机生成):` → 发送 `SS_PASSWORD`（即“使用自设密码”）
   - `(默认: 12. chacha20-ietf-poly1305):` → 发送 `SS_CIPHER`
   - `(默认：N 禁用):` → 发送 `SS_VERBOSE`
4. **脱敏**：`read -e` 会在终端回显密码，因此写入持久日志前统一替换为 `********`。
5. **校验**：检查配置文件、二进制、进程与端口，最后打印连接信息。

---

## 密码与日志安全

- 仓库与示例配置中**只有占位符**（`CHANGE_ME_DO_NOT_COMMIT`），没有任何真实密码。
- 密码通过环境变量传给 expect，**不写入生成的临时脚本、不出现在进程命令行参数中**。
- 临时日志权限为 `600`，持久日志权限为 `600`，且密码字段已替换为 `********`。
- 注意：上游 `ss-go.sh` 自身会把密码以明文写入 `/usr/local/shadowsocks-go/shadowsocks-go.conf`，这是上游行为，本项目无法更改。请控制该文件的访问权限，且不要把配置文件提交到任何仓库。

---

## 常见错误与排错

| 报错 | 原因与处理 |
|------|-----------|
| `需要 root 权限` | 先执行 `sudo su` |
| `仅支持 x86_64` | 上游脚本限制，请更换 64 位系统 |
| `检测到 Shadowsocks 已安装` | 用 `bash /root/ss-go-onekey/ss-go.sh` 菜单管理，或选 3 卸载后重试 |
| `下载 ss-go.sh 失败` | 检查网络，或设置 `SS_SCRIPT_URL` 为可达镜像 |
| `下载内容不像是 ss-go.sh` | `SS_SCRIPT_URL` 指向了错误文件 |
| `[AUTO-ERROR] 阶段：xxx` | 上游脚本提示文本可能与本版本不同；查看日志中的实际提示后反馈 |
| `等待安装结束超时` | 调大 `SS_INSTALL_TIMEOUT`，通常是 GitHub 下载缓慢 |
| `安装完成但未检测到进程运行` | 执行 `bash /root/ss-go-onekey/ss-go.sh` 选 4 启动，并检查日志 |

完整会话日志：`/root/ss-go-onekey/install.log`（可用 `SS_LOG_FILE` 覆盖）。

---

## 后续管理

安装脚本会被保留在工作目录，直接运行即可打开上游管理菜单：

```bash
bash /root/ss-go-onekey/ss-go.sh
```

常用菜单项：`4` 启动、`5` 停止、`6` 重启、`7` 设置账号配置、`8` 查看账号信息、`9` 查看日志、`3` 卸载。

---

## 许可证

MIT
