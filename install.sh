#!/usr/bin/env bash
#===============================================================================
# ss-go-onekey
# 用途：在 Vultr 等 VPS 上，用一条命令自动化 Toyo/doubi 的 ss-go.sh 安装流程
# 项目模板：https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>
# 完整文档：README.md
#
# 密码来源（按优先级）：
#   1. 环境变量 SS_PASSWORD
#   2. 未设置时，运行时交互式密文输入（两次确认）
# 本脚本与仓库中均不包含任何真实密码。
#===============================================================================

set -uo pipefail

VERSION="1.0.0"

#-------------------------------------------------------------------------------
# 可配置参数：全部可通过环境变量覆盖，详见 README.md
#-------------------------------------------------------------------------------
UPSTREAM_URL="${SS_SCRIPT_URL:-https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/ss-go.sh}"
WORKDIR="${SS_WORKDIR:-/root/ss-go-onekey}"
LOG_FILE="${SS_LOG_FILE:-${WORKDIR}/install.log}"

PORT="${SS_PORT:-443}"
CIPHER="${SS_CIPHER:-12}"          # 1-12，对应上游脚本的加密方式菜单
VERBOSE="${SS_VERBOSE:-N}"         # Y 开启详细日志，N 关闭

PROMPT_TIMEOUT="${SS_PROMPT_TIMEOUT:-30}"    # 等待每个交互提示的秒数
INSTALL_TIMEOUT="${SS_INSTALL_TIMEOUT:-900}" # 等待整个安装过程结束的秒数

# 上游脚本的固定路径（Toyo/doubi ss-go.sh）
CONF="/usr/local/shadowsocks-go/shadowsocks-go.conf"
BIN="/usr/local/shadowsocks-go/shadowsocks-go"
INIT_SCRIPT="/etc/init.d/ss-go"

TMP_EXPECT=""
TMP_LOG=""
PASSWORD=""

#-------------------------------------------------------------------------------
# 基础输出函数
#-------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_RESET=''
fi

log_ok()   { printf '%s[ OK ]%s %s\n'  "$C_GREEN"  "$C_RESET" "$*"; }
log_info() { printf '%s[INFO]%s %s\n'  "$C_GREEN"  "$C_RESET" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n'  "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err()  { printf '%s[ERR ]%s %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; }

die() {
    log_err "$*"
    log_err "安装已中止。若已产生日志，请查看：${LOG_FILE}"
    exit 1
}

cleanup() {
    [[ -n "$TMP_EXPECT" && -f "$TMP_EXPECT" ]] && rm -f "$TMP_EXPECT"
    [[ -n "$TMP_LOG" && -f "$TMP_LOG" ]] && rm -f "$TMP_LOG"
}
trap cleanup EXIT INT TERM

#-------------------------------------------------------------------------------
# 参数校验
#-------------------------------------------------------------------------------
check_root() {
    [[ "$EUID" -eq 0 ]] || die "需要 root 权限。请先执行 sudo su 切换到 root 后重试。"
}

need_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        die "系统缺少 curl 或 wget，无法下载上游脚本。请先安装其一（如 apt-get install -y curl）。"
    fi
}

check_arch() {
    local arch
    arch="$(uname -m)"
    [[ "$arch" == "x86_64" || "$arch" == "amd64" ]] || \
        die "上游 ss-go.sh 仅支持 x86_64 64 位系统，当前架构为 ${arch}。"
}

check_os() {
    if [[ -f /etc/redhat-release ]]; then
        OS_FAMILY="centos"
    elif grep -qiE 'debian' /etc/issue 2>/dev/null || grep -qiE 'debian' /proc/version 2>/dev/null; then
        OS_FAMILY="debian"
    elif grep -qiE 'ubuntu' /etc/issue 2>/dev/null || grep -qiE 'ubuntu' /proc/version 2>/dev/null; then
        OS_FAMILY="debian"
    else
        OS_FAMILY="unknown"
        log_warn "未能识别操作系统发行版，上游脚本对 CentOS/Debian/Ubuntu 支持最好。"
    fi
}

