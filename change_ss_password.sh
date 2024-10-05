#!/bin/bash

# 设置相关路径和变量
CONFIG_FILE="/etc/shadowsocks.json"
REPORT_URL="https://app.vpnin.xyz/api/vps/report_password"
LOG_FILE="/var/log/ss_password_change.log"

# 检查 jq 是否安装，如果未安装则自动安装
if ! command -v jq &> /dev/null
then
    echo "jq 工具未安装，正在安装 jq..."
    sudo apt update && sudo apt install -y jq
fi

# 1. 生成新的随机密码
NEW_PASSWORD=$(openssl rand -base64 16)

# 2. 获取当前的公网 IP 地址
PUBLIC_IP=$(curl -s ifconfig.me)

# 3. 更新 Shadowsocks 配置文件中的密码
sudo jq '.password = "'$NEW_PASSWORD'"' $CONFIG_FILE > /tmp/shadowsocks.json && sudo mv /tmp/shadowsocks.json $CONFIG_FILE

# 4. 重启 Shadowsocks 服务
sudo systemctl restart shadowsocks

# 5. 输出新密码到日志
echo "$(date): Password changed to $NEW_PASSWORD, Public IP: $PUBLIC_IP" >> $LOG_FILE

# 6. 将新密码和公网 IP 上报到指定的 URL
HOSTNAME=$(hostname)  # 获取服务器主机名，可用于上报信息
curl -X POST -H "Content-Type: application/json" -d '{"hostname": "'$HOSTNAME'", "new_password": "'$NEW_PASSWORD'", "public_ip": "'$PUBLIC_IP'"}' $REPORT_URL
