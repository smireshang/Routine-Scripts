#!/bin/bash

# 检查 curl 是否安装
if ! command -v curl >/dev/null 2>&1; then
  echo "错误：系统未安装 curl，请先安装 curl 后再运行此脚本。"
  exit 1
fi

# 四个下载地址（自适应、联通、移动、电信）
URLS=(
  "https://dlied4.myapp.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
  "https://ml-dlied4.bytes.tcdnos.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
  "https://875e1151af8aa9e3b793f51f6049996d.dlied1.cdntips.net/dlied4.myapp.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
  "https://dlied4.csy.tcdnos.com/myapp/1104466820/cos.release-40109/10040714_com.tencent.tmgp.sgame_a2480356_8.2.1.9_F0BvnI.apk"
)

# 读取用户输入循环次数
read -p "请输入循环次数（正整数）： " count

# 校验输入是否为正整数
if ! [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
  echo "错误：请输入一个正整数"
  exit 1
fi

echo "开始循环下载，每轮下载4个地址，共 $count 轮"

for ((i=1; i<=count; i++)); do
  echo "第 $i 轮开始..."

  for url in "${URLS[@]}"; do
    echo "下载地址：$url"
    curl -L --progress-bar -o /dev/null "$url"
  done

  echo "第 $i 轮结束"
done

echo "全部循环完成。"