check_not_installed() {
    [[ ! -e "$BIN" ]] || \
        die "检测到 Shadowsocks 已安装（${BIN}）。请直接使用 'bash ${WORKDIR}/ss-go.sh' 菜单管理，或先从菜单选择 3 卸载。"
}

validate_params() {
    [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || \
        die "端口 SS_PORT 必须为 1-65535 的整数，当前值：${PORT}"

    [[ "$CIPHER" =~ ^[0-9]+$ ]] && (( CIPHER >= 1 && CIPHER <= 12 )) || \
        die "加密方式 SS_CIPHER 必须为 1-12 的数字，当前值：${CIPHER}"

    case "$VERBOSE" in
        [Yy]) VERBOSE="Y" ;;
        [Nn]) VERBOSE="N" ;;
        *) die "SS_VERBOSE 只能是 Y 或 N，当前值：${VERBOSE}" ;;
    esac

    [[ "$PROMPT_TIMEOUT" =~ ^[0-9]+$ ]] && (( PROMPT_TIMEOUT > 0 )) || \
        die "SS_PROMPT_TIMEOUT 必须为正整数秒数。"
    [[ "$INSTALL_TIMEOUT" =~ ^[0-9]+$ ]] && (( INSTALL_TIMEOUT > 0 )) || \
        die "SS_INSTALL_TIMEOUT 必须为正整数秒数。"
}

