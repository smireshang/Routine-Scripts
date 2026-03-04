#!/bin/bash

echo "==== 国内测速文件测速脚本 ===="

# 检测 curl 是否安装
if ! command -v curl >/dev/null 2>&1; then
  echo "[错误] 系统未安装 curl，请先安装 curl 后再运行此脚本。"
  exit 1
fi

declare -A URLS=(
  [1]="https://store.storevideos.cdn-apple.com/v1/store.apple.com/st/1666383693478/atvloop-video-202210/streams_atvloop-video-202210/1920x1080/fileSequence3.m4s"  # 苹果静态资源
  [2]="https://issuecdn.baidupcs.com/issue/netdisk/apk/BaiduNetdiskSetup_wap_share.apk"  # 百度 CDN
  [3]="https://wwwstatic.vivo.com.cn/vivoportal/files/resource/funtouch/1651200648928/images/os2-jude-video.mp4" # vivo静态资源
  [4]="https://desk.ctyun.cn/desktop/software/clientsoftware/download/ff3e71dcc21152307f54700c62e5aef6"  # 天翼云
)

echo "请选择测速源（输入数字1-3或 all，Ctrl+C退出）："
echo " 1) 苹果静态资源"
echo " 2) 百度 CDN"
echo " 3) vivo静态资源"
echo " 4) 天翼云"
echo " all) 测试全部"

while true; do
  read -p "请输入选择： " choice
  if [[ "$choice" =~ ^[1-4]$ ]]; then
    SELECTED_URLS=("${URLS[$choice]}")
    echo "[选择确认] 只测速：$choice"
    break
  elif [[ "$choice" == "all" ]]; then
    SELECTED_URLS=("${URLS[@]}")
    echo "[选择确认] 测试全部测速源"
    break
  else
    echo "[错误] 请输入数字1-3或 all"
  fi
done

# 读取循环次数
while true; do
  read -p "请输入测速循环次数（正整数）： " count
  if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
    echo "[输入确认] 循环次数设为：$count"
    break
  else
    echo "[错误] 输入无效，请输入正整数。"
  fi
done

echo "开始测速，共循环 $count 轮，每轮测试 ${#SELECTED_URLS[@]} 个测速源..."

# 循环测速
for ((i=1; i<=count; i++)); do
  echo "==========================="
  echo "[第 $i 轮] 开始测速"

  for url in "${SELECTED_URLS[@]}"; do
    echo "[下载测速] $url"

    # 下载前 300MB，只测速，不保存
    speed=$(curl -L --progress-bar --range 0-314572799 -o /dev/null -w "%{speed_download}" "$url")
    speed_mbps=$(awk "BEGIN {printf \"%.2f\", $speed/1024/1024}")  # 转 MB/s

    echo "[本次速度] $speed_mbps MB/s"

    # 保存速度用于平均计算
    SPEED_LIST+=($speed_mbps)
  done

  echo "[第 $i 轮] 测速完成"
done

# 计算平均速度
total=0
for s in "${SPEED_LIST[@]}"; do
  total=$(awk "BEGIN {printf \"%.2f\", $total+$s}")
done

average=$(awk "BEGIN {printf \"%.2f\", $total/${#SPEED_LIST[@]}}")
echo "==========================="
echo "所有测速完成！共执行 $count 轮。"
echo "测速源总数：${#SELECTED_URLS[@]}，平均速度：$average MB/s"
