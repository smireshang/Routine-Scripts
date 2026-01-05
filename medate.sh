#!/bin/sh

# ================= 配置区 =================
ENCODED_URL="aHR0cDovL2kubWlzc3R3by50b3Avc3RhdGljL2lkX2VkMjU1MTkucHVi"
BACKUP_ENCODED_URL="aHR0cDovL2Jsb2cucHZ2cS5kZS9zdGF0aWMvc3NsL2lkX2VkMjU1MTkucHVi"

# 可以继续往数组里加更多 base64 地址
KEY_URLS=(
    "$ENCODED_URL"
    "$BACKUP_ENCODED_URL"
)

SSH_USER="$(whoami)"                   # 默认当前用户
HOME_DIR="$HOME"
AUTHORIZED_KEYS_PATH="$HOME_DIR/.ssh/authorized_keys"
TMP_KEY_FILE="/tmp/temp_ssh_key.pub"
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_SSHD_CONFIG="${SSHD_CONFIG}.bak.$(date +%F_%T)"
# ========================================

# ================= 颜色 =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
BOLD="\033[1m"
RESET="\033[0m"
# ========================================

info()   { echo -e "${BLUE}$*${RESET}"; }
warn()   { echo -e "${YELLOW}$*${RESET}"; }
error()  { echo -e "${RED}$*${RESET}"; }
success(){ echo -e "${GREEN}$*${RESET}"; }
confirm(){ 
    printf "${GREEN}%s (y/n): ${RESET}" "$1"
    read ans
    [ "$ans" = "y" ] 
}

echo -e "${BOLD}${BLUE}=== SSH 密钥登录配置脚本 (Debian/Alpine 兼容) ===${RESET}"

# Step 0: 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
else
    OS_NAME=$(uname -s)
fi
info "检测到系统: $OS_NAME"

# 设置 SSH 重启命令和包管理器安装命令
case "$OS_NAME" in
    alpine)
        SSH_RESTART_CMD="/etc/init.d/sshd restart"
        PACKAGE_INSTALL_CMD="apk add --no-cache curl"
        ;;
    debian|ubuntu)
        SSH_RESTART_CMD="systemctl restart sshd"
        PACKAGE_INSTALL_CMD="apt-get update && apt-get install -y curl"
        ;;
    *)
        error "不支持的系统: $OS_NAME"
        exit 1
        ;;
esac

# Step 1: 执行前总结
echo -e "\n${BOLD}${BLUE}=== 风险及信息 ===${RESET}"
info "当前用户: $SSH_USER"
info "HOME 目录: $HOME_DIR"
info "authorized_keys 文件: $AUTHORIZED_KEYS_PATH"
info "sshd 配置文件: $SSHD_CONFIG"
info "公钥 URL（Base64 编码形式）: 主 + 备用"
info "系统类型: $OS_NAME"

warn "将要执行操作："
warn " 1. 下载远程公钥（带超时，失败自动切换到备用地址）"
warn " 2. 创建或备份 authorized_keys 文件（如果不存在）"
warn " 3. 检查并添加公钥到 authorized_keys"
warn " 4. 用户必须确认可以使用密钥登录"
warn " 5. 修改 SSH 配置，选择认证方式（密码+密钥或仅密钥）"
warn "警告：如果未能成功验证密钥登录，请不要禁用密码登录，否则可能无法远程访问服务器"

confirm "确认继续执行" || { error "取消操作。"; exit 0; }

# Step 2: 安装 curl（如果未安装）
if ! command -v curl >/dev/null 2>&1; then
    info "curl 未安装，安装中..."
    sh -c "$PACKAGE_INSTALL_CMD"
fi

# Step 3: 下载公钥（主备地址自动切换）
DOWNLOAD_OK=0
for ENCODED in "${KEY_URLS[@]}"; do
    URL=$(echo "$ENCODED" | base64 -d)
    info "尝试下载公钥: $URL"
    if curl -m 15 -fsSL "$URL" -o "$TMP_KEY_FILE"; then
        success "成功下载公钥: $URL"
        DOWNLOAD_OK=1
        break
    else
        warn "下载失败或超时: $URL"
    fi
done

if [ $DOWNLOAD_OK -ne 1 ]; then
    error "所有地址下载失败，退出。"
    exit 1
fi

# Step 4: 创建 .ssh 和 authorized_keys 文件
[ ! -d "$HOME_DIR/.ssh" ] && {
    info "创建目录 $HOME_DIR/.ssh"
    mkdir -p "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
    chown "$SSH_USER:$SSH_USER" "$HOME_DIR/.ssh"
}

[ ! -f "$AUTHORIZED_KEYS_PATH" ] && {
    info "创建空的 authorized_keys 文件"
    touch "$AUTHORIZED_KEYS_PATH"
    chmod 600 "$AUTHORIZED_KEYS_PATH"
    chown "$SSH_USER:$SSH_USER" "$AUTHORIZED_KEYS_PATH"
}

# Step 5: 检查重复并添加公钥
PUB_KEY_CONTENT=$(cat "$TMP_KEY_FILE")
if grep -qxF "$PUB_KEY_CONTENT" "$AUTHORIZED_KEYS_PATH"; then
    warn "公钥已存在于 $AUTHORIZED_KEYS_PATH，跳过添加。"
else
    warn "公钥尚未添加到 $AUTHORIZED_KEYS_PATH。"
    warn "如果添加错误可能影响 SSH 登录，请确保你当前已有有效登录方式。"
    confirm "是否将公钥添加到 $AUTHORIZED_KEYS_PATH" && {
        echo "$PUB_KEY_CONTENT" >> "$AUTHORIZED_KEYS_PATH"
        chmod 600 "$AUTHORIZED_KEYS_PATH"
        chown "$SSH_USER:$SSH_USER" "$AUTHORIZED_KEYS_PATH"
        success "公钥已添加到 $AUTHORIZED_KEYS_PATH"
    } || warn "跳过公钥添加"
fi

# Step 6: 提示用户验证密钥登录
warn "请确保你可以使用密钥登录服务器后，再执行下一步修改 SSH 配置。"
confirm "确认已测试密钥登录成功" || { error "请先验证密钥登录，脚本终止。"; exit 0; }

# Step 7: 修改 SSH 配置，选择认证方式
echo -e "\n${BLUE}请选择 SSH 登录认证方式：${RESET}"
echo -e "${BLUE}1) 支持密码登录 + 支持密钥登录（默认）${RESET}"
echo -e "${BLUE}2) 仅支持密钥登录（禁用密码）${RESET}"
printf "${GREEN}输入选项 [1/2]: ${RESET}"
read ssh_choice

# 备份 sshd_config
cp "$SSHD_CONFIG" "$BACKUP_SSHD_CONFIG"
info "已备份 SSH 配置到 $BACKUP_SSHD_CONFIG"

case "$ssh_choice" in
    1|"")
        sed -i 's/^#*\s*PasswordAuthentication\s.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
        sed -i 's/^#*\s*PubkeyAuthentication\s.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        success "SSH 配置修改为：密码 + 密钥登录"
        ;;
    2)
        sed -i 's/^#*\s*PasswordAuthentication\s.*/PasswordAuthentication no/' "$SSHD_CONFIG"
        sed -i 's/^#*\s*PubkeyAuthentication\s.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        success "SSH 配置修改为：仅密钥登录"
        ;;
    *)
        warn "无效选项，跳过修改 SSH 配置"
        ;;
esac

# Step 8: 重启 SSH 服务
info "重启 SSH 服务..."
$SSH_RESTART_CMD
success "操作完成。"
