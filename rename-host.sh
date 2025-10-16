#!/bin/sh
# rename-host.sh
# 用途：重命名 Linux 主机名，兼容 Debian/Ubuntu/CentOS/Alpine
# Alpine 上智能修改 /etc/hosts 中 127.0.0.1 和 ::1 的主机名映射

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户或 sudo 运行此脚本。"
    exit 1
fi

# 当前主机名
current_hostname=$(hostname)
echo "当前主机名: $current_hostname"

# 输入新主机名
printf "请输入新的主机名: "
read new_hostname

# 校验主机名格式
case "$new_hostname" in
    ''|*[!a-zA-Z0-9-]*|-) 
        echo "主机名格式不合法，只允许字母、数字和中划线，且不能以中划线开头或为空。"
        exit 1
        ;;
esac

# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    distro=$ID
else
    distro=$(uname -s)
fi

echo "检测到系统: $distro"

# 修改 /etc/hostname
echo "$new_hostname" > /etc/hostname
echo "已更新 /etc/hostname"

# 修改 /etc/hosts 中的旧主机名（只替换 127.0.0.1 和 ::1 的行）
if grep -q "$current_hostname" /etc/hosts; then
    awk -v old="$current_hostname" -v new="$new_hostname" '
    /^127\.0\.0\.1/ {gsub(old, new)}
    /^::1/ {gsub(old, new)}
    {print}
    ' /etc/hosts > /etc/hosts.tmp && mv /etc/hosts.tmp /etc/hosts
    echo "已更新 /etc/hosts 中的本地主机名映射"
else
    echo "警告: /etc/hosts 中未找到旧主机名，未修改"
fi

# 临时修改主机名
case "$distro" in
    alpine)
        hostname "$new_hostname"
        ;;
    debian|ubuntu|centos|rhel|fedora)
        if command -v hostnamectl >/dev/null 2>&1; then
            hostnamectl set-hostname "$new_hostname"
        else
            hostname "$new_hostname"
        fi
        ;;
    *)
        hostname "$new_hostname"
        ;;
esac

echo "当前主机名已生效: $(hostname)"
echo "主机名修改完成，建议重启系统以确保所有服务生效。"
