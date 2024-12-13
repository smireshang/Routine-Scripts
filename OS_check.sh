#!/bin/bash

if [ -f /etc/os-release ]; then
    # 读取 /etc/os-release 文件
    source /etc/os-release
    
    if [[ "$ID" == "debian" ]]; then
        echo "This is a Debian-based system."
        echo "Version: $VERSION"
    elif [[ "$ID" == "ubuntu" ]]; then
        echo "This is an Ubuntu-based system."
        echo "Version: $VERSION"
    else
        echo "This is a different $NAME system."
        echo "Version: $VERSION"
    fi
elif [ -f /etc/freebsd-version ]; then
    echo "This is a FreeBSD system."
    cat /etc/freebsd-version
else
    echo "Unknown system."
fi
