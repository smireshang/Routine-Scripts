#!/bin/sh
# 文件名: statusCheck.sh
# 功能: 监控 x-ui 服务，如被 kill 自动重启

SERVICE_NAME="x-ui"
LOG_FILE="/var/log/xui_monitor.log"

# 日志输出函数
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a "$LOG_FILE"
}

# 重启服务函数
restart_service() {
    rc-service $SERVICE_NAME stop
    sleep 2
    rc-service $SERVICE_NAME start
    sleep 2

    rc-service $SERVICE_NAME status >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_info "$SERVICE_NAME 重启成功"
    else
        log_error "$SERVICE_NAME 重启失败，请检查日志"
    fi
}

# 检查服务状态函数
check_service() {
    rc-service $SERVICE_NAME status >/dev/null 2>&1
    return $?
}

# 主循环
while true; do
    check_service
    if [ $? -ne 0 ]; then
        log_error "$SERVICE_NAME 未运行，尝试重启..."
        restart_service
    fi
    # 每 30 秒检查一次，可以根据实际内存压力调整
    sleep 30
done
