
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ======================== 配置区 ========================

# 国内主站（优先）
PRIMARY_URL="https://cat.misstwo.top/vps/id_ed25519.pub"

# 境外备用站
BACKUP_URL="https://cdn.1213866.xyz/vps/id_ed25519.pub"

KEY_URLS=(
    "$PRIMARY_URL"
    "$BACKUP_URL"
)

# 已验证的 SSH 公钥 SHA256 指纹
EXPECTED_FP="SHA256:ROKJjahIBPrrt7SbFN7DdfxbdhI6p4qx2xQ/Tl31pE0"

# 默认目标用户：
# sudo 执行时使用 sudo 发起者；直接 root 执行时使用 root
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(id -un)}}"

# =======================================================

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
BOLD='\033[1m'
RESET='\033[0m'

info() {
    printf "${BLUE}[信息]${RESET} %s\n" "$*"
}

warn() {
    printf "${YELLOW}[警告]${RESET} %s\n" "$*"
}

error() {
    printf "${RED}[错误]${RESET} %s\n" "$*" >&2
}

success() {
    printf "${GREEN}[成功]${RESET} %s\n" "$*"
}

confirm() {
    local answer
    printf "${YELLOW}%s (y/n): ${RESET}" "$1"
    read -r answer || return 1
    [[ "$answer" == "y" || "$answer" == "Y" ]]
}

die() {
    error "$*"
    exit 1
}

echo -e "${BOLD}${BLUE}=== SSH 公钥安装与登录配置脚本 ===${RESET}"

# ======================== Step 0：环境检查 ========================

[[ "$(id -u)" -eq 0 ]] ||
    die "请使用 root 或 sudo 执行本脚本。"

command -v ssh-keygen >/dev/null 2>&1 ||
    die "未找到 ssh-keygen，请安装 OpenSSH 客户端工具。"

command -v getent >/dev/null 2>&1 ||
    die "未找到 getent，无法安全确定目标用户信息。"

[[ "$EXPECTED_FP" == SHA256:* ]] ||
    die "公钥指纹配置无效。"

[[ "$EXPECTED_FP" != *请替换* ]] ||
    die "请先填写正确的公钥指纹。"

# 检测系统
OS_NAME="unknown"

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    OS_NAME="${ID:-unknown}"
fi

case "$OS_NAME" in
    debian|ubuntu|alpine)
        ;;
    *)
        die "暂不支持的系统：$OS_NAME"
        ;;
esac

info "检测到系统：$OS_NAME"

# 获取目标用户真实 HOME
PASSWD_ENTRY="$(getent passwd "$TARGET_USER" 2>/dev/null || true)"
[[ -n "$PASSWD_ENTRY" ]] ||
    die "目标用户不存在：$TARGET_USER"

IFS=: read -r _ _ TARGET_UID TARGET_GID _ TARGET_HOME _ \
    <<< "$PASSWD_ENTRY"

