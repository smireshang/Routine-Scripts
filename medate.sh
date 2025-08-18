#!/bin/sh

# ================= 配置区 =================
ENCODED_URL="aHR0cDovL2kubWlzc3R3by50b3Avc3RhdGljL2lkX2VkMjU1MTkucHVi"  # Base64 隐藏的公钥 URL
SSH_USER="$(whoami)"                                     # 当前用户
AUTHORIZED_KEYS_PATH="/$SSH_USER/.ssh/authorized_keys"
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

echo -e "${BOLD}${BLUE}=== SSH 密钥登录配置脚本 (Debian/Alpine 兼容) ===${RESET}"

# Step 0: 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
else
    OS_NAME=$(uname -s)
fi
echo -e "${BLUE}检测到系统: $OS_NAME${RESET}"

# 设置 SSH 重启命令
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
        echo -e "${RED}不支持的系统: $OS_NAME${RESET}"
        exit 1
        ;;
esac

# Step 1: 执行前总结
echo -e "\n${BOLD}${BLUE}=== 执行前总结信息 ===${RESET}"
echo -e "${BLUE}当前用户: $SSH_USER${RESET}"
echo -e "${BLUE}authorized_keys 文件: $AUTHORIZED_KEYS_PATH${RESET}"
echo -e "${BLUE}sshd 配置文件: $SSHD_CONFIG${RESET}"
echo -e "${BLUE}公钥 URL（隐藏形式）: $ENCODED_URL${RESET}"
echo -e "${BLUE}系统类型: $OS_NAME${RESET}"
echo -e "${YELLOW}将要执行操作：${RESET}"
echo -e "${YELLOW} 1. 下载远程公钥${RESET}"
echo -e "${YELLOW} 2. 创建或备份 authorized_keys 文件（如果不存在）${RESET}"
echo -e "${YELLOW} 3. 检查并添加公钥到 authorized_keys${RESET}"
echo -e "${YELLOW} 4. 用户必须确认可以使用密钥登录${RESET}"
echo -e "${YELLOW} 5. 修改 SSH 配置，选择认证方式（密码+密钥或仅密钥）${RESET}"
echo -e "${RED}警告：如果未能成功验证密钥登录，请不要禁用密码登录，否则可能无法远程访问服务器${RESET}"
printf "${GREEN}确认继续执行吗？(y/n): ${RESET}"
read confirm
[ "$confirm" != "y" ] && echo -e "${RED}取消操作。${RESET}" && exit 0

# Step 2: 安装 curl（如果未安装）
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${BLUE}curl 未安装，安装中...${RESET}"
    sh -c "$PACKAGE_INSTALL_CMD"
fi

# Step 3: 下载公钥
PUB_URL=$(echo "$ENCODED_URL" | base64 -d)
echo -e "${BLUE}下载公钥: $PUB_URL${RESET}"
curl -fsSL "$PUB_URL" -o "$TMP_KEY_FILE" || { echo -e "${RED}公钥下载失败${RESET}"; exit 1; }

# Step 4: 创建 .ssh 和 authorized_keys 文件
if [ ! -d "/home/$SSH_USER/.ssh" ]; then
    echo -e "${BLUE}创建目录 /home/$SSH_USER/.ssh${RESET}"
    mkdir -p "/home/$SSH_USER/.ssh"
    chmod 700 "/home/$SSH_USER/.ssh"
    chown $SSH_USER:$SSH_USER "/home/$SSH_USER/.ssh"
fi

if [ ! -f "$AUTHORIZED_KEYS_PATH" ]; then
    echo -e "${BLUE}创建空的 authorized_keys 文件${RESET}"
    touch "$AUTHORIZED_KEYS_PATH"
    chmod 600 "$AUTHORIZED_KEYS_PATH"
    chown $SSH_USER:$SSH_USER "$AUTHORIZED_KEYS_PATH"
fi

# Step 5: 检查重复并添加公钥
PUB_KEY_CONTENT=$(cat "$TMP_KEY_FILE")
if grep -qxF "$PUB_KEY_CONTENT" "$AUTHORIZED_KEYS_PATH"; then
    echo -e "${YELLOW}公钥已存在于 $AUTHORIZED_KEYS_PATH，跳过添加。${RESET}"
else
    echo -e "${YELLOW}公钥尚未添加到 $AUTHORIZED_KEYS_PATH。${RESET}"
    echo -e "${RED}如果添加错误可能影响 SSH 登录，请确保你当前已有有效登录方式。${RESET}"
    printf "${GREEN}是否将公钥添加到 %s？(y/n): ${RESET}" "$AUTHORIZED_KEYS_PATH"
    read confirm
    if [ "$confirm" = "y" ]; then
        echo "$PUB_KEY_CONTENT" >> "$AUTHORIZED_KEYS_PATH"
        chmod 600 "$AUTHORIZED_KEYS_PATH"
        chown $SSH_USER:$SSH_USER "$AUTHORIZED_KEYS_PATH"
        echo -e "${GREEN}公钥已添加到 $AUTHORIZED_KEYS_PATH${RESET}"
    else
        echo -e "${YELLOW}跳过公钥添加${RESET}"
    fi
fi

# Step 6: 提示用户验证密钥登录
echo -e "\n${YELLOW}请确保你可以使用密钥登录服务器后，再执行下一步修改 SSH 配置。${RESET}"
printf "${GREEN}确认已测试密钥登录成功？(y/n): ${RESET}"
read confirm
[ "$confirm" != "y" ] && echo -e "${RED}请先验证密钥登录，脚本终止。${RESET}" && exit 0

# Step 7: 修改 SSH 配置，选择认证方式
echo -e "\n${BLUE}请选择 SSH 登录认证方式：${RESET}"
echo -e "${BLUE}1) 支持密码登录 + 支持密钥登录（默认）${RESET}"
echo -e "${BLUE}2) 仅支持密钥登录（禁用密码）${RESET}"
printf "${GREEN}输入选项 [1/2]: ${RESET}"
read ssh_choice

# 备份 sshd_config
cp "$SSHD_CONFIG" "$BACKUP_SSHD_CONFIG"
echo -e "${BLUE}已备份 SSH 配置到 $BACKUP_SSHD_CONFIG${RESET}"

case "$ssh_choice" in
    1)
        sed -i 's/^#*\s*PasswordAuthentication\s.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
        sed -i 's/^#*\s*PubkeyAuthentication\s.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        echo -e "${GREEN}SSH 配置修改为：密码 + 密钥登录${RESET}"
        ;;
    2)
        sed -i 's/^#*\s*PasswordAuthentication\s.*/PasswordAuthentication no/' "$SSHD_CONFIG"
        sed -i 's/^#*\s*PubkeyAuthentication\s.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        echo -e "${GREEN}SSH 配置修改为：仅密钥登录${RESET}"
        ;;
    *)
        echo -e "${RED}无效选项，跳过修改 SSH 配置${RESET}"
        ;;
esac

# Step 8: 重启 SSH 服务
echo -e "${BLUE}重启 SSH 服务...${RESET}"
$SSH_RESTART_CMD
echo -e "${GREEN}操作完成。${RESET}"
