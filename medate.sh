#!/bin/sh

# ================= 配置区 =================
ENCODED_URL="aHR0cDovL2kubWlzc3R3by50b3Avc3RhdGljL2lkX2VkMjU1MTkucHVi"  # Base64 隐藏的公钥 URL
SSH_USER="$(whoami)"                                     # 当前用户
AUTHORIZED_KEYS_PATH="/home/$SSH_USER/.ssh/authorized_keys"
TMP_KEY_FILE="/tmp/temp_ssh_key.pub"
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_SSHD_CONFIG="${SSHD_CONFIG}.bak.$(date +%F_%T)"
# ========================================

echo "=== SSH 密钥登录配置脚本 (Debian/Alpine 兼容) ==="

# Step 0: 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
else
    OS_NAME=$(uname -s)
fi
echo "检测到系统: $OS_NAME"

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
        echo "不支持的系统: $OS_NAME"
        exit 1
        ;;
esac

# Step 1: 执行前总结
echo
echo "=== 风险提示 ==="
echo "当前用户: $SSH_USER"
echo "authorized_keys 文件: $AUTHORIZED_KEYS_PATH"
echo "sshd 配置文件: $SSHD_CONFIG"
echo "公钥 URL（隐藏形式）: $ENCODED_URL"
echo "系统类型: $OS_NAME"
echo "将要执行操作："
echo " 1. 下载远程公钥"
echo " 2. 创建或备份 authorized_keys 文件（如果不存在）"
echo " 3. 检查并添加公钥到 authorized_keys"
echo " 4. 用户必须确认可以使用密钥登录"
echo " 5. 修改 SSH 配置，选择认证方式（密码+密钥或仅密钥）"
echo "警告：如果未能成功验证密钥登录，请不要禁用密码登录，否则可能无法远程访问服务器"
echo "========================"
printf "确认继续执行吗？(y/n): "
read confirm
[ "$confirm" != "y" ] && echo "取消操作。" && exit 0

# Step 2: 安装 curl（如果未安装）
if ! command -v curl >/dev/null 2>&1; then
    echo "curl 未安装，安装中..."
    sh -c "$PACKAGE_INSTALL_CMD"
fi

# Step 3: 下载公钥
PUB_URL=$(echo "$ENCODED_URL" | base64 -d)
echo "下载公钥: $PUB_URL"
curl -fsSL "$PUB_URL" -o "$TMP_KEY_FILE" || { echo "公钥下载失败"; exit 1; }

# Step 4: 创建 .ssh 和 authorized_keys 文件
if [ ! -d "/home/$SSH_USER/.ssh" ]; then
    echo "创建目录 /home/$SSH_USER/.ssh"
    mkdir -p "/home/$SSH_USER/.ssh"
    chmod 700 "/home/$SSH_USER/.ssh"
    chown $SSH_USER:$SSH_USER "/home/$SSH_USER/.ssh"
fi

if [ ! -f "$AUTHORIZED_KEYS_PATH" ]; then
    echo "创建空的 authorized_keys 文件"
    touch "$AUTHORIZED_KEYS_PATH"
    chmod 600 "$AUTHORIZED_KEYS_PATH"
    chown $SSH_USER:$SSH_USER "$AUTHORIZED_KEYS_PATH"
fi

# Step 5: 检查重复并添加公钥
PUB_KEY_CONTENT=$(cat "$TMP_KEY_FILE")
if grep -qxF "$PUB_KEY_CONTENT" "$AUTHORIZED_KEYS_PATH"; then
    echo "公钥已存在于 $AUTHORIZED_KEYS_PATH，跳过添加。"
else
    echo "公钥尚未添加到 $AUTHORIZED_KEYS_PATH。"
    echo "如果添加错误可能影响 SSH 登录，请确保你当前已有有效登录方式。"
    printf "是否将公钥添加到 %s？(y/n): " "$AUTHORIZED_KEYS_PATH"
    read confirm
    if [ "$confirm" = "y" ]; then
        echo "$PUB_KEY_CONTENT" >> "$AUTHORIZED_KEYS_PATH"
        chmod 600 "$AUTHORIZED_KEYS_PATH"
        chown $SSH_USER:$SSH_USER "$AUTHORIZED_KEYS_PATH"
        echo "公钥已添加到 $AUTHORIZED_KEYS_PATH"
    else
        echo "跳过公钥添加"
    fi
fi

# Step 6: 提示用户验证密钥登录
echo
echo "请确保你可以使用密钥登录服务器后，再执行下一步修改 SSH 配置。"
printf "确认已测试密钥登录成功？(y/n): "
read confirm
[ "$confirm" != "y" ] && echo "请先验证密钥登录，脚本终止。" && exit 0

# Step 7: 修改 SSH 配置，选择认证方式
echo
echo "请选择 SSH 登录认证方式："
echo "1) 支持密码登录 + 支持密钥登录（默认）"
echo "2) 仅支持密钥登录（禁用密码）"
printf "输入选项 [1/2]: "
read ssh_choice

# 备份 sshd_config
cp "$SSHD_CONFIG" "$BACKUP_SSHD_CONFIG"
echo "已备份 SSH 配置到 $BACKUP_SSHD_CONFIG"

case "$ssh_choice" in
    1)
        sed -i 's/^#*\s*PasswordAuthentication\s.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
        sed -i 's/^#*\s*PubkeyAuthentication\s.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        echo "SSH 配置修改为：密码 + 密钥登录"
        ;;
    2)
        sed -i 's/^#*\s*PasswordAuthentication\s.*/PasswordAuthentication no/' "$SSHD_CONFIG"
        sed -i 's/^#*\s*PubkeyAuthentication\s.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        echo "SSH 配置修改为：仅密钥登录"
        ;;
    *)
        echo "无效选项，跳过修改 SSH 配置"
        ;;
esac

# Step 8: 重启 SSH 服务
echo "重启 SSH 服务..."
$SSH_RESTART_CMD
echo "操作完成。"
