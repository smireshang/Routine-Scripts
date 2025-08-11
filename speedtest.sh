#!/bin/bash

echo "==== 测速脚本 ===="

# 检查 curl 是否安装
if ! command -v curl >/dev/null 2>&1; then
  echo "[错误] 系统未安装 curl，请先安装 curl 后再运行此脚本。"
  exit 1
fi
echo "[检测] curl 已安装，准备开始测速。"

# 四个下载地址（自适应、联通、移动、电信）
URLS=(
  "https://dlied4.myapp.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
  "https://ml-dlied4.bytes.tcdnos.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
  "https://875e1151af8aa9e3b793f51f6049996d.dlied1.cdntips.net/dlied4.myapp.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
  "https://dlied4.csy.tcdnos.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
)

# 读取用户输入循环次数
while true; do
  read -p "请输入测速循环次数（正整数，Ctrl+C退出）： " count
  if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
    echo "[输入确认] 循环次数设为：$count"
    break
  else
    echo "[错误] 输入无效，请输入一个正整数。"
  fi
done

echo "开始执行测速，总共循环 $count 轮，每轮下载4个不同节点..."

for ((i=1; i<=count; i++)); do
  echo "============================"
  echo "[第 $i 轮] 开始"
  
  for url in "${URLS[@]}"; do
    echo "[下载] $url"
    curl -L --progress-bar -o /dev/null "$url"
  done
  
  echo "[第 $i 轮] 完成"
done

echo "============================"
echo "测速完成！共执行了 $count 轮。感谢使用！"
