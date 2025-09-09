#!/bin/bash

echo "==== 国内测速文件测速脚本 ===="

# 检测 curl 是否安装
if ! command -v curl >/dev/null 2>&1; then
  echo "[错误] 系统未安装 curl，请先安装 curl 后再运行此脚本。"
  exit 1
fi

declare -A URLS=(
  [1]="https://dlied4.myapp.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"  # 腾讯手游 CDN
  [2]="https://autopatchcn.yuanshen.com/client_app/download/Android/20250718182628_nnOpvKMewCwYMAFU/ydbackup318/yuanshen_5.8.0.apk"  # 米哈游 CDN
  [3]="https://u5.gdl.netease.com/party_netease_103_1.0.215_a94d99.apk?key1=7f4f47929952de2d974597f588dd23c6&key2=68c0e4fd" # 网易手游 CDN
)

echo "请选择测速源（输入数字1-3或 all，Ctrl+C退出）："
echo " 1) 腾讯手游 CDN"
echo " 2) 米哈游 CDN"
echo " 3) 网易手游 CDN"
echo " all) 测试全部"

while true; do
  read -p "请输入选择： " choice
  if [[ "$choice" =~ ^[1-3]$ ]]; then
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

for ((i=1; i<=count; i++)); do
  echo "==========================="
  echo "[第 $i 轮] 开始测速"

  for url in "${SELECTED_URLS[@]}"; do
    echo "[下载测速] $url"
    curl -L --progress-bar -o /dev/null "$url"
  done

  echo "[第 $i 轮] 测速完成"
done

echo "==========================="
echo "所有测速完成！共执行 $count 轮。感谢使用！"
