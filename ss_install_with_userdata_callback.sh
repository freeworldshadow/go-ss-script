#!/bin/bash

export HOME=/root
export GOCACHE=/tmp/gocache

# 将 needrestart 的模式设为自动重启，避免弹窗
export NEEDRESTART_MODE=a
# 如无需求可直接暂停 needrestart
# export NEEDRESTART_SUSPEND=1

# 将 APT/Debian 配置为非交互
export DEBIAN_FRONTEND=noninteractive


set -e

echo "🔧 开始安装 Shadowsocks（适配 ARM64）"

# === 更新系统 ===
sudo -E apt update && sudo -E apt upgrade -y
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

# === 安装 Go（自定义版本） ===
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

# === 写入配置文件 ===
mkdir -p ~/.config
cat > ~/.config/shadowsocks.json <<EOF
{
  "server": "0.0.0.0",
  "port": 443,
  "method": "aes-256-gcm",
  "password": "amazongreatvpn",
  "timeout": 300
}
EOF

# === 创建 systemd 服务 ===
sudo bash -c "cat > /etc/systemd/system/shadowsocks.service" <<EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
ExecStart=/root/go/bin/go-shadowsocks2 -s "0.0.0.0:443" -cipher "aes-256-gcm" -password "amazongreatvpn" -verbose
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# === 启动服务 ===
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable shadowsocks
sudo systemctl start shadowsocks

# === 启用 BBR ===
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "✅ Shadowsocks 安装完成，已启用 BBR，加密算法：aes-256-gcm，监听端口：443"

# 回传aws-instance-public-ip到Bussiness-server
curl -s -X POST https://app.vpnin.xyz/api/aws/rent-userdata-callback
