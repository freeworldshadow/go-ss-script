#!/bin/bash

# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装必要的依赖
sudo apt install -y curl git

# 安装 Go
GO_VERSION="1.20.3"
curl -LO "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
source ~/.profile

# 下载并安装 Shadowsocks
go install github.com/shadowsocks/go-shadowsocks2@latest

# 设置加密方式、端口和密码
mkdir -p ~/.config
cat <<EOF > ~/.config/shadowsocks.json
{
  "server": "0.0.0.0",
  "port": 443,
  "method": "aes-256-gcm",
  "password": "amazongreatvpn",
  "timeout": 300
}
EOF

# 创建 systemd 服务文件
sudo bash -c 'cat <<EOF > /etc/systemd/system/shadowsocks.service
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
ExecStart=/root/go/bin/go-shadowsocks2 -s "ss://aes-256-gcm:amazongreatvpn@:443" -verbose
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF'

# 启动 Shadowsocks 服务并设置开机自启动
sudo systemctl daemon-reload
sudo systemctl enable shadowsocks
sudo systemctl start shadowsocks

# 启用 BBR
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 提示完成
echo "Shadowsocks 安装完成，BBR 已启用，并已设置为随系统自动启动。"
