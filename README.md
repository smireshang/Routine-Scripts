# 常用脚本

### Linux磁盘清理
```
sudo bash -c "$(curl -fsSL https://github.com/smireshang/Routine-Scripts/raw/main/diskclean.sh)"
```
### 网络速度测试
```
curl -sS -O https://raw.githubusercontent.com/smireshang/Routine-Scripts/main/speedtest.sh && chmod +x speedtest.sh && ./speedtest.sh
```
### Debian系vps 小硬盘(3GB内)清理维护
```
curl -Ls https://raw.githubusercontent.com/smireshang/Routine-Scripts/main/diskcleanlite.sh -o diskcleanlite.sh && chmod +x diskcleanlite.sh && ./diskcleanlite.sh
```