[[ "$TARGET_HOME" == /* && -d "$TARGET_HOME" ]] ||
    die "目标用户 HOME 目录无效：$TARGET_HOME"

SSH_DIR="$TARGET_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

# 检查 SSH 服务端
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_BIN="$(command -v sshd || true)"

[[ -f "$SSHD_CONFIG" ]] ||
    die "未找到 SSH 配置文件：$SSHD_CONFIG"

[[ -n "$SSHD_BIN" ]] ||
    die "未找到 sshd，请确认已安装 OpenSSH 服务端。"

# 临时文件
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_KEY="$TMP_DIR/id_ed25519.pub"

# 下载工具
if command -v curl >/dev/null 2>&1; then
    DOWNLOAD_TOOL="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOAD_TOOL="wget"
else
    die "未找到 curl 或 wget，请先安装其中一个。"
fi

# ======================== Step 1：操作前确认 ========================

echo
info "目标用户：$TARGET_USER"
info "用户 HOME：$TARGET_HOME"
info "授权文件：$AUTHORIZED_KEYS"
info "系统类型：$OS_NAME"
info "国内公钥地址：$PRIMARY_URL"
info "境外备用地址：$BACKUP_URL"
info "预期公钥指纹：$EXPECTED_FP"

warn "执行顺序："
warn " 1. 下载公钥并校验指纹"
warn " 2. 创建 .ssh 并安装公钥"
warn " 3. 由你从另一个终端测试密钥登录"
warn " 4. 测试成功后，再选择是否关闭密码登录"
warn " 5. 修改前备份配置，修改后检查并尝试重载 SSH"

confirm "确认继续执行" || die "已取消操作。"

# ======================== Step 2：下载与验证公钥 ========================

download_key() {
    local url="$1"
    local actual_fp
    local line_count

    [[ "$url" == https://* ]] || {
        warn "拒绝非 HTTPS 地址：$url"
        return 1
    }

    info "尝试下载公钥：$url"

    if [[ "$DOWNLOAD_TOOL" == "curl" ]]; then
        if ! curl --fail --silent --show-error --location \
            --proto '=https' --proto-redir '=https' \
            --connect-timeout 8 --max-time 20 \
            "$url" -o "$TMP_KEY"; then
            warn "下载失败或超时。"
            return 1
        fi
    else
        if ! wget --https-only -q -T 20 -O "$TMP_KEY" "$url"; then
            warn "下载失败或超时。"
            return 1
        fi
    fi

    [[ -s "$TMP_KEY" ]] || {
        warn "下载内容为空。"
        return 1
    }

    line_count="$(awk 'NF {n++} END {print n+0}' "$TMP_KEY")"

    [[ "$line_count" -eq 1 ]] || {
        warn "公钥文件必须只包含一行非空内容。"
        return 1
    }

    ssh-keygen -lf "$TMP_KEY" >/dev/null 2>&1 || {
        warn "下载内容不是有效的 SSH 公钥。"
        return 1
    }

    actual_fp="$(ssh-keygen -lf "$TMP_KEY" | awk 'NR==1 {print $2}')"

    if [[ "$actual_fp" != "$EXPECTED_FP" ]]; then
        warn "公钥指纹不匹配，拒绝安装。"
        warn "预期：$EXPECTED_FP"
        warn "实际：$actual_fp"
        return 1
    fi

    [[ "$(awk 'NF {print $1}' "$TMP_KEY")" == "ssh-ed25519" ]] || {
        warn "公钥算法不是 ED25519。"
        return 1
    }

    success "公钥下载及指纹校验通过。"
    return 0
}

DOWNLOAD_OK=0

for url in "${KEY_URLS[@]}"; do
    if download_key "$url"; then
        DOWNLOAD_OK=1
        break
    fi

    warn "当前地址失败，切换下一个地址。"
done

[[ "$DOWNLOAD_OK" -eq 1 ]] ||
    die "所有地址均下载失败或校验不通过。"

PUBKEY_TYPE="$(awk 'NF {print $1}' "$TMP_KEY")"
PUBKEY_BODY="$(awk 'NF {print $2}' "$TMP_KEY")"
PUBKEY_ID="$PUBKEY_TYPE $PUBKEY_BODY"

# ======================== Step 3：安装公钥 ========================

if [[ -e "$SSH_DIR" && ! -d "$SSH_DIR" ]]; then
    die "$SSH_DIR 存在但不是目录。"
fi

install -d -m 700 "$SSH_DIR"

if [[ -L "$AUTHORIZED_KEYS" ]]; then
    die "$AUTHORIZED_KEYS 是符号链接，为安全起见停止操作。"
fi

touch "$AUTHORIZED_KEYS"

if awk -v key="$PUBKEY_ID" '
    NF >= 2 && ($1 " " $2) == key { found=1 }
    END { exit !found }
' "$AUTHORIZED_KEYS"; then
    warn "公钥已经存在，跳过重复添加。"
else
    warn "即将追加公钥到 $AUTHORIZED_KEYS"

    confirm "确认添加公钥" || die "用户取消公钥安装。"

    cat "$TMP_KEY" >> "$AUTHORIZED_KEYS"
    success "公钥已添加。"
fi

chown "$TARGET_UID:$TARGET_GID" "$SSH_DIR" "$AUTHORIZED_KEYS"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTHORIZED_KEYS"

success "公钥安装完成。"

# ======================== Step 4：人工测试登录 ========================

echo
warn "现在请打开另一个终端，使用对应的私钥测试登录。"
warn "示例："
printf 'ssh -i ~/.ssh/id_ed25519 %s@服务器IP\n' "$TARGET_USER"
echo
warn "请勿关闭当前 SSH 会话。"
warn "如果使用非默认端口，请加上 -p 端口号。"
warn "如果私钥不在默认位置，请将示例中的私钥路径替换为实际路径。"

if ! confirm "是否已在另一个终端成功使用公钥登录？"; then
    warn "未确认公钥登录成功。"
    warn "脚本将在此退出，不会修改 SSH 认证配置。"
    exit 0
fi

# ======================== Step 5：选择认证方式 ========================

echo
echo -e "${BOLD}${BLUE}请选择 SSH 登录认证方式：${RESET}"
echo "1) 保留密码登录 + 启用公钥登录（默认）"
echo "2) 仅公钥登录（关闭 PasswordAuthentication）"
echo "3) 不修改 SSH 配置"

printf "请输入选项 [1/2/3，默认 1]: "
read -r SSH_CHOICE || SSH_CHOICE=1
[[ -n "$SSH_CHOICE" ]] || SSH_CHOICE=1

case "$SSH_CHOICE" in
    1|2)
        ;;
    3)
        success "公钥安装完成，未修改 SSH 配置。"
        exit 0
        ;;
    *)
        die "无效选项，未修改 SSH 配置。"
        ;;
esac

if [[ "$SSH_CHOICE" == "2" ]]; then
    warn "此操作将禁用 PasswordAuthentication。"
    warn "如果其他认证策略、用户限制或网络配置有问题，可能影响后续登录。"

    confirm "再次确认：确定关闭密码认证吗？" ||
        die "已取消关闭密码认证。"
fi

# ======================== Step 6：备份并修改 SSH 配置 ========================

if ! "$SSHD_BIN" -t; then
    die "当前 SSH 配置语法检查失败，停止修改。"
fi

BACKUP_SSHD_CONFIG="${SSHD_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
NEW_CONFIG="$TMP_DIR/sshd_config.new"

cp -p "$SSHD_CONFIG" "$BACKUP_SSHD_CONFIG"
info "已备份 SSH 配置：$BACKUP_SSHD_CONFIG"

if [[ "$SSH_CHOICE" == "1" ]]; then
    PASSWORD_AUTH="yes"
else
    PASSWORD_AUTH="no"
fi

# 先在主配置文件顶部设置全局值。
# 注意：Include、Match 块可能影响特定连接，仍需核验最终配置。
{
    printf 'PubkeyAuthentication yes\n'
    printf 'PasswordAuthentication %s\n' "$PASSWORD_AUTH"
    cat "$SSHD_CONFIG"
} > "$NEW_CONFIG"

cat "$NEW_CONFIG" > "$SSHD_CONFIG"

if ! "$SSHD_BIN" -t; then
    error "修改后的 SSH 配置检查失败，开始回滚。"
    cp -p "$BACKUP_SSHD_CONFIG" "$SSHD_CONFIG"

    "$SSHD_BIN" -t ||
        error "回滚后的配置检查仍失败，请通过服务器控制台排查。"

    die "SSH 配置修改失败，已尝试恢复原配置。"
fi

# ======================== Step 7：重载 SSH 服务 ========================

RELOAD_OK=0

if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet sshd 2>/dev/null; then
        systemctl reload sshd && RELOAD_OK=1
    elif systemctl is-active --quiet ssh 2>/dev/null; then
        systemctl reload ssh && RELOAD_OK=1
    fi
fi

if [[ "$RELOAD_OK" -ne 1 && -x /etc/init.d/sshd ]]; then
    /etc/init.d/sshd reload && RELOAD_OK=1
fi

if [[ "$RELOAD_OK" -ne 1 ]]; then
    warn "未能确认 SSH 服务重载成功。"
    warn "请保持当前连接，不要关闭终端。"
    warn "配置备份：$BACKUP_SSHD_CONFIG"
    exit 1
fi

# ======================== Step 8：完成 ========================

success "SSH 配置已通过语法检查，并已请求服务重载。"
success "公钥安装流程完成。"

if [[ "$SSH_CHOICE" == "2" ]]; then
    warn "已将 PasswordAuthentication 设置为 no。"
    warn "这不一定禁用所有密码类认证，请检查最终生效配置。"
    warn "请再次从另一个终端测试密钥登录后，再关闭当前会话。"
else
    success "已保留密码登录，同时启用公钥登录。"
fi

info "SSH 配置备份：$BACKUP_SSHD_CONFIG"
