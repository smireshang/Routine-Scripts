
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ======================== 配置区 ========================

PRIMARY_URL="https://cat.misstwo.top/vps/id_ed25519.pub"
BACKUP_URL="https://cdn.1213866.xyz/vps/id_ed25519.pub"

KEY_URLS=("$PRIMARY_URL" "$BACKUP_URL")

EXPECTED_FP="SHA256:ROKJjahIBPrrt7SbFN7DdfxbdhI6p4qx2xQ/Tl31pE0"

# sudo 执行时默认使用发起者；直接 root 执行时使用 root
TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(id -un)}}"

# =======================================================

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { printf "${BLUE}[信息]${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}[警告]${RESET} %s\n" "$*"; }
error()   { printf "${RED}[错误]${RESET} %s\n" "$*" >&2; }
success() { printf "${GREEN}[成功]${RESET} %s\n" "$*"; }

die() {
    error "$*"
    exit 1
}

confirm() {
    local answer
    printf "${YELLOW}%s (y/n): ${RESET}" "$1"
    read -r answer || return 1
    [[ "$answer" == "y" || "$answer" == "Y" ]]
}

echo -e "${BOLD}${BLUE}=== SSH 公钥安装与更新脚本 ===${RESET}"

# ======================== Step 0：环境检查 ========================

[[ "$(id -u)" -eq 0 ]] ||
    die "请使用 root 或 sudo 执行本脚本。"

for cmd in ssh-keygen getent awk mktemp install cp chmod chown; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "缺少必要命令：$cmd"
done

[[ "$EXPECTED_FP" == SHA256:* ]] ||
    die "公钥指纹配置无效。"

OS_NAME="unknown"
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    OS_NAME="${ID:-unknown}"
fi

case "$OS_NAME" in
    debian|ubuntu|alpine) ;;
    *) die "暂不支持的系统：$OS_NAME" ;;
esac

PASSWD_ENTRY="$(getent passwd "$TARGET_USER" 2>/dev/null || true)"
[[ -n "$PASSWD_ENTRY" ]] || die "目标用户不存在：$TARGET_USER"

IFS=: read -r _ _ TARGET_UID TARGET_GID _ TARGET_HOME _ \
    <<< "$PASSWD_ENTRY"

