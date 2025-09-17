#!/bin/bash

# VPS 硬盘空间维护脚本
set -e

# 定义颜色
green='\033[0;32m'
yellow='\033[1;33m'
cyan='\033[1;36m'
plain='\033[0m'

echo -e "${cyan}================ Debian系VPS硬盘自动维护 =================${plain}"

# 判断是否安装过 XrayR，若存在则卸载 unzip（临时依赖）
if [ -d "/etc/XrayR" ] || [ -f "/usr/local/XrayR/XrayR" ]; then
    echo -e "${yellow}[临时依赖清理] 检测到 XrayR，正在卸载 unzip ...${plain}"
    apt purge -y unzip || true
    apt autoremove -y || true
    apt clean || true
else
    echo -e "${yellow}[临时依赖清理] 未检测到 XrayR，跳过 unzip 卸载${plain}"
fi

# 依赖检测
echo -e "${yellow}[依赖检测] 安装必要组件...${plain}"
apt install bc -y || true

# 判断是否容器环境
virt_env="normal"
if command -v systemd-detect-virt >/dev/null; then
    if systemd-detect-virt --container >/dev/null 2>&1; then
        virt_env="container"
    fi
fi

# 定义清理目标
targets="/usr/share/doc /usr/share/man /usr/share/info /usr/share/lintian /usr/share/locale"
if [ "$virt_env" = "container" ]; then
    targets="$targets /lib/modules"
    echo -e "${yellow}[环境检测] 容器环境，包含 /lib/modules 清理${plain}"
else
    echo -e "${yellow}[环境检测] 非容器环境，跳过 /lib/modules 清理${plain}"
fi

# 精确统计清理前可释放空间
cleared_size=$(du -sk $targets 2>/dev/null | awk '{sum+=$1} END {print sum}')
cleared_mb=$(echo "scale=2; $cleared_size/1024" | bc)

echo ""
echo -e "${yellow}[本轮预清理空间]${plain} 预计可释放: ${green}${cleared_mb} MB${plain}"

# 开始清理
apt clean
rm -rf /var/lib/apt/lists/*
find /var/log -type f -delete
command -v journalctl >/dev/null && journalctl --vacuum-time=1d || true
rm -rf $targets

# 确保日志目录存在
mkdir -p /var/log/vps-lite
log_file="/var/log/vps-lite/daily-clean.log"

# 清理完毕后显示磁盘状态
echo ""
echo -e "${yellow}[磁盘使用]${plain}"
df -h /

# 写入日志
echo "$(date '+%Y-%m-%d %H:%M:%S') 本轮清理释放: ${cleared_mb} MB" >> "$log_file"

# 自动配置每日定时任务
echo ""
echo -e "${yellow}[定时任务]${plain} 写入每日自动清理任务..."

cat <<EOF > /usr/local/bin/vps-lite-daily-clean.sh
#!/bin/bash
targets="/usr/share/doc /usr/share/man /usr/share/info /usr/share/lintian /usr/share/locale"
if command -v systemd-detect-virt >/dev/null && systemd-detect-virt --container >/dev/null 2>&1; then
    targets="\$targets /lib/modules"
fi
cleared_size=\$(du -sk \$targets 2>/dev/null | awk '{sum+=\$1} END {print sum}')
cleared_mb=\$(echo "scale=2; \$cleared_size/1024" | bc)
apt clean
rm -rf /var/lib/apt/lists/*
find /var/log -type f -delete
command -v journalctl >/dev/null && journalctl --vacuum-time=1d || true
rm -rf \$targets
mkdir -p /var/log/vps-lite
echo "\$(date '+%Y-%m-%d %H:%M:%S') 本轮清理释放: \${cleared_mb} MB" >> /var/log/vps-lite/daily-clean.log
EOF

chmod +x /usr/local/bin/vps-lite-daily-clean.sh

# 安装定时任务（避免重复添加）
if ! crontab -l 2>/dev/null | grep -q "vps-lite-daily-clean.sh"; then
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/vps-lite-daily-clean.sh >/dev/null 2>&1") | crontab -
fi

echo ""
echo -e "${green}✅ 自动定时任务配置完成 (每天凌晨3点自动清理)${plain}"
echo -e "${yellow}[日志位置]${plain} $log_file"
echo -e "${cyan}================ 部署完成 =================${plain}"
