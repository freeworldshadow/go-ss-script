#!/bin/bash

set -e

echo "🔧 开始安装 Shadowsocks（适用于 x86_64 和 ARM64 架构）"

# === 更新系统 ===
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git

# === 检测系统架构 ===
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    GO_ARCH="arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    GO_ARCH="amd64"
else
    echo "❌ 不支持的架构: $ARCH"
    exit 1
fi

# === 安装 Go（版本 1.20.3） ===
GO_VERSION="1.20.3"
cd /tmp
curl -LO "https://golang.org/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
echo 'export GOPATH=$HOME/go' >> ~/.profile
echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
source ~/.profile

# === 安装 go-shadowsocks2 ===
go install github.com/shadowsocks/go-shadowsocks2@latest

# === 将可执行文件移动到全局目录 ===
sudo mv "$HOME/go/bin/go-shadowsocks2" /usr/local/bin/
sudo chmod +x /usr/local/bin/go-shadowsocks2

# === 创建 Shadowsocks 配置目录 ===
sudo mkdir -p /etc/shadowsocks

# === 写入配置文件 ===
sudo tee /etc/shadowsocks/config.json > /dev/null <<EOF
{
  "server": "0.0.0.0",
  "port": 443,
  "method": "aes-256-gcm",
  "password": "amazongreatvpn",
  "timeout": 300
}
EOF

# === 创建 systemd 服务 ===
sudo tee /etc/systemd/system/shadowsocks.service > /dev/null <<EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
ExecStart=/usr/local/bin/go-shadowsocks2 -s "0.0.0.0:443" -k "amazongreatvpn" -m "aes-256-gcm" -verbose
Restart=on-failure
User=nobody
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# === 启动并启用服务 ===
sudo systemctl daemon-reload
sudo systemctl enable shadowsocks
sudo systemctl start shadowsocks

# === 启用 BBR 拥塞控制算法 ===
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "✅ Shadowsocks 安装完成，已启用 BBR，加密算法：aes-256-gcm，监听端口：443"