[[ "$TARGET_HOME" == /* && -d "$TARGET_HOME" ]] ||
    die "目标用户 HOME 目录无效：$TARGET_HOME"

SSH_DIR="$TARGET_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_BIN="$(command -v sshd || true)"

[[ -f "$SSHD_CONFIG" ]] || die "未找到 $SSHD_CONFIG"
[[ -n "$SSHD_BIN" ]] || die "未找到 sshd，请安装 OpenSSH 服务端。"

if command -v curl >/dev/null 2>&1; then
    DOWNLOAD_TOOL="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOAD_TOOL="wget"
else
    die "请先安装 curl 或 wget。"
fi

TMP_DIR="$(mktemp -d)"
NEW_KEYS_FILE=""
cleanup() {
    rm -rf "$TMP_DIR"
    if [[ -n "$NEW_KEYS_FILE" ]]; then
        rm -f "$NEW_KEYS_FILE"
    fi
}
trap cleanup EXIT

TMP_KEY="$TMP_DIR/id_ed25519.pub"

info "系统：$OS_NAME"
info "目标用户：$TARGET_USER"
info "授权文件：$AUTHORIZED_KEYS"
info "预期指纹：$EXPECTED_FP"

warn "更新旧公钥时，会先保留旧密钥并添加新密钥。"
warn "只有确认新密钥登录成功后，才会询问是否移除旧密钥。"

confirm "确认继续执行" || die "已取消操作。"

# ======================== Step 1：下载和验证公钥 ========================

download_key() {
    local url="$1"
    local actual_fp
    local line_count

    [[ "$url" == https://* ]] || {
        warn "拒绝非 HTTPS 地址：$url"
        return 1
    }

    info "尝试下载：$url"

    if [[ "$DOWNLOAD_TOOL" == "curl" ]]; then
        curl --fail --silent --show-error --location \
            --proto '=https' --proto-redir '=https' \
            --connect-timeout 8 --max-time 20 \
            "$url" -o "$TMP_KEY" || {
                warn "下载失败。"
                return 1
            }
    else
        wget --https-only -q -T 20 -O "$TMP_KEY" "$url" || {
            warn "下载失败。"
            return 1
        }
    fi

    [[ -s "$TMP_KEY" ]] || {
        warn "下载内容为空。"
        return 1
    }

    line_count="$(awk 'NF {n++} END {print n+0}' "$TMP_KEY")"
    [[ "$line_count" -eq 1 ]] || {
        warn "公钥文件必须恰好包含一行非空内容。"
        return 1
    }

    ssh-keygen -lf "$TMP_KEY" >/dev/null 2>&1 || {
        warn "下载内容不是有效的 SSH 公钥。"
        return 1
    }

    actual_fp="$(ssh-keygen -lf "$TMP_KEY" | awk 'NR==1 {print $2}')"

    [[ "$actual_fp" == "$EXPECTED_FP" ]] || {
        warn "公钥指纹不匹配。"
        warn "预期：$EXPECTED_FP"
        warn "实际：$actual_fp"
        return 1
    }

    [[ "$(awk 'NF {print $1}' "$TMP_KEY")" == "ssh-ed25519" ]] || {
        warn "公钥算法不是 ED25519。"
        return 1
    }

    success "公钥指纹和算法验证通过。"
    return 0
}

DOWNLOAD_OK=0
for url in "${KEY_URLS[@]}"; do
    if download_key "$url"; then
        DOWNLOAD_OK=1
        break
    fi
    warn "尝试备用地址。"
done

[[ "$DOWNLOAD_OK" -eq 1 ]] || die "所有公钥地址均下载失败或验证不通过。"

PUBKEY_TYPE="$(awk 'NF {print $1}' "$TMP_KEY")"
PUBKEY_BODY="$(awk 'NF {print $2}' "$TMP_KEY")"
PUBKEY_ID="$PUBKEY_TYPE $PUBKEY_BODY"

# ======================== Step 2：检测现有公钥 ========================

if [[ -L "$SSH_DIR" ]]; then
    die "$SSH_DIR 是符号链接，为安全起见停止。"
fi

if [[ -e "$SSH_DIR" && ! -d "$SSH_DIR" ]]; then
    die "$SSH_DIR 存在但不是目录。"
fi

install -d -o "$TARGET_UID" -g "$TARGET_GID" -m 700 "$SSH_DIR"

if [[ -L "$AUTHORIZED_KEYS" ]]; then
    die "$AUTHORIZED_KEYS 是符号链接，为安全起见停止。"
fi

if [[ -e "$AUTHORIZED_KEYS" && ! -f "$AUTHORIZED_KEYS" ]]; then
    die "$AUTHORIZED_KEYS 不是普通文件。"
fi

EXISTING_LINES=0
TARGET_PRESENT=0
OTHER_LINES=0

if [[ -f "$AUTHORIZED_KEYS" ]]; then
    EXISTING_LINES="$(awk 'NF {n++} END {print n+0}' "$AUTHORIZED_KEYS")"

    if awk -v key="$PUBKEY_ID" '
        NF >= 2 && ($1 " " $2) == key { found=1 }
        END { exit !found }
    ' "$AUTHORIZED_KEYS"; then
        TARGET_PRESENT=1
    fi

    OTHER_LINES="$(awk -v key="$PUBKEY_ID" '
        NF && !($1 " " $2 == key) { n++ }
        END {print n+0}
    ' "$AUTHORIZED_KEYS")"
fi

UPDATE_REQUIRED=0
KEYS_BACKUP=""

if [[ "$EXISTING_LINES" -eq 0 ]]; then
    info "检测结果：没有现有授权公钥，执行添加模式。"

    install -o "$TARGET_UID" -g "$TARGET_GID" -m 600 \
        "$TMP_KEY" "$AUTHORIZED_KEYS"

    success "新公钥已安装。"

elif [[ "$TARGET_PRESENT" -eq 1 && "$OTHER_LINES" -eq 0 ]]; then
    info "检测结果：目标公钥已经是唯一授权公钥。"
    success "无需添加或更新。"

elif [[ "$TARGET_PRESENT" -eq 1 ]]; then
    info "检测结果：新公钥已存在，但授权文件还包含其他内容。"
    UPDATE_REQUIRED=1

else
    info "检测结果：没有目标公钥，存在其他授权内容。"
    warn "先备份旧授权文件，再临时添加新公钥，以便测试登录。"

    confirm "确认备份并临时添加新公钥" ||
        die "已取消操作，原授权文件未修改。"

    KEYS_BACKUP="$SSH_DIR/authorized_keys.bak.$(date +%Y%m%d_%H%M%S)"
    cp -p "$AUTHORIZED_KEYS" "$KEYS_BACKUP"
    chmod 600 "$KEYS_BACKUP"
    chown "$TARGET_UID:$TARGET_GID" "$KEYS_BACKUP"
    info "原授权文件备份：$KEYS_BACKUP"

    # 只追加目标公钥，不删除任何旧公钥
    cat "$TMP_KEY" >> "$AUTHORIZED_KEYS"
    chown "$TARGET_UID:$TARGET_GID" "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"

    UPDATE_REQUIRED=1
    success "新公钥已临时添加，旧公钥仍保留。"
fi

# ======================== Step 3：测试新密钥 ========================

echo
warn "请打开另一个终端，使用新公钥对应的私钥测试登录。"
warn "示例："
printf 'ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 %s@服务器IP\n' "$TARGET_USER"
warn "请将私钥路径和服务器 IP 替换为实际值。"
warn "请勿关闭当前 SSH 会话。"

if ! confirm "是否已在另一个终端成功使用新密钥登录？"; then
    warn "没有确认新密钥登录成功。"
    warn "旧公钥尚未移除；请先排查新密钥登录问题。"
    exit 0
fi

success "已确认新密钥可以登录。"

# ======================== Step 4：可选移除旧公钥 ========================

if [[ "$UPDATE_REQUIRED" -eq 1 ]]; then
    echo
    warn "现在可以选择是否只保留新公钥。"
    warn "移除旧公钥会影响依赖旧密钥的设备、管理员和自动化任务。"

    if confirm "确认备份并移除其他授权内容，只保留新公钥"; then
        # 若之前尚未备份（例如新公钥已存在且有其他授权内容），先备份
        if [[ -z "$KEYS_BACKUP" ]]; then
            KEYS_BACKUP="$SSH_DIR/authorized_keys.bak.$(date +%Y%m%d_%H%M%S)"
            cp -p "$AUTHORIZED_KEYS" "$KEYS_BACKUP"
            chmod 600 "$KEYS_BACKUP"
            chown "$TARGET_UID:$TARGET_GID" "$KEYS_BACKUP"
            info "旧授权文件备份：$KEYS_BACKUP"
        fi

        # 用已验证指纹的新公钥生成临时文件并替换
        NEW_KEYS_FILE="$(mktemp "$SSH_DIR/.authorized_keys.XXXXXX")"
        install -o "$TARGET_UID" -g "$TARGET_GID" -m 600 \
            "$TMP_KEY" "$NEW_KEYS_FILE"

        if ! mv -f "$NEW_KEYS_FILE" "$AUTHORIZED_KEYS"; then
            rm -f "$NEW_KEYS_FILE"
            NEW_KEYS_FILE=""
            die "替换授权文件失败；备份位于：$KEYS_BACKUP"
        fi
        NEW_KEYS_FILE=""

        chown "$TARGET_UID:$TARGET_GID" "$AUTHORIZED_KEYS"
        chmod 600 "$AUTHORIZED_KEYS"

        success "旧授权内容已移除，仅保留新公钥。"
    else
        info "保留其他授权内容，不执行替换。"
    fi
fi

# 最终检查文件内容
FINAL_COUNT="$(awk -v key="$PUBKEY_ID" '
    NF >= 2 && ($1 " " $2) == key { n++ }
    END {print n+0}
' "$AUTHORIZED_KEYS")"

[[ "$FINAL_COUNT" -ge 1 ]] ||
    die "最终检查未找到目标公钥，请检查 $AUTHORIZED_KEYS。"

# ======================== Step 5：选择 SSH 认证方式 ========================

echo
echo -e "${BOLD}${BLUE}请选择 SSH 登录认证方式：${RESET}"
echo "1) 保留密码登录 + 公钥登录（默认）"
echo "2) 关闭 PasswordAuthentication"
echo "3) 不修改 SSH 配置"

printf "请输入选项 [1/2/3，默认 1]: "
read -r SSH_CHOICE || SSH_CHOICE=1
[[ -n "$SSH_CHOICE" ]] || SSH_CHOICE=1

case "$SSH_CHOICE" in
    1|2) ;;
    3)
        success "公钥操作完成，未修改 SSH 配置。"
        exit 0
        ;;
    *) die "无效选项，未修改 SSH 配置。" ;;
esac

if [[ "$SSH_CHOICE" == "2" ]]; then
    warn "关闭密码认证可能影响其他登录方式。"
    confirm "再次确认：确定关闭密码认证吗？" ||
        die "已取消关闭密码认证。"
fi

# ======================== Step 6：备份并修改 SSH 配置 ========================

"$SSHD_BIN" -t || die "当前 SSH 配置语法检查失败，停止修改。"

BACKUP_SSHD_CONFIG="${SSHD_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
NEW_CONFIG="$TMP_DIR/sshd_config.new"

cp -p "$SSHD_CONFIG" "$BACKUP_SSHD_CONFIG"
info "SSH 配置备份：$BACKUP_SSHD_CONFIG"

if [[ "$SSH_CHOICE" == "1" ]]; then
    PASSWORD_AUTH="yes"
else
    PASSWORD_AUTH="no"
fi

{
    printf 'PubkeyAuthentication yes\n'
    printf 'PasswordAuthentication %s\n' "$PASSWORD_AUTH"
    cat "$SSHD_CONFIG"
} > "$NEW_CONFIG"

cat "$NEW_CONFIG" > "$SSHD_CONFIG"

if ! "$SSHD_BIN" -t; then
    error "修改后的 SSH 配置检查失败，尝试恢复。"
    cp -p "$BACKUP_SSHD_CONFIG" "$SSHD_CONFIG"
    "$SSHD_BIN" -t || error "恢复后的配置仍有问题，请使用服务器控制台排查。"
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
    warn "SSH 配置备份：$BACKUP_SSHD_CONFIG"
    exit 1
fi

# ======================== Step 8：完成 ========================

success "SSH 配置语法检查通过，已请求重载服务。"

if [[ "$SSH_CHOICE" == "2" ]]; then
    warn "PasswordAuthentication 已设置为 no。"
    warn "请再次测试新密钥登录成功后，再关闭当前会话。"
else
    success "已保留密码登录，同时启用公钥登录。"
fi

info "SSH 配置备份：$BACKUP_SSHD_CONFIG"
[[ -n "$KEYS_BACKUP" ]] && info "授权公钥备份：$KEYS_BACKUP"

success "脚本执行完成。"