get_password() {
    if [[ -n "${SS_PASSWORD:-}" ]]; then
        PASSWORD="$SS_PASSWORD"
        log_info "已从环境变量 SS_PASSWORD 读取密码。"
    else
        printf '%s请输入 Shadowsocks 密码（输入内容不显示）: %s' "$C_YELLOW" "$C_RESET" >&2
        read -r -s PASSWORD || die "无法读取密码输入。"
        printf '\n' >&2
        printf '%s请再次确认密码: %s' "$C_YELLOW" "$C_RESET" >&2
        local confirm=""
        read -r -s confirm || die "无法读取确认密码输入。"
        printf '\n' >&2
        [[ "$PASSWORD" == "$confirm" ]] || die "两次输入的密码不一致。"
        unset confirm
    fi

    local len=${#PASSWORD}
    (( len >= 8 && len <= 64 )) || die "密码长度必须为 8-64 位，当前为 ${len} 位。"
    [[ "$PASSWORD" != *[[:space:]]* ]] || \
        die "密码不能包含空格或制表符：上游脚本按空格解析配置文件，含空白会导致安装后密码异常。"
}

ensure_expect() {
    command -v expect >/dev/null 2>&1 && return 0

    log_info "未检测到 expect，正在尝试自动安装（自动化交互所需）..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq expect
    elif command -v yum >/dev/null 2>&1; then
        yum install -y expect
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y expect
    else
        die "无法自动安装 expect。请手动安装后重试：CentOS: yum install -y expect / Debian: apt-get install -y expect"
    fi

    command -v expect >/dev/null 2>&1 || \
        die "expect 安装失败。请手动执行：yum install -y expect 或 apt-get install -y expect"
    log_ok "expect 安装完成。"
}

download_upstream() {
    SCRIPT_PATH="${WORKDIR}/ss-go.sh"
    log_info "下载上游脚本：${UPSTREAM_URL}"

    if [[ "$DOWNLOADER" == "curl" ]]; then
        curl -fsSL --retry 3 --connect-timeout 15 "$UPSTREAM_URL" -o "$SCRIPT_PATH" || \
            die "下载 ss-go.sh 失败，请检查网络或 SS_SCRIPT_URL。"
    else
        wget -q --no-check-certificate --tries=3 --timeout=15 "$UPSTREAM_URL" -O "$SCRIPT_PATH" || \
            die "下载 ss-go.sh 失败，请检查网络或 SS_SCRIPT_URL。"
    fi

    [[ -s "$SCRIPT_PATH" ]] || die "下载的 ss-go.sh 为空文件。"
    grep -q 'Shadowsocks-Go 一键管理脚本' "$SCRIPT_PATH" || \
        die "下载内容不像是 ss-go.sh，请检查 SS_SCRIPT_URL 是否指向正确文件。"
    chmod +x "$SCRIPT_PATH"
    log_ok "上游脚本已下载至 ${SCRIPT_PATH}。"
}

#-------------------------------------------------------------------------------
# 生成 expect 自动化脚本
# 关键点：按“提示文本”匹配而非按行号灌输入，上游脚本调整顺序时也能定位到正确输入点。
#-------------------------------------------------------------------------------
write_expect_script() {
    TMP_EXPECT="$(mktemp "${TMPDIR:-/tmp}/ss-go-onekey-exp.XXXXXX")"
    chmod 600 "$TMP_EXPECT"

    cat > "$TMP_EXPECT" <<'EXPECT_EOF'
#!/usr/bin/expect -f
# 本文件由 install.sh 在运行时生成，请勿手工修改。
# 密码通过环境变量传入，不写入脚本文件、不出现在命令行参数中。

proc step_failed {stage detail} {
    global env
    puts stderr ""
    puts stderr {  [AUTO-ERROR] 自动化交互失败}
    puts stderr "  阶段：$stage"
    puts stderr "  原因：$detail"
    puts stderr "  会话日志：$env(SS_TMP_LOG)"
    exit 1
}

set timeout $env(SS_PROMPT_TIMEOUT)
set script_path $env(SS_SCRIPT_PATH)

log_file -a $env(SS_TMP_LOG)

spawn bash $script_path

# 1) 主菜单 -> 选择 1：安装 Shadowsocks
expect {
    -ex {请输入数字 [0-10]:} { send -- "1\r" }
    timeout { step_failed "主菜单" "等待菜单提示超时（$env(SS_PROMPT_TIMEOUT) 秒）" }
    eof     { step_failed "主菜单" "上游脚本在进入菜单前意外退出" }
}

# 2) 端口
expect {
    -ex "(默认: 443):" { send -- "$env(SS_PORT)\r" }
    timeout { step_failed "端口设置" "等待端口提示超时" }
    eof     { step_failed "端口设置" "上游脚本在端口设置前意外退出" }
}

# 3) 密码（使用自设密码：直接发送运行时传入的值）
expect {
    -ex "(默认: 随机生成):" { send -- "$env(SS_PASSWORD)\r" }
    timeout { step_failed "密码设置" "等待密码提示超时" }
    eof     { step_failed "密码设置" "上游脚本在密码设置前意外退出" }
}

# 4) 加密方式
expect {
    -ex "(默认: 12. chacha20-ietf-poly1305):" { send -- "$env(SS_CIPHER)\r" }
    timeout { step_failed "加密方式设置" "等待加密方式提示超时" }
    eof     { step_failed "加密方式设置" "上游脚本在加密设置前意外退出" }
}

# 5) 详细日志模式
expect {
    -ex "(默认：N 禁用):" { send -- "$env(SS_VERBOSE)\r" }
    timeout { step_failed "日志模式设置" "等待日志模式提示超时" }
    eof     { step_failed "日志模式设置" "上游脚本在日志设置前意外退出" }
}

# 6) 等待安装（下载二进制、写配置、防火墙、启动）结束
set timeout $env(SS_INSTALL_TIMEOUT)
expect {
    eof     { }
    timeout { step_failed "安装执行" "等待安装结束超时（$env(SS_INSTALL_TIMEOUT) 秒），请检查网络或查看日志" }
}
EXPECT_EOF

    chmod 600 "$TMP_EXPECT"
}

run_automation() {
    TMP_LOG="$(mktemp "${TMPDIR:-/tmp}/ss-go-onekey-log.XXXXXX")"
    chmod 600 "$TMP_LOG"

    export SS_PROMPT_TIMEOUT SS_INSTALL_TIMEOUT
    export SS_SCRIPT_PATH="$SCRIPT_PATH"
    export SS_TMP_LOG="$TMP_LOG"
    export SS_PORT="$PORT" SS_CIPHER="$CIPHER" SS_VERBOSE="$VERBOSE"
    export SS_PASSWORD="$PASSWORD"

    log_info "开始自动应答安装流程（端口 ${PORT}，加密 ${CIPHER}，详细日志 ${VERBOSE}）..."
    expect -f "$TMP_EXPECT"
    local rc=$?

    # 会话日志脱敏：read -e 会在终端回显密码，因此写入持久日志前统一替换为 ********
    SS_PASSWORD="$PASSWORD" awk '
        BEGIN { p = ENVIRON["SS_PASSWORD"] }
        {
            while ((i = index($0, p)) > 0) {
                $0 = substr($0, 1, i - 1) "********" substr($0, i + length(p))
            }
            print
        }
    ' "$TMP_LOG" > "$LOG_FILE" || log_warn "日志脱敏写入失败，原始临时日志将不会被保留。"
    chmod 600 "$LOG_FILE"

    (( rc == 0 )) || die "expect 自动化执行失败（退出码 ${rc}），请查看日志：${LOG_FILE}"
    log_ok "自动应答流程执行完毕，开始校验安装结果。"
}

verify_installation() {
    [[ -f "$CONF" ]] || die "安装后未找到配置文件 ${CONF}，安装可能失败，请查看日志：${LOG_FILE}"
    [[ -x "$BIN" ]] || die "安装后未找到可执行文件 ${BIN}，请查看日志：${LOG_FILE}"

    local running=0 i
    for i in $(seq 1 15); do
        if pgrep -f "$BIN" >/dev/null 2>&1; then
            running=1
            break
        fi
        if [[ -x "$INIT_SCRIPT" ]] && "$INIT_SCRIPT" status 2>/dev/null | grep -qiE 'running|运行|started|启动'; then
            running=1
            break
        fi
        sleep 1
    done
    (( running == 1 )) || die "安装完成但未检测到 Shadowsocks 进程运行，请查看日志：${LOG_FILE}。可尝试：bash ${SCRIPT_PATH} 选择 4 启动。"

    if command -v ss >/dev/null 2>&1; then
        ss -lnt 2>/dev/null | grep -qE ":${PORT}[[:space:]]" || \
            log_warn "端口 ${PORT} 未在监听列表中检测到，请检查配置或防火墙设置。"
    fi

    local conf_port conf_password conf_cipher
    conf_port="$(awk -F ' = ' '/^PORT = /{print $2; exit}' "$CONF")"
    conf_password="$(awk -F ' = ' '/^PASSWORD = /{print $2; exit}' "$CONF")"
    conf_cipher="$(awk -F ' = ' '/^CIPHER = /{print $2; exit}' "$CONF")"

    log_ok "安装校验通过。"
    printf '\n'
    printf '  %s========================================%s\n' "$C_GREEN" "$C_RESET"
    printf '  %s Shadowsocks-Go 安装结果%s\n' "$C_GREEN" "$C_RESET"
    printf '  %s========================================%s\n' "$C_GREEN" "$C_RESET"
    printf '  端口    : %s\n' "$conf_port"
    printf '  密码    : %s\n' "$conf_password"
    printf '  加密    : %s\n' "$conf_cipher"
    printf '  配置文件: %s\n' "$CONF"
    printf '  安装日志: %s（密码已脱敏）\n' "$LOG_FILE"
    printf '  管理脚本: bash %s\n' "$SCRIPT_PATH"
    printf '\n'
    log_warn "请妥善保存上方密码；配置文件 ${CONF} 中含明文密码，请避免泄露。"
}

main() {
    printf '%s\n' "ss-go-onekey v${VERSION} —— 自动化安装 Shadowsocks-Go"

    check_root
    need_downloader
    check_arch
    check_os
    check_not_installed
    validate_params
    get_password

    mkdir -p "$WORKDIR" && chmod 700 "$WORKDIR" || die "无法创建工作目录 ${WORKDIR}。"

    ensure_expect
    download_upstream
    write_expect_script
    run_automation
    verify_installation
}

main "$@"
